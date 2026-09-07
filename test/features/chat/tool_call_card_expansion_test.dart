import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/models/json_value.dart';
import 'package:hermes_ui/core/models/tool_call.dart';
import 'package:hermes_ui/features/chat/widgets/tool_call_card.dart';
import 'package:hermes_ui/l10n/app_localizations.dart';

Widget _buildTestApp({
  required Widget child,
  PageStorageBucket? bucket,
}) {
  return CupertinoApp(
    locale: const Locale('zh'),
    supportedLocales: const [Locale('zh'), Locale('en')],
    localizationsDelegates: const [
      AppLocalizationsDelegate(),
      DefaultCupertinoLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
    ],
    home: CupertinoPageScaffold(
      child: PageStorage(
        bucket: bucket ?? PageStorageBucket(),
        child: Center(
          child: SizedBox(
            width: 400,
            child: child,
          ),
        ),
      ),
    ),
  );
}

Finder findGroupHeader([Finder? ofGroup]) {
  final parent = ofGroup ?? find.byType(ToolCallGroupCard);
  return find.descendant(of: parent, matching: find.byType(GestureDetector)).first;
}

Finder findCardHeader([Finder? ofCard]) {
  final parent = ofCard ?? find.byType(ToolCallCard);
  return find.descendant(of: parent, matching: find.byType(GestureDetector)).first;
}

