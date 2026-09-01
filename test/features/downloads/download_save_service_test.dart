import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/features/downloads/download_save_service.dart';

void main() {
  group('DownloadSaveService 文件名清理与冲突处理', () {
    test('sanitizeFileName 移除路径遍历与非法字符', () {
      expect(
        DownloadSaveService.sanitizeFileName('foo/bar/baz.pdf'),
        'baz.pdf',
      );
      expect(
        DownloadSaveService.sanitizeFileName(r'C:\Users\Admin\file.zip'),
        'file.zip',
      );
      expect(
        DownloadSaveService.sanitizeFileName('../../secret.txt'),
        'secret.txt',
      );
      expect(
        DownloadSaveService.sanitizeFileName('report:2026*final?.docx'),
        'report_2026_final_.docx',
      );
      expect(
        DownloadSaveService.sanitizeFileName('archive.tar.gz?v=2#sec'),
        'archive.tar.gz',
      );
      expect(
        DownloadSaveService.sanitizeFileName('   .hidden.txt   '),
        'hidden.txt',
      );
    });

    test('sanitizeFileName 空文件名兜底', () {
      final emptyResult = DownloadSaveService.sanitizeFileName('   ');
      expect(emptyResult, startsWith('download_'));

      final mimeResult = DownloadSaveService.sanitizeFileName(
        '   ',
        mimeType: 'image/png',
      );
      expect(mimeResult, startsWith('download_'));
      expect(mimeResult, endsWith('.png'));
    });

    test('resolveNonConflictingFile 自动生成 (1), (2) 序列并不覆盖', () {
      final tempDir = Directory.systemTemp.createTempSync('hermes_save_test_');
      addTearDown(() async {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {}
      });

      // 首次：直接返回 原文件名
      final file1 = DownloadSaveService.resolveNonConflictingFile(
        tempDir,
        'doc.pdf',
      );
      expect(file1.path, endsWith('doc.pdf'));
      file1.writeAsStringSync('first');

      // 第二次：冲突，返回 doc (1).pdf
      final file2 = DownloadSaveService.resolveNonConflictingFile(
        tempDir,
        'doc.pdf',
      );
      expect(file2.path, endsWith('doc (1).pdf'));
      file2.writeAsStringSync('second');

      // 第三次：再次冲突，返回 doc (2).pdf
      final file3 = DownloadSaveService.resolveNonConflictingFile(
        tempDir,
        'doc.pdf',
      );
      expect(file3.path, endsWith('doc (2).pdf'));
      file3.writeAsStringSync('third');

      // 验证原文件未被覆盖
      expect(file1.readAsStringSync(), 'first');
      expect(file2.readAsStringSync(), 'second');
      expect(file3.readAsStringSync(), 'third');
    });

    test('resolveNonConflictingFile 无扩展名文件', () {
      final tempDir = Directory.systemTemp.createTempSync('hermes_save_noext_');
      addTearDown(() async {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {}
      });

      final f1 = DownloadSaveService.resolveNonConflictingFile(
        tempDir,
        'LICENSE',
      );
      expect(f1.path, endsWith('LICENSE'));
      f1.writeAsStringSync('mit');

      final f2 = DownloadSaveService.resolveNonConflictingFile(
        tempDir,
        'LICENSE',
      );
      expect(f2.path, endsWith('LICENSE (1)'));
    });
  });

  group('DownloadSaveService 跨平台保存与测试注入', () {
    test('注入 destinationDirOverride 保存文件成功', () async {
      final tempDir = Directory.systemTemp.createTempSync(
        'hermes_save_override_',
      );
      addTearDown(() async {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {}
      });

      final service = DownloadSaveService(destinationDirOverride: tempDir);
      final bytes = Uint8List.fromList([1, 2, 3, 4, 5]);

      final savedPath = await service.save(fileName: 'hello.bin', bytes: bytes);

      expect(savedPath, contains('hello.bin'));
      final savedFile = File(savedPath);
      expect(savedFile.existsSync(), isTrue);
      expect(savedFile.readAsBytesSync(), bytes);
    });

    test('Windows 平台优先解析 USERPROFILE/Downloads', () async {
      final fakeUserProfile = Directory.systemTemp.createTempSync('fake_user_');
      addTearDown(() async {
        try {
          await fakeUserProfile.delete(recursive: true);
        } catch (_) {}
      });

      final service = DownloadSaveService(
        isWindowsOverride: true,
        environmentOverride: {'USERPROFILE': fakeUserProfile.path},
      );

      final dir = await service.resolveDestinationDirectory();
      expect(dir.path, equals('${fakeUserProfile.path}\\Downloads'));
      expect(dir.existsSync(), isTrue);
    });

    test('Android 平台在无法写入公共 Downloads 时显式抛出 DownloadSaveException', () async {
      final service = DownloadSaveService(isAndroidOverride: true);

      // 在非 Android 设备（如 Windows 测试机）上，/storage/emulated/0/Download 不存在且不可写，
      // 必须显式抛出 DownloadSaveException 失败，绝不能静默写私有目录。
      expect(
        () => service.resolveDestinationDirectory(),
        throwsA(isA<DownloadSaveException>()),
      );
    });

    test('注入 fileWriterOverride 测试双', () async {
      final tempDir = Directory.systemTemp.createTempSync(
        'hermes_save_writer_',
      );
      addTearDown(() async {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {}
      });

      var customWriterCalled = false;
      final service = DownloadSaveService(
        destinationDirOverride: tempDir,
        fileWriterOverride: (file, bytes) async {
          customWriterCalled = true;
          await file.writeAsBytes(bytes);
        },
      );

      final savedPath = await service.save(
        fileName: 'custom.txt',
        bytes: Uint8List.fromList([10, 20]),
      );

      expect(customWriterCalled, isTrue);
      expect(File(savedPath).existsSync(), isTrue);
    });
  });
}
