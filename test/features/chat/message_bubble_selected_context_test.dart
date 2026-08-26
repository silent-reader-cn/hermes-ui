import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/models/chat_message.dart';
import 'package:hermes_ui/features/chat/widgets/message_bubble.dart';
import 'package:hermes_ui/features/chat/widgets/selected_context_card.dart';

Widget _wrap(Widget child) {
  return CupertinoApp(home: CupertinoPageScaffold(child: child));
}

void main() {
  group('ChatMessageBubble SelectedContext 集成', () {
    testWidgets('user 消息：解析后卡片可见，cleanText 渲染', (tester) async {
      const raw = '请解释一下\n\n'
          '**Context 1:**\n'
          '<!-- hermes-selected-context -->\n'
          '> hello\n'
          '> world\n\n';
      const msg = ChatMessage(role: 'user', content: raw);
      await tester.pumpWidget(_wrap(const ChatMessageBubble(message: msg)));
      await tester.pump();
      expect(find.byType(SelectedContextCardGroup), findsOneWidget);
      expect(find.text('Context 1'), findsOneWidget);
      expect(find.text('hello\nworld'), findsOneWidget);
      // cleanText 剩余
      expect(find.textContaining('请解释一下'), findsOneWidget);
    });

    testWidgets('user 消息：多块卡片均可见', (tester) async {
      const raw = '**A:**\n<!-- hermes-selected-context -->\n> a\n\n'
          '**B:**\n<!-- hermes-selected-context -->\n> b';
      const msg = ChatMessage(role: 'user', content: raw);
      await tester.pumpWidget(_wrap(const ChatMessageBubble(message: msg)));
      await tester.pump();
      expect(find.byType(SelectedContextCard), findsNWidgets(2));
    });

    testWidgets('user 消息：仅卡片无正文时不渲染空 Text', (tester) async {
      const raw = '**label:**\n<!-- hermes-selected-context -->\n> hi';
      const msg = ChatMessage(role: 'user', content: raw);
      await tester.pumpWidget(_wrap(const ChatMessageBubble(message: msg)));
      await tester.pump();
      expect(find.byType(SelectedContextCardGroup), findsOneWidget);
      // cleanText 为空，不应渲染气泡白字 Text("hi") 的重复
      expect(find.text('label'), findsOneWidget);
    });

    testWidgets('assistant 消息：SelectedContext 块同样置顶卡片', (tester) async {
      const raw = '**label:**\n<!-- hermes-selected-context -->\n> hi\n\n正文';
      const msg = ChatMessage(role: 'assistant', content: raw);
      await tester.pumpWidget(_wrap(const ChatMessageBubble(message: msg)));
      await tester.pump();
      expect(find.byType(SelectedContextCardGroup), findsOneWidget);
    });

    testWidgets('围栏内不解析，不产生卡片', (tester) async {
      const raw = '```\n**fake:**\n<!-- hermes-selected-context -->\n> hi\n```';
      const msg = ChatMessage(role: 'user', content: raw);
      await tester.pumpWidget(_wrap(const ChatMessageBubble(message: msg)));
      await tester.pump();
      expect(find.byType(SelectedContextCardGroup), findsNothing);
      expect(find.byType(SelectedContextCard), findsNothing);
    });

    testWidgets('无 marker 不产生卡片，原样渲染', (tester) async {
      const raw = '**加粗标题:**\n普通正文';
      const msg = ChatMessage(role: 'user', content: raw);
      await tester.pumpWidget(_wrap(const ChatMessageBubble(message: msg)));
      await tester.pump();
      expect(find.byType(SelectedContextCardGroup), findsNothing);
    });
  });
}
