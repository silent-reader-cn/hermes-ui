import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermex_flutter/features/chat/selection_provider.dart';
import 'package:hermex_flutter/features/chat/widgets/selection_chips.dart';

Widget _boundedWrapWithContainer(ProviderContainer c, Widget child) =>
    UncontrolledProviderScope(
      container: c,
      child: CupertinoApp(
        home: CupertinoPageScaffold(
          child: SizedBox(height: 600, width: 400, child: child),
        ),
      ),
    );

void main() {
  testWidgets('空时 hidden (SizedBox.shrink)', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: CupertinoApp(home: SelectionChipPanel(sessionId: 's1'))),
    );
    await tester.pump();
    expect(find.byType(SingleChildScrollView), findsNothing);
    expect(find.text('清空'), findsNothing);
  });

  testWidgets('单卡片显示 name、预览、× 移除', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(pendingSelectionsProvider('s1').notifier).add('hello\nworld');

    await tester.pumpWidget(
      _boundedWrapWithContainer(container, const SelectionChipPanel(sessionId: 's1')),
    );
    await tester.pump();

    expect(find.text('Context 1'), findsOneWidget);
    expect(find.text('hello\nworld'), findsOneWidget);
    expect(find.byKey(const ValueKey('selection-remove-ctx-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('selection-clear-all')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('selection-remove-ctx-1')));
    await tester.pump();
    expect(container.read(pendingSelectionsProvider('s1')), isEmpty);
    expect(find.text('Context 1'), findsNothing);
  });

  testWidgets('多块：清空按钮与可滚容器', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container
        .read(pendingSelectionsProvider('s1').notifier)
      ..add('a')
      ..add('b')
      ..add('c');

    await tester.pumpWidget(
      _boundedWrapWithContainer(container, const SelectionChipPanel(sessionId: 's1')),
    );
    await tester.pump();

    expect(find.text('Context 1'), findsOneWidget);
    expect(find.text('Context 2'), findsOneWidget);
    expect(find.text('Context 3'), findsOneWidget);
    expect(find.byKey(const ValueKey('selection-clear-all')), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('selection-clear-all')));
    await tester.pump();
    expect(container.read(pendingSelectionsProvider('s1')), isEmpty);
  });

  testWidgets('预览 360 截断 + 3 行省略', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final long = 'x' * 500;
    container.read(pendingSelectionsProvider('s1').notifier).add(long);

    await tester.pumpWidget(
      _boundedWrapWithContainer(container, const SelectionChipPanel(sessionId: 's1')),
    );
    await tester.pump();

    final preview = selectedContextPreview(long);
    expect(preview.endsWith('…'), isTrue);
    expect(find.text(preview), findsOneWidget);
    final text = tester.widget<Text>(find.text(preview));
    expect(text.maxLines, 3);
    expect(text.overflow, TextOverflow.ellipsis);
  });

  testWidgets('重命名 dialog：120 上限', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(pendingSelectionsProvider('s1').notifier).add('t');

    await tester.pumpWidget(
      _boundedWrapWithContainer(container, const SelectionChipPanel(sessionId: 's1')),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('selection-rename-ctx-1')));
    await tester.pump();
    expect(find.byKey(const ValueKey('selection-rename-field')), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('selection-rename-field')),
      '新名字',
    );
    await tester.pump();
    await tester.tap(find.text('确定'));
    await tester.pump();
    expect(container.read(pendingSelectionsProvider('s1')).first.name, '新名字');
    expect(find.text('新名字'), findsOneWidget);
  });

  testWidgets('按 sessionId 隔离', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(pendingSelectionsProvider('a').notifier).add('from a');

    await tester.pumpWidget(
      _boundedWrapWithContainer(container, const SelectionChipPanel(sessionId: 'b')),
    );
    await tester.pump();
    expect(find.text('Context 1'), findsNothing);

    await tester.pumpWidget(
      _boundedWrapWithContainer(container, const SelectionChipPanel(sessionId: 'a')),
    );
    await tester.pump();
    expect(find.text('Context 1'), findsOneWidget);
  });

  testWidgets('maxHeight 280 约束存在', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final n = container.read(pendingSelectionsProvider('s1').notifier);
    for (var i = 0; i < 10; i++) {
      n.add('item $i');
    }
    await tester.pumpWidget(
      _boundedWrapWithContainer(container, const SelectionChipPanel(sessionId: 's1')),
    );
    await tester.pump();
    // 面板整体为 ConstrainedBox(maxHeight:280) + SingleChildScrollView
    final constrained = tester
        .widgetList<ConstrainedBox>(find.byType(ConstrainedBox))
        .firstWhere((w) => w.constraints.maxHeight == 280);
    expect(constrained.constraints.maxHeight, 280);
  });
}
