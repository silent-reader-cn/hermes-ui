import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// Exception thrown when parsing an office document fails.
class OfficeParseException implements Exception {
  final String message;
  final bool isTooLarge;

  const OfficeParseException(this.message, {this.isTooLarge = false});

  @override
  String toString() => 'OfficeParseException: $message';
}

/// Kind of office document parsed.
enum OfficeDocumentKind {
  docx,
  xlsx,
  pptx,
  legacy,
}

/// A block within a docx document (paragraph or table).
class OfficeBlock {
  final String? heading;
  final String? text;
  final List<List<String>>? table;

  const OfficeBlock({this.heading, this.text, this.table});

  bool get isTable => table != null;
  bool get isParagraph => table == null;
}

/// A paragraph block in a docx document.
class OfficeParagraph extends OfficeBlock {
  OfficeParagraph({required super.text, super.heading});
}

/// A table block in a docx document.
class OfficeTable extends OfficeBlock {
  OfficeTable(List<List<String>> table) : super(table: table);
}

/// A sheet in an xlsx workbook.
class OfficeSheet {
  final String name;
  final List<List<String>> rows;

  const OfficeSheet({required this.name, required this.rows});
}

/// A slide in a pptx presentation.
class OfficeSlide {
  final int index;
  final List<String> lines;

  const OfficeSlide({required this.index, required this.lines});
}

/// Parsed office document structure.
class OfficeDocument {
  final OfficeDocumentKind kind;
  final List<OfficeBlock> blocks;
  final List<OfficeSheet> sheets;
  final List<OfficeSlide> slides;
  final String legacyText;

  const OfficeDocument({
    required this.kind,
    this.blocks = const [],
    this.sheets = const [],
    this.slides = const [],
    this.legacyText = '',
  });
}

/// Parser functions for office documents (docx, xlsx, pptx, doc, xls, ppt).
class OfficeDocumentParser {
  OfficeDocumentParser._();

  static const int maxFileBytes = 50 * 1024 * 1024; // 50MB
  static const int maxZipEntryBytes = 20 * 1024 * 1024; // 20MB
  static const int maxLegacyOutputChars = 200 * 1024; // 200KB

  /// Parse bytes according to the file extension.
  static OfficeDocument parse(Uint8List bytes, String extension) {
    if (bytes.length > maxFileBytes) {
      throw const OfficeParseException('File too large', isTooLarge: true);
    }
    final ext = extension.startsWith('.')
        ? extension.toLowerCase()
        : '.$extension'.toLowerCase();

    switch (ext) {
      case '.docx':
        return parseDocx(bytes);
      case '.xlsx':
        return parseXlsx(bytes);
      case '.pptx':
        return parsePptx(bytes);
      case '.doc':
      case '.xls':
      case '.ppt':
        return parseLegacy(bytes);
      default:
        throw OfficeParseException('Unsupported office file extension: $ext');
    }
  }

