import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/api/sse_client.dart';
import 'package:hermes_ui/core/models/server_catalog.dart';
import 'package:hermes_ui/features/chat/chat_page.dart';
import 'package:hermes_ui/features/chat/chat_providers.dart';
import 'package:hermes_ui/features/chat/widgets/chat_message_list.dart';
import 'package:hermes_ui/features/settings/tool_group_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_chat_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('#92 live 流式页面停留上方时 y 轴上下抖动治理', () {
    ScrollPosition positionOf(WidgetTester tester) {
      final scrollableFinder = find
          .descendant(
            of: find.byType(ChatMessageList),
            matching: find.byType(Scrollable),
          )
          .first;
      return tester.state<ScrollableState>(scrollableFinder).position;
    }

    ChatMessageListState stateOf(WidgetTester tester) {
      return tester.state<ChatMessageListState>(find.byType(ChatMessageList));
    }

    testWidgets('1. 单次位移补偿后立即收敛：消除同步读取未布局 dy 导致的周期性反向震荡死循环', (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final api = FakeChatApi()
        ..statusResponse = const ChatStreamStatusResponse(active: true);

      final messages = List.generate(
        30,
        (i) => {
          'role': i.isEven ? 'user' : 'assistant',
          'content': '消息 $i: 内容用于撑高列表\n第2行\n第3行',
          'message_id': 'm$i',
        },
      );

      api.sessionResult = {
        'session': {
          'session_id': 's-oscillation-convergence',
          'active_stream_id': 'stream-conv',
          'messages': messages,
          'message_count': 30,
        },
      };

      await tester.pumpWidget(
        ProviderScope(
          overrides: [chatApiProvider.overrideWithValue(api)],
          child: const CupertinoApp(
            home: ChatPage(sessionId: 's-oscillation-convergence'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final scrollable = find.byType(Scrollable).first;
      final pos = positionOf(tester);
      final listState = stateOf(tester);

      // 上滑 400px 离底
      await tester.drag(scrollable, const Offset(0, 400));
      await tester.pumpAndSettle();

      expect(listState.userHasScrolled, isTrue);
      expect(listState.nearBottom, isFalse);

      final scrollableBox =
          tester.renderObject(find.byType(ChatMessageList)) as RenderBox;
      final anchorKey = listState.readingAnchorCandidateKey!;
      final globalKey = listState.itemKeys[anchorKey]!;
      final box = globalKey.currentContext!.findRenderObject() as RenderBox;
      final actualDy = box
          .localToGlobal(Offset.zero, ancestor: scrollableBox)
          .dy;

      final initialPixels = pos.pixels;

      // 模拟上方异步布局导致锚点发生 5.0px 位移 (diff = +5.0px >= 4.0px 死区)
      listState.testSetReadingAnchor(
        candidateKey: anchorKey,
        renderId: anchorKey,
        topOffset: actualDy - 5.0,
      );

      final pixelTrace = <double>[];

      // 连续推进 30 轮流式 token
      for (var frame = 0; frame < 30; frame++) {
        api.emit(TokenSseEvent('token_$frame '));
        await tester.pump(const Duration(milliseconds: 16));
        await tester.pump(const Duration(milliseconds: 48));
        pixelTrace.add(pos.pixels);
      }

      // 验证：第 0 帧执行一次 jumpTo(pixels + 5.0) 补偿
      expect(pixelTrace.first, closeTo(initialPixels + 5.0, 0.5));

      // 验证：从第 1 帧到第 29 帧，pixels 绝对静止，不再发生任何反向跳回与周期性震荡
      final settledPixels = pixelTrace.sublist(1);
      final maxSettled = settledPixels.reduce((a, b) => a > b ? a : b);
      final minSettled = settledPixels.reduce((a, b) => a < b ? a : b);
      final settledSpan = maxSettled - minSettled;

      expect(
        settledSpan,
        lessThan(1.0),
        reason: '补偿后后续 29 帧 pixels 必须绝对静止，不得周期性震荡 (span=$settledSpan)',
      );
    });

    testWidgets('2. 用户上滑离底停留上方 + 持续 live 文本流式：全程静止零抖动 (span < 1.0px, reversals = 0)', (tester) async {
      SharedPreferences.setMockInitialValues({kTurnCollapseKey: false});
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final api = FakeChatApi()
        ..statusResponse = const ChatStreamStatusResponse(active: true);

      final messages = <Map<String, dynamic>>[];
      for (var i = 0; i < 35; i++) {
        final isLong = i % 2 == 0;
        final content = isLong
            ? '### 历史记录分析 $i\n\n'
                  '长段落文本用于撑满视口高度并产生真实卡片，'
                  '确保视口上方完全由已完成的历史消息填充。\n' *
                3
            : '短回复 $i：确认收到了上一条请求。';
        messages.add({
          'role': i.isEven ? 'user' : 'assistant',
          'content': content,
          'message_id': 'msg_$i',
        });
      }

      api.sessionResult = {
        'session': {
          'session_id': 's-streaming-jitter-test',
          'active_stream_id': 'stream-txt',
          'messages': messages,
          'message_count': messages.length,
        },
      };

      await tester.pumpWidget(
        ProviderScope(
          overrides: [chatApiProvider.overrideWithValue(api)],
          child: const CupertinoApp(
            home: ChatPage(sessionId: 's-streaming-jitter-test'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final scrollable = find.byType(Scrollable).first;
      final pos = positionOf(tester);
      final listState = stateOf(tester);

      // 上滑 350px 离底停留
      await tester.drag(scrollable, const Offset(0, 350));
      await tester.pumpAndSettle();

      expect(listState.userHasScrolled, isTrue);
      expect(listState.nearBottom, isFalse);

      final sampledPixels = <double>[pos.pixels];

      // 高频推进 40 个 live token (模拟每 32ms 一个 token 的高密流式输出)
      for (var i = 0; i < 40; i++) {
        api.emit(TokenSseEvent('token$i '));
        await tester.pump(const Duration(milliseconds: 32));
        sampledPixels.add(pos.pixels);
      }

      final maxP = sampledPixels.reduce((a, b) => a > b ? a : b);
      final minP = sampledPixels.reduce((a, b) => a < b ? a : b);
      final span = maxP - minP;

      var reversals = 0;
      double? lastDir;
      for (var i = 1; i < sampledPixels.length; i++) {
        final delta = sampledPixels[i] - sampledPixels[i - 1];
        if (delta.abs() >= 1.0) {
          final dir = delta > 0 ? 1.0 : -1.0;
          if (lastDir != null && dir != lastDir) {
            reversals++;
          }
          lastDir = dir;
        }
      }

      expect(
        span,
        lessThan(1.0),
        reason: '流式期间停留上方时 pixels 总波动跨度必须 < 1.0px (实际 span=$span)',
      );
      expect(
        reversals,
        equals(0),
        reason: '流式期间停留上方时绝对不得发生任何 y 轴方向反转抖动 (实际 reversals=$reversals)',
      );
    });

    testWidgets('3. 用户上滑离底停留上方 + 混合流式（token + tool_start + tool_complete）：全程静止零抖动', (tester) async {
      SharedPreferences.setMockInitialValues({kTurnCollapseKey: false});
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final api = FakeChatApi()
        ..statusResponse = const ChatStreamStatusResponse(active: true);

      final messages = <Map<String, dynamic>>[];
      for (var i = 0; i < 30; i++) {
        messages.add({
          'role': i.isEven ? 'user' : 'assistant',
          'content': '历史消息 $i: 段落行一\n段落行二\n段落行三',
          'message_id': 'm_$i',
        });
      }

      api.sessionResult = {
        'session': {
          'session_id': 's-mixed-stream',
          'active_stream_id': 'stream-mixed',
          'messages': messages,
          'message_count': messages.length,
        },
      };

      await tester.pumpWidget(
        ProviderScope(
          overrides: [chatApiProvider.overrideWithValue(api)],
          child: const CupertinoApp(home: ChatPage(sessionId: 's-mixed-stream')),
        ),
      );
      await tester.pumpAndSettle();

      final scrollable = find.byType(Scrollable).first;
      final pos = positionOf(tester);
      final listState = stateOf(tester);

      await tester.drag(scrollable, const Offset(0, 320));
      await tester.pumpAndSettle();

      expect(listState.userHasScrolled, isTrue);
      expect(listState.nearBottom, isFalse);

      final sampledPixels = <double>[pos.pixels];

      // 5 轮混合流式：token 增量 + 工具开始 + 工具完成
      for (var r = 0; r < 5; r++) {
        for (var t = 0; t < 3; t++) {
          api.emit(TokenSseEvent('word_${r}_$t '));
          await tester.pump(const Duration(milliseconds: 40));
          sampledPixels.add(pos.pixels);
        }

        api.emit(
          ToolStartedSseEvent(
            ToolStreamEvent(
              name: 'fetch_data',
              preview: 'query $r',
              stableId: 'tool_call_$r',
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 50));
        sampledPixels.add(pos.pixels);

        api.emit(
          ToolCompletedSseEvent(
            ToolStreamEvent(
              name: 'fetch_data',
              preview: 'done $r',
              stableId: 'tool_call_$r',
              duration: 0.5,
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 50));
        sampledPixels.add(pos.pixels);
      }

      final maxP = sampledPixels.reduce((a, b) => a > b ? a : b);
      final minP = sampledPixels.reduce((a, b) => a < b ? a : b);
      final span = maxP - minP;

      expect(span, lessThan(1.0), reason: '混合流式期间视口跨度必须 < 1.0px (实际 span=$span)');
    });

    testWidgets('4. 滚轮上滚停止后：旧锚点清除并建立新锚点，后续流式期间 pixels 维持静止', (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final api = FakeChatApi()
        ..statusResponse = const ChatStreamStatusResponse(active: true);

      final messages = List.generate(
        30,
        (i) => {
          'role': i.isEven ? 'user' : 'assistant',
          'content': '历史消息 $i: 内容用于测试滚轮停止后的锚点行为\n第二行内容\n第三行内容',
          'message_id': 'wheel_$i',
        },
      );

      api.sessionResult = {
        'session': {
          'session_id': 's-wheel-anchor-test',
          'active_stream_id': 'stream-wheel',
          'messages': messages,
          'message_count': 30,
        },
      };

      await tester.pumpWidget(
        ProviderScope(
          overrides: [chatApiProvider.overrideWithValue(api)],
          child: const CupertinoApp(
            home: ChatPage(sessionId: 's-wheel-anchor-test'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final pos = positionOf(tester);
      final listState = stateOf(tester);

      // PC 滚轮上滚多次累计 120px (模拟滚轮滚动手势)
      for (var i = 0; i < 6; i++) {
        await tester.sendEventToBinding(
          const PointerScrollEvent(
            position: Offset(400, 300),
            kind: PointerDeviceKind.mouse,
            scrollDelta: Offset(0, -20),
          ),
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
      await tester.pumpAndSettle();

      expect(listState.userHasScrolled, isTrue);
      expect(listState.nearBottom, isFalse);
      expect(listState.hasReadingAnchor, isTrue);

      final settledPixels = pos.pixels;
      final sampledPixels = <double>[settledPixels];

      // 滚轮停驻后，流式输出持续进行
      for (var t = 0; t < 25; t++) {
        api.emit(TokenSseEvent('wheel_token_$t '));
        await tester.pump(const Duration(milliseconds: 40));
        sampledPixels.add(pos.pixels);
      }

      final maxP = sampledPixels.reduce((a, b) => a > b ? a : b);
      final minP = sampledPixels.reduce((a, b) => a < b ? a : b);
      final span = maxP - minP;

      expect(
        span,
        lessThan(1.0),
        reason: '滚轮上滚停止后，后续流式期间 pixels 必须维持绝对静止 (实际 span=$span)',
      );
    });
  });
}
