import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/models/tool_call.dart';
import 'package:hermes_ui/features/chat/widgets/collapsible_process_capsule.dart';
import 'package:hermes_ui/features/chat/widgets/tool_call_card.dart';
import 'package:hermes_ui/l10n/app_localizations.dart';

Widget _buildTestApp({
  required Widget child,
  Locale locale = const Locale('zh'),
  double width = 400,
}) {
  return CupertinoApp(
    locale: locale,
    supportedLocales: const [Locale('zh'), Locale('en')],
    localizationsDelegates: const [
      AppLocalizationsDelegate(),
      DefaultCupertinoLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
    ],
    home: CupertinoPageScaffold(
      child: Center(
        child: SizedBox(
          width: width,
          child: child,
        ),
      ),
    ),
  );
}

void main() {
  group('CollapsibleProcessCapsule Widget 测试', () {
    testWidgets('默认折叠状态：只展示胶囊摘要标题，不渲染展开子卡片', (tester) async {
      final group = ToolCallGroup(
        toolCalls: [
          ToolCall.thinking('思考测试步骤'),
          ToolCall(name: 'read_file', isCompleted: true),
          ToolCall(name: 'bash', isCompleted: true),
        ],
      );

      await tester.pumpWidget(
        _buildTestApp(
          child: CollapsibleProcessCapsule(
            toolGroups: [group],
            children: [
              ToolCallGroupCard(group: group),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 摘要标题应包含"思考 · 2 工具"
      expect(find.text('思考 · 2 工具'), findsOneWidget);
      expect(find.byKey(const ValueKey('process-capsule-header')), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.chevron_down), findsOneWidget);

      // 默认折叠时，内部子卡片不在树中
      expect(find.byType(ToolCallGroupCard), findsNothing);
    });

    testWidgets('点击胶囊展开：显示子卡片；再次点击收起', (tester) async {
      final group = ToolCallGroup(
        toolCalls: [
          ToolCall.thinking('详细分析中'),
          ToolCall(name: 'grep', isCompleted: true),
        ],
      );

      await tester.pumpWidget(
        _buildTestApp(
          child: CollapsibleProcessCapsule(
            toolGroups: [group],
            children: [
              ToolCallGroupCard(group: group),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ToolCallGroupCard), findsNothing);
      expect(find.byIcon(CupertinoIcons.chevron_down), findsOneWidget);

      // 1. 点击展开
      await tester.tap(find.byKey(const ValueKey('process-capsule-header')));
      await tester.pumpAndSettle();

      expect(find.byType(ToolCallGroupCard), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.chevron_up), findsOneWidget);

      // 2. 再次点击收起
      await tester.tap(find.byKey(const ValueKey('process-capsule-header')));
      await tester.pumpAndSettle();

      expect(find.byType(ToolCallGroupCard), findsNothing);
      expect(find.byIcon(CupertinoIcons.chevron_down), findsOneWidget);
    });

    testWidgets('英文环境摘要格式正确', (tester) async {
      final group = ToolCallGroup(
        toolCalls: [
          ToolCall.thinking('Planning approach'),
          ToolCall(name: 'read_file', isCompleted: true),
          ToolCall(name: 'edit_file', isCompleted: true),
          ToolCall(name: 'bash', isCompleted: true),
        ],
      );

      await tester.pumpWidget(
        _buildTestApp(
          locale: const Locale('en'),
          child: CollapsibleProcessCapsule(
            toolGroups: [group],
            children: [
              ToolCallGroupCard(group: group),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Thinking · 3 tools'), findsOneWidget);
    });

    testWidgets('长过程（10+工具）计数摘要准确', (tester) async {
      final calls = <ToolCall>[
        ToolCall.thinking('深度推理过程'),
        for (var i = 0; i < 12; i++)
          ToolCall(name: 'tool_$i', isCompleted: true),
      ];
      final group = ToolCallGroup(toolCalls: calls);

      await tester.pumpWidget(
        _buildTestApp(
          child: CollapsibleProcessCapsule(
            toolGroups: [group],
            children: [
              ToolCallGroupCard(group: group),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('思考 · 12 工具'), findsOneWidget);
    });

    testWidgets('仅有思考无工具时摘要为"思考"', (tester) async {
      final group = ToolCallGroup(
        toolCalls: [
          ToolCall.thinking('纯思考内容'),
        ],
      );

      await tester.pumpWidget(
        _buildTestApp(
          child: CollapsibleProcessCapsule(
            toolGroups: [group],
            children: [
              ToolCallGroupCard(group: group),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('思考'), findsOneWidget);
    });

    testWidgets('仅有 1 个工具无思考时摘要为"1 工具" / "1 tool"', (tester) async {
      final group = ToolCallGroup(
        toolCalls: [
          ToolCall(name: 'bash', isCompleted: true),
        ],
      );

      await tester.pumpWidget(
        _buildTestApp(
          child: CollapsibleProcessCapsule(
            toolGroups: [group],
            children: [
              ToolCallGroupCard(group: group),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('1 工具'), findsOneWidget);

      await tester.pumpWidget(
        _buildTestApp(
          locale: const Locale('en'),
          child: CollapsibleProcessCapsule(
            toolGroups: [group],
            children: [
              ToolCallGroupCard(group: group),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('1 tool'), findsOneWidget);
    });

    testWidgets('hideThinking 为 true 时，思考不计入摘要', (tester) async {
      final group = ToolCallGroup(
        toolCalls: [
          ToolCall.thinking('隐藏的思考'),
          ToolCall(name: 'read_file', isCompleted: true),
        ],
      );

      await tester.pumpWidget(
        _buildTestApp(
          child: CollapsibleProcessCapsule(
            toolGroups: [group],
            hideThinking: true,
            children: [
              ToolCallGroupCard(group: group, hideThinking: true),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('1 工具'), findsOneWidget);
      expect(find.textContaining('思考'), findsNothing);
    });

    testWidgets('工具失败时图标显示红色警告', (tester) async {
      final group = ToolCallGroup(
        toolCalls: [
          ToolCall(name: 'bash', isCompleted: true, isError: true),
        ],
      );

      await tester.pumpWidget(
        _buildTestApp(
          child: CollapsibleProcessCapsule(
            toolGroups: [group],
            children: [
              ToolCallGroupCard(group: group),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byIcon(CupertinoIcons.exclamationmark_triangle_fill),
        findsOneWidget,
      );
    });
  });
}
