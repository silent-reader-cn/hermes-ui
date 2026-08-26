import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermex_flutter/core/api/sse_client.dart';
import 'package:hermex_flutter/core/models/server_catalog.dart';
import 'package:hermex_flutter/features/chat/chat_page.dart';
import 'package:hermex_flutter/features/chat/chat_providers.dart';
import 'package:hermex_flutter/features/settings/tool_group_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_chat_api.dart';

/// live 时间线：流式回合内 think/text/tools 按事件先后穿插聚合。
///
/// 数据流：SSE 事件（reasoning/token/tool_start）到达时 controller 在
/// [LiveSegmentKind] 断点记录游标 → [liveTimelineProvider] 按断点切片
/// content / liveReasoningText / liveToolCalls → 列表逐段渲染。
void main() {
  /// 进入一个「服务端已在流式」的会话（active_stream_id），等待恢复连接。
  Future<FakeChatApi> pumpStreamingSession(
    WidgetTester tester, {
    bool coalesceTools = true,
    bool coalesceThink = true,
    bool hideReasoning = false,
    List<Map<String, Object?>> transcript = const [
      {'role': 'user', 'content': 'hi', 'message_id': 'u1'},
    ],
  }) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({
      kToolGroupCoalesceKey: coalesceTools,
      kThinkGroupCoalesceKey: coalesceThink,
      kHideReasoningKey: hideReasoning,
    });
    final api = FakeChatApi()
      ..statusResponse = const ChatStreamStatusResponse(active: true);
    api.sessionResult = {
      'session': {
        'session_id': 's-live',
        'title': 'live',
        'active_stream_id': 'stream-live',
        'messages': transcript,
        'message_count': transcript.length,
      },
    };
    await tester.pumpWidget(
      ProviderScope(
        overrides: [chatApiProvider.overrideWithValue(api)],
        child: const CupertinoApp(home: ChatPage(sessionId: 's-live')),
      ),
    );
    await tester.pump(); // 加载 transcript + 状态检查微任务
    await tester.pump(const Duration(milliseconds: 30)); // 恢复连接
    expect(api.startStreamCalls, 1, reason: 'active 流应完成恢复连接');
    return api;
  }

  /// 按事件顺序驱动一段 SSE，并等待合并(16ms)/reveal(48ms) 落地。
  Future<void> drive(
    WidgetTester tester,
    FakeChatApi api,
    List<SseEvent> events,
  ) async {
    for (final event in events) {
      api.emit(event);
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 16));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 48));
    }
  }

  /// 断言一组渲染 key 按纵向从上到下的顺序出现。
  void expectVerticalOrder(WidgetTester tester, List<String> renderKeys) {
    double? previous;
    for (final key in renderKeys) {
      final finder = find.byKey(ValueKey(key));
      expect(finder, findsOneWidget, reason: '时间线条目 $key 应存在');
      final dy = tester.getTopLeft(finder).dy;
      if (previous != null) {
        expect(dy, greaterThan(previous), reason: '$key 应排在上一条目之后（按事件先后穿插）');
      }
      previous = dy;
    }
  }

  testWidgets('coalesce=false：think/text/tool 按事件到达顺序穿插', (tester) async {
    final api = await pumpStreamingSession(
      tester,
      coalesceTools: false,
      coalesceThink: false,
    );

    await drive(tester, api, [
      const ReasoningSseEvent('think1'),
      const TokenSseEvent('text1 '),
      const ToolStartedSseEvent(
        ToolStreamEvent(stableId: 't1', name: 'cd', args: {'path': 'x'}),
      ),
      const ToolCompletedSseEvent(ToolStreamEvent(stableId: 't1', name: 'cd')),
      const ReasoningSseEvent('think2'),
      const TokenSseEvent('text2'),
      const ToolStartedSseEvent(
        ToolStreamEvent(stableId: 't2', name: 'ls', args: {'p': '.'}),
      ),
    ]);

    // 断点序列号按事件到达递增：think1(1) text1(2) tools1(3) think2(4)
    // text2(5) tools2(6)；关闭聚合 → 每段独立一卡。
    expectVerticalOrder(tester, [
      'live:think:1',
      'live:text:2',
      'live:tools:3',
      'live:think:4',
      'live:text:5',
      'live:tools:6',
    ]);
    expect(find.byKey(const ValueKey('live:tools:3')), findsOneWidget);
    expect(find.byKey(const ValueKey('live:tools:6')), findsOneWidget);
  });

  testWidgets('coalesce=true：think/tool 各自整轮合并为一卡，位置取首现', (tester) async {
    final api = await pumpStreamingSession(
      tester,
      coalesceTools: true,
      coalesceThink: true,
    );

    await drive(tester, api, [
      const ReasoningSseEvent('think1'),
      const TokenSseEvent('text1 '),
      const ToolStartedSseEvent(
        ToolStreamEvent(stableId: 't1', name: 'cd', args: {'path': 'x'}),
      ),
      const ToolCompletedSseEvent(ToolStreamEvent(stableId: 't1', name: 'cd')),
      const ReasoningSseEvent('think2'),
      const TokenSseEvent('text2'),
      const ToolStartedSseEvent(
        ToolStreamEvent(stableId: 't2', name: 'ls', args: {'p': '.'}),
      ),
    ]);

    // 合并卡：think 挂首个 thinking 断点、tools 挂首个 tools 断点；text 段保留独立。
    expectVerticalOrder(tester, [
      'live:think:merged',
      'live:text:2',
      'live:tools:merged',
      'live:text:5',
    ]);
    expect(find.byKey(const ValueKey('live:text:2')), findsOneWidget);
    expect(find.byKey(const ValueKey('live:text:5')), findsOneWidget);
  });

  testWidgets('隐藏思考：think 卡不渲染，text/tools 顺序保持', (tester) async {
    final api = await pumpStreamingSession(
      tester,
      coalesceTools: false,
      coalesceThink: false,
      hideReasoning: true,
    );

    await drive(tester, api, [
      const ReasoningSseEvent('think1'),
      const TokenSseEvent('text1 '),
      const ToolStartedSseEvent(
        ToolStreamEvent(stableId: 't1', name: 'cd', args: {'path': 'x'}),
      ),
      const ReasoningSseEvent('think2'),
      const TokenSseEvent('text2'),
    ]);

    expect(find.byKey(const ValueKey('live:think:1')), findsNothing);
    expect(find.byKey(const ValueKey('live:think:4')), findsNothing);
    expectVerticalOrder(tester, ['live:text:2', 'live:tools:3', 'live:text:5']);
  });

  testWidgets('reasoning 已到时未 flush：显示思考中指示器，flush 后出卡', (tester) async {
    final api = await pumpStreamingSession(tester);

    api.emit(const ReasoningSseEvent('首个思考段'));
    await tester.pump();
    // 未到 16ms 合并 tick：断点已建但文本未落地 → 时间线空 → 指示器。
    expect(
      find.byType(CupertinoActivityIndicator),
      findsWidgets,
      reason: '流式空态显示思考中指示器',
    );

    await tester.pump(const Duration(milliseconds: 16));
    expect(find.byKey(const ValueKey('live:think:merged')), findsOneWidget);
    expect(find.textContaining('首个思考段'), findsOneWidget);
  });

  testWidgets(
      'coalesce=false：无 text 打断时 think/tool 各自聚合为一卡（text 才分隔）',
      (tester) async {
    final api = await pumpStreamingSession(
      tester,
      coalesceTools: false,
      coalesceThink: false,
    );

    // think1 → tool1 → think2 → tool2（无 text 打断：think 与 tool 互不拆卡）。
    await drive(tester, api, [
      const ReasoningSseEvent('思考段1'),
      const ToolStartedSseEvent(
        ToolStreamEvent(stableId: 't1', name: 'cd', args: {'path': 'x'}),
      ),
      const ToolCompletedSseEvent(ToolStreamEvent(stableId: 't1', name: 'cd')),
      const ReasoningSseEvent('思考段2'),
      const ToolStartedSseEvent(
        ToolStreamEvent(stableId: 't2', name: 'ls', args: {'p': '.'}),
      ),
    ]);

    // 合并结果：思考 1 张（含两段）+ 工具 1 张（含两次调用），keys 取首现。
    expectVerticalOrder(tester, ['live:think:1', 'live:tools:2']);
    // 思考卡内容包含两段合并文本。
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('live:think:1')),
        matching: find.textContaining('思考段1'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('live:think:1')),
        matching: find.textContaining('思考段2'),
      ),
      findsOneWidget,
    );
    // 工具卡合并两次调用（id 含 t1 与 t2 的标题行）。
    final toolsCard = find.byKey(const ValueKey('live:tools:2'));
    expect(toolsCard, findsOneWidget);
    expect(
      find.descendant(of: toolsCard, matching: find.textContaining('cd')),
      findsWidgets,
    );
    expect(
      find.descendant(of: toolsCard, matching: find.textContaining('ls')),
      findsWidgets,
    );
  });

  testWidgets('coalesce=false：text 打断 → think 拆成两区段各一张卡', (tester) async {
    final api = await pumpStreamingSession(
      tester,
      coalesceTools: false,
      coalesceThink: false,
    );

    await drive(tester, api, [
      const ReasoningSseEvent('思考段A'),
      const TokenSseEvent('正文1 '),
      const ReasoningSseEvent('思考段B'),
    ]);

    // text 是分隔符：thinkA 与 thinkB 分属两个区段，各自成卡。
    expectVerticalOrder(tester, [
      'live:think:1',
      'live:text:2',
      'live:think:3',
    ]);
    expect(find.byKey(const ValueKey('live:think:1')), findsOneWidget);
    expect(find.byKey(const ValueKey('live:think:3')), findsOneWidget);
  });
}
