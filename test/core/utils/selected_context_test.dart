import 'package:flutter_test/flutter_test.dart';
import 'package:hermex_flutter/core/utils/selected_context.dart';

// ignore_for_file: prefer_single_quotes
void main() {
  group('SelectedContextParser — 基础解析', () {
    test('单块 + 正文：解析 label/quote 与 cleanText', () {
      const raw = '请解释一下\n\n**Context 1:**\n'
          '<!-- hermes-selected-context -->\n'
          '> hello\n'
          '> world\n\n';
      final r = SelectedContextParser.parse(raw);
      expect(r.blocks.length, 1);
      expect(r.blocks.first.label, 'Context 1');
      expect(r.blocks.first.quote, 'hello\nworld');
      expect(r.cleanText, '请解释一下');
    });

    test('多块 + 无正文：两张卡片，cleanText 为空', () {
      const raw = '**报错:**\n'
          '<!-- hermes-selected-context -->\n'
          '> Null check operator used on a null value\n\n'
          '**Context 2:**\n'
          '<!-- hermes-selected-context -->\n'
          '> lib/main.dart:42\n\n';
      final r = SelectedContextParser.parse(raw);
      expect(r.blocks.length, 2);
      expect(r.blocks[0].label, '报错');
      expect(r.blocks[1].label, 'Context 2');
      expect(r.cleanText, '');
    });

    test('多块顺序保留', () {
      const raw = '**A:**\n<!-- hermes-selected-context -->\n> a\n\n'
          '**B:**\n<!-- hermes-selected-context -->\n> b\n\n'
          '**C:**\n<!-- hermes-selected-context -->\n> c';
      final r = SelectedContextParser.parse(raw);
      expect(r.blocks.map((b) => b.label).toList(), ['A', 'B', 'C']);
    });

    test('无 marker 不处理，原样归入 cleanText', () {
      const raw = '**短label:**\nhello';
      final r = SelectedContextParser.parse(raw);
      expect(r.blocks, isEmpty);
      expect(r.cleanText, raw);
    });

    test('marker 后无 > 行不处理', () {
      const raw = '**label:**\n<!-- hermes-selected-context -->\n';
      final r = SelectedContextParser.parse(raw);
      expect(r.blocks, isEmpty);
      expect(r.hasBlocks, isFalse);
    });

    test('空引用（"> " 空白）不计块', () {
      const raw = '**label:**\n<!-- hermes-selected-context -->\n>    \n';
      final r = SelectedContextParser.parse(raw);
      expect(r.blocks, isEmpty);
    });

    test('超 200 字符 label 不处理', () {
      final longLabel = 'a' * 201;
      final raw = '**$longLabel:**\n<!-- hermes-selected-context -->\n> hello';
      final r = SelectedContextParser.parse(raw);
      expect(r.blocks, isEmpty);
      expect(r.cleanText.contains(longLabel), isTrue);
    });

    test('200 字符 label 可处理', () {
      final label200 = 'a' * 200;
      final raw = '**$label200:**\n<!-- hermes-selected-context -->\n> hi';
      final r = SelectedContextParser.parse(raw);
      expect(r.blocks.length, 1);
      expect(r.blocks.first.label, label200);
    });

    test('尾随空白的 label 行可处理', () {
      const raw = '**label:**   \n<!-- hermes-selected-context -->\n> hi';
      final r = SelectedContextParser.parse(raw);
      expect(r.blocks.length, 1);
      expect(r.blocks.first.label, 'label');
    });

    test('> quote 前有空格不识别为引用', () {
      const raw = '**label:**\n<!-- hermes-selected-context -->\n > quote';
      final r = SelectedContextParser.parse(raw);
      // 只有 " > quote" 不以 > 开头，quoteLines 为空 → 回退
      expect(r.blocks, isEmpty);
    });

    test('>quote 无空格可识别', () {
      const raw = '**label:**\n<!-- hermes-selected-context -->\n>quote';
      final r = SelectedContextParser.parse(raw);
      expect(r.blocks.length, 1);
      expect(r.blocks.first.quote, 'quote');
    });

    test('> 空行剥离保留空字符串 join', () {
      const raw = '**label:**\n<!-- hermes-selected-context -->\n> a\n> \n> c';
      final r = SelectedContextParser.parse(raw);
      expect(r.blocks.first.quote, 'a\n\nc');
    });

    test('归一化：块移除后连续空行压缩为 \\n\\n', () {
      const raw =
          'hello\n\n\n\n**label:**\n<!-- hermes-selected-context -->\n> hi\n\n\n\nworld';
      final r = SelectedContextParser.parse(raw);
      expect(r.blocks.length, 1);
      // 移除块后 hello 与 world 之间不应有 3+ 空行
      expect(r.cleanText.contains('\n\n\n'), isFalse);
      expect(r.cleanText, 'hello\n\nworld');
    });

    test('marker 严格相等，前后空白不容忍', () {
      const raw = '**label:**\n <!-- hermes-selected-context -->\n> hi';
      final r = SelectedContextParser.parse(raw);
      expect(r.blocks, isEmpty);
    });

    test('空输入返回空结果', () {
      final r = SelectedContextParser.parse('');
      expect(r.blocks, isEmpty);
      expect(r.cleanText, '');
    });
  });

  group('围栏保护', () {
    test('围栏内不应解析', () {
      const raw = '请看代码：\n```\n**假的:**\n'
          '<!-- hermes-selected-context -->\n'
          '> 不应解析\n'
          '```';
      final r = SelectedContextParser.parse(raw);
      expect(r.blocks, isEmpty);
      expect(r.cleanText.contains('**假的:**'), isTrue);
    });

    test('行内代码内不应解析', () {
      const raw =
          '使用 `**假的:**\\n<!-- hermes-selected-context -->\\n> hi` 说明';
      // 行内反引号保护：内容在 stash 中，解析器看不到
      final r = SelectedContextParser.parse(raw);
      expect(r.blocks, isEmpty);
    });

    test('围栏外仍可解析', () {
      const raw = '```\ncode\n```\n\n'
          '**real:**\n<!-- hermes-selected-context -->\n> hi';
      final r = SelectedContextParser.parse(raw);
      expect(r.blocks.length, 1);
      expect(r.blocks.first.label, 'real');
    });

    test('跨围栏不处理（label 在围栏内，marker 在外 — 已提存不匹配）', () {
      const raw = '```\n**label:**\n```\n<!-- hermes-selected-context -->\n> hi';
      final r = SelectedContextParser.parse(raw);
      expect(r.blocks, isEmpty);
    });
  });

  group('buildForApi', () {
    test('单块串联格式正确', () {
      const blocks = [SelectedContextBlock(label: 'Context 1', quote: 'hello\nworld')];
      final s = SelectedContextParser.buildForApi(blocks);
      expect(s, '**Context 1:**\n<!-- hermes-selected-context -->\n> hello\n> world');
    });

    test('多块以 \\n\\n 拼接', () {
      const blocks = [
        SelectedContextBlock(label: 'A', quote: 'a'),
        SelectedContextBlock(label: 'B', quote: 'b'),
      ];
      final s = SelectedContextParser.buildForApi(blocks);
      expect(s, '**A:**\n<!-- hermes-selected-context -->\n> a\n\n**B:**\n<!-- hermes-selected-context -->\n> b');
    });

    test('空列表返回空', () {
      expect(SelectedContextParser.buildForApi([]), '');
    });

    test('空 quote 跳过', () {
      const blocks = [
        SelectedContextBlock(label: 'A', quote: '   '),
        SelectedContextBlock(label: 'B', quote: 'ok'),
      ];
      final s = SelectedContextParser.buildForApi(blocks);
      expect(s.contains('**A:**'), isFalse);
      expect(s.contains('**B:**'), isTrue);
    });

    test('round-trip: buildForApi → parse 还原', () {
      const blocks = [
        SelectedContextBlock(label: 'Context 1', quote: 'hello\nworld'),
        SelectedContextBlock(label: '报错', quote: 'Null check'),
      ];
      final api = SelectedContextParser.buildForApi(blocks);
      final r = SelectedContextParser.parse(api);
      expect(r.blocks.length, 2);
      expect(r.blocks[0].label, 'Context 1');
      expect(r.blocks[0].quote, 'hello\nworld');
      expect(r.blocks[1].label, '报错');
    });
  });

  group('preview', () {
    test('360 截断加 …', () {
      final long = 'a' * 400;
      final p = SelectedContextParser.preview(long, max: 360);
      expect(p.length, 361); // 360 + …
      expect(p.endsWith('…'), isTrue);
    });

    test('精确 360 不截断', () {
      final s = 'a' * 360;
      expect(SelectedContextParser.preview(s, max: 360), s);
    });

    test('归一化 \\r\\n → \\n 与 \\n{3,} → \\n\\n', () {
      const raw = 'a\r\nb\r\n\n\n\nc';
      final p = SelectedContextParser.preview(raw);
      expect(p.contains('\r'), isFalse);
      expect(p.contains('\n\n\n'), isFalse);
      expect(p, 'a\nb\n\nc');
    });

    test('空归一化返回空', () {
      expect(SelectedContextParser.preview('   \n\n  '), '');
    });

    test('截断后 trimEnd', () {
      final s = '${'a' * 359}   b';
      final p = SelectedContextParser.preview(s, max: 360);
      expect(p.endsWith('…'), isTrue);
      expect(p.endsWith(' …'), isFalse); // trimRight 去尾空格
    });
  });

  group('SelectedContextParseResult 别名', () {
    test('SelectedContextParseResult 与 SelectedContextParse 等价', () {
      const r = SelectedContextParse(blocks: [], cleanText: 'hi');
      expect(r, isA<SelectedContextParseResult>());
    });
  });
}
