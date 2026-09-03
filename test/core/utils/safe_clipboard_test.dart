import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/utils/safe_clipboard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('safe_clipboard_test_');
    SafeClipboard.destinationDirOverride = tempDir;
  });

  tearDown(() {
    SafeClipboard.resetOverridesForTesting();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('SafeClipboard 纯函数判定与格式化', () {
    test('getUtf8ByteLength 准确计算不同编码字符字节数', () {
      expect(SafeClipboard.getUtf8ByteLength('abc'), 3);
      // 中文 UTF-8 为 3 字节，字符串长度为 1
      expect(SafeClipboard.getUtf8ByteLength('中'), 3);
      // Emoji 😀 UTF-8 为 4 字节，UTF-16 长度为 2
      expect(SafeClipboard.getUtf8ByteLength('😀'), 4);
      // 复合字符串
      expect(SafeClipboard.getUtf8ByteLength('hello 世界 😀'), 5 + 1 + 6 + 1 + 4);
    });

    test('shouldUseFileExport 在 512KB 边界准确切换', () {
      const boundary = SafeClipboard.maxClipboardBytes; // 524,288 字节
      expect(boundary, 512 * 1024);

      // ≤ 512KB：走剪贴板
      final exactBoundary = 'a' * boundary;
      expect(SafeClipboard.getUtf8ByteLength(exactBoundary), boundary);
      expect(SafeClipboard.shouldUseFileExport(exactBoundary), isFalse);

      final underBoundary = 'a' * (boundary - 1);
      expect(SafeClipboard.shouldUseFileExport(underBoundary), isFalse);

      // > 512KB：走文件导出
      final overBoundary = 'a' * (boundary + 1);
      expect(SafeClipboard.shouldUseFileExport(overBoundary), isTrue);

      // 中文字符 UTF-8 字节膨胀：174,763 个中文字符 = 524,289 字节 > 512KB
      // 虽然 String.length 仅 174,763，远小于 524,288，但 UTF-8 字节数已超限
      final chineseOverBoundary = '中' * 174763;
      expect(SafeClipboard.getUtf8ByteLength(chineseOverBoundary), 524289);
      expect(SafeClipboard.shouldUseFileExport(chineseOverBoundary), isTrue);

      final chineseUnderBoundary = '中' * 174762;
      expect(SafeClipboard.getUtf8ByteLength(chineseUnderBoundary), 524286);
      expect(SafeClipboard.shouldUseFileExport(chineseUnderBoundary), isFalse);
    });

    test('shouldUseFileExport 支持自定义阈值与测试覆盖', () {
      expect(SafeClipboard.shouldUseFileExport('hello', 4), isTrue);
      expect(SafeClipboard.shouldUseFileExport('hello', 5), isFalse);

      SafeClipboard.maxBytesOverride = 10;
      expect(SafeClipboard.shouldUseFileExport('1234567890'), isFalse);
      expect(SafeClipboard.shouldUseFileExport('12345678901'), isTrue);
    });

    test('formatExportFileName 生成符合规范的时间戳文件名', () {
      final time = DateTime(2026, 9, 3, 19, 5, 33);
      expect(
        SafeClipboard.formatExportFileName(time),
        'hermes_logs_export_20260903_190533.txt',
      );

      expect(
        SafeClipboard.formatExportFileName(time, prefix: 'custom_export'),
        'custom_export_20260903_190533.txt',
      );
    });
  });

  group('SafeClipboard 结果模型契约', () {
    test('SafeClipboardSuccess 与 SafeClipboardFileSaved 类型属性', () {
      const success = SafeClipboardSuccess();
      expect(success.isClipboard, isTrue);
      expect(success.isFileSaved, isFalse);
      expect(success.filePath, isNull);

      const fileSaved = SafeClipboardFileSaved('/path/to/file.txt');
      expect(fileSaved.isClipboard, isFalse);
      expect(fileSaved.isFileSaved, isTrue);
      expect(fileSaved.filePath, '/path/to/file.txt');
    });
  });

  group('SafeClipboard copyOrSave 行为与落盘验证', () {
    test('小文本（≤ 512KB）成功写入剪贴板且不落盘', () async {
      String? copiedText;
      SafeClipboard.clipboardSetterOverride = (text) async {
        copiedText = text;
      };

      final result = await SafeClipboard.copyOrSave('短小日志文本');

      expect(result, isA<SafeClipboardSuccess>());
      expect(copiedText, '短小日志文本');
      expect(tempDir.listSync(), isEmpty);
    });

    test('大文本（> 512KB）不碰剪贴板，自动落盘并返回路径', () async {
      var clipboardCalled = false;
      SafeClipboard.clipboardSetterOverride = (text) async {
        clipboardCalled = true;
      };

      final fakeTime = DateTime(2026, 9, 3, 18, 0, 0);
      SafeClipboard.clockOverride = () => fakeTime;

      // 构造超 512KB 的日志文本
      final bigText = 'log entry line: 1234567890\n' * 25000; // ~675KB
      expect(SafeClipboard.shouldUseFileExport(bigText), isTrue);

      final result = await SafeClipboard.copyOrSave(bigText);

      expect(result, isA<SafeClipboardFileSaved>());
      expect(clipboardCalled, isFalse);

      final savedPath = (result as SafeClipboardFileSaved).filePath;
      expect(savedPath, endsWith('hermes_logs_export_20260903_180000.txt'));

      final savedFile = File(savedPath);
      expect(savedFile.existsSync(), isTrue);
      expect(savedFile.readAsStringSync(), bigText);
    });

    test('同时间戳重复落盘自动生成 (1), (2) 序号防止覆盖', () async {
      SafeClipboard.maxBytesOverride = 10;
      final fakeTime = DateTime(2026, 9, 3, 18, 30, 0);
      SafeClipboard.clockOverride = () => fakeTime;

      final res1 = await SafeClipboard.copyOrSave('first content over limit');
      final res2 = await SafeClipboard.copyOrSave('second content over limit');
      final res3 = await SafeClipboard.copyOrSave('third content over limit');

      final path1 = (res1 as SafeClipboardFileSaved).filePath;
      final path2 = (res2 as SafeClipboardFileSaved).filePath;
      final path3 = (res3 as SafeClipboardFileSaved).filePath;

      expect(path1, endsWith('hermes_logs_export_20260903_183000.txt'));
      expect(path2, endsWith('hermes_logs_export_20260903_183000 (1).txt'));
      expect(path3, endsWith('hermes_logs_export_20260903_183000 (2).txt'));

      expect(File(path1).readAsStringSync(), 'first content over limit');
      expect(File(path2).readAsStringSync(), 'second content over limit');
      expect(File(path3).readAsStringSync(), 'third content over limit');
    });

    test('mock 通道抛出 TransactionTooLargeException 降级落盘不 crash', () async {
      // 模拟 Flutter 真实平台通道抛出 TransactionTooLargeException
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (
            MethodCall methodCall,
          ) async {
            if (methodCall.method == 'Clipboard.setData') {
              throw PlatformException(
                code: 'TransactionTooLargeException',
                message: 'The data in the transaction is too large for Binder buffer',
              );
            }
            return null;
          });

      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null);
      });

      final smallText = '虽未超 512KB 阈值，但系统 Binder 事务超限抛错';
      expect(SafeClipboard.shouldUseFileExport(smallText), isFalse);

      final result = await SafeClipboard.copyOrSave(smallText);

      expect(result, isA<SafeClipboardFileSaved>());
      final savedPath = (result as SafeClipboardFileSaved).filePath;
      expect(File(savedPath).existsSync(), isTrue);
      expect(File(savedPath).readAsStringSync(), smallText);
    });
  });
}
