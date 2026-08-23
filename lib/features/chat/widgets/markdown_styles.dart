library;

import 'package:flutter/cupertino.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;

/// 聊天气泡与正文 Markdown 样式（chat_spec.md §6.3 Markdown 渲染）。
///
/// 从 `MarkdownStyleSheet.fromCupertinoTheme` 继承基底结构（标题/列表等的
/// 布局常量），但**全部文本样式显式重写**：
///
/// 1. **动态色必须 resolve**：`fromCupertinoTheme` 生成的
///    h1-h6/strong/em/del/blockquote/table 等样式直接复制
///    `theme.textTheme.textStyle`，其 color 是**未解析的**动态色
///    `CupertinoColors.label` —— 绘制时 `toARGB32()` 恒取浅色变体，
///    暗黑模式下会渲染成黑字（正文已解析为白字 → 极不协调）。
/// 2. **加粗不得放大**：该基底强样式继承的是主题 17pt 正文，
///    而本项目正文统一为 15pt —— 直接继承会让 `**加粗**` 变成 17pt
///   比正文大一号。这里 strong/em/del 一律基于 15pt 正文基准，
///   只改字重/字形。
/// 3. 标题收敛为气泡内协调的层级阶梯（20/18/16/15…），不再用 27pt 起步。

/// 会话列表/聊天通用：15pt body 基线（MiSans Regular 400）。
const double kMarkdownBodyFontSize = 15.0;

/// 加粗字重：MiSans Medium（500/600 均映射 Medium 字形，不触发伪粗体）。
const FontWeight kMarkdownStrongWeight = FontWeight.w600;

/// 行内代码 pill 默认圆角：4px。
const double kInlineCodeBorderRadius = 4.0;

/// 行内代码 pill 默认内边距：水平 4px，垂直 1px（轻量留白，不抬高行高）。
const EdgeInsetsGeometry kInlineCodePadding = EdgeInsets.symmetric(
  horizontal: 4.0,
  vertical: 1.0,
);

TextStyle _body({
  required Color color,
  double size = kMarkdownBodyFontSize,
  FontWeight? weight,
  FontStyle? style,
  TextDecoration? decoration,
}) {
  return TextStyle(
    fontSize: size,
    height: 1.4,
    color: color,
    fontWeight: weight,
    fontStyle: style,
    decoration: decoration,
  );
}

/// 标题字号阶梯（气泡内收敛：h1=20 → h6=15，全部 w600）。
double _headingSize(int level) => switch (level) {
      1 => 20.0,
      2 => 18.0,
      3 => 16.0,
      _ => kMarkdownBodyFontSize,
    };

/// assistant 气泡（浅/深色均可）：正文 label 色，标题/加粗同色同基准。
MarkdownStyleSheet buildAssistantMarkdownStyleSheet(BuildContext context) {
  final theme = CupertinoTheme.of(context);
  final label = CupertinoColors.label.resolveFrom(context);
  final link = CupertinoColors.link.resolveFrom(context);
  final grey5 = CupertinoColors.systemGrey5.resolveFrom(context);
  final separator = CupertinoColors.separator.resolveFrom(context);

  TextStyle heading(int level) => _body(
        color: label,
        size: _headingSize(level),
        weight: kMarkdownStrongWeight,
      );

  return MarkdownStyleSheet.fromCupertinoTheme(theme).copyWith(
    a: _body(color: link, decoration: TextDecoration.underline),
    p: _body(color: label),
    pPadding: EdgeInsets.zero,
    listBullet: _body(color: label),
    h1: heading(1),
    h2: heading(2),
    h3: heading(3),
    h4: heading(4),
    h5: heading(5),
    h6: heading(6),
    em: _body(color: label, style: FontStyle.italic),
    strong: _body(color: label, weight: kMarkdownStrongWeight),
    del: _body(
      color: label,
      decoration: TextDecoration.lineThrough,
    ),
    blockquote: _body(color: label),
    code: TextStyle(
      fontSize: 13,
      height: 1.4,
      fontFamily: 'monospace',
      color: label,
      backgroundColor: grey5,
    ),
    codeblockDecoration: BoxDecoration(
      color: grey5,
      borderRadius: BorderRadius.circular(6),
    ),
    codeblockPadding: const EdgeInsets.all(12),
    blockquoteDecoration: BoxDecoration(
      color: grey5,
      borderRadius: BorderRadius.circular(6),
    ),
    blockquotePadding: const EdgeInsets.all(8),
    tableHead: _body(color: label, weight: kMarkdownStrongWeight),
    tableBody: _body(color: label, size: 14),
    tableBorder: TableBorder.all(color: separator, width: 0.5),
    checkbox: _body(color: theme.primaryColor),
  );
}

