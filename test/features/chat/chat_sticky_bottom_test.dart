import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/api/sse_client.dart';
import 'package:hermes_ui/core/models/server_catalog.dart';
import 'package:hermes_ui/features/chat/chat_page.dart';
import 'package:hermes_ui/features/chat/chat_providers.dart';
import 'package:hermes_ui/features/chat/widgets/chat_message_list.dart';

import '../../helpers/fake_chat_api.dart';

void main() {
  group('#13 滚动粘底保持测试', () {
    ScrollPosition positionOf(WidgetTester tester) {
      final scrollableFinder = find
          .descendant(
            of: find.byType(ChatMessageList),
            matching: find.byType(Scrollable),
          )
          .first;
      return tester.state<ScrollableState>(scrollableFinder).position;
    }

    testWidgets('Live token 增量无动画 jump 跟随（不触发 DrivenScrollActivity）', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final api = FakeChatApi()
        ..statusResponse = const ChatStreamStatusResponse(active: true);

      final messages = List.generate(
        30,
        (i) => {
          'role': i.isEven ? 'user' : 'assistant',
          'content': '消息 $i：' * 10,
          'message_id': 'm$i',
        },
      );

      api.sessionResult = {
        'session': {
          'session_id': 's-sticky-live',
          'active_stream_id': 'stream-sticky',
          'messages': messages,
          'message_count': 30,
        },
      };

      await tester.pumpWidget(
        ProviderScope(
          overrides: [chatApiProvider.overrideWithValue(api)],
          child: const CupertinoApp(home: ChatPage(sessionId: 's-sticky-live')),
        ),
      );

      await tester.pumpAndSettle();

      var drivenCount = 0;
      final pos = positionOf(tester);
      void onPosChanged() {
        if (pos.activity is DrivenScrollActivity) drivenCount++;
      }

      pos.addListener(onPosChanged);

      // 发送 token 增量，验证滚动跟随为无动画 jump
      for (var i = 0; i < 5; i++) {
        api.emit(TokenSseEvent('new text chunk $i ' * 10));
        await tester.pump(const Duration(milliseconds: 16));
        await tester.pump(const Duration(milliseconds: 48));
        await tester.pump();
      }

      pos.removeListener(onPosChanged);

      expect(drivenCount, 0, reason: 'Live 增量 token 不应产生 animateTo 动画活动');
      expect(
        pos.pixels,
        closeTo(pos.maxScrollExtent, 1.0),
        reason: 'Live 增量更新应始终保持粘底',
      );
    });

    testWidgets('阶段切换（sending 开始）保留平滑动画', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final api = FakeChatApi();
      final messages = List.generate(
        20,
        (i) => {
          'role': i.isEven ? 'user' : 'assistant',
          'content': '消息 $i：' * 10,
          'message_id': 'm$i',
        },
      );

      api.sessionResult = {
        'session': {
          'session_id': 's-phase-anim',
          'messages': messages,
          'message_count': 20,
        },
      };
      api.startChatResult = {
        'ok': true,
        'stream_id': 'stream-new',
      };

      await tester.pumpWidget(
        ProviderScope(
          overrides: [chatApiProvider.overrideWithValue(api)],
          child: const CupertinoApp(home: ChatPage(sessionId: 's-phase-anim')),
        ),
      );

      await tester.pumpAndSettle();

      final pos = positionOf(tester);

      // 发送消息触发 sending 相位
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ChatMessageList)),
      );
      unawaited(
        container
            .read(chatControllerProvider('s-phase-anim').notifier)
            .send('test message'),
      );

      await tester.pump();
      expect(pos.activity, isA<DrivenScrollActivity>(), reason: '阶段切换到 sending 应触发 200ms 平滑动画');

      // 推进多帧让 200ms 动画收敛完成
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(pos.pixels, closeTo(pos.maxScrollExtent, 1.0));
    });

    testWidgets('Android 下软键盘弹出/收起触发 postFrame 无动画 jump 回底', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final api = FakeChatApi();
        final messages = List.generate(
          30,
          (i) => {
            'role': i.isEven ? 'user' : 'assistant',
            'content': '消息 $i：' * 10,
            'message_id': 'm$i',
          },
        );

        api.sessionResult = {
          'session': {
            'session_id': 's-android-ime',
            'messages': messages,
            'message_count': 30,
          },
        };

        await tester.pumpWidget(
          ProviderScope(
            overrides: [chatApiProvider.overrideWithValue(api)],
            child: const MediaQuery(
              data: MediaQueryData(
                size: Size(390, 844),
                viewInsets: EdgeInsets.zero,
              ),
              child: CupertinoApp(
                home: CupertinoPageScaffold(
                  child: ChatMessageList(sessionId: 's-android-ime'),
                ),
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();

        final pos = positionOf(tester);
        expect(pos.pixels, closeTo(pos.maxScrollExtent, 1.0));

        // 模拟键盘弹出 (bottom viewInset = 300)
        await tester.pumpWidget(
          ProviderScope(
            overrides: [chatApiProvider.overrideWithValue(api)],
            child: const MediaQuery(
              data: MediaQueryData(
                size: Size(390, 844),
                viewInsets: EdgeInsets.only(bottom: 300.0),
              ),
              child: CupertinoApp(
                home: CupertinoPageScaffold(
                  child: ChatMessageList(sessionId: 's-android-ime'),
                ),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        final posAfterKeyboard = positionOf(tester);
        expect(
          posAfterKeyboard.pixels,
          closeTo(posAfterKeyboard.maxScrollExtent, 1.0),
          reason: '键盘弹出后在 Android 上应 postFrame jump 回底',
        );

        // 模拟键盘收起 (bottom viewInset = 0)
        await tester.pumpWidget(
          ProviderScope(
            overrides: [chatApiProvider.overrideWithValue(api)],
            child: const MediaQuery(
              data: MediaQueryData(
                size: Size(390, 844),
                viewInsets: EdgeInsets.zero,
              ),
              child: CupertinoApp(
                home: CupertinoPageScaffold(
                  child: ChatMessageList(sessionId: 's-android-ime'),
                ),
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        final posAfterDismiss = positionOf(tester);
        expect(
          posAfterDismiss.pixels,
          closeTo(posAfterDismiss.maxScrollExtent, 1.0),
          reason: '键盘收起后在 Android 上应 postFrame jump 回底',
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });
}
