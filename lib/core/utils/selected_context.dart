/// SelectedContext 解析器 — 对齐 WebUI `messages.js` / `ui.js` 行级扫描规格.
///
/// 传输形态（WebUI）：
/// ```
/// **LABEL:**\n<!-- hermes-selected-context -->\n> line1\n> line2
/// ```
/// 多块以 `\n\n` 拼接；围栏与行内代码受保护不解析.
library;

import 'dart:core';

/// 选中上下文块标记（严格相等，无 trim）。
const String kSelectedContextMarker = '<!-- hermes-selected-context -->';

/// Label 行正则：`^\*\*([^\n]{1,200}):\*\*\s*$`
final RegExp kSelectedContextLabelRegex =
    RegExp(r'^\*\*([^\n]{1,200}):\*\*\s*$');

/// 引用行判定：行首 `>`
final RegExp kSelectedContextQuoteLineRegex = RegExp(r'^>');

/// 引用前缀剥离：`^>[ \t]?`
final RegExp kSelectedContextQuoteStripRegex = RegExp(r'^>[ \t]?');

/// 多行围栏代码块（复用 ChatMediaParser 范式）。
final RegExp kSelectedContextFencedBlockRegex = RegExp(
  r'(^|\n)[ ]{0,3}(`{3,})[^\n`]*\n[\s\S]*?\n[ ]{0,3}\2`*(?=\n|$)',
);

/// 行内代码反引号跨度.
final RegExp kSelectedContextInlineCodeRegex = RegExp(r'`[^`\n]+`');

/// 单个选中上下文块（对应一次 addNamedContextBlock）。
class SelectedContextBlock {
  const SelectedContextBlock({
    required this.label,
    required this.quote,
  });

  /// 卡片标题（已 trim，空回退 "Context" 由渲染侧处理，1-200 字符）。
  final String label;

  /// 引用原文（已剥离 `> ` 前缀、保留内部换行、尾部 \s+ 已去除）。
  final String quote;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SelectedContextBlock &&
          runtimeType == other.runtimeType &&
          label == other.label &&
          quote == other.quote;

  @override
  int get hashCode => label.hashCode ^ quote.hashCode;

  @override
  String toString() => 'SelectedContextBlock(label: $label, quote: $quote)';
}

/// 解析结果：卡片列表 + 剥离卡片后的剩余文本.
class SelectedContextParse {
  const SelectedContextParse({
    required this.blocks,
    required this.cleanText,
  });

  final List<SelectedContextBlock> blocks;

  /// 已移除所有选中块后的剩余文本；可能为空.
  final String cleanText;

  /// 是否含有效块.
  bool get hasBlocks => blocks.isNotEmpty;
}

/// 兼容别名（spec 曾用名）.
typedef SelectedContextParseResult = SelectedContextParse;

/// SelectedContext 解析器 — 纯函数，无状态.
class SelectedContextParser {
  const SelectedContextParser._();

