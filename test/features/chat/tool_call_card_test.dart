import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/models/json_value.dart';
import 'package:hermes_ui/core/models/tool_call.dart';
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
  group('ToolCallCard Widget', () {
    testWidgets('Header 展示本地化工具名与参数摘要', (tester) async {
      final call = ToolCall(
        name: 'read_file',
        args: {'file_path': const JsonString('/path/to/main.dart')},
        isCompleted: true,
      );

      await tester.pumpWidget(_buildTestApp(child: ToolCallCard(call: call)));
      await tester.pumpAndSettle();

      final richTextFinder = find.byWidgetPredicate(
        (w) => w is RichText && w.text.toPlainText().contains('读取文件 — main.dart'),
      );
      expect(richTextFinder, findsOneWidget);
    });

    testWidgets('英文环境展示英文工具名与摘要', (tester) async {
      final call = ToolCall(
        name: 'bash',
        args: {'command': const JsonString('flutter test')},
        isCompleted: true,
      );

      await tester.pumpWidget(_buildTestApp(
        locale: const Locale('en'),
        child: ToolCallCard(call: call),
      ));
      await tester.pumpAndSettle();

      final richTextFinder = find.byWidgetPredicate(
        (w) => w is RichText && w.text.toPlainText().contains('Terminal — flutter test'),
      );
      expect(richTextFinder, findsOneWidget);
    });

    testWidgets('Summary 超过 36 字符时截断为 33 + …', (tester) async {
      final longParam = 'abcdefghijklmnopqrstuvwxyz0123456789_extra_long_string';
      final call = ToolCall(
        name: 'custom_tool',
        args: {'content': JsonString(longParam)},
        isCompleted: true,
      );

      await tester.pumpWidget(_buildTestApp(child: ToolCallCard(call: call)));
      await tester.pumpAndSettle();

      final expectedSummary = '${longParam.substring(0, 33)}\u2026';
      final richTextFinder = find.byWidgetPredicate(
        (w) => w is RichText && w.text.toPlainText().contains(' — $expectedSummary'),
      );
      expect(richTextFinder, findsOneWidget);
    });

    testWidgets('无有效摘要时仅显示工具名，不显示破折号', (tester) async {
      final call = ToolCall(
        name: 'custom_tool',
        isCompleted: true,
      );

      await tester.pumpWidget(_buildTestApp(child: ToolCallCard(call: call)));
      await tester.pumpAndSettle();

      final richTextFinder = find.byWidgetPredicate(
        (w) => w is RichText && w.text.toPlainText().contains('—'),
      );
      expect(richTextFinder, findsNothing);
    });
  });

  group('ToolCallGroupCard 自适应标题与省略号', () {
    testWidgets('宽屏下展示全部工具分类与频次', (tester) async {
      final group = ToolCallGroup(
        toolCalls: [
          ToolCall(name: 'read_file', isCompleted: true),
          ToolCall(name: 'read_file', isCompleted: true),
          ToolCall(name: 'bash', isCompleted: true),
          ToolCall(name: 'grep', isCompleted: true),
        ],
      );

      await tester.pumpWidget(_buildTestApp(
        width: 800,
        child: ToolCallGroupCard(group: group),
      ));
      await tester.pumpAndSettle();

      expect(find.text('读取文件 \u00D72, 终端 \u00D71, 搜索 \u00D71'), findsOneWidget);
    });

    testWidgets('宽度不足时自适应截断并以单个省略号 U+2026 结尾', (tester) async {
      final group = ToolCallGroup(
        toolCalls: [
          ToolCall(name: 'read_file', isCompleted: true),
          ToolCall(name: 'read_file', isCompleted: true),
          ToolCall(name: 'read_file', isCompleted: true),
          ToolCall(name: 'bash', isCompleted: true),
          ToolCall(name: 'grep', isCompleted: true),
          ToolCall(name: 'write_file', isCompleted: true),
        ],
      );

      // 设置适中宽度，使得无法放下全部 4 种工具名
      await tester.pumpWidget(_buildTestApp(
        width: 220,
        child: ToolCallGroupCard(group: group),
      ));
      await tester.pumpAndSettle();

      final textWidget = tester.widget<Text>(find.byWidgetPredicate(
        (w) => w is Text && (w.data?.contains('\u2026') == true),
      ));
      expect(textWidget.data, endsWith(' \u2026'));
      expect(textWidget.data, startsWith('读取文件 \u00D73'));
    });

    testWidgets('首个 entry 宽度不足时兜底只显示名称 + 省略号', (tester) async {
      final group = ToolCallGroup(
        toolCalls: [
          ToolCall(name: 'read_file', isCompleted: true),
        ],
      );

      // 设置极窄但足够的卡片宽度（比如 85px），使得 text 宽度仅约 25px（容纳不下 "读取文件 ×1"）
      await tester.pumpWidget(_buildTestApp(
        width: 85,
        child: ToolCallGroupCard(group: group),
      ));
      await tester.pumpAndSettle();

      final textWidget = tester.widget<Text>(find.byWidgetPredicate(
        (w) => w is Text && (w.data?.contains('\u2026') == true),
      ));
      expect(textWidget.data, '读取文件 \u2026');
    });

    testWidgets('空工具调用列表显示无工具', (tester) async {
      final group = ToolCallGroup(toolCalls: []);

      await tester.pumpWidget(_buildTestApp(child: ToolCallGroupCard(group: group)));
      await tester.pumpAndSettle();

      expect(find.text('无工具'), findsOneWidget);
    });
  });
}
