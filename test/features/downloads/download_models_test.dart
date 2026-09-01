import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/features/downloads/download_models.dart';

void main() {
  group('DownloadStatus', () {
    test('fromString 正确解析各枚举及默认兜底', () {
      expect(DownloadStatus.fromString('queued'), DownloadStatus.queued);
      expect(
        DownloadStatus.fromString('downloading'),
        DownloadStatus.downloading,
      );
      expect(DownloadStatus.fromString('completed'), DownloadStatus.completed);
      expect(DownloadStatus.fromString('failed'), DownloadStatus.failed);
      expect(DownloadStatus.fromString('cancelled'), DownloadStatus.cancelled);
      expect(DownloadStatus.fromString('unknown_value'), DownloadStatus.queued);
      expect(DownloadStatus.fromString(null), DownloadStatus.queued);
    });
  });

  group('DownloadTask 模型', () {
    test('基本属性与 copyWith', () {
      const task = DownloadTask(
        id: 'dl-1',
        sourceUrl: 'https://example.com/test.zip',
        fileName: 'test.zip',
        mimeType: 'application/zip',
        expectedBytes: 1000,
        receivedBytes: 500,
        status: DownloadStatus.downloading,
        createdAt: 10000,
        sessionId: 'sess-1',
      );

      expect(task.id, 'dl-1');
      expect(task.progress, 0.5);
      expect(task.isActive, isTrue);
      expect(task.isTerminal, isFalse);

      final updated = task.copyWith(
        receivedBytes: 1000,
        status: DownloadStatus.completed,
        savedPath: '/downloads/test.zip',
        completedAt: 12000,
      );

      expect(updated.receivedBytes, 1000);
      expect(updated.status, DownloadStatus.completed);
      expect(updated.savedPath, '/downloads/test.zip');
      expect(updated.completedAt, 12000);
      expect(updated.progress, 1.0);
      expect(updated.isActive, isFalse);
      expect(updated.isTerminal, isTrue);
    });

    test('progress 边界情况（expectedBytes 为 null 或 <= 0 时返回 null）', () {
      const taskNoExpected = DownloadTask(
        id: '1',
        sourceUrl: '',
        fileName: '',
        receivedBytes: 100,
        createdAt: 0,
      );
      expect(taskNoExpected.progress, isNull);

      const taskZeroExpected = DownloadTask(
        id: '2',
        sourceUrl: '',
        fileName: '',
        expectedBytes: 0,
        receivedBytes: 100,
        createdAt: 0,
      );
      expect(taskZeroExpected.progress, isNull);

      const taskNegativeExpected = DownloadTask(
        id: '3',
        sourceUrl: '',
        fileName: '',
        expectedBytes: -10,
        receivedBytes: 100,
        createdAt: 0,
      );
      expect(taskNegativeExpected.progress, isNull);

      const taskOverReceived = DownloadTask(
        id: '4',
        sourceUrl: '',
        fileName: '',
        expectedBytes: 100,
        receivedBytes: 200,
        createdAt: 0,
      );
      expect(taskOverReceived.progress, 1.0);
    });

    test('toJson 与 fromJson 正常反序列化', () {
      const original = DownloadTask(
        id: 'dl-test',
        sourceUrl: 'https://example.com/image.png',
        fileName: 'image.png',
        mimeType: 'image/png',
        expectedBytes: 2048,
        receivedBytes: 2048,
        status: DownloadStatus.completed,
        savedPath: r'C:\Users\Downloads\image.png',
        createdAt: 1700000000,
        completedAt: 1700000050,
        failureMessage: null,
        sessionId: 'session-xyz',
      );

      final json = original.toJson();
      final reconstructed = DownloadTask.fromJson(json);

      expect(reconstructed, equals(original));
      expect(reconstructed.hashCode, equals(original.hashCode));
      expect(reconstructed.toString(), contains('dl-test'));
    });

    test('fromJson 容错测试（畸形类型、空值、缺失键、非 Map）', () {
      expect(DownloadTask.fromJson(null).id, '');
      expect(DownloadTask.fromJson('not a map').fileName, '');
      expect(DownloadTask.fromJson(123).createdAt, 0);

      final tolerantMap = {
        'id': 12345, // int 容错为 string
        'source_url': 'https://example.com/file',
        'file_name': 'file.txt',
        'mime_type': 'text/plain',
        'expected_bytes': '500', // string 容错为 int
        'received_bytes': '250',
        'status': 'downloading',
        'created_at': '1000000',
        'completed_at': 2000000.0, // double 容错为 int
        'failure_message': 'something',
        'session_id': 'sess-42',
      };

      final parsed = DownloadTask.fromJson(tolerantMap);
      expect(parsed.id, '12345');
      expect(parsed.sourceUrl, 'https://example.com/file');
      expect(parsed.expectedBytes, 500);
      expect(parsed.receivedBytes, 250);
      expect(parsed.status, DownloadStatus.downloading);
      expect(parsed.createdAt, 1000000);
      expect(parsed.completedAt, 2000000);
      expect(parsed.failureMessage, 'something');
      expect(parsed.sessionId, 'sess-42');
    });
  });

  group('文件类型与大小格式化纯函数', () {
    test('getDownloadFileType 推断', () {
      expect(
        getDownloadFileType(mimeType: 'image/jpeg'),
        DownloadFileType.image,
      );
      expect(
        getDownloadFileType(fileName: 'photo.PNG'),
        DownloadFileType.image,
      );
      expect(
        getDownloadFileType(mimeType: 'audio/mp3'),
        DownloadFileType.audio,
      );
      expect(
        getDownloadFileType(fileName: 'track.flac'),
        DownloadFileType.audio,
      );
      expect(
        getDownloadFileType(mimeType: 'video/mp4'),
        DownloadFileType.video,
      );
      expect(getDownloadFileType(fileName: 'clip.mkv'), DownloadFileType.video);
      expect(
        getDownloadFileType(mimeType: 'application/pdf'),
        DownloadFileType.document,
      );
      expect(
        getDownloadFileType(fileName: 'report.docx'),
        DownloadFileType.document,
      );
      expect(
        getDownloadFileType(fileName: 'archive.tar.gz'),
        DownloadFileType.archive,
      );
      expect(
        getDownloadFileType(fileName: 'app.apk'),
        DownloadFileType.archive,
      );
      expect(getDownloadFileType(fileName: 'script.py'), DownloadFileType.code);
      expect(getDownloadFileType(fileName: 'data.json'), DownloadFileType.code);
      expect(
        getDownloadFileType(fileName: 'unknown.xyz'),
        DownloadFileType.other,
      );
    });

    test('extractFileExtension 提取扩展名', () {
      expect(extractFileExtension('test.png'), 'png');
      expect(extractFileExtension('foo.bar.tar.gz'), 'gz');
      expect(extractFileExtension('path/to/file.PDF'), 'pdf');
      expect(extractFileExtension(r'C:\path\to\file.docx'), 'docx');
      expect(extractFileExtension('noext'), '');
      expect(extractFileExtension('file.'), '');
    });

    test('formatDownloadByteSize 格式化大小', () {
      expect(formatDownloadByteSize(-1), '0 B');
      expect(formatDownloadByteSize(0), '0 B');
      expect(formatDownloadByteSize(512), '512 B');
      expect(formatDownloadByteSize(1024), '1.0 KB');
      expect(formatDownloadByteSize(1536), '1.5 KB');
      expect(formatDownloadByteSize(1024 * 1024), '1.0 MB');
      expect(formatDownloadByteSize(1024 * 1024 * 1024), '1.00 GB');
      expect(
        formatDownloadByteSize((2.5 * 1024 * 1024 * 1024).toInt()),
        '2.50 GB',
      );
    });
  });
}