  /// Parse docx bytes into [OfficeDocument].
  static OfficeDocument parseDocx(Uint8List bytes) {
    if (bytes.length > maxFileBytes) {
      throw const OfficeParseException('File too large', isTooLarge: true);
    }
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes, verify: false);
    } catch (e) {
      throw OfficeParseException('Invalid docx archive: $e');
    }

    final docEntry = archive.findFile('word/document.xml');
    if (docEntry == null) {
      throw const OfficeParseException(
          'Missing word/document.xml in docx archive');
    }
    if (docEntry.size > maxZipEntryBytes) {
      throw const OfficeParseException('document.xml exceeds entry limit');
    }

    final XmlDocument xml;
    try {
      xml = XmlDocument.parse(utf8.decode(docEntry.content));
    } catch (e) {
      throw OfficeParseException('Failed to parse word/document.xml: $e');
    }

    final body = xml.findAllElements('body', namespaceUri: '*').firstOrNull;
    if (body == null) {
      throw const OfficeParseException('Missing body in word/document.xml');
    }

    final blocks = <OfficeBlock>[];

    for (final child in body.children.whereType<XmlElement>()) {
      final localName = child.name.local;
      if (localName == 'p') {
        final heading = _extractDocxHeading(child);
        final text = _extractDocxParagraphText(child);
        if (text.isNotEmpty) {
          blocks.add(OfficeParagraph(text: text, heading: heading));
        }
      } else if (localName == 'tbl') {
        final table = _extractDocxTable(child);
        if (table.isNotEmpty) {
          blocks.add(OfficeTable(table));
        }
      }
    }

    return OfficeDocument(kind: OfficeDocumentKind.docx, blocks: blocks);
  }

  static String? _extractDocxHeading(XmlElement pElement) {
    for (final pPr in pElement.findElements('pPr', namespaceUri: '*')) {
      for (final pStyle in pPr.findElements('pStyle', namespaceUri: '*')) {
        final val = pStyle.getAttribute('w:val') ??
            pStyle.getAttribute('val') ??
            _attrLocal(pStyle, 'val');
        if (val != null && val.isNotEmpty) {
          return val;
        }
      }
    }
    return null;
  }

  static String _extractDocxParagraphText(XmlElement pElement) {
    final buffer = StringBuffer();
    _walkDocxText(pElement, buffer);
    return buffer.toString().trim();
  }

  static void _walkDocxText(XmlNode node, StringBuffer buffer) {
    for (final child in node.children) {
      if (child is XmlElement) {
        final name = child.name.local;
        if (name == 't') {
          buffer.write(child.innerText);
        } else if (name == 'tab') {
          buffer.write(' ');
        } else if (name == 'br' || name == 'cr') {
          buffer.write('\n');
        } else {
          _walkDocxText(child, buffer);
        }
      }
    }
  }

  static List<List<String>> _extractDocxTable(XmlElement tblElement) {
    final rows = <List<String>>[];
    for (final tr in tblElement.findElements('tr', namespaceUri: '*')) {
      final row = <String>[];
      for (final tc in tr.findElements('tc', namespaceUri: '*')) {
        final cellParagraphs = <String>[];
        for (final p in tc.findElements('p', namespaceUri: '*')) {
          final pText = _extractDocxParagraphText(p);
          if (pText.isNotEmpty) {
            cellParagraphs.add(pText);
          }
        }
        row.add(cellParagraphs.join('\n'));
      }
      if (row.isNotEmpty) {
        rows.add(row);
      }
    }
    return rows;
  }

  /// Parse xlsx bytes into [OfficeDocument].
  static OfficeDocument parseXlsx(Uint8List bytes) {
    if (bytes.length > maxFileBytes) {
      throw const OfficeParseException('File too large', isTooLarge: true);
    }
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes, verify: false);
    } catch (e) {
      throw OfficeParseException('Invalid xlsx archive: $e');
    }

    final wbEntry = archive.findFile('xl/workbook.xml');
    if (wbEntry == null) {
      throw const OfficeParseException(
          'Missing xl/workbook.xml in xlsx archive');
    }
    if (wbEntry.size > maxZipEntryBytes) {
      throw const OfficeParseException('workbook.xml exceeds entry limit');
    }

    final XmlDocument wbXml;
    try {
      wbXml = XmlDocument.parse(utf8.decode(wbEntry.content));
    } catch (e) {
      throw OfficeParseException('Failed to parse xl/workbook.xml: $e');
    }

    // Parse xl/_rels/workbook.xml.rels
    final relsMap = <String, String>{};
    final relsEntry = archive.findFile('xl/_rels/workbook.xml.rels');
    if (relsEntry != null && relsEntry.size <= maxZipEntryBytes) {
      try {
        final relsXml = XmlDocument.parse(utf8.decode(relsEntry.content));
        for (final rel
            in relsXml.findAllElements('Relationship', namespaceUri: '*')) {
          final id = rel.getAttribute('Id') ?? '';
          final target = rel.getAttribute('Target') ?? '';
          if (id.isNotEmpty && target.isNotEmpty) {
            relsMap[id] = target;
          }
        }
      } catch (_) {}
    }

    // Parse xl/sharedStrings.xml
    final sharedStrings = <String>[];
    final sstEntry = archive.findFile('xl/sharedStrings.xml');
    if (sstEntry != null && sstEntry.size <= maxZipEntryBytes) {
      try {
        final sstXml = XmlDocument.parse(utf8.decode(sstEntry.content));
        for (final si in sstXml.findAllElements('si', namespaceUri: '*')) {
          final buf = StringBuffer();
          for (final t in si.findAllElements('t', namespaceUri: '*')) {
            buf.write(t.innerText);
          }
          sharedStrings.add(buf.toString());
        }
      } catch (_) {}
    }

    final sheets = <OfficeSheet>[];
    final sheetElements = wbXml.findAllElements('sheet', namespaceUri: '*');
    int fallbackIdx = 1;

    for (final sheetEl in sheetElements) {
      final sheetName = sheetEl.getAttribute('name') ?? 'Sheet$fallbackIdx';
      final rId = sheetEl.getAttribute('r:id') ??
          sheetEl.getAttribute('id') ??
          _attrLocal(sheetEl, 'id') ??
          '';

      String target = relsMap[rId] ?? 'worksheets/sheet$fallbackIdx.xml';
      if (target.startsWith('/')) target = target.substring(1);
      final sheetPath = target.startsWith('xl/') ? target : 'xl/$target';

      fallbackIdx++;

      final sheetEntry = archive.findFile(sheetPath);
      if (sheetEntry == null || sheetEntry.size > maxZipEntryBytes) {
        sheets.add(OfficeSheet(name: sheetName, rows: const []));
        continue;
      }

      final XmlDocument sheetXml;
      try {
        sheetXml = XmlDocument.parse(utf8.decode(sheetEntry.content));
      } catch (_) {
        sheets.add(OfficeSheet(name: sheetName, rows: const []));
        continue;
      }

      final parsedRows = _parseWorksheetRows(sheetXml, sharedStrings);
      sheets.add(OfficeSheet(name: sheetName, rows: parsedRows));
    }

    return OfficeDocument(kind: OfficeDocumentKind.xlsx, sheets: sheets);
  }

  static List<List<String>> _parseWorksheetRows(
    XmlDocument sheetXml,
    List<String> sharedStrings,
  ) {
    final rowMap = <int, Map<int, String>>{};
    int maxColIndex = -1;
    int maxRowIndex = -1;

    final rowElements = sheetXml.findAllElements('row', namespaceUri: '*');
    int sequentialRow = 1;

    for (final rowEl in rowElements) {
      final rAttr = rowEl.getAttribute('r');
      final rowNum =
          (rAttr != null ? int.tryParse(rAttr) : null) ?? sequentialRow;
      sequentialRow = rowNum + 1;
      final rIdx = rowNum - 1;
      if (rIdx < 0) continue;
      if (rIdx > maxRowIndex) maxRowIndex = rIdx;

      final cols = rowMap.putIfAbsent(rIdx, () => <int, String>{});

      int sequentialCol = 0;
      for (final cEl in rowEl.findElements('c', namespaceUri: '*')) {
        final cellRef = cEl.getAttribute('r');
        final int cIdx;
        if (cellRef != null && cellRef.isNotEmpty) {
          cIdx = _colRefToIndex(cellRef);
        } else {
          cIdx = sequentialCol;
        }
        sequentialCol = cIdx + 1;
        if (cIdx > maxColIndex) maxColIndex = cIdx;

        final t = cEl.getAttribute('t');
        final String val;
        if (t == 's') {
          final vEl = cEl.findElements('v', namespaceUri: '*').firstOrNull;
          final sIdx = vEl != null ? int.tryParse(vEl.innerText.trim()) : null;
          if (sIdx != null && sIdx >= 0 && sIdx < sharedStrings.length) {
            val = sharedStrings[sIdx];
          } else {
            val = vEl?.innerText.trim() ?? '';
          }
        } else if (t == 'inlineStr') {
          final isEl = cEl.findElements('is', namespaceUri: '*').firstOrNull;
          if (isEl != null) {
            final buf = StringBuffer();
            for (final tEl in isEl.findAllElements('t', namespaceUri: '*')) {
              buf.write(tEl.innerText);
            }
            val = buf.toString();
          } else {
            val = '';
          }
        } else {
          final vEl = cEl.findElements('v', namespaceUri: '*').firstOrNull;
          val = vEl != null ? vEl.innerText.trim() : '';
        }

        cols[cIdx] = val;
      }
    }

    if (maxRowIndex < 0 || maxColIndex < 0) {
      return const [];
    }

    final totalCols = maxColIndex + 1;
    final result = <List<String>>[];

    for (int r = 0; r <= maxRowIndex; r++) {
      final cols = rowMap[r];
      if (cols == null) {
        result.add(List.filled(totalCols, ''));
      } else {
        final rowList = List<String>.filled(totalCols, '');
        cols.forEach((c, v) {
          if (c < totalCols) rowList[c] = v;
        });
        result.add(rowList);
      }
    }

    return result;
  }

  static int _colRefToIndex(String cellRef) {
    int col = 0;
    for (int i = 0; i < cellRef.length; i++) {
      final code = cellRef.codeUnitAt(i);
      if (code >= 65 && code <= 90) {
        col = col * 26 + (code - 65 + 1);
      } else if (code >= 97 && code <= 122) {
        col = col * 26 + (code - 97 + 1);
      } else {
        break;
      }
    }
    return col > 0 ? col - 1 : 0;
  }

  /// Parse pptx bytes into [OfficeDocument].
  static OfficeDocument parsePptx(Uint8List bytes) {
    if (bytes.length > maxFileBytes) {
      throw const OfficeParseException('File too large', isTooLarge: true);
    }
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes, verify: false);
    } catch (e) {
      throw OfficeParseException('Invalid pptx archive: $e');
    }

    final presEntry = archive.findFile('ppt/presentation.xml');
    if (presEntry == null) {
      throw const OfficeParseException(
          'Missing ppt/presentation.xml in pptx archive');
    }
    if (presEntry.size > maxZipEntryBytes) {
      throw const OfficeParseException('presentation.xml exceeds entry limit');
    }

    final XmlDocument presXml;
    try {
      presXml = XmlDocument.parse(utf8.decode(presEntry.content));
    } catch (e) {
      throw OfficeParseException('Failed to parse ppt/presentation.xml: $e');
    }

    // Parse ppt/_rels/presentation.xml.rels
    final relsMap = <String, String>{};
    final relsEntry = archive.findFile('ppt/_rels/presentation.xml.rels');
    if (relsEntry != null && relsEntry.size <= maxZipEntryBytes) {
      try {
        final relsXml = XmlDocument.parse(utf8.decode(relsEntry.content));
        for (final rel
            in relsXml.findAllElements('Relationship', namespaceUri: '*')) {
          final id = rel.getAttribute('Id') ?? '';
          final target = rel.getAttribute('Target') ?? '';
          if (id.isNotEmpty && target.isNotEmpty) {
            relsMap[id] = target;
          }
        }
      } catch (_) {}
    }

    final slides = <OfficeSlide>[];
    final sldIdElements = presXml.findAllElements('sldId', namespaceUri: '*');
    int slideIndex = 1;

    for (final sldId in sldIdElements) {
      final rId = sldId.getAttribute('r:id') ??
          sldId.getAttribute('id') ??
          _attrLocal(sldId, 'id') ??
          '';

      String target = relsMap[rId] ?? 'slides/slide$slideIndex.xml';
      if (target.startsWith('/')) target = target.substring(1);
      final slidePath = target.startsWith('ppt/') ? target : 'ppt/$target';

      final currentIdx = slideIndex++;
      final slideEntry = archive.findFile(slidePath);
      if (slideEntry == null || slideEntry.size > maxZipEntryBytes) {
        continue;
      }

      final XmlDocument slideXml;
      try {
        slideXml = XmlDocument.parse(utf8.decode(slideEntry.content));
      } catch (_) {
        continue;
      }

      final lines = <String>[];
      for (final p in slideXml.findAllElements('p', namespaceUri: '*')) {
        final buf = StringBuffer();
        for (final t in p.findAllElements('t', namespaceUri: '*')) {
          buf.write(t.innerText);
        }
        final line = buf.toString().trim();
        if (line.isNotEmpty) {
          lines.add(line);
        }
      }

      slides.add(OfficeSlide(index: currentIdx, lines: lines));
    }

    return OfficeDocument(kind: OfficeDocumentKind.pptx, slides: slides);
  }

  /// Parse legacy OLE2 (.doc, .xls, .ppt) by extracting printable text heuristically.
  static OfficeDocument parseLegacy(Uint8List bytes) {
    if (bytes.length > maxFileBytes) {
      throw const OfficeParseException('File too large', isTooLarge: true);
    }

    final text = extractLegacyOfficeText(bytes);
    if (text.trim().isEmpty) {
      throw const OfficeParseException(
        'No text could be extracted from legacy office document',
      );
    }

    return OfficeDocument(
      kind: OfficeDocumentKind.legacy,
      legacyText: text,
    );
  }

  /// Heuristically extract printable ASCII and UTF-16LE text fragments (>= 4 chars).
  static String extractLegacyOfficeText(Uint8List bytes) {
    final fragments = <String>[];
    int totalChars = 0;

    int i = 0;
    final n = bytes.length;

    while (i < n && totalChars < maxLegacyOutputChars) {
      // 1. Check single-byte ASCII run
      int j = i;
      while (j < n && _isPrintableAscii(bytes[j])) {
        j++;
      }
      final asciiLen = j - i;
      if (asciiLen >= 4) {
        final s = String.fromCharCodes(bytes.sublist(i, j)).trim();
        if (s.isNotEmpty) {
          fragments.add(s);
          totalChars += s.length + 2;
        }
        i = j;
        continue;
      }

      // If i is a single non-ASCII byte right before an ASCII run of >= 4,
      // skip it so the ASCII run can be extracted intact.
      if (i + 1 < n && _isPrintableAscii(bytes[i + 1])) {
        int k = i + 1;
        while (k < n && _isPrintableAscii(bytes[k])) {
          k++;
        }
        if (k - (i + 1) >= 4) {
          i++;
          continue;
        }
      }

      // 2. Check UTF-16LE run
      j = i;
      final utf16Chars = <int>[];
      while (j + 1 < n) {
        final code = bytes[j] | (bytes[j + 1] << 8);
        if (_isPrintableUtf16(code)) {
          utf16Chars.add(code);
          j += 2;
        } else {
          break;
        }
      }
      if (utf16Chars.length >= 4) {
        final s = String.fromCharCodes(utf16Chars).trim();
        if (s.isNotEmpty) {
          fragments.add(s);
          totalChars += s.length + 2;
        }
        i = j;
        continue;
      }

      i++;
    }

    var result = fragments.join('\n\n');
    if (result.length > maxLegacyOutputChars) {
      result = result.substring(0, maxLegacyOutputChars);
    }
    return result;
  }

  static bool _isPrintableAscii(int b) {
    return (b >= 0x20 && b <= 0x7E) || b == 0x09 || b == 0x0A || b == 0x0D;
  }

  static bool _isPrintableUtf16(int c) {
    if ((c >= 0x20 && c <= 0x7E) || c == 0x09 || c == 0x0A || c == 0x0D) {
      return true;
    }
    if (c >= 0x4E00 && c <= 0x9FFF) return true; // CJK Unified Ideographs
    if (c >= 0x3400 && c <= 0x4DBF) return true; // CJK Ext A
    if (c >= 0x3000 && c <= 0x303F) return true; // CJK Symbols & Punctuation
    if (c >= 0xFF00 && c <= 0xFFEF) return true; // Fullwidth Forms
    if (c >= 0x2000 && c <= 0x206F) return true; // General Punctuation
    if (c >= 0x00A0 && c <= 0x00FF) return true; // Latin-1 Supplement printable
    return false;
  }

  static String? _attrLocal(XmlElement el, String localName) {
    for (final a in el.attributes) {
      if (a.name.local == localName) return a.value;
    }
    return null;
  }
}
