// fullReconnect 重放场景：断线重连恢复已 flush 的流式回合后，重放帧
// （run journal 从 0 全量重放）会被客户端去重吞噬（内容已在 transcript），
// 不再追加）——但**断点必须重建**，否则 liveTimelinePoints 为空 + 归档锚定
// → liveTimelineProvider 返回 null → 回退旧分组式气泡（正文整块在上、工具卡沉底）。
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

void main() {
  /// 进入一个「服务端已有流式且 transcript 已含部分内容」的会话：首次恢复
  /// （active_stream_id）即 fullReconnect（从 0 重放 run journal）。
  Future<FakeChatApi> pumpReconnectSession(
    WidgetTester tester, {
    bool coalesceTools = false,
    bool coalesceThink = false,
    bool hideReasoning = false,
  }) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({
      kToolGroupCoalesceKey: coalesceTools,
      kThinkGroupCoalesceKey: coalesceThink,
      kHideReasoningKey: hideReasoning,
    });
    final api = FakeChatApi()..statusResponse = const ChatStreamStatusResponse(active: true);
    api.sessionResult = {
      'session': {
        'session_id': 's-reconnect',
        'title': 'reconnect',
        'active_stream_id': 'stream-reconnect',
        // transcript 已含「文本1 文本2」整段（断线前已 flush 到服务端）。
        'messages': [
          {'role': 'user', 'content': 'hi', 'message_id': 'u1'},
          {'role': 'assistant', 'content': '文本1 文本2', 'message_id': 'a1'},
        ],
        'message_count': 2,
      },
    };
    await tester.pumpWidget(
      ProviderScope(
        overrides: [chatApiProvider.overrideWithValue(api)],
        child: const CupertinoApp(home: ChatPage(sessionId: 's-reconnect')),
      ),
    );
    await tester.pump(); // 加载 transcript + 状态检查微任务
    await tester.pump(const Duration(milliseconds: 30)); // 恢复连接（fullReconnect）
    expect(api.startStreamCalls, 1, reason: 'active 流应完成恢复连接');
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

  testWidgets('fullReconnect：重放帧去重命中但重建断点，live 时间线恢复 text/tools 穿插', (tester) async {
    final api = await pumpReconnectSession(tester, coalesceTools: false);

    // 模拟 run journal 从 0 全量重放：文本帧全部命中已 flush 的 transcript（去重
    // 吞噬）→ 内容不追加，但修复前断点不重建 → 时间线回退 legacy（沉底）。
    // 工具帧走正常路径重新 append 回 liveToolCalls（并打 tools 点）。
    await drive(tester, api, [
      const TokenSseEvent('文本1 '),
      const ToolStartedSseEvent(
        ToolStreamEvent(stableId: 't1', name: 'terminal', args: {'command': 'grep'}),
      ),
      const ToolCompletedSseEvent(ToolStreamEvent(stableId: 't1', name: 'terminal')),
      const TokenSseEvent('文本2'),
      const ToolStartedSseEvent(
        ToolStreamEvent(stableId: 't2', name: 'terminal', args: {'command': 'ls'}),
      ),
    ]);

    // 断点重建：text@0（文本1）→ tools@0（t1）→ text@4（文本2）→ tools@1（t2）。
    // renderKey 序列按打点 sequence 递增 = 事件时间线。
    expectVerticalOrder(tester, [
      'live:text:1',
      'live:tools:2',
      'live:text:3',
      'live:tools:4',
    ]);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('live:text:1')),
        matching: find.textContaining('文本1'),
      ),
      findsOneWidget,
      reason: '文本1 应显示在时间线首段',
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('live:text:3')),
        matching: find.textContaining('文本2'),
      ),
      findsOneWidget,
      reason: '文本2 应显示在时间线第三段',
    );
  });

  }