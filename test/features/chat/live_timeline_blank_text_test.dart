import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/api/sse_client.dart';
import 'package:hermes_ui/core/models/server_catalog.dart';
import 'package:hermes_ui/features/chat/chat_page.dart';
import 'package:hermes_ui/features/chat/chat_providers.dart';
import 'package:hermes_ui/features/settings/tool_group_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_chat_api.dart';

/// #62：live 时间线中「空白 text 段」不得切断相邻工具卡。
///
/// 模型在工具调用间隙常吐 '\n\n' / 空格 token（interim 分隔符同理），
/// 这类段落在事件流里产生 text 断点，但渲染为零高度隐形文本。旧逻辑对
/// 每个 text 断点无条件 flushBlock → 相邻工具被看不见的文本劈成一排
/// 「连续四张 tools 折叠卡」。修复语义：仅**可见**文本段才是分隔符。
void main() {
  Future<FakeChatApi> pumpStreamingSession(
    WidgetTester tester, {
    bool coalesceTools = false,
  }) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({
      kToolGroupCoalesceKey: coalesceTools,
      kThinkGroupCoalesceKey: true,
      kHideReasoningKey: false,
    });
    final api = FakeChatApi()
      ..statusResponse = const ChatStreamStatusResponse(active: true);
    api.sessionResult = {
      'session': {
        'session_id': 's-live',
        'title': 'live',
        'active_stream_id': 'stream-live',
        'messages': const [
          {'role': 'user', 'content': 'hi', 'message_id': 'u1'},
        ],
        'message_count': 1,
      },
    };
    await tester.pumpWidget(
      ProviderScope(
        overrides: [chatApiProvider.overrideWithValue(api)],
        child: const CupertinoApp(home: ChatPage(sessionId: 's-live')),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    expect(api.startStreamCalls, 1);
    return api;
  }

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

  testWidgets('coalesce=false：工具间的空白 token 不切卡，相邻工具合并一张', (
    tester,
  ) async {
    final api = await pumpStreamingSession(tester);

    await drive(tester, api, [
      const TokenSseEvent('A'),
      const ToolStartedSseEvent(
        ToolStreamEvent(stableId: 't1', name: 'cd', args: {'path': 'x'}),
      ),
      const ToolCompletedSseEvent(ToolStreamEvent(stableId: 't1', name: 'cd')),
      const TokenSseEvent('\n\n'),
      const ToolStartedSseEvent(
        ToolStreamEvent(stableId: 't2', name: 'ls', args: {'p': '.'}),
      ),
      const ToolCompletedSseEvent(ToolStreamEvent(stableId: 't2', name: 'ls')),
      const TokenSseEvent(' '),
      const ToolStartedSseEvent(
        ToolStreamEvent(stableId: 't3', name: 'pwd', args: {}),
      ),
    ]);

    // 断点序：text(A)=1 tools(t1)=2 text(\n\n)=3 tools(t2)=4 text(' ')=5
    // tools(t3)=6。修复后：3/5 为空白段 → 不 flush 不渲染 → t1/t2/t3 同卡。
    expect(find.byKey(const ValueKey('live:tools:2')), findsOneWidget);
    expect(find.byKey(const ValueKey('live:tools:4')), findsNothing);
    expect(find.byKey(const ValueKey('live:tools:6')), findsNothing);
    expect(find.byKey(const ValueKey('live:text:3')), findsNothing);
    expect(find.byKey(const ValueKey('live:text:5')), findsNothing);
    // 可见文本段保留。
    expect(find.byKey(const ValueKey('live:text:1')), findsOneWidget);
    // 合并卡内含三个工具行。
    final card = find.byKey(const ValueKey('live:tools:2'));
    await tester.tap(card);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.descendant(of: card, matching: find.textContaining('cd')),
      findsWidgets,
    );
    expect(
      find.descendant(of: card, matching: find.textContaining('ls')),
      findsWidgets,
    );
    expect(
      find.descendant(of: card, matching: find.textContaining('pwd')),
      findsWidgets,
    );
  });

  testWidgets('回归：可见文本仍切断相邻工具卡（穿插语义不误伤）', (
    tester,
  ) async {
    final api = await pumpStreamingSession(tester);

    await drive(tester, api, [
      const ToolStartedSseEvent(
        ToolStreamEvent(stableId: 't1', name: 'cd', args: {'path': 'x'}),
      ),
      const ToolCompletedSseEvent(ToolStreamEvent(stableId: 't1', name: 'cd')),
      const TokenSseEvent('中间有正文'),
      const ToolStartedSseEvent(
        ToolStreamEvent(stableId: 't2', name: 'ls', args: {'p': '.'}),
      ),
    ]);

    // 断点序：tools(t1)=1、text(中间有正文)=2、tools(t2)=3 → t1 与 t2 之间
    // 被可见文本分隔 → 两张卡 + 中间文本段。
    expect(find.byKey(const ValueKey('live:text:2')), findsOneWidget);
    expect(find.byKey(const ValueKey('live:tools:1')), findsOneWidget);
    expect(find.byKey(const ValueKey('live:tools:3')), findsOneWidget);
  });

  testWidgets('coalesce=true：空白段场景仍整轮一张 merged 卡（不受影响）', (
    tester,
  ) async {
    final api = await pumpStreamingSession(tester, coalesceTools: true);

    await drive(tester, api, [
      const TokenSseEvent('A'),
      const ToolStartedSseEvent(
        ToolStreamEvent(stableId: 't1', name: 'cd', args: {'path': 'x'}),
      ),
      const TokenSseEvent('\n\n'),
      const ToolStartedSseEvent(
        ToolStreamEvent(stableId: 't2', name: 'ls', args: {'p': '.'}),
      ),
    ]);

    expect(find.byKey(const ValueKey('live:tools:merged')), findsOneWidget);
  });
}