/// user 气泡（蓝底白字）：全部文字固定白，代码块用半透明白底。
MarkdownStyleSheet buildUserMarkdownStyleSheet(BuildContext context) {
  final theme = CupertinoTheme.of(context);
  const white = CupertinoColors.white;

  TextStyle heading(int level) => _body(
        color: white,
        size: _headingSize(level),
        weight: kMarkdownStrongWeight,
      );

  return MarkdownStyleSheet.fromCupertinoTheme(theme).copyWith(
    a: _body(color: white, decoration: TextDecoration.underline),
    p: _body(color: white),
    pPadding: EdgeInsets.zero,
    listBullet: _body(color: white),
    h1: heading(1),
    h2: heading(2),
    h3: heading(3),
    h4: heading(4),
    h5: heading(5),
    h6: heading(6),
    em: _body(color: white, style: FontStyle.italic),
    strong: _body(color: white, weight: kMarkdownStrongWeight),
    del: _body(color: white, decoration: TextDecoration.lineThrough),
    blockquote: _body(color: white),
    code: TextStyle(
      fontSize: 13,
      height: 1.4,
      fontFamily: 'monospace',
      color: white,
      backgroundColor: white.withValues(alpha: 0.22),
    ),
    codeblockDecoration: BoxDecoration(
      color: white.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(6),
    ),
    codeblockPadding: const EdgeInsets.all(12),
    blockquoteDecoration: BoxDecoration(
      color: white.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(6),
    ),
    blockquotePadding: const EdgeInsets.all(8),
    tableHead: _body(color: white, weight: kMarkdownStrongWeight),
    tableBody: _body(color: white, size: 14),
    tableBorder: TableBorder.all(color: white.withValues(alpha: 0.4), width: 0.5),
    checkbox: _body(color: white),
  );
}

/// 行内代码 `code` 块 pill 样式构建器。
///
/// 将行内 `code` 渲染为带轻量圆角和内边距的 pill 块（[WidgetSpan] 包裹的 [Container]），
/// 解决原生 `TextStyle.backgroundColor` 无 padding、紧贴文字且无圆角的问题。
///
/// 机制说明：
/// 1. 通过 AST 属性与换行特征识别并放行 `<pre>` 块级代码（保留其 [Scrollbar] 与 [codeblockDecoration]）；
/// 2. 对行内 `code` 生成 [WidgetSpan] 并居中对齐（[PlaceholderAlignment.middle]）；
/// 3. 返回 [Text.rich] 供 `flutter_markdown` 的 `_mergeInlineChildren` 归并进段落富文本中，
///    保持 [SelectableText] 统一可选/复制能力与正常行高。
class InlineCodeElementBuilder extends MarkdownElementBuilder {
  InlineCodeElementBuilder({
    this.backgroundColor,
    this.textStyle,
    this.padding = kInlineCodePadding,
    this.borderRadius = const BorderRadius.all(
      Radius.circular(kInlineCodeBorderRadius),
    ),
  });

  /// pill 背景色（未传时从 preferredStyle?.backgroundColor 或 systemGrey5 获取）。
  final Color? backgroundColor;

