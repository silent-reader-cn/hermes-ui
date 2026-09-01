import 'package:drift/drift.dart';

import '../../core/cache/app_database.dart';
import 'download_models.dart';

/// 下载记录持久化仓储（drift `download_records` 表交互层）。
///
/// 契约说明：
/// 1. 负责 completed / failed / cancelled / active 状态的增量或更新落库；
/// 2. 启动时自动执行 [recoverInterruptedTasks]，将上次遗留的 queued / downloading
///    未完任务转为 failed，并标记文案「应用已退出，下载未完成」；
/// 3. 支持根据 sourceUrl 快速查重已完成记录。
class DownloadRepository {
  DownloadRepository(this._database);

  final AppDatabase _database;

  /// 启动中断恢复：将数据库中遗留的 queued 或 downloading 任务转为 failed。
  Future<void> recoverInterruptedTasks() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final rows =
        await (_database.select(_database.downloadRecords)..where(
              (t) =>
                  t.status.equals(DownloadStatus.queued.name) |
                  t.status.equals(DownloadStatus.downloading.name),
            ))
            .get();

    for (final row in rows) {
      await (_database.update(
        _database.downloadRecords,
      )..where((t) => t.id.equals(row.id))).write(
        DownloadRecordsCompanion(
          status: Value(DownloadStatus.failed.name),
          failureMessage: const Value('应用已退出，下载未完成'),
          completedAt: Value(now),
        ),
      );
    }
  }

  /// 保存或更新单个下载记录。
  Future<void> saveRecord(DownloadTask task) async {
    await _database
        .into(_database.downloadRecords)
        .insertOnConflictUpdate(_taskToCompanion(task));
  }

  /// 批量保存或更新下载记录。
  Future<void> saveRecords(List<DownloadTask> tasks) async {
    await _database.batch((batch) {
      for (final task in tasks) {
        batch.insert(
          _database.downloadRecords,
          _taskToCompanion(task),
          onConflict: DoUpdate((old) => _taskToCompanion(task)),
        );
      }
    });
  }

  /// 读取所有历史下载记录（按创建时间倒序排列）。
  Future<List<DownloadTask>> getAllRecords() async {
    final rows = await (_database.select(
      _database.downloadRecords,
    )..orderBy([(t) => OrderingTerm.desc(t.createdAt)])).get();
    return rows.map(_rowToTask).toList(growable: false);
  }

  /// 根据 ID 查询单个任务记录。
  Future<DownloadTask?> getRecordById(String id) async {
    final rows =
        await (_database.select(_database.downloadRecords)
              ..where((t) => t.id.equals(id))
              ..limit(1))
            .get();
    if (rows.isEmpty) return null;
    return _rowToTask(rows.first);
  }

  /// 根据 sourceUrl 查找最近一条已完成的下载记录。
  Future<DownloadTask?> findCompletedBySourceUrl(String sourceUrl) async {
    final rows =
        await (_database.select(_database.downloadRecords)
              ..where(
                (t) =>
                    t.sourceUrl.equals(sourceUrl) &
                    t.status.equals(DownloadStatus.completed.name),
              )
              ..orderBy([(t) => OrderingTerm.desc(t.completedAt)])
              ..limit(1))
            .get();
    if (rows.isEmpty) return null;
    return _rowToTask(rows.first);
  }

  /// 根据 ID 删除记录。
  Future<void> deleteRecord(String id) async {
    await (_database.delete(
      _database.downloadRecords,
    )..where((t) => t.id.equals(id))).go();
  }

  /// 清空所有下载记录。
  Future<void> clearAll() async {
    await _database.delete(_database.downloadRecords).go();
  }

  DownloadRecordsCompanion _taskToCompanion(DownloadTask task) {
    return DownloadRecordsCompanion(
      id: Value(task.id),
      sourceUrl: Value(task.sourceUrl),
      fileName: Value(task.fileName),
      mimeType: Value(task.mimeType),
      expectedBytes: Value(task.expectedBytes),
      receivedBytes: Value(task.receivedBytes),
      status: Value(task.status.name),
      savedPath: Value(task.savedPath),
      createdAt: Value(task.createdAt),
      completedAt: Value(task.completedAt),
      failureMessage: Value(task.failureMessage),
      sessionId: Value(task.sessionId),
    );
  }

  DownloadTask _rowToTask(DownloadRecord row) {
    return DownloadTask(
      id: row.id,
      sourceUrl: row.sourceUrl,
      fileName: row.fileName,
      mimeType: row.mimeType,
      expectedBytes: row.expectedBytes,
      receivedBytes: row.receivedBytes,
      status: DownloadStatus.fromString(row.status),
      savedPath: row.savedPath,
      createdAt: row.createdAt,
      completedAt: row.completedAt,
      failureMessage: row.failureMessage,
      sessionId: row.sessionId,
    );
  }
}
