import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermex_flutter/core/models/chat_message.dart';
import 'package:hermex_flutter/core/models/message_attachment.dart';

void main() {
  group('ChatMessage.fromJson 正常解析', () {
    test('规格示例：字符串 content + 附件 + tool_calls', () {
      final json = jsonDecode('''
      {
        "role": "assistant",
        "content": [{"type": "text", "text": "完成了。"}],
        "_ts": 1723700000.5,
        "message_id": "msg-42",
        "tool_calls": [{"id": "call_1", "function": {"name": "write_file", "arguments": "{\\"path\\":\\"/tmp/a.txt\\"}"}}],
        "_turnTps": 12.3,
        "attachments": [{"name": "a.png", "path": "/tmp/a.png", "mime": "image/png", "size": 1024, "is_image": true}]
      }
      ''');
      final message = ChatMessage.fromJson(Map<String, Object?>.from(json));
      expect(message.role, 'assistant');
      expect(message.content, '完成了。');
      expect(message.timestamp, 1723700000.5);
      expect(message.messageId, 'msg-42');
      expect(message.turnTps, 12.3);
      expect(message.toolCalls, isNotNull);
      expect(message.toolCalls!.length, 1);
      expect(message.contentParts, isNotNull);
      expect(message.contentParts!.length, 1);
      expect(message.attachments, isNotNull);
      expect(message.attachments!.single.name, 'a.png');
      expect(message.attachments!.single.isImage, true);
      expect(message.id, 'msg-42');
    });

    test('字符串 content 直接取用', () {
      final message = ChatMessage.fromJson({'role': 'user', 'content': '你好'});
      expect(message.content, '你好');
      expect(message.contentParts, isNull);
    });

    test('非字符串 content（对象）→ compactJsonString', () {
      // Dart jsonEncode 把 double 1.0 编码为 1.0
      final message = ChatMessage.fromJson({'content': {'a': 1}});
      expect(message.content, '{"a":1.0}');
      expect(message.contentParts, isNull);
    });

    test('数字 content 经 lossyString 转字符串', () {
      final message = ChatMessage.fromJson({'content': 42});
      expect(message.content, '42');
    });

    test('_ts 优先于 timestamp（Swift 顺序）', () {
      final message = ChatMessage.fromJson({'_ts': 1.0, 'timestamp': 2.0});
      expect(message.timestamp, 1.0);
      final message2 = ChatMessage.fromJson({'timestamp': 2.0});
      expect(message2.timestamp, 2.0);
    });

    test('裸字符串附件形态', () {
      final message = ChatMessage.fromJson({
        'attachments': ['legacy_a.txt', {'name': 'b.png', 'path': '/x/b.png'}],
      });
      expect(message.attachments!.length, 2);
      expect(message.attachments![0].name, 'legacy_a.txt');
      expect(message.attachments![1].name, 'b.png');
    });

    test('reasoning 多键名容错与 contentParts / thinking 标签提取', () {
      final m1 = ChatMessage.fromJson({
        'role': 'assistant',
        'content': 'hello',
        'reasoning_content': 'thought process 1',
      });
      expect(m1.reasoning, 'thought process 1');

      final m2 = ChatMessage.fromJson({
        'role': 'assistant',
        'content': 'hello',
        'thought': 'thought process 2',
      });
      expect(m2.reasoning, 'thought process 2');

      final m3 = ChatMessage.fromJson({
        'role': 'assistant',
        'content': [
          {'type': 'thinking', 'thinking': 'parts thinking'},
          {'type': 'text', 'text': 'final text'},
        ],
      });
      expect(m3.reasoning, 'parts thinking');
      expect(m3.content, 'final text');

      final m4 = ChatMessage.fromJson({
        'role': 'assistant',
        'content': '<thinking>\ntag thinking\n</thinking>\nclean answer',
      });
      expect(m4.reasoning, 'tag thinking');
      expect(m4.content, 'clean answer');
    });
  });

  group('ChatMessage.fromJson 畸形输入', () {
    test('字段缺失 → 全 null 不 crash', () {
      final message = ChatMessage.fromJson(const <String, Object?>{});
      expect(message.role, isNull);
      expect(message.content, isNull);
      expect(message.timestamp, isNull);
      expect(message.messageId, isNull);
      expect(message.attachments, isNull);
      // 与 Swift 一致：`timestamp ?? 0` 在 Double 上下文里是 0.0，转字符串为 '0.0'
      expect(message.id, 'null-0.0-');
    });

    test('类型不符 → lossy 容错', () {
      final message = ChatMessage.fromJson({
        'role': 7,
        'content': false,
        'message_id': 3.5,
        'tool_calls': 'not-a-list',
        'reasoning': {'x': 1},
      });
      expect(message.role, '7');
      expect(message.content, 'false');
      expect(message.messageId, '3.5');
      expect(message.toolCalls, isNull);
      expect(message.reasoning, isNull);
    });

    test('attachments 坏元素丢弃不拖垮整体（慢路径兜底）', () {
      final message = ChatMessage.fromJson({
        'attachments': [
          {'name': 'ok.png', 'path': '/x/ok.png'},
          12345,
          'bare.txt',
        ],
      });
      expect(message.attachments, isNotNull);
      expect(message.attachments!.length, 2);
      expect(message.attachments![0].name, 'ok.png');
      expect(message.attachments![1].name, 'bare.txt');
    });

    test('content 部件数组含坏元素 → 文本拼接过滤', () {
      final message = ChatMessage.fromJson({
        'content': [
          {'type': 'text', 'text': '第一段'},
          '第二段',
          {'type': 'image', 'text': '不应取'},
          42,
        ],
      });
      expect(message.content, '第一段第二段');
      expect(message.contentParts!.length, 4);
    });

    test('attachments 与 [Attached files: …] 标记合并补全 path', () {
      final message = ChatMessage.fromJson({
        'content': '完成\n\n[Attached files: /tmp/a.png]',
        'attachments': [
          {'name': 'a.png', 'mime': 'image/png', 'size': 100, 'is_image': false},
        ],
      });
      final attachment = message.attachments!.single;
      expect(attachment.name, 'a.png');
      expect(attachment.path, '/tmp/a.png');
      expect(attachment.mime, 'image/png');
      expect(attachment.size, 100);
      // 标记只补缺失字段：is_image 显式为 false 时保留 false（对齐 Swift ?? 语义）
      expect(attachment.isImage, false);
    });
  });

  group('TranscriptTurnClassifier', () {
    ChatMessage user(String text) =>
        ChatMessage(role: 'user', content: text, messageId: 'u-$text');
    ChatMessage assistant(String id) =>
        ChatMessage(role: 'assistant', content: 'a', messageId: id);

    test('isUserTurnBoundary：user 且有可见内容或附件', () {
      expect(TranscriptTurnClassifier.isUserTurnBoundary(user('hi')), true);
      expect(
        TranscriptTurnClassifier.isUserTurnBoundary(
          const ChatMessage(role: 'user', content: '   '),
        ),
        false,
      );
      expect(
        TranscriptTurnClassifier.isUserTurnBoundary(
          const ChatMessage(role: 'user', attachments: [
            MessageAttachment(name: 'a.png'),
          ]),
        ),
        true,
      );
      expect(
        TranscriptTurnClassifier.isUserTurnBoundary(assistant('a1')),
        false,
      );
    });

    test('isToolResultOnlyMessage：user 且无可见内容', () {
      expect(
        TranscriptTurnClassifier.isToolResultOnlyMessage(
          const ChatMessage(role: 'user', content: '  '),
        ),
        true,
      );
      expect(
        TranscriptTurnClassifier.isToolResultOnlyMessage(user('hi')),
        false,
      );
    });

    test('anchorID：messageId 优先，否则 raw:offset+index', () {
      final messages = [assistant('m1'), assistant('m2')];
      expect(
        TranscriptTurnClassifier.anchorID(messages[0], at: 0),
        'm1',
      );
      final noId = const ChatMessage(role: 'assistant', content: 'x');
      expect(TranscriptTurnClassifier.anchorID(noId, at: 3, messageOffset: 10), 'raw:13');
    });

    test('assistantTurnKeysByAnchorID：回合 key 划分', () {
      final messages = [
        user('q1'),
        assistant('a1'),
        assistant('a2'),
        user('q2'),
        assistant('a3'),
      ];
      final keys = TranscriptTurnClassifier.assistantTurnKeysByAnchorID(messages);
      expect(keys['a1'], 'turn:user:0');
      expect(keys['a2'], 'turn:user:0');
      expect(keys['a3'], 'turn:user:3');
    });

    test('assistantAnchorID：前后查找同回合 assistant', () {
      final messages = [
        user('q1'),
        assistant('a1'),
        assistant('a2'),
        user('q2'),
      ];
      expect(TranscriptTurnClassifier.assistantAnchorID(1, messages), 'a1');
      // 消息本身就是 assistant → 返回自己的 anchor（对齐 Swift）
      expect(TranscriptTurnClassifier.assistantAnchorID(2, messages), 'a2');
      expect(TranscriptTurnClassifier.assistantAnchorID(0, messages), 'a1');
      // 用户边界自身也在上一回合内，向前找到 a2（对齐 Swift 实现细节）
      expect(TranscriptTurnClassifier.assistantAnchorID(3, messages), 'a2');
      expect(TranscriptTurnClassifier.assistantAnchorID(9, messages), isNull);
    });

    test('currentTurnAssistantAnchorIDs：最后一个用户边界之后', () {
      final messages = [
        user('q1'),
        assistant('a1'),
        user('q2'),
        assistant('a2'),
        assistant('a3'),
      ];
      expect(
        TranscriptTurnClassifier.currentTurnAssistantAnchorIDs(messages),
        ['a2', 'a3'],
      );
    });
  });

  test('== / hashCode / toString', () {
    final a = ChatMessage.fromJson({'role': 'user', 'content': 'x'});
    final b = ChatMessage.fromJson({'role': 'user', 'content': 'x'});
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a.toString(), contains('ChatMessage'));
  });
}
