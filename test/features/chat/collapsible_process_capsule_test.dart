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
              ThinkingRow(call: group.toolCalls[0]),
              ToolCallCard(call: group.toolCalls[1]),
              ToolCallCard(call: group.toolCalls[2]),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 摘要标题为明细自适应
      expect(find.text('思考 \u00D71, 读取文件 \u00D71, 终端 \u00D71'), findsOneWidget);
      expect(find.byKey(const ValueKey('process-capsule-header')), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.chevron_down), findsOneWidget);

      // 默认折叠时，内部子卡片不在树中
      expect(find.byType(ToolCallCard), findsNothing);
      expect(find.byType(ThinkingRow), findsNothing);
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
              ThinkingRow(call: group.toolCalls[0]),
              ToolCallCard(call: group.toolCalls[1]),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ToolCallCard), findsNothing);
      expect(find.byType(ThinkingRow), findsNothing);
      expect(find.byIcon(CupertinoIcons.chevron_down), findsOneWidget);

      // 1. 点击展开
      await tester.tap(find.byKey(const ValueKey('process-capsule-header')));
      await tester.pumpAndSettle();

      expect(find.byType(ThinkingRow), findsOneWidget);
      expect(find.byType(ToolCallCard), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.chevron_up), findsOneWidget);

      // 2. 再次点击收起
      await tester.tap(find.byKey(const ValueKey('process-capsule-header')));
      await tester.pumpAndSettle();

      expect(find.byType(ThinkingRow), findsNothing);
      expect(find.byType(ToolCallCard), findsNothing);
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
          width: 800,
          child: CollapsibleProcessCapsule(
            toolGroups: [group],
            children: [
              ThinkingRow(call: group.toolCalls[0]),
              ToolCallCard(call: group.toolCalls[1]),
              ToolCallCard(call: group.toolCalls[2]),
              ToolCallCard(call: group.toolCalls[3]),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Thinking \u00D71, Read File \u00D71, Apply Patch \u00D71, Terminal \u00D71'),
        findsOneWidget,
      );
    });

    testWidgets('长过程（10+工具）计数摘要准确并自适应截断', (tester) async {
      final calls = <ToolCall>[
        ToolCall.thinking('深度推理过程'),
        for (var i = 0; i < 12; i++)
          ToolCall(name: 'tool_$i', isCompleted: true),
      ];
      final group = ToolCallGroup(toolCalls: calls);

      await tester.pumpWidget(
        _buildTestApp(
          width: 400,
          child: CollapsibleProcessCapsule(
            toolGroups: [group],
            children: [
              for (final c in calls)
                if (c.isThinking) ThinkingRow(call: c) else ToolCallCard(call: c),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('思考 \u00D71'), findsOneWidget);
      expect(find.textContaining('\u2026'), findsOneWidget);
    });

    testWidgets('仅有思考无工具时摘要为"思考 ×1"', (tester) async {
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
              ThinkingRow(call: group.toolCalls[0]),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('思考 \u00D71'), findsOneWidget);
    });

    testWidgets('仅有 1 个工具无思考时摘要为"终端 ×1" / "Terminal ×1"', (tester) async {
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
              ToolCallCard(call: group.toolCalls[0]),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('终端 \u00D71'), findsOneWidget);

      await tester.pumpWidget(
        _buildTestApp(
          locale: const Locale('en'),
          child: CollapsibleProcessCapsule(
            toolGroups: [group],
            children: [
              ToolCallCard(call: group.toolCalls[0]),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Terminal \u00D71'), findsOneWidget);
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
              ToolCallCard(call: group.toolCalls[1]),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('读取文件 \u00D71'), findsOneWidget);
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
              ToolCallCard(call: group.toolCalls[0]),
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

    testWidgets('外壳无框且展开后支持平铺文本与带框卡片', (tester) async {
      final group = ToolCallGroup(
        toolCalls: [
          ToolCall(name: 'read_file', isCompleted: true),
        ],
      );

      await tester.pumpWidget(
        _buildTestApp(
          child: CollapsibleProcessCapsule(
            toolGroups: [group],
            children: [
              ToolCallCard(call: group.toolCalls[0]),
              const Text('早段说明文本'),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 默认折叠态：无外框（仅标题行），子项不可见
      expect(find.byKey(const ValueKey('collapsible-process-capsule')), findsOneWidget);
      expect(find.byType(ToolCallCard), findsNothing);
      expect(find.text('早段说明文本'), findsNothing);

      // 展开：工具卡片与文本均渲染
      await tester.tap(find.byKey(const ValueKey('process-capsule-header')));
      await tester.pumpAndSettle();

      expect(find.byType(ToolCallCard), findsOneWidget);
      expect(find.text('早段说明文本'), findsOneWidget);
    });
  });
}
