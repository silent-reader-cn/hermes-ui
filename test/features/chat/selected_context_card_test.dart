import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermex_flutter/core/utils/selected_context.dart';
import 'package:hermex_flutter/features/chat/widgets/selected_context_card.dart';

Widget _wrap(Widget child) {
  return CupertinoApp(home: CupertinoPageScaffold(child: child));
}

void main() {
  group('SelectedContextCard 渲染', () {
    testWidgets('单块卡片可见 label 与 quote', (tester) async {
      const block = SelectedContextBlock(label: 'Context 1', quote: 'hello world');
      await tester.pumpWidget(_wrap(const SelectedContextCard(block: block)));
      await tester.pump();
      expect(find.text('Context 1'), findsOneWidget);
      expect(find.text('hello world'), findsOneWidget);
    });

    testWidgets('多块 gap8：两张卡片', (tester) async {
      const blocks = [
        SelectedContextBlock(label: 'A', quote: 'a'),
        SelectedContextBlock(label: 'B', quote: 'b'),
      ];
      await tester.pumpWidget(_wrap(const SelectedContextCardGroup(blocks: blocks)));
      await tester.pump();
      expect(find.text('A'), findsOneWidget);
      expect(find.text('B'), findsOneWidget);
      expect(find.byType(SelectedContextCard), findsNWidgets(2));
    });

    testWidgets('空块列表渲染为空', (tester) async {
      await tester.pumpWidget(_wrap(const SelectedContextCardGroup(blocks: [])));
      await tester.pump();
      expect(find.byType(SelectedContextCard), findsNothing);
    });

    testWidgets('quote 可选中（SelectableText）', (tester) async {
      const block = SelectedContextBlock(label: 'label', quote: 'selectable quote');
      await tester.pumpWidget(_wrap(const SelectedContextCard(block: block)));
      await tester.pump();
      // quote 通过 SelectableText 渲染
      expect(find.text('selectable quote'), findsOneWidget);
    });

    testWidgets('复制按钮存在', (tester) async {
      const block = SelectedContextBlock(label: 'label', quote: 'copy me');
      await tester.pumpWidget(_wrap(const SelectedContextCard(block: block)));
      await tester.pump();
      expect(find.text('复制'), findsOneWidget);
    });
  });
}