void main() {
  group('ToolCallCard PageStorage 展开状态持久化测试', () {
    testWidgets('展开 → 重建 → PageStorage 恢复展开态（GREEN）', (tester) async {
      final bucket = PageStorageBucket();
      final call = ToolCall(
        id: 'call-expansion-1',
        name: 'read_file',
        args: {'file_path': const JsonString('/path/to/test.dart')},
        isCompleted: true,
      );
      final group = ToolCallGroup(
        id: 'group-expansion-1',
        toolCalls: [call],
      );

      // 1. 渲染组卡
      await tester.pumpWidget(_buildTestApp(
        bucket: bucket,
        child: ToolCallGroupCard(
          key: const ValueKey('group-v1'),
          group: group,
        ),
      ));
      await tester.pumpAndSettle();

      // 初始：组卡收起
      expect(find.byType(ToolCallCard), findsNothing);

      // 2. 点击展开组卡
      await tester.tap(findGroupHeader());
      await tester.pumpAndSettle();

      expect(find.byType(ToolCallCard), findsOneWidget);
      expect(find.textContaining('/path/to/test.dart'), findsNothing);

      // 3. 点击展开内层 ToolCallCard
      await tester.tap(findCardHeader());
      await tester.pumpAndSettle();

      // 验证展开成功
      expect(find.textContaining('/path/to/test.dart'), findsOneWidget);

      // 4. 重建（模拟列表重挂载或外部 key 变化）
      await tester.pumpWidget(_buildTestApp(
        bucket: bucket,
        child: ToolCallGroupCard(
          key: const ValueKey('group-v2'),
          group: group,
        ),
      ));
      await tester.pumpAndSettle();

      // 验证：组卡与内层 ToolCallCard 均通过 PageStorage 恢复展开态
      expect(find.byType(ToolCallCard), findsOneWidget);
      expect(find.textContaining('/path/to/test.dart'), findsOneWidget);
    });

    testWidgets('收起 → 重建 → 保持收起', (tester) async {
      final bucket = PageStorageBucket();
      final call = ToolCall(
        id: 'call-expansion-2',
        name: 'read_file',
        args: {'file_path': const JsonString('/path/to/keep_collapsed.dart')},
        isCompleted: true,
      );
      final group = ToolCallGroup(
        id: 'group-expansion-2',
        toolCalls: [call],
      );

      // 1. 渲染并展开组卡
      await tester.pumpWidget(_buildTestApp(
        bucket: bucket,
        child: ToolCallGroupCard(
          key: const ValueKey('group-v1'),
          group: group,
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(findGroupHeader());
      await tester.pumpAndSettle();

      // 2. 点击展开内层卡，再点击收起
      await tester.tap(findCardHeader());
      await tester.pumpAndSettle();
      expect(find.textContaining('/path/to/keep_collapsed.dart'), findsOneWidget);

      await tester.tap(findCardHeader());
      await tester.pumpAndSettle();
      expect(find.textContaining('/path/to/keep_collapsed.dart'), findsNothing);

      // 3. 重建组卡
      await tester.pumpWidget(_buildTestApp(
        bucket: bucket,
        child: ToolCallGroupCard(
          key: const ValueKey('group-v2'),
          group: group,
        ),
      ));
      await tester.pumpAndSettle();

      // 验证：组卡展开，内层保持收起
      expect(find.byType(ToolCallCard), findsOneWidget);
      expect(find.textContaining('/path/to/keep_collapsed.dart'), findsNothing);
    });

    testWidgets('didUpdateWidget 流式数据更新（同 ID）保持展开状态', (tester) async {
      final bucket = PageStorageBucket();
      final runningCall = ToolCall(
        id: 'call-stream-1',
        name: 'read_file',
        args: {'file_path': const JsonString('/path/to/streaming.dart')},
        isCompleted: false,
      );
      final groupRunning = ToolCallGroup(
        id: 'group-stream-1',
        toolCalls: [runningCall],
      );

      // 1. 渲染并展开
      await tester.pumpWidget(_buildTestApp(
        bucket: bucket,
        child: ToolCallGroupCard(
          key: const ValueKey('group-stream'),
          group: groupRunning,
        ),
      ));
      await tester.pump();

      await tester.tap(findGroupHeader());
      await tester.pump();

      await tester.tap(findCardHeader());
      await tester.pump();
      expect(find.textContaining('/path/to/streaming.dart'), findsOneWidget);

      // 2. 模拟流式完成事件触发 didUpdateWidget
      final completedCall = ToolCall(
        id: 'call-stream-1',
        name: 'read_file',
        args: {'file_path': const JsonString('/path/to/streaming.dart')},
        duration: 1.2,
        isCompleted: true,
        startedAt: runningCall.startedAt,
      );
      final groupCompleted = ToolCallGroup(
        id: 'group-stream-1',
        toolCalls: [completedCall],
      );

      await tester.pumpWidget(_buildTestApp(
        bucket: bucket,
        child: ToolCallGroupCard(
          key: const ValueKey('group-stream'),
          group: groupCompleted,
        ),
      ));
      await tester.pumpAndSettle();

      // 验证：didUpdateWidget 后仍然保持展开，并显示耗时
      expect(find.textContaining('/path/to/streaming.dart'), findsOneWidget);
      expect(find.text('1.2s'), findsOneWidget);
    });

    testWidgets('uuid- 前缀与空 id 兜底标识符在重建后恢复展开态', (tester) async {
      final bucket = PageStorageBucket();
      final uuidCall = ToolCall(
        id: 'uuid-mock-12345',
        name: 'bash',
        args: {'command': const JsonString('echo hello')},
        isCompleted: true,
      );
      final emptyIdCall = ToolCall(
        id: '',
        name: 'grep',
        args: {'pattern': const JsonString('test')},
        isCompleted: true,
        startedAt: 1000.0,
      );

      final group = ToolCallGroup(
        id: 'group-fallbacks',
        toolCalls: [uuidCall, emptyIdCall],
      );

      await tester.pumpWidget(_buildTestApp(
        bucket: bucket,
        child: ToolCallGroupCard(
          key: const ValueKey('group-f1'),
          group: group,
        ),
      ));
      await tester.pumpAndSettle();

      // 展开组卡
      await tester.tap(findGroupHeader());
      await tester.pumpAndSettle();

      final cards = find.byType(ToolCallCard);
      expect(cards, findsNWidgets(2));

      // 展开第一张 (uuid- 前缀)
      await tester.tap(findCardHeader(cards.at(0)));
      await tester.pumpAndSettle();
      expect(find.textContaining('command: echo hello'), findsOneWidget);

      // 展开第二张 (空 id，带 startedAt)
      await tester.tap(findCardHeader(cards.at(1)));
      await tester.pumpAndSettle();
      expect(find.textContaining('pattern: test'), findsOneWidget);

      // 重建整个组卡
      await tester.pumpWidget(_buildTestApp(
        bucket: bucket,
        child: ToolCallGroupCard(
          key: const ValueKey('group-f2'),
          group: ToolCallGroup(
            id: 'group-fallbacks',
            toolCalls: [
              ToolCall(
                id: 'uuid-mock-12345',
                name: 'bash',
                args: {'command': const JsonString('echo hello')},
                isCompleted: true,
              ),
              ToolCall(
                id: '',
                name: 'grep',
                args: {'pattern': const JsonString('test')},
                isCompleted: true,
                startedAt: 1000.0,
              ),
            ],
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // 两张卡片均通过各自的兜底标识符成功恢复展开态
      expect(find.textContaining('command: echo hello'), findsOneWidget);
      expect(find.textContaining('pattern: test'), findsOneWidget);
    });

    testWidgets('独立使用 ToolCallCard 时 PageStorage 同样生效', (tester) async {
      final bucket = PageStorageBucket();
      final call = ToolCall(
        id: 'standalone-call-1',
        name: 'read_file',
        args: {'file_path': const JsonString('/path/to/standalone.dart')},
        isCompleted: true,
      );

      // 1. 独立渲染 ToolCallCard
      await tester.pumpWidget(_buildTestApp(
        bucket: bucket,
        child: ToolCallCard(
          key: const ValueKey('standalone-v1'),
          call: call,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('/path/to/standalone.dart'), findsNothing);

      // 2. 点击展开
      await tester.tap(findCardHeader());
      await tester.pumpAndSettle();
      expect(find.textContaining('/path/to/standalone.dart'), findsOneWidget);

      // 3. 重建（换 Key）
      await tester.pumpWidget(_buildTestApp(
        bucket: bucket,
        child: ToolCallCard(
          key: const ValueKey('standalone-v2'),
          call: call,
        ),
      ));
      await tester.pumpAndSettle();

      // 4. 验证恢复展开态
      expect(find.textContaining('/path/to/standalone.dart'), findsOneWidget);
    });
  });
}
