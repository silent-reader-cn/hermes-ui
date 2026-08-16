import 'package:flutter_test/flutter_test.dart';
import 'package:hermex_flutter/core/models/chat_message.dart';
import 'package:hermex_flutter/core/models/json_value.dart';
import 'package:hermex_flutter/core/models/tool_call.dart';

void main() {
  group('ToolCall（非 JSON 模型）', () {
    test('默认构造：live-tool- 前缀 id、startedAt 当前秒', () {
      final call = ToolCall(name: 'write_file');
      expect(call.id, startsWith('live-tool-'));
      expect(call.isCompleted, false);
      expect(call.startedAt, closeTo(DateTime.now().millisecondsSinceEpoch / 1000, 5));
      expect(call.displayName, 'write_file');
      expect(ToolCall(name: '  ').displayName, 'Tool');
      expect(ToolCall().displayName, 'Tool');
    });
  });

  group('PersistedToolCall.fromJson', () {
    test('规格示例正常解析', () {
      final call = PersistedToolCall.fromJson({
        'name': 'write_file',
        'snippet': 'Wrote /tmp/a.txt',
        'tid': 'call_9',
        'assistant_msg_idx': 3,
        'args': {'path': '/tmp/a.txt'},
      });
      expect(call.name, 'write_file');
      expect(call.snippet, 'Wrote /tmp/a.txt');
      expect(call.tid, 'call_9');
      expect(call.assistantMsgIdx, 3);
      expect(call.args!['path'], const JsonString('/tmp/a.txt'));
    });

    test('assistant_msg_idx 与 camel 双键', () {
      expect(
        PersistedToolCall.fromJson({'assistantMsgIdx': 5}).assistantMsgIdx,
        5,
      );
    });

    test('畸形输入：缺失/错型 → null 容错', () {
      final call = PersistedToolCall.fromJson({
        'name': 1,
        'snippet': false,
        'tid': null,
        'assistant_msg_idx': 'oops',
        'args': 'not-an-object',
      });
      expect(call.name, '1');
      expect(call.snippet, 'false');
      expect(call.tid, isNull);
      expect(call.assistantMsgIdx, isNull);
      expect(call.args, isNull);
    });

    test('toolCall(fallbackIndex)：tid 优先，否则 persisted-tool-N', () {
      final withTid = PersistedToolCall.fromJson({'tid': ' call_1 '});
      final toolCall = withTid.toolCall(2);
      expect(toolCall.id, 'call_1');
      expect(toolCall.isCompleted, true);
      expect(toolCall.preview, withTid.snippet);

      final fallback = PersistedToolCall.fromJson({'name': 'x'}).toolCall(2);
      expect(fallback.id, 'persisted-tool-2');
    });
  });

  group('ToolCallGroup 基础', () {
    test('activityTitle / isComplete / hasFailedTool', () {
      final group = ToolCallGroup(
        anchorMessageID: 'a1',
        toolCalls: [
          ToolCall(name: 't1', isCompleted: true),
          ToolCall(name: 't2'),
        ],
      );
      expect(group.activityTitle, 'Activity: 2 tools');
      expect(group.isComplete, false);
      expect(group.hasFailedTool, false);

      final failed = ToolCallGroup(
        toolCalls: [ToolCall(isError: true, isCompleted: true)],
      );
      expect(failed.isComplete, true);
      expect(failed.hasFailedTool, true);
    });

    test('live：id = live-tools-<anchor ?? unanchored>', () {
      expect(
        ToolCallGroup.live(anchorMessageID: 'a1', toolCalls: []).id,
        'live-tools-a1',
      );
      expect(
        ToolCallGroup.live(toolCalls: []).id,
        'live-tools-unanchored',
      );
    });
  });

  group('ToolCallGroup.groups 聚合', () {
    test('groupsFromPersistedToolCalls：按 assistantMsgIdx 归组', () {
      final messages = [
        const ChatMessage(role: 'user', content: 'q', messageId: 'u1'),
        const ChatMessage(role: 'assistant', content: 'a', messageId: 'm1'),
        const ChatMessage(role: 'assistant', content: 'a', messageId: 'm2'),
      ];
      final groups = ToolCallGroup.groups(
        persistedToolCalls: [
          const PersistedToolCall(
            name: 'write_file',
            tid: 'call_1',
            assistantMsgIdx: 1,
          ),
          const PersistedToolCall(
            name: 'read_file',
            tid: 'call_2',
            assistantMsgIdx: 2,
          ),
        ],
        messages: messages,
      );
      expect(groups, hasLength(1));
      expect(groups.single.anchorMessageID, 'm1');
      expect(groups.single.toolCalls, hasLength(2));
      expect(groups.single.toolCalls[0].id, 'call_1');
      expect(groups.single.toolCalls[1].id, 'call_2');
    });

    test('无持久化调用时从消息元数据派生（OpenAI tool_calls）', () {
      final messages = [
        const ChatMessage(role: 'user', content: 'q', messageId: 'u1'),
        const ChatMessage(
          role: 'assistant',
          messageId: 'm1',
          toolCalls: [
            JsonObject({
              'id': JsonString('call_x'),
              'function': JsonObject({
                'name': JsonString('bash'),
                'arguments': JsonString('{"cmd": "ls"}'),
              }),
            }),
          ],
        ),
      ];
      final groups = ToolCallGroup.groups(
        persistedToolCalls: const [],
        messages: messages,
      );
      expect(groups, hasLength(1));
      final call = groups.single.toolCalls.single;
      expect(call.id, 'call_x');
      expect(call.name, 'bash');
      expect(call.args!['cmd'], const JsonString('ls'));
      expect(call.isCompleted, true);
    });

    test('合并 + 按 assistant 回合去重（uniqueToolCalls）', () {
      final messages = [
        const ChatMessage(role: 'user', content: 'q', messageId: 'u1'),
        const ChatMessage(
          role: 'assistant',
          messageId: 'm1',
          toolCalls: [
            JsonObject({
              'id': JsonString('call_x'),
              'function': JsonObject({
                'name': JsonString('bash'),
                'arguments': JsonString('{"cmd": "ls"}'),
              }),
            }),
          ],
        ),
      ];
      final groups = ToolCallGroup.groups(
        persistedToolCalls: [
          const PersistedToolCall(
            name: 'bash',
            tid: 'call_x',
            assistantMsgIdx: 1,
            args: {'cmd': JsonString('ls')},
          ),
        ],
        messages: messages,
      );
      expect(groups, hasLength(1));
      expect(groups.single.toolCalls, hasLength(1));
    });

    test('messageOffset 参与 raw index 换算', () {
      final messages = [
        const ChatMessage(role: 'user', content: 'q', messageId: 'u1'),
        const ChatMessage(role: 'assistant', content: 'a', messageId: 'm1'),
      ];
      final groups = ToolCallGroup.groups(
        persistedToolCalls: [
          const PersistedToolCall(name: 'x', assistantMsgIdx: 5),
        ],
        messages: messages,
        messageOffset: 4,
      );
      expect(groups, hasLength(1));
      expect(groups.single.anchorMessageID, 'm1');
    });

    test('assistantMsgIdx 越界 / 缺失 → 跳过', () {
      final messages = [
        const ChatMessage(role: 'assistant', content: 'a', messageId: 'm1'),
      ];
      final groups = ToolCallGroup.groups(
        persistedToolCalls: [
          const PersistedToolCall(name: 'x', assistantMsgIdx: 99),
          const PersistedToolCall(name: 'y'),
        ],
        messages: messages,
      );
      expect(groups, isEmpty);
    });
  });

  test('ToolCallGroupAnchorLookup', () {
    final lookup = ToolCallGroupAnchorLookup(groups: [
      ToolCallGroup(anchorMessageID: 'a', toolCalls: [ToolCall()]),
      ToolCallGroup(toolCalls: [ToolCall()]),
    ]);
    expect(lookup.groups(anchorMessageID: 'a'), hasLength(1));
    expect(lookup.groups(anchorMessageID: null), hasLength(1));
    expect(lookup.groups(anchorMessageID: 'zz'), isEmpty);
  });
}
