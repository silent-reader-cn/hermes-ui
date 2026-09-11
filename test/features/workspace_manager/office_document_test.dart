import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/features/workspace_manager/office_document.dart';

void main() {
  group('OfficeDocumentParser - docx', () {
    test('sample.docx parses headings, paragraphs, and tables', () {
      final bytes = File('test/fixtures/office/sample.docx').readAsBytesSync();
      final doc = OfficeDocumentParser.parse(bytes, '.docx');

      expect(doc.kind, OfficeDocumentKind.docx);
      expect(doc.blocks.isNotEmpty, isTrue);

      // Paragraph 1: Heading1
      final p1 = doc.blocks[0];
      expect(p1.isParagraph, isTrue);
      expect(p1.heading, 'Heading1');
      expect(p1.text, '项目周报 Report 周三');

      // Paragraph 2: mixed Chinese/English with special characters & and <tag>
      final p2 = doc.blocks[1];
      expect(p2.isParagraph, isTrue);
      expect(p2.heading, isNull);
      expect(p2.text, contains('hello world'));
      expect(p2.text, contains('&'));
      expect(p2.text, contains('<tag>'));
      expect(p2.text, contains('加粗补充'));

      // Paragraph 3: plain text
      final p3 = doc.blocks[2];
      expect(p3.isParagraph, isTrue);
      expect(p3.text, '第二段：纯文本。');

      // Table: 2 rows x 3 cols
      final tableBlock = doc.blocks.firstWhere((b) => b.isTable);
      final table = tableBlock.table!;
      expect(table.length, 2);
      expect(table[0], ['工作项', '状态', '负责人']);
      expect(table[1], ['PDF预览', '进行中', '柚子']);
    });

    test('broken.docx throws OfficeParseException', () {
      final bytes = File('test/fixtures/office/broken.docx').readAsBytesSync();
      expect(
        () => OfficeDocumentParser.parse(bytes, '.docx'),
        throwsA(isA<OfficeParseException>()),
      );
    });

    test('missing_part.docx throws OfficeParseException', () {
      final bytes =
          File('test/fixtures/office/missing_part.docx').readAsBytesSync();
      expect(
        () => OfficeDocumentParser.parse(bytes, '.docx'),
        throwsA(isA<OfficeParseException>()),
      );
    });
  });

  group('OfficeDocumentParser - xlsx', () {
    test('sample.xlsx parses multiple sheets, shared strings, inlineStr and aligned empty cells', () {
      final bytes = File('test/fixtures/office/sample.xlsx').readAsBytesSync();
      final doc = OfficeDocumentParser.parse(bytes, '.xlsx');

      expect(doc.kind, OfficeDocumentKind.xlsx);
      expect(doc.sheets.length, 2);

      // Sheet 1: 销售
      final sheet1 = doc.sheets[0];
      expect(sheet1.name, '销售');
      expect(sheet1.rows.length, greaterThanOrEqualTo(3));

      // Row 1: A1=产品, B1=销量, C1='', D1=富文本A富文本B (shared string + rich text runs merged)
      expect(sheet1.rows[0][0], '产品');
      expect(sheet1.rows[0][1], '销量');
      expect(sheet1.rows[0][2], '');
      expect(sheet1.rows[0][3], '富文本A富文本B');

      // Row 2: A2=Apple, B2=120, C2='', D1 column exists in grid alignment
      expect(sheet1.rows[1][0], 'Apple');
      expect(sheet1.rows[1][1], '120');
      expect(sheet1.rows[1][2], '');
      expect(sheet1.rows[1].length, greaterThanOrEqualTo(4));

      // Row 3: A3=橙子 inline (inlineStr), C3=7.5
      expect(sheet1.rows[2][0], '橙子 inline');
      expect(sheet1.rows[2][2], '7.5');

      // Sheet 2: 备注
      final sheet2 = doc.sheets[1];
      expect(sheet2.name, '备注');
      expect(sheet2.rows.isNotEmpty, isTrue);
      expect(sheet2.rows[0][0], '备注页内容');
    });
  });

  group('OfficeDocumentParser - pptx', () {
    test('sample.pptx parses slides and text lines', () {
      final bytes = File('test/fixtures/office/sample.pptx').readAsBytesSync();
      final doc = OfficeDocumentParser.parse(bytes, '.pptx');

      expect(doc.kind, OfficeDocumentKind.pptx);
      expect(doc.slides.length, 2);

      // Slide 1
      expect(doc.slides[0].index, 1);
      expect(doc.slides[0].lines, ['产品介绍', '第一页 要点一']);

      // Slide 2
      expect(doc.slides[1].index, 2);
      expect(doc.slides[1].lines, ['第二页标题']);
    });
  });

  group('OfficeDocumentParser - legacy OLE2', () {
    test('extracts ASCII and UTF-16LE Chinese fragments', () {
      final builder = BytesBuilder();
      // Leading binary noise
      builder.add(List.filled(16, 0x01));
      // ASCII text fragment
      builder.add(ascii.encode('Microsoft Word 97-2003 Document Header'));
      // Intermediate binary noise
      builder.add(List.filled(16, 0xFF));
      // UTF-16LE Chinese text fragment
      final chinese = '这是一份旧版文档中文内容测试';
      for (final codeUnit in chinese.codeUnits) {
        builder.addByte(codeUnit & 0xFF);
        builder.addByte((codeUnit >> 8) & 0xFF);
      }
      // Trailing binary noise
      builder.add(List.filled(8, 0x00));
      // ASCII footer
      builder.add(ascii.encode('Footer section text'));

      final bytes = builder.toBytes();
      final doc = OfficeDocumentParser.parse(bytes, '.doc');

      expect(doc.kind, OfficeDocumentKind.legacy);
      expect(doc.legacyText, contains('Microsoft Word 97-2003 Document Header'));
      expect(doc.legacyText, contains('这是一份旧版文档中文内容测试'));
      expect(doc.legacyText, contains('Footer section text'));
    });

    test('all-zero bytes throws OfficeParseException', () {
      final zeros = Uint8List(256);
      expect(
        () => OfficeDocumentParser.parse(zeros, '.doc'),
        throwsA(isA<OfficeParseException>()),
      );
      expect(
        () => OfficeDocumentParser.parse(zeros, '.xls'),
        throwsA(isA<OfficeParseException>()),
      );
      expect(
        () => OfficeDocumentParser.parse(zeros, '.ppt'),
        throwsA(isA<OfficeParseException>()),
      );
    });

    test('file larger than 50MB throws OfficeParseException with isTooLarge=true', () {
      final largeBytes = Uint8List(50 * 1024 * 1024 + 1);
      expect(
        () => OfficeDocumentParser.parse(largeBytes, '.docx'),
        throwsA(
          isA<OfficeParseException>().having(
            (e) => e.isTooLarge,
            'isTooLarge',
            isTrue,
          ),
        ),
      );
    });
  });
}
