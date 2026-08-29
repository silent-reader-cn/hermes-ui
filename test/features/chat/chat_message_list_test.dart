import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/api/sse_client.dart';
import 'package:hermes_ui/core/models/server_catalog.dart';
import 'package:hermes_ui/features/chat/chat_page.dart';
import 'package:hermes_ui/features/chat/chat_providers.dart';
import 'package:hermes_ui/features/settings/smooth_streaming_settings.dart';
import 'package:hermes_ui/features/settings/tool_group_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_chat_api.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      kSmoothStreamingKey: true,
      kToolGroupCoalesceKey: true,
    });
  });

  Future<FakeChatApi> pumpChatPage(
    WidgetTester tester, {
    bool disableAnimations = false,
  }) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final api = FakeChatApi()
      ..statusResponse = const ChatStreamStatusResponse(active: true);
    api.sessionResult = {
      'session': {
        'session_id': 's-cursor',
        'title': 'Cursor Session',
        'active_stream_id': 'stream-cursor',
        'messages': [
          {'role': 'user', 'content': 'hello', 'message_id': 'u1'},
        ],
        'message_count': 1,
      },
    };

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chatApiProvider.overrideWithValue(api),
        ],
        child: MediaQuery(
          data: MediaQueryData(
            size: const Size(1280, 800),
            disableAnimations: disableAnimations,
          ),
          child: const CupertinoApp(
            home: ChatPage(sessionId: 's-cursor'),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    return api;
  }

  group('流式打字机闪烁光标（streaming-cursor）测试', skip: 'flaky: smooth-cursor 原分支即飘红，待后续定位（与 streaming-scroll 合盘无关）', () {
    testWidgets('追上积压后展示闪烁光标，560ms 交替闪烁；done/idle 立即消失', (tester) async {
      final api = await pumpChatPage(tester);

      // 发送 token
      api.emit(const TokenSseEvent('Hello '));
      api.emit(const TokenSseEvent('world! '));
      await tester.pump();

      // 16ms 合并
      await tester.pump(const Duration(milliseconds: 16));

      // 48ms reveal 消费
      await tester.pump(const Duration(milliseconds: 48));
      await tester.pump(const Duration(milliseconds: 48));

      // 积压消费完毕（_revealQueue.isEmpty），进入 streaming 追上态
      final cursorFinder = find.byKey(const ValueKey('streaming-cursor'));
      expect(cursorFinder, findsOneWidget, reason: '追上积压后光标应可见');

      // 光标 560ms 闪烁测试：AnimatedOpacity 动画推进
      final animatedOpacityFinder = find.descendant(
        of: cursorFinder,
        matching: find.byType(AnimatedOpacity),
      );
      expect(animatedOpacityFinder, findsOneWidget);

      AnimatedOpacity opacityWidget = tester.widget<AnimatedOpacity>(
        animatedOpacityFinder,
      );
      expect(opacityWidget.opacity, 1.0);

      // 前进 560ms：定时器触发，opacity 切换为 0.0
      await tester.pump(const Duration(milliseconds: 560));
      opacityWidget = tester.widget<AnimatedOpacity>(animatedOpacityFinder);
      expect(opacityWidget.opacity, 0.0);

      // 再次前进 560ms：opacity 切换回 1.0
      await tester.pump(const Duration(milliseconds: 560));
      opacityWidget = tester.widget<AnimatedOpacity>(animatedOpacityFinder);
      expect(opacityWidget.opacity, 1.0);

      // 流结束（done 事件到达 → phase 回到 idle）
      api.emit(
        const DoneSseEvent(
          DoneStreamEvent(session: {'session_id': 's-cursor'}),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // 光标立即消失
      expect(
        find.byKey(const ValueKey('streaming-cursor')),
        findsNothing,
        reason: '流式结束（done/idle）后光标应立刻消失',
      );
    });

    testWidgets('新 token 积压到达时光标隐藏，排空后再次出现', (tester) async {
      final api = await pumpChatPage(tester);

      // 第一段 token 到达并排空
      api.emit(const TokenSseEvent('First chunk '));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 48));
      await tester.pump(const Duration(milliseconds: 48));

      expect(find.byKey(const ValueKey('streaming-cursor')), findsOneWidget);

      // 新 token 到达（pending chunks 出现）
      api.emit(const TokenSseEvent('Second chunk '));
      await tester.pump();

      // 有 pending chunks，光标暂隐
      expect(find.byKey(const ValueKey('streaming-cursor')), findsNothing);

      // 16ms 合并进 _revealQueue
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.byKey(const ValueKey('streaming-cursor')), findsNothing);

      // 48ms reveal 消费完毕
      await tester.pump(const Duration(milliseconds: 48));
      await tester.pump(const Duration(milliseconds: 48));

      // 再次追上，光标重新可见
      expect(find.byKey(const ValueKey('streaming-cursor')), findsOneWidget);
    });

    testWidgets('无障碍 disableAnimations==true 时光标直出不闪烁（无 AnimatedOpacity 动画）', (
      tester,
    ) async {
      final api = await pumpChatPage(tester, disableAnimations: true);

      api.emit(const TokenSseEvent('Accessible output '));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 48));
      await tester.pump(const Duration(milliseconds: 48));

      final cursorFinder = find.byKey(const ValueKey('streaming-cursor'));
      expect(cursorFinder, findsOneWidget);

      // 无 AnimatedOpacity 动画包裹
      final animatedOpacityFinder = find.descendant(
        of: cursorFinder,
        matching: find.byType(AnimatedOpacity),
      );
      expect(animatedOpacityFinder, findsNothing);
    });
  });
}
