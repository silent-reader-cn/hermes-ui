import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/cache/app_database.dart';
import 'package:hermes_ui/features/downloads/download_models.dart';
import 'package:hermes_ui/features/downloads/download_repository.dart';

void main() {
  late AppDatabase db;
  late DownloadRepository repository;

  setUp(() {
    db = AppDatabase.memory();
    repository = DownloadRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('DownloadRepository', () {
    test('saveRecord 与 getAllRecords（按创建时间倒序）', () async {
      const task1 = DownloadTask(
        id: 'task-1',
        sourceUrl: 'https://example.com/file1.png',
        fileName: 'file1.png',
        mimeType: 'image/png',
        expectedBytes: 100,
        receivedBytes: 100,
        status: DownloadStatus.completed,
        savedPath: '/downloads/file1.png',
        createdAt: 1000,
        completedAt: 1050,
      );

      const task2 = DownloadTask(
        id: 'task-2',
        sourceUrl: 'https://example.com/file2.zip',
        fileName: 'file2.zip',
        mimeType: 'application/zip',
        expectedBytes: 500,
        receivedBytes: 250,
        status: DownloadStatus.downloading,
        createdAt: 2000,
      );

      await repository.saveRecord(task1);
      await repository.saveRecord(task2);

      final records = await repository.getAllRecords();
      expect(records, hasLength(2));
      expect(records[0].id, 'task-2'); // 2000 > 1000
      expect(records[1].id, 'task-1');
      expect(records[1].status, DownloadStatus.completed);
      expect(records[1].savedPath, '/downloads/file1.png');
    });

    test('getRecordById 查询存在与不存在', () async {
      const task = DownloadTask(
        id: 'task-find',
        sourceUrl: 'https://example.com/doc.pdf',
        fileName: 'doc.pdf',
        createdAt: 100,
      );

      await repository.saveRecord(task);

      final found = await repository.getRecordById('task-find');
      expect(found, isNotNull);
      expect(found?.fileName, 'doc.pdf');

      final notFound = await repository.getRecordById('non-existent');
      expect(notFound, isNull);
    });

    test('findCompletedBySourceUrl 仅返回 completed 状态的最近记录', () async {
      const queuedTask = DownloadTask(
        id: 'q1',
        sourceUrl: 'https://example.com/same.zip',
        fileName: 'same.zip',
        status: DownloadStatus.queued,
        createdAt: 100,
      );
      await repository.saveRecord(queuedTask);

      expect(
        await repository.findCompletedBySourceUrl(
          'https://example.com/same.zip',
        ),
        isNull,
      );

      const completedTask = DownloadTask(
        id: 'c1',
        sourceUrl: 'https://example.com/same.zip',
        fileName: 'same.zip',
        status: DownloadStatus.completed,
        savedPath: '/downloads/same.zip',
        createdAt: 200,
        completedAt: 250,
      );
      await repository.saveRecord(completedTask);

      final found = await repository.findCompletedBySourceUrl(
        'https://example.com/same.zip',
      );
      expect(found, isNotNull);
      expect(found?.id, 'c1');
      expect(found?.savedPath, '/downloads/same.zip');
    });

    test('deleteRecord 与 clearAll', () async {
      const task1 = DownloadTask(
        id: 'd1',
        sourceUrl: 'https://example.com/1',
        fileName: '1',
        createdAt: 1,
      );
      const task2 = DownloadTask(
        id: 'd2',
        sourceUrl: 'https://example.com/2',
        fileName: '2',
        createdAt: 2,
      );

      await repository.saveRecords([task1, task2]);
      expect(await repository.getAllRecords(), hasLength(2));

      await repository.deleteRecord('d1');
      final remaining = await repository.getAllRecords();
      expect(remaining, hasLength(1));
      expect(remaining.single.id, 'd2');

      await repository.clearAll();
      expect(await repository.getAllRecords(), isEmpty);
    });

    test('recoverInterruptedTasks：启动时 queued/downloading 记录转 failed，文案为“应用已退出，下载未完成”', () async {
      const queuedTask = DownloadTask(
        id: 't-queued',
        sourceUrl: 'https://example.com/q',
        fileName: 'q.bin',
        status: DownloadStatus.queued,
        createdAt: 100,
      );
      const downloadingTask = DownloadTask(
        id: 't-downloading',
        sourceUrl: 'https://example.com/dl',
        fileName: 'dl.bin',
        status: DownloadStatus.downloading,
        expectedBytes: 1000,
        receivedBytes: 300,
        createdAt: 110,
      );
      const completedTask = DownloadTask(
        id: 't-completed',
        sourceUrl: 'https://example.com/done',
        fileName: 'done.bin',
        status: DownloadStatus.completed,
        savedPath: '/path/done.bin',
        createdAt: 90,
        completedAt: 95,
      );
      const cancelledTask = DownloadTask(
        id: 't-cancelled',
        sourceUrl: 'https://example.com/cancel',
        fileName: 'cancel.bin',
        status: DownloadStatus.cancelled,
        createdAt: 80,
        completedAt: 85,
      );

      await repository.saveRecords([
        queuedTask,
        downloadingTask,
        completedTask,
        cancelledTask,
      ]);

      await repository.recoverInterruptedTasks();

      final records = await repository.getAllRecords();
      final map = {for (final r in records) r.id: r};

      // queued 与 downloading 转为 failed
      expect(map['t-queued']?.status, DownloadStatus.failed);
      expect(map['t-queued']?.failureMessage, '应用已退出，下载未完成');
      expect(map['t-queued']?.completedAt, isNotNull);

      expect(map['t-downloading']?.status, DownloadStatus.failed);
      expect(map['t-downloading']?.failureMessage, '应用已退出，下载未完成');
      expect(map['t-downloading']?.completedAt, isNotNull);

      // completed 与 cancelled 保持原样
      expect(map['t-completed']?.status, DownloadStatus.completed);
      expect(map['t-completed']?.failureMessage, isNull);
      expect(map['t-completed']?.completedAt, 95);

      expect(map['t-cancelled']?.status, DownloadStatus.cancelled);
      expect(map['t-cancelled']?.completedAt, 85);
    });

    test('recoverInterruptedTasks：有 .part 文件的 URL 任务重置为 queued 并恢复 receivedBytes，其他转 failed', () async {
      final tempDir = Directory.systemTemp.createTempSync('hermes_repo_recover_');
      addTearDown(() async {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {}
      });

      final repoWithTemp = DownloadRepository(
        db,
        tempDirectoryProvider: () => tempDir,
      );

      // 创建一个 .part 文件，包含 512 字节
      final partFile = File('${tempDir.path}/task-with-part.part');
      partFile.writeAsBytesSync(List.filled(512, 1));

      final taskWithPart = DownloadTask(
        id: 'task-with-part',
        sourceUrl: 'https://example.com/file.zip',
        fileName: 'file.zip',
        status: DownloadStatus.downloading,
        expectedBytes: 1024,
        receivedBytes: 200,
        tempPath: partFile.path,
        createdAt: 100,
      );

      final taskWithoutPart = const DownloadTask(
        id: 'task-without-part',
        sourceUrl: 'https://example.com/other.zip',
        fileName: 'other.zip',
        status: DownloadStatus.downloading,
        expectedBytes: 1024,
        receivedBytes: 200,
        tempPath: '/non/existent/path.part',
        createdAt: 110,
      );

      final bytesTask = const DownloadTask(
        id: 'task-bytes',
        sourceUrl: 'bytes:data',
        fileName: 'bytes.bin',
        status: DownloadStatus.downloading,
        createdAt: 120,
      );

      await repoWithTemp.saveRecords([taskWithPart, taskWithoutPart, bytesTask]);

      await repoWithTemp.recoverInterruptedTasks();

      final records = await repoWithTemp.getAllRecords();
      final map = {for (final r in records) r.id: r};

      // taskWithPart 有有效的 .part 文件，应该被重置为 queued，且 receivedBytes 为 512
      final recoveredTask = map['task-with-part'];
      expect(recoveredTask?.status, DownloadStatus.queued);
      expect(recoveredTask?.receivedBytes, 512);
      expect(recoveredTask?.tempPath, partFile.path);
      expect(recoveredTask?.failureMessage, isNull);
      expect(recoveredTask?.completedAt, isNull);

      // taskWithoutPart 没有有效的 .part 文件，转为 failed
      final failedTask = map['task-without-part'];
      expect(failedTask?.status, DownloadStatus.failed);
      expect(failedTask?.failureMessage, '应用已退出，下载未完成');
      expect(failedTask?.completedAt, isNotNull);

      // bytesTask 即使在 downloading，也转为 failed
      final failedBytes = map['task-bytes'];
      expect(failedBytes?.status, DownloadStatus.failed);
      expect(failedBytes?.failureMessage, '应用已退出，下载未完成');
      expect(failedBytes?.completedAt, isNotNull);
    });
  });
}
