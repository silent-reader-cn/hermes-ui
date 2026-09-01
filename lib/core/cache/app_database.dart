import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'app_database_connection.dart'
    if (dart.library.ffi) 'app_database_connection_native.dart'
    if (dart.library.js_interop) 'app_database_connection_web.dart';

part 'app_database.g.dart';

/// 最近会话缓存表。
class CachedSessions extends Table {
  TextColumn get sessionId => text()();
  TextColumn get title => text().withDefault(const Constant(''))();
  TextColumn get payload => text()();
  IntColumn get cachedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {sessionId};
}

/// 最近消息缓存表（纯文本 payload，避免把富媒体写入离线库）。
class CachedMessages extends Table {
  TextColumn get messageId => text()();
  TextColumn get sessionId => text()();
  TextColumn get payload => text()();
  IntColumn get cachedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {messageId};
}

/// 媒体缓存元数据索引（二进制内容在文件系统，本表只存索引与访问时间）。
///
/// cacheKey = sha256(完整 URL)（含 session_id query），天然区分「同一文件、
/// 不同会话授权」的取回；filePath 存相对文件名，便于整体迁移缓存目录。
class CachedMedia extends Table {
  TextColumn get cacheKey => text()();
  TextColumn get url => text()();
  TextColumn get mimeType => text().nullable()();
  TextColumn get filePath => text()();
  IntColumn get byteSize => integer()();
  IntColumn get cachedAt => integer()();
  IntColumn get lastAccessedAt => integer()();
  TextColumn get sessionId => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {cacheKey};
}

/// 诊断日志表（#33：SharedPreferences → drift 迁移）。
///
/// timestamp 存 epoch 毫秒（与缓存表 cachedAt 同约定）；level 存枚举 name
/// 字符串；details 存脱敏后的 JSON 文本。按 timestamp 建索引以支持
/// 30 天保留清理与最老优先淘汰的排序查询。
@TableIndex(name: 'idx_diagnostics_logs_timestamp', columns: {#timestamp})
class DiagnosticsLogs extends Table {
  TextColumn get id => text()();
  IntColumn get timestamp => integer()();
  TextColumn get level => text()();
  TextColumn get tag => text()();
  TextColumn get message => text()();
  TextColumn get details => text().nullable()();
  IntColumn get durationMs => integer().nullable()();
  TextColumn get errorKind => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// 下载记录持久化表（下载核心层）。
class DownloadRecords extends Table {
  TextColumn get id => text()();
  TextColumn get sourceUrl => text()();
  TextColumn get fileName => text()();
  TextColumn get mimeType => text().nullable()();
  IntColumn get expectedBytes => integer().nullable()();
  IntColumn get receivedBytes => integer().withDefault(const Constant(0))();
  TextColumn get status => text()();
  TextColumn get savedPath => text().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get completedAt => integer().nullable()();
  TextColumn get failureMessage => text().nullable()();
  TextColumn get sessionId => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// **单例约束**：生产代码不要直接多次 `AppDatabase.production()`。
/// 请改为 `ref.watch(appDatabaseProvider)` 取得全进程唯一实例，避免
/// 同名 `hermes_cache` 的 `QueryExecutor` 争用导致崩溃。
@DriftDatabase(
  tables: [
    CachedSessions,
    CachedMessages,
    CachedMedia,
    DiagnosticsLogs,
    DownloadRecords,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  /// 生产数据库：平台私有目录中的 hermes_cache.sqlite。
  factory AppDatabase.production() =>
      AppDatabase(driftDatabase(name: 'hermes_cache'));

  /// 测试数据库：内存 SQLite，不触碰平台文件。
  factory AppDatabase.memory() => AppDatabase(openConnectionInMemory());

  @override
  int get schemaVersion => 4;

  /// 迁移策略：新建库创建全部表；升级时按版本增量补建表（drift 默认在
  /// schema 升级时若未提供 onUpgrade 会直接抛异常）。
  /// - v1→v2：给已有生产库补建 `cached_media` 表；
  /// - v2→v3：补建 `diagnostics_logs` 诊断日志表（#33 存储迁移）；
  /// - v3→v4：补建 `download_records` 下载记录表。
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.createTable(cachedMedia);
      }
      if (from < 3) {
        await m.createTable(diagnosticsLogs);
        // drift 的 createTable 不建索引，需显式补建（#33）。
        await m.createIndex(idxDiagnosticsLogsTimestamp);
      }
      if (from < 4) {
        await m.createTable(downloadRecords);
      }
    },
  );
}
