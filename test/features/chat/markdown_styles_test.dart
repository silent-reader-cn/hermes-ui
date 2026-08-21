import 'package:flutter/cupertino.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermex_flutter/features/chat/widgets/markdown_styles.dart';

/// 聊天气泡 Markdown 样式契约测试。
///
/// 修复目标（regression 防回归）：
/// 1. 深浅色一致性：标题/加粗/代码/引用/表格全部使用**解析后的** label/link
///    语义色（不得保留未解析的动态色 → 暗黑下画浅色变体黑字）；
/// 2. 加粗不放大：strong/em/del 与正文同基准 15pt（不得继承主题 17pt）；
/// 3. 标题层级收敛：h1=20 / h2=18 / h3=16 / h4-h6=15，w600。
void main() {
  Future<BuildContext> pumpStyleContext(
    WidgetTester tester,
    Brightness brightness,
  ) async {
    await tester.pumpWidget(
      CupertinoApp(
        theme: CupertinoThemeData(brightness: brightness),
        home: const SizedBox.shrink(),
      ),
    );
    return tester.element(find.byType(SizedBox));
  }

  for (final brightness in [Brightness.light, Brightness.dark]) {
    final themeName = brightness == Brightness.light ? '浅色' : '深色';

    testWidgets('assistant 样式 $themeName：全部文本色=解析后 label，标题阶梯收敛，加粗不放大',
        (tester) async {
      final context = await pumpStyleContext(tester, brightness);
      final label = CupertinoColors.label.resolveFrom(context);
      final link = CupertinoColors.link.resolveFrom(context);
      final grey5 = CupertinoColors.systemGrey5.resolveFrom(context);
      final sheet = buildAssistantMarkdownStyleSheet(context);

      // 基础：正文 / 列表 / 引用 = 15pt label
      expect(sheet.p!.fontSize, 15);
      expect(sheet.p!.color, label);
      expect(sheet.listBullet!.fontSize, 15);
      expect(sheet.listBullet!.color, label);
      expect(sheet.blockquote!.fontSize, 15);
      expect(sheet.blockquote!.color, label);

      // 加粗/斜体/删除线：同 15pt 基准、仅字重/字形变化
      expect(sheet.strong!.fontSize, 15);
      expect(sheet.strong!.fontWeight, FontWeight.w600);
      expect(sheet.strong!.color, label);
      expect(sheet.em!.fontSize, 15);
      expect(sheet.em!.fontStyle, FontStyle.italic);
      expect(sheet.del!.fontSize, 15);
      expect(sheet.del!.decoration, TextDecoration.lineThrough);

      // 标题阶梯：20/18/16/15/15/15，全部 w600 + label
      const sizes = [20.0, 18.0, 16.0, 15.0, 15.0, 15.0];
      for (var i = 0; i < 6; i++) {
        final h = [sheet.h1, sheet.h2, sheet.h3, sheet.h4, sheet.h5, sheet.h6][i];
        expect(h!.fontSize, sizes[i], reason: 'h${i + 1} 字号');
        expect(h.fontWeight, FontWeight.w600, reason: 'h${i + 1} 字重');
        expect(h.color, label, reason: 'h${i + 1} 颜色');
      }

      // 链接：解析后 link 色 + 下划线
      expect(sheet.a!.color, link);
      expect(sheet.a!.decoration, TextDecoration.underline);

      // 内联代码：13pt monospace + label + grey5 底
      expect(sheet.code!.fontSize, 13);
      expect(sheet.code!.fontFamily, 'monospace');
      expect(sheet.code!.color, label);
      expect(sheet.code!.backgroundColor, grey5);
      expect(
        (sheet.codeblockDecoration! as BoxDecoration).color,
        grey5,
        reason: '代码块底必须 resolve（BoxDecoration 不自动解析）',
      );

      // 表格：表头 w600/label，表体 14pt label，边框 separator resolve
      expect(sheet.tableHead!.fontWeight, FontWeight.w600);
      expect(sheet.tableHead!.color, label);
      expect(sheet.tableBody!.fontSize, 14);
      expect(
        sheet.tableBorder!.top.color,
        CupertinoColors.separator.resolveFrom(context),
      );
    });

    testWidgets('user 样式 $themeName：统一白字、加粗同号', (tester) async {
      final context = await pumpStyleContext(tester, brightness);
      final sheet = buildUserMarkdownStyleSheet(context);
      const white = CupertinoColors.white;

      expect(sheet.p!.fontSize, 15);
      expect(sheet.p!.color, white);
      expect(sheet.strong!.fontSize, 15);
      expect(sheet.strong!.fontWeight, FontWeight.w600);
      expect(sheet.strong!.color, white);
      expect(sheet.h1!.fontSize, 20);
      expect(sheet.h1!.fontWeight, FontWeight.w600);
      expect(sheet.h1!.color, white);
      expect(sheet.code!.fontSize, 13);
      expect(sheet.code!.fontFamily, 'monospace');
      expect(sheet.code!.color, white);
    });
  }

  testWidgets('渲染冒烟：markdown 全文（标题/加粗/代码/引用/列表/表格）正常渲染',
      (tester) async {
    await tester.pumpWidget(
      CupertinoApp(
        theme: const CupertinoThemeData(brightness: Brightness.dark),
        home: Builder(
          builder: (context) => MarkdownBody(
            data: '# 标题\n\n正文 **加粗** 与 `代码`。\n\n> 引用\n\n- 列表\n\n| a | b |\n|---|---|\n| 1 | 2 |',
            styleSheet: buildAssistantMarkdownStyleSheet(context),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.textContaining('标题'), findsWidgets);
    expect(find.textContaining('加粗'), findsOneWidget);
  });
}