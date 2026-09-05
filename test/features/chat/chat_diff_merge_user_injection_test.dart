import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/models/chat_message.dart';
import 'package:hermes_ui/features/chat/chat_diff_merge.dart';

void main() {
  group('TASK #61 用户消息双气泡与服务端注入行 diff-merge 测试', () {
    test('1. RED 复现：带服务端注入标记的 server 消息与 local 乐观消息成功匹配，消除双气泡并剥离标记', () {
      const local = [
        ChatMessage(
          messageId: 'local-x',
          role: 'user',
          content: '图中出现两个先两个跑的原因是什么',
          timestamp: 100.0,
        ),
      ];

      const server = [
        ChatMessage(
          messageId: '42',
          role: 'user',
          content:
              '[Workspace::v1: D:\\projects\\hermes-ui]\n图中出现两个先两个跑的原因是什么\n\n[Attached files: C:\\a\\b.jpg]\n[screenshot]',
          timestamp: 105.0,
        ),
      ];

      final merged = diffMergeMessages(
        localMessages: local,
        serverMessages: server,
      );

      // 断言 merge 结果只有一条 user 消息
      expect(merged, hasLength(1));
      final msg = merged.first;
      expect(msg.role, 'user');
      expect(msg.messageId, '42');

      // 断言 content 不含注入标记
      expect(msg.content, isNot(contains('[Workspace::v1')));
      expect(msg.content, isNot(contains('[Attached files')));
      expect(msg.content, isNot(contains('[screenshot]')));
      expect(msg.content, '图中出现两个先两个跑的原因是什么');
    });

    test('2. 不误伤：两条内容确实不同的 user 消息（归一化后仍不等）保持双条', () {
      const local = [
        ChatMessage(
          messageId: 'local-x',
          role: 'user',
          content: '这是用户第一条问题',
          timestamp: 100.0,
        ),
      ];

      const server = [
        ChatMessage(
          messageId: '42',
          role: 'user',
          content:
              '[Workspace::v1: D:\\projects\\hermes-ui]\n这是完全不同的第二条问题\n\n[Attached files: C:\\a\\b.jpg]\n[screenshot]',
          timestamp: 105.0,
        ),
      ];

      final merged = diffMergeMessages(
        localMessages: local,
        serverMessages: server,
      );

      expect(merged, hasLength(2));
      expect(merged[0].messageId, 'local-x');
      expect(merged[1].messageId, '42');
    });

    test('3. 时间窗外（>120s）相同内容不匹配（维持既有语义）', () {
      const local = [
        ChatMessage(
          messageId: 'local-x',
          role: 'user',
          content: '图中出现两个先两个跑的原因是什么',
          timestamp: 100.0,
        ),
      ];

      const server = [
        ChatMessage(
          messageId: '42',
          role: 'user',
          content:
              '[Workspace::v1: D:\\projects\\hermes-ui]\n图中出现两个先两个跑的原因是什么\n\n[Attached files: C:\\a\\b.jpg]\n[screenshot]',
          timestamp: 300.0, // 差 200s > 120s
        ),
      ];

      final merged = diffMergeMessages(
        localMessages: local,
        serverMessages: server,
      );

      // 超过 120s 不匹配，保持双条
      expect(merged, hasLength(2));
    });

    test('4. 归一化后为空串时，保留 local.content 兜底', () {
      const local = [
        ChatMessage(
          messageId: 'local-empty-text',
          role: 'user',
          content: '',
          timestamp: 100.0,
        ),
      ];

      const server = [
        ChatMessage(
          messageId: '43',
          role: 'user',
          content:
              '[Workspace::v1: D:\\projects\\hermes-ui]\n[Attached files: C:\\a\\b.jpg]\n[screenshot]',
          timestamp: 105.0,
        ),
      ];

      final merged = diffMergeMessages(
        localMessages: local,
        serverMessages: server,
      );

      expect(merged, hasLength(1));
      expect(merged.first.messageId, '43');
      expect(merged.first.content, '');
    });

    test('5. 行内占位符不误伤，整行精确匹配才删', () {
      const local = [
        ChatMessage(
          messageId: 'local-inline',
          role: 'user',
          content: '请参考 [screenshot] 和 [image] 的说明',
          timestamp: 100.0,
        ),
      ];

      const server = [
        ChatMessage(
          messageId: '44',
          role: 'user',
          content:
              '[Workspace::v1: D:\\projects\\hermes-ui]\n请参考 [screenshot] 和 [image] 的说明\n\n[Attached files: C:\\a\\b.jpg]\n[screenshot]',
          timestamp: 105.0,
        ),
      ];

      final merged = diffMergeMessages(
        localMessages: local,
        serverMessages: server,
      );

      expect(merged, hasLength(1));
      expect(merged.first.content, '请参考 [screenshot] 和 [image] 的说明');
    });

    test('6. 容忍前导换行、转义反斜杠、大小写与行内多余空格', () {
      const local = [
        ChatMessage(
          messageId: 'local-loose',
          role: 'user',
          content: '多行测试\n第二行正文',
          timestamp: 100.0,
        ),
      ];

      const server = [
        ChatMessage(
          messageId: '45',
          role: 'user',
          content:
              '\n\n[Workspace::v1: C:\\Users\\Admin\\project (branch-x)]  \n多行测试\n第二行正文\n\n[Attached files: C:\\path with space\\image.png]  \n  [SCREENSHOT]  \n  [image]  \n  [attachment]  ',
          timestamp: 102.0,
        ),
      ];

      final merged = diffMergeMessages(
        localMessages: local,
        serverMessages: server,
      );

      expect(merged, hasLength(1));
      expect(merged.first.content, '多行测试\n第二行正文');
    });
  });
}
