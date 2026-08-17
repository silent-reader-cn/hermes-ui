import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_flutter/drift_flutter.dart';

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

@DriftDatabase(tables: [CachedSessions, CachedMessages])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  /// 生产数据库：平台私有目录中的 hermex_cache.sqlite。
  factory AppDatabase.production() => AppDatabase(
        driftDatabase(name: 'hermex_cache'),
      );

  /// 测试数据库：内存 SQLite，不触碰平台文件。
  factory AppDatabase.memory() => AppDatabase(NativeDatabase.memory());

  @override
  int get schemaVersion => 1;
}
