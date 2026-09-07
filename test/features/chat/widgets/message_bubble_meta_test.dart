import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/models/chat_message.dart';
import 'package:hermes_ui/features/chat/widgets/message_bubble.dart';

void main() {
  group('#83 formatMessageTimestamp 纯函数测试', () {
    test('当天时间戳格式化为 HH:mm', () {
      final now = DateTime(2026, 9, 7, 14, 30);
      final sameDayDate = DateTime(2026, 9, 7, 9, 5);
      final ts = sameDayDate.millisecondsSinceEpoch / 1000.0;

      final result = formatMessageTimestamp(ts, now: now);
      expect(result, '09:05');
    });

    test('跨天时间戳格式化为 MM-dd HH:mm', () {
      final now = DateTime(2026, 9, 7, 10, 0);
      final crossDayDate = DateTime(2026, 9, 6, 23, 45);
      final ts = crossDayDate.millisecondsSinceEpoch / 1000.0;

      final result = formatMessageTimestamp(ts, now: now);
      expect(result, '09-06 23:45');
    });

    test('跨年或不同月份补零格式化', () {
      final now = DateTime(2026, 9, 7, 10, 0);
      final pastDate = DateTime(2025, 1, 2, 3, 4);
      final ts = pastDate.millisecondsSinceEpoch / 1000.0;

      final result = formatMessageTimestamp(ts, now: now);
      expect(result, '01-02 03:04');
    });

    test('无效或边界时间戳返回空字符串', () {
      expect(formatMessageTimestamp(0), '');
      expect(formatMessageTimestamp(-100), '');
      expect(formatMessageTimestamp(double.nan), '');
      expect(formatMessageTimestamp(double.infinity), '');
      expect(formatMessageTimestamp(double.negativeInfinity), '');
    });
  });

  group('#83 ChatMessageBubble meta 行渲染测试', () {
    testWidgets('同时具备 turnTps 与 timestamp 时渲染 Row 且包含两段与分隔符', (tester) async {
      final msgDate = DateTime(2026, 9, 7, 15, 30);
      final ts = msgDate.millisecondsSinceEpoch / 1000.0;

      final message = ChatMessage(
        role: 'assistant',
        content: '你好，我是助手。',
        turnTps: 18.5,
        timestamp: ts,
      );

      await tester.pumpWidget(
        CupertinoApp(
          home: CupertinoPageScaffold(
            child: ChatMessageBubble(message: message),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final expectedTime = formatMessageTimestamp(ts);
      expect(find.text('18.5 tok/s · $expectedTime'), findsOneWidget);
    });

    testWidgets('仅具备 turnTps 时渲染 Row 且仅展示 tok/s', (tester) async {
      const message = ChatMessage(
        role: 'assistant',
        content: '你好，我是助手。',
        turnTps: 22.0,
      );

      await tester.pumpWidget(
        const CupertinoApp(
          home: CupertinoPageScaffold(
            child: ChatMessageBubble(message: message),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('22.0 tok/s'), findsOneWidget);
      expect(find.textContaining('·'), findsNothing);
    });

    testWidgets('仅具备 timestamp 时不渲染 meta 行（时间不独立出现，与 tok/s 对齐）', (tester) async {
      final msgDate = DateTime(2026, 9, 7, 11, 20);
      final ts = msgDate.millisecondsSinceEpoch / 1000.0;

      final message = ChatMessage(
        role: 'assistant',
        content: '你好，我是助手。',
        timestamp: ts,
      );

      await tester.pumpWidget(
        CupertinoApp(
          home: CupertinoPageScaffold(
            child: ChatMessageBubble(message: message),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final expectedTime = formatMessageTimestamp(ts);
      expect(find.text(expectedTime), findsNothing);
      expect(find.textContaining('tok/s'), findsNothing);
    });

    testWidgets('两段都无时不渲染 meta 行', (tester) async {
      const message = ChatMessage(
        role: 'assistant',
        content: '你好，我是助手。',
      );

      await tester.pumpWidget(
        const CupertinoApp(
          home: CupertinoPageScaffold(
            child: ChatMessageBubble(message: message),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('tok/s'), findsNothing);
    });
  });
}
