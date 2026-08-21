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

@DriftDatabase(tables: [CachedSessions, CachedMessages, CachedMedia])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  /// 生产数据库：平台私有目录中的 hermex_cache.sqlite。
  factory AppDatabase.production() =>
      AppDatabase(driftDatabase(name: 'hermex_cache'));

  /// 测试数据库：内存 SQLite，不触碰平台文件。
  factory AppDatabase.memory() => AppDatabase(openConnectionInMemory());

  @override
  int get schemaVersion => 2;

  /// 迁移策略：新建库创建全部表；v1→v2 给已有生产库补建 `cached_media` 表
  /// （drift 默认在 schema 升级时若未提供 onUpgrade 会直接抛异常）。
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.createTable(cachedMedia);
      }
    },
  );
}
