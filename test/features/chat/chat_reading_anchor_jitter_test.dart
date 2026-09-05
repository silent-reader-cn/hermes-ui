import 'package:flutter/cupertino.dart';
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

  group('#56 阅读锚点抖动修复与机制单测', () {
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

    testWidgets('真实形状下离底阅读（回合折叠关）：统计像素抖动反转次数与锚点切换', (tester) async {
      SharedPreferences.setMockInitialValues({kTurnCollapseKey: false});

      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final api = FakeChatApi()
        ..statusResponse = const ChatStreamStatusResponse(active: true);

      // 构造长短悬殊的历史消息（短消息与长 markdown 交替产生显著高度方差）
      final messages = <Map<String, dynamic>>[];
      for (var i = 0; i < 40; i++) {
        final isLong = i % 3 == 0;
        final content = isLong
            ? '### 长章节分析报告 $i\n\n'
                      '这是用于模拟长 markdown 渲染的段落内容，包含代码段与列表：\n'
                      '```dart\n'
                      'void processBatch$i() {\n'
                      '  for (var k = 0; k < 15; k++) {\n'
                      '    print("Batch item \$k for report $i");\n'
                      '  }\n'
                      '}\n'
                      '```\n\n'
                      '- 重点指标 A: 正常\n'
                      '- 重点指标 B: 警告需要关注\n'
                      '- 重点指标 C: 延迟 120ms\n\n'
                      '补充说明文字段落以撑起条目高度，使其在视口进出 cacheExtent 边界时产生明显的估算高度差异。' *
                  2
            : '短回复 $i：这是一条简短的确认文本。';
        messages.add({
          'role': i.isEven ? 'user' : 'assistant',
          'content': content,
          'message_id': 'm$i',
        });
      }

      api.sessionResult = {
        'session': {
          'session_id': 's-jitter-test',
          'active_stream_id': 'stream-jitter',
          'messages': messages,
          'message_count': messages.length,
        },
      };

      await tester.pumpWidget(
        ProviderScope(
          overrides: [chatApiProvider.overrideWithValue(api)],
          child: const CupertinoApp(home: ChatPage(sessionId: 's-jitter-test')),
        ),
      );

      await tester.pumpAndSettle();

      final scrollable = find.byType(Scrollable).first;
      final pos = positionOf(tester);
      final listState = stateOf(tester);

      // 拖拽离底：多档测试使视口顶部条目贴边
      await tester.drag(scrollable, const Offset(0, 312));
      await tester.pumpAndSettle();

      expect(listState.userHasScrolled, isTrue);
      expect(listState.nearBottom, isFalse);

      final sampledPixels = <double>[];
      final anchorKeys = <String?>[];

      // 6 轮真实节奏 live 事件：token + tool_start + tool_complete
      for (var round = 0; round < 6; round++) {
        for (var t = 0; t < 4; t++) {
          api.emit(TokenSseEvent('token $round-$t '));
          await tester.pump(const Duration(milliseconds: 50));
          sampledPixels.add(pos.pixels);
          anchorKeys.add(listState.readingAnchorCandidateKey);
        }

        api.emit(
          ToolStartedSseEvent(
            ToolStreamEvent(
              name: 'execute_command',
              preview: 'run round $round',
              stableId: 'tool_$round',
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 50));
        sampledPixels.add(pos.pixels);
        anchorKeys.add(listState.readingAnchorCandidateKey);

        api.emit(
          ToolCompletedSseEvent(
            ToolStreamEvent(
              name: 'execute_command',
              preview: 'completed $round',
              stableId: 'tool_$round',
              duration: 0.8,
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 50));
        sampledPixels.add(pos.pixels);
        anchorKeys.add(listState.readingAnchorCandidateKey);
      }

      // 计算方向反转次数（幅度 >= 1.0px）
      var reversals = 0;
      double? lastDirection;
      for (var i = 1; i < sampledPixels.length; i++) {
        final delta = sampledPixels[i] - sampledPixels[i - 1];
        if (delta.abs() >= 1.0) {
          final dir = delta > 0 ? 1.0 : -1.0;
          if (lastDirection != null && dir != lastDirection) {
            reversals++;
          }
          lastDirection = dir;
        }
      }

      // 统计锚点键交替切换次数
      var anchorSwitches = 0;
      for (var i = 1; i < anchorKeys.length; i++) {
        if (anchorKeys[i] != null &&
            anchorKeys[i - 1] != null &&
            anchorKeys[i] != anchorKeys[i - 1]) {
          anchorSwitches++;
        }
      }

      expect(
        reversals,
        equals(0),
        reason: '离底阅读时不应发生像素方向反转抖动 (reversals=$reversals)',
      );
      expect(
        anchorSwitches,
        equals(0),
        reason: '流式期间阅读锚点不应在不同条目间来回横跳 (switches=$anchorSwitches)',
      );
    });

    testWidgets('真实形状下离底阅读（#55 回合折叠开）：统计像素抖动与锚点稳定性', (tester) async {
      SharedPreferences.setMockInitialValues({kTurnCollapseKey: true});

      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final api = FakeChatApi()
        ..statusResponse = const ChatStreamStatusResponse(active: true);

      final messages = <Map<String, dynamic>>[];
      for (var i = 0; i < 40; i++) {
        final isLong = i % 3 == 0;
        final content = isLong
            ? '### 长章节分析报告 $i\n\n'
                      '包含代码段与长文本：\n'
                      '```dart\n'
                      'void processBatch$i() {}\n'
                      '```\n\n'
                      '补充说明文字段落以撑起条目高度。' *
                  3
            : '短回复 $i：这是一条简短的确认文本。';
        messages.add({
          'role': i.isEven ? 'user' : 'assistant',
          'content': content,
          'message_id': 'm$i',
        });
      }

      api.sessionResult = {
        'session': {
          'session_id': 's-jitter-collapse',
          'active_stream_id': 'stream-jitter-col',
          'messages': messages,
          'message_count': messages.length,
        },
      };

      await tester.pumpWidget(
        ProviderScope(
          overrides: [chatApiProvider.overrideWithValue(api)],
          child: const CupertinoApp(
            home: ChatPage(sessionId: 's-jitter-collapse'),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final scrollable = find.byType(Scrollable).first;
      final pos = positionOf(tester);
      final listState = stateOf(tester);

      // 上滑离底
      await tester.drag(scrollable, const Offset(0, 300));
      await tester.pumpAndSettle();

      expect(listState.userHasScrolled, isTrue);
      expect(listState.nearBottom, isFalse);

      final sampledPixels = <double>[];
      final anchorKeys = <String?>[];

      for (var round = 0; round < 4; round++) {
        for (var t = 0; t < 3; t++) {
          api.emit(TokenSseEvent('token col $round-$t '));
          await tester.pump(const Duration(milliseconds: 50));
          sampledPixels.add(pos.pixels);
          anchorKeys.add(listState.readingAnchorCandidateKey);
        }
      }

      var reversals = 0;
      double? lastDirection;
      for (var i = 1; i < sampledPixels.length; i++) {
        final delta = sampledPixels[i] - sampledPixels[i - 1];
        if (delta.abs() >= 1.0) {
          final dir = delta > 0 ? 1.0 : -1.0;
          if (lastDirection != null && dir != lastDirection) {
            reversals++;
          }
          lastDirection = dir;
        }
      }

      var anchorSwitches = 0;
      for (var i = 1; i < anchorKeys.length; i++) {
        if (anchorKeys[i] != null &&
            anchorKeys[i - 1] != null &&
            anchorKeys[i] != anchorKeys[i - 1]) {
          anchorSwitches++;
        }
      }

      expect(reversals, equals(0));
      expect(anchorSwitches, equals(0));
    });

    testWidgets('方向 A 锚点准入：顶部只露一条缝的贴边条目跳过，选中下一个充足可见条目', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final api = FakeChatApi()
        ..statusResponse = const ChatStreamStatusResponse(active: false);

      final messages = List.generate(
        30,
        (i) => {
          'role': i.isEven ? 'user' : 'assistant',
          'content': i == 3
              ? '长消息 3：\n第一行说明\n第二行说明\n第三行说明\n第四行说明，用于撑大自身高度以测试准入准则'
              : '消息 $i：普通内容',
          'message_id': 'm$i',
        },
      );

      api.sessionResult = {
        'session': {
          'session_id': 's-admission-test',
          'messages': messages,
          'message_count': 30,
        },
      };

      await tester.pumpWidget(
        ProviderScope(
          overrides: [chatApiProvider.overrideWithValue(api)],
          child: const CupertinoApp(
            home: ChatPage(sessionId: 's-admission-test'),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final scrollable = find.byType(Scrollable).first;
      final listState = stateOf(tester);

      // 上滑离底 400px
      await tester.drag(scrollable, const Offset(0, 400));
      await tester.pumpAndSettle();

      final scrollableBox =
          tester.renderObject(find.byType(ChatMessageList)) as RenderBox;

      // 验证阅读锚点存在
      expect(listState.hasReadingAnchor, isTrue);

      // 直接单测 _updateReadingAnchor 对贴边条目的准入过滤逻辑：
      // 人工微调滚动位置，使某条目处于贴边一条缝状态（露 5px，小于 24px 且小于条目高度 1/3）
      final anchorKey = listState.readingAnchorCandidateKey!;
      final globalKey = listState.itemKeys[anchorKey]!;
      final box = globalKey.currentContext!.findRenderObject() as RenderBox;
      final anchorDy = box
          .localToGlobal(Offset.zero, ancestor: scrollableBox)
          .dy;

      final pos = positionOf(tester);
      final deltaToMakeSliver = anchorDy + box.size.height - 5.0;
      if (deltaToMakeSliver > 0 && box.size.height > 20.0) {
        pos.jumpTo(pos.pixels + deltaToMakeSliver);
        await tester.pump();
        listState.testUpdateReadingAnchor();

        // 准入过滤应使新选出的锚点不是该贴边条目，而是其下一个条目
        expect(
          listState.readingAnchorCandidateKey,
          isNot(equals(anchorKey)),
          reason: '微调至只露 5px 缝隙后，该条目必须被跳过，选择下一个稳定条目',
        );
      }
    });

    testWidgets('方向 B 补偿死区：diff < 4px 不触发 jumpTo，diff >= 4px 触发补偿', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final api = FakeChatApi()
        ..statusResponse = const ChatStreamStatusResponse(active: false);

      final messages = List.generate(
        30,
        (i) => {
          'role': i.isEven ? 'user' : 'assistant',
          'content': '消息 $i：测试死区与补偿',
          'message_id': 'm$i',
        },
      );

      api.sessionResult = {
        'session': {
          'session_id': 's-deadzone-test',
          'messages': messages,
          'message_count': 30,
        },
      };

      await tester.pumpWidget(
        ProviderScope(
          overrides: [chatApiProvider.overrideWithValue(api)],
          child: const CupertinoApp(
            home: ChatPage(sessionId: 's-deadzone-test'),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final scrollable = find.byType(Scrollable).first;
      final pos = positionOf(tester);
      final listState = stateOf(tester);

      await tester.drag(scrollable, const Offset(0, 300));
      await tester.pumpAndSettle();

      final scrollableBox =
          tester.renderObject(find.byType(ChatMessageList)) as RenderBox;

      // 获取当前锚点对应的真实 RenderBox
      final anchorKey = listState.readingAnchorCandidateKey!;
      final globalKey = listState.itemKeys[anchorKey]!;
      final box = globalKey.currentContext!.findRenderObject() as RenderBox;
      final actualDy = box
          .localToGlobal(Offset.zero, ancestor: scrollableBox)
          .dy;

      final initialPixels = pos.pixels;

      // 1. 设置 topOffset 制造 diff = 2.0px (< 4.0px 死区)
      listState.testSetReadingAnchor(
        candidateKey: anchorKey,
        renderId: anchorKey,
        topOffset: actualDy - 2.0, // currentDy - topOffset = +2.0
      );

      listState.testMaybeRestoreReadingAnchor();
      await tester.pump();

      expect(
        pos.pixels,
        equals(initialPixels),
        reason: 'diff < 4px 在死区内，不得触发 jumpTo 补偿',
      );

      // 2. 设置 topOffset 制造 diff = 6.0px (>= 4.0px 超出死区)
      listState.testSetReadingAnchor(
        candidateKey: anchorKey,
        renderId: anchorKey,
        topOffset: actualDy - 6.0, // currentDy - topOffset = +6.0
      );

      listState.testMaybeRestoreReadingAnchor();
      await tester.pump();

      expect(
        pos.pixels,
        closeTo(initialPixels + 6.0, 0.5),
        reason: 'diff >= 4px 超出死区，应执行 jumpTo(pixels + diff) 补偿',
      );
    });

    testWidgets('方向 B 防抖锁：同锚点连续反向补偿触发冻结 10 帧', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final api = FakeChatApi()
        ..statusResponse = const ChatStreamStatusResponse(active: false);

      final messages = List.generate(
        30,
        (i) => {
          'role': i.isEven ? 'user' : 'assistant',
          'content': '消息 $i：测试防抖锁',
          'message_id': 'm$i',
        },
      );

      api.sessionResult = {
        'session': {
          'session_id': 's-anti-shake-test',
          'messages': messages,
          'message_count': 30,
        },
      };

      await tester.pumpWidget(
        ProviderScope(
          overrides: [chatApiProvider.overrideWithValue(api)],
          child: const CupertinoApp(
            home: ChatPage(sessionId: 's-anti-shake-test'),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final scrollable = find.byType(Scrollable).first;
      final pos = positionOf(tester);
      final listState = stateOf(tester);

      await tester.drag(scrollable, const Offset(0, 300));
      await tester.pumpAndSettle();

      final scrollableBox =
          tester.renderObject(find.byType(ChatMessageList)) as RenderBox;

      final anchorKey = listState.readingAnchorCandidateKey!;
      final globalKey = listState.itemKeys[anchorKey]!;
      final box = globalKey.currentContext!.findRenderObject() as RenderBox;

      // 1. 第一次正向补偿 diff = +5.0px (方向 +1.0)
      final actualDy1 = box
          .localToGlobal(Offset.zero, ancestor: scrollableBox)
          .dy;
      listState.testSetReadingAnchor(
        candidateKey: anchorKey,
        renderId: anchorKey,
        topOffset: actualDy1 - 5.0,
      );
      listState.testMaybeRestoreReadingAnchor();
      await tester.pump();

      expect(listState.lastAnchorCompensationDirection, equals(1.0));
      expect(listState.anchorFreezeRemainingFrames, equals(0));

      // 2. 第二次反向补偿 diff = -5.0px (方向 -1.0，反号震荡！)
      final actualDy2 = box
          .localToGlobal(Offset.zero, ancestor: scrollableBox)
          .dy;
      listState.testSetReadingAnchor(
        candidateKey: anchorKey,
        renderId: anchorKey,
        topOffset: actualDy2 + 5.0, // currentDy - topOffset = -5.0
      );
      final pixelsBeforeSecond = pos.pixels;

      listState.testMaybeRestoreReadingAnchor();
      await tester.pump();

      // 应触发防抖锁冻结 10 帧，且不得执行反向 jumpTo
      expect(
        listState.anchorFreezeRemainingFrames,
        equals(10),
        reason: '连续反号补偿应触发防抖锁冻结 10 帧',
      );
      expect(pos.pixels, equals(pixelsBeforeSecond), reason: '触发防抖锁时不应执行反向跳转');

      // 3. 冻结期间后续帧跳过补偿并逐帧递减
      listState.testMaybeRestoreReadingAnchor();
      await tester.pump();
      expect(listState.anchorFreezeRemainingFrames, equals(9));
    });

    testWidgets('方向 C 锚点稳定性：出树 <= 5 帧保留旧锚点，超时才降级重选', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final api = FakeChatApi()
        ..statusResponse = const ChatStreamStatusResponse(active: false);

      final messages = List.generate(
        30,
        (i) => {
          'role': i.isEven ? 'user' : 'assistant',
          'content': '消息 $i：测试稳定性',
          'message_id': 'm$i',
        },
      );

      api.sessionResult = {
        'session': {
          'session_id': 's-stability-test',
          'messages': messages,
          'message_count': 30,
        },
      };

      await tester.pumpWidget(
        ProviderScope(
          overrides: [chatApiProvider.overrideWithValue(api)],
          child: const CupertinoApp(
            home: ChatPage(sessionId: 's-stability-test'),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final scrollable = find.byType(Scrollable).first;
      final listState = stateOf(tester);

      await tester.drag(scrollable, const Offset(0, 300));
      await tester.pumpAndSettle();

      // 人工设置一个出树的 fake 锚点键
      listState.testSetReadingAnchor(
        candidateKey: 'transcript:fake_unmounted',
        renderId: 'transcript:fake_unmounted',
        topOffset: -100.0,
      );

      // 连续 5 帧调用：由于出树在 5 帧以内，锚点必须保留不换
      for (var f = 1; f <= 5; f++) {
        listState.testMaybeRestoreReadingAnchor();
        await tester.pump();
        expect(listState.anchorMissingFrames, equals(f));
        expect(
          listState.readingAnchorCandidateKey,
          equals('transcript:fake_unmounted'),
          reason: '出树 <= 5 帧期间必须保留旧锚点',
        );
      }

      // 第 6 帧调用（超过 5 帧容忍）：超时降级，重选视口内稳定条目
      listState.testMaybeRestoreReadingAnchor();
      await tester.pump();

      expect(listState.anchorMissingFrames, equals(0));
      expect(
        listState.readingAnchorCandidateKey,
        isNot(equals('transcript:fake_unmounted')),
        reason: '超过 5 帧超时后必须降级更新到新的视口条目',
      );
    });
  });
}