  /// 文字样式（未传时从 preferredStyle 或 13pt monospace 基准派生）。
  final TextStyle? textStyle;

  /// pill 内部留白。
  final EdgeInsetsGeometry padding;

  /// pill 圆角。
  final BorderRadiusGeometry borderRadius;

  /// 判断当前 AST 元素是否为 `<pre>` 块级代码中的 `<code>`。
  ///
  /// CommonMark / GFM 规范中：
  /// - 块级代码（Fenced/Indented）恒以换行符 `\n` 结尾或携带 `language-*` class / metadata 属性；
  /// - 行内代码（Inline code span）规范要求内部换行均转换为单个空格，且无 class/metadata 属性。
  bool _isCodeBlock(md.Element element) {
    if (element.attributes.containsKey('class') ||
        element.attributes.containsKey('data-metadata')) {
      return true;
    }
    final text = element.textContent;
    return text.contains('\n') || text.endsWith('\n');
  }

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    if (element.tag == 'code') {
      if (_isCodeBlock(element)) {
        // 处于代码块 (<pre>) 内部，放行给默认 codeblock 渲染管道
        return null;
      }

      final color = backgroundColor ??
          preferredStyle?.backgroundColor ??
          CupertinoColors.systemGrey5.resolveFrom(context);

      final baseStyle = preferredStyle ??
          textStyle ??
          TextStyle(
            fontSize: 13,
            height: 1.4,
            fontFamily: 'monospace',
            color: CupertinoColors.label.resolveFrom(context),
          );

      // 将内层文本背景置为透明，避免与外层 pill Container 背景重复叠加
      final innerTextStyle = baseStyle.copyWith(
        backgroundColor: const Color(0x00000000),
      );

      final text = element.textContent;

      return Text.rich(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: color,
              borderRadius: borderRadius,
            ),
            child: Text(
              text,
              style: innerTextStyle,
            ),
          ),
        ),
      );
    }

    return null;
  }
}

/// 创建通用 Markdown 元素构建器映射表（注册 code 标签以支持行内 pill）。
Map<String, MarkdownElementBuilder> createMarkdownElementBuilders(
  BuildContext context, {
  Color? codeBackgroundColor,
  TextStyle? codeTextStyle,
  EdgeInsetsGeometry codePadding = kInlineCodePadding,
  BorderRadiusGeometry codeBorderRadius = const BorderRadius.all(
    Radius.circular(kInlineCodeBorderRadius),
  ),
}) {
  final builder = InlineCodeElementBuilder(
    backgroundColor: codeBackgroundColor,
    textStyle: codeTextStyle,
    padding: codePadding,
    borderRadius: codeBorderRadius,
  );
  return <String, MarkdownElementBuilder>{
    'code': builder,
  };
}

/// assistant / memory 等正文场景 Markdown 构建器（灰色 pill 底色）。
Map<String, MarkdownElementBuilder> createAssistantMarkdownBuilders(
  BuildContext context,
) {
  final label = CupertinoColors.label.resolveFrom(context);
  final grey5 = CupertinoColors.systemGrey5.resolveFrom(context);
  return createMarkdownElementBuilders(
    context,
    codeBackgroundColor: grey5,
    codeTextStyle: TextStyle(
      fontSize: 13,
      height: 1.4,
      fontFamily: 'monospace',
      color: label,
    ),
  );
}

/// user 气泡场景 Markdown 构建器（蓝底半透明白 pill 底色）。
Map<String, MarkdownElementBuilder> createUserMarkdownBuilders(
  BuildContext context,
) {
  return createMarkdownElementBuilders(
    context,
    codeBackgroundColor: CupertinoColors.white.withValues(alpha: 0.22),
    codeTextStyle: const TextStyle(
      fontSize: 13,
      height: 1.4,
      fontFamily: 'monospace',
      color: CupertinoColors.white,
    ),
  );
}