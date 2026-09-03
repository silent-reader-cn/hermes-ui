import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/features/chat/chat_page.dart';
import 'package:hermes_ui/features/chat/chat_providers.dart';
import 'package:hermes_ui/features/chat/widgets/tool_call_card.dart';
import 'package:hermes_ui/features/settings/tool_group_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_chat_api.dart';

/// 回归：完成态渲染时工具折叠卡应排在正文文本「下方」而非「上方」。
///
/// 背景（2026-09-03 会话 7ea92838441b 消息 #160298 实证）：assistant 消息
/// content（「好喵，这是个新的方向/一致性问题。…」）与 tool_calls（2×read_file）
/// 同一条消息，文本在前、工具在后。但 message_bubble.dart 旧实现把工具卡
/// 无条件渲染在正文上方（注释误写「Hermes 流序：思考→工具→文本」）→ 截图
/// 看到 tools 卡在「好喵」上方。修复：text 是唯一分隔符，工具卡排文本下方。
void main() {
  Future<FakeChatApi> pumpHistorySession(
    WidgetTester tester, {
    bool coalesceTools = true,
  }) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({
      kToolGroupCoalesceKey: coalesceTools,
      kThinkGroupCoalesceKey: true,
      kHideReasoningKey: false,
    });
    final api = FakeChatApi();
    api.sessionResult = {
      'session': {
        'session_id': 's-h',
        'title': 'history',
        'active_stream_id': null,
        'messages': [
          {'role': 'user', 'content': 'hi', 'message_id': 'u1'},
          {
            'role': 'assistant',
            'content': '好喵，这是个新的方向/一致性问题。柚子先明确：先摸清侧栏工具栏和窄屏导航的实现。',
            'message_id': 'a1',
            'tool_calls': [
              {
                'id': 'call_1',
                'call_id': 'call_1',
                'type': 'function',
                'function': {
                  'name': 'read_file',
                  'arguments': '{"path": "x"}',
                },
              },
              {
                'id': 'call_2',
                'call_id': 'call_2',
                'type': 'function',
                'function': {
                  'name': 'read_file',
                  'arguments': '{"path": "y"}',
                },
              },
            ],
          },
          {'role': 'tool', 'tool_call_id': 'call_1', 'content': '{"ok":1}'},
          {'role': 'tool', 'tool_call_id': 'call_2', 'content': '{"ok":1}'},
        ],
        'message_count': 4,
      },
    };
    await tester.pumpWidget(
      ProviderScope(
        overrides: [chatApiProvider.overrideWithValue(api)],
        child: const CupertinoApp(home: ChatPage(sessionId: 's-h')),
      ),
    );
    await tester.pumpAndSettle();
    return api;
  }

  testWidgets('完成态：工具折叠卡在正文「下方」，不在「上方」', (tester) async {
    await pumpHistorySession(tester);

    // 文本与工具卡都存在
    expect(find.textContaining('好喵，这是个新的方向'), findsOneWidget);
    final toolCard = find.byType(ToolCallGroupCard);
    expect(toolCard, findsWidgets);

    // 核心断言：文本底边 < 工具卡顶边（文本在上、卡在下）
    final textTop = tester.getTopLeft(find.textContaining('好喵，这是个新的方向')).dy;
    final cardTop = tester.getTopLeft(toolCard.first).dy;
    expect(
      cardTop,
      greaterThan(textTop),
      reason: '工具卡应排在正文文本下方（text 是分隔符），实际 textTop=$textTop cardTop=$cardTop',
    );
  });
}