  /// 行级扫描解析（对齐 `ui.js:320-339` stashSelectedContextBlocks）。
  static SelectedContextParse parse(String raw) {
    if (raw.isEmpty) {
      return const SelectedContextParse(blocks: [], cleanText: '');
    }

    // 1. 提围栏与行内代码（占位保护）。
    final stash = <String>[];
    var s = raw.replaceAllMapped(kSelectedContextFencedBlockRegex, (m) {
      final matched = m.group(0)!;
      stash.add(matched);
      return '\x00FENCE_${stash.length - 1}\x00';
    });
    s = s.replaceAllMapped(kSelectedContextInlineCodeRegex, (m) {
      final matched = m.group(0)!;
      stash.add(matched);
      return '\x00CODE_${stash.length - 1}\x00';
    });

    // 2. 行级扫描.
    final lines = s.split('\n');
    final blocks = <SelectedContextBlock>[];
    final outLines = <String>[];

    for (var i = 0; i < lines.length; i++) {
      final lm = kSelectedContextLabelRegex.firstMatch(lines[i]);
      if (lm == null) {
        outLines.add(lines[i]);
        continue;
      }
      final rawLabel = lm.group(1) ?? '';
      final label = rawLabel.trim();
      if (label.isEmpty) {
        outLines.add(lines[i]);
        continue;
      }
      final j0 = i + 1;
      if (j0 >= lines.length || lines[j0] != kSelectedContextMarker) {
        outLines.add(lines[i]);
        continue;
      }
      var j = j0 + 1;
      final q = <String>[];
      while (j < lines.length && kSelectedContextQuoteLineRegex.hasMatch(lines[j])) {
        q.add(lines[j].replaceFirst(kSelectedContextQuoteStripRegex, ''));
        j++;
      }
      if (q.isEmpty) {
        outLines.add(lines[i]);
        continue;
      }
      final quote = q.join('\n').replaceAll(RegExp(r'\s+$'), '');
      if (quote.isEmpty) {
        // 空引用不计块，回退普通文本.
        outLines.add(lines[i]);
        continue;
      }
      // 空白-only 的引用（剥离后 join 为空或仅空白）已在上一行处理；
      // 但若 quote 仅含空白字符（例如 ">   "），剥离后为 "  "，trim 后空.
      if (quote.trim().isEmpty) {
        outLines.add(lines[i]);
        continue;
      }
      blocks.add(SelectedContextBlock(label: label, quote: quote));
      // 当前块行不入 outLines；跳至引用区后一行之前.
      i = j - 1;
    }

    var clean = outLines.join('\n');

    // 还原围栏/行内代码.
    clean = clean.replaceAllMapped(
      RegExp(r'\x00(?:FENCE|CODE)_(\d+)\x00'),
      (m) {
        final idx = int.tryParse(m.group(1) ?? '') ?? -1;
        if (idx >= 0 && idx < stash.length) {
          return stash[idx];
        }
        return m.group(0)!;
      },
    );

    // 块移除后连续空行压缩为最多 \n\n（对齐 WebUI \n{3,}→\n\n）.
    clean = clean.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
    if (clean.trim().isEmpty) {
      clean = '';
    }

    return SelectedContextParse(blocks: blocks, cleanText: clean);
  }

  /// 按 WebUI 同格式串块（不含用户正文）。
  ///
  /// 每块：`**label:**\n<!-- marker -->\n> line...`
  /// 多块以 `\n\n` 拼接.
  static String buildForApi(List<SelectedContextBlock> blocks) {
    if (blocks.isEmpty) return '';
    final parts = <String>[];
    for (final b in blocks) {
      final normalized = b.quote
          .replaceAll(RegExp(r'\r\n?'), '\n')
          .replaceAll(RegExp(r'\n{3,}'), '\n\n')
          .trim();
      if (normalized.isEmpty) continue;
      final quoted = normalized.split('\n').map((l) => '> $l').join('\n');
      parts.add('**${b.label}:**\n$kSelectedContextMarker\n$quoted');
    }
    return parts.join('\n\n');
  }

  /// 引用预览截断（对齐 `messages.js:926-931` _selectedContextPreview）。
  ///
  /// 归一化：`\r\n`/`\r`→`\n`，`\n{3,}`→`\n\n`，trim；超过 [max] 则 `slice(0,max).trimEnd() + '…'`.
  static String preview(String text, {int max = 360}) {
    final normalized = text
        .replaceAll(RegExp(r'\r\n?'), '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
    if (normalized.isEmpty) return '';
    if (normalized.length > max) {
      return '${normalized.substring(0, max).trimRight()}…';
    }
    return normalized;
  }

  /// 内部复用：格式化单条引用（marker + > 前缀），对外暴露以便待发区组装.
  static String formatQuote(String text) {
    final normalized = text
        .replaceAll(RegExp(r'\r\n?'), '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
    if (normalized.isEmpty) return '';
    return '$kSelectedContextMarker\n${normalized.split('\n').map((l) => '> $l').join('\n')}';
  }
}
