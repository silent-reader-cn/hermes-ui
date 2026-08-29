import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/cache/app_database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

/// 构造一个「旧版 schemaVersion=1」的 SQLite 文件库（两张旧表 + user_version=1），
/// 用于验证 schemaVersion=3 打开时 v1→v2→v3 的 onUpgrade 能依次补建
/// `cached_media` 与 `diagnostics_logs` 表（drift 默认升级无 onUpgrade 会直接
/// 抛异常，见 migration.dart 的 _defaultOnUpdate）。
void _createV1Database(String path) {
  final db = sqlite3.sqlite3.open(path);
  try {
    db.execute(
      'CREATE TABLE cached_sessions ('
      'session_id TEXT NOT NULL PRIMARY KEY,'
      'title TEXT NOT NULL DEFAULT \'\','
      'payload TEXT NOT NULL,'
      'cached_at INTEGER NOT NULL)',
    );
    db.execute(
      'CREATE TABLE cached_messages ('
      'message_id TEXT NOT NULL PRIMARY KEY,'
      'session_id TEXT NOT NULL,'
      'payload TEXT NOT NULL,'
      'cached_at INTEGER NOT NULL)',
    );
    db.execute('PRAGMA user_version = 1');
  } finally {
    db.close();
  }
}

/// 构造一个「schemaVersion=2」的 SQLite 文件库（三张表 + user_version=2），
/// 用于验证 v2→v3 迁移补建 `diagnostics_logs` 诊断日志表（#33）。
void _createV2Database(String path) {
  final db = sqlite3.sqlite3.open(path);
  try {
    db.execute(
      'CREATE TABLE cached_sessions ('
      'session_id TEXT NOT NULL PRIMARY KEY,'
      'title TEXT NOT NULL DEFAULT \'\','
      'payload TEXT NOT NULL,'
      'cached_at INTEGER NOT NULL)',
    );
    db.execute(
      'CREATE TABLE cached_messages ('
      'message_id TEXT NOT NULL PRIMARY KEY,'
      'session_id TEXT NOT NULL,'
      'payload TEXT NOT NULL,'
      'cached_at INTEGER NOT NULL)',
    );
    db.execute(
      'CREATE TABLE cached_media ('
      'cache_key TEXT NOT NULL PRIMARY KEY,'
      'url TEXT NOT NULL,'
      'mime_type TEXT,'
      'file_path TEXT NOT NULL,'
      'byte_size INTEGER NOT NULL,'
      'cached_at INTEGER NOT NULL,'
      'last_accessed_at INTEGER NOT NULL,'
      'session_id TEXT)',
    );
    db.execute('PRAGMA user_version = 2');
  } finally {
    db.close();
  }
}

void main() {
  group('AppDatabase drift schema 迁移', () {
    test('v1 生产库升级到 v3：补建 cached_media 与 diagnostics_logs 表且旧表可用', () async {
      final dir = Directory.systemTemp.createTempSync('hermes_migrate_');
      final file = File('${dir.path}${Platform.pathSeparator}old_v1.sqlite');
      addTearDown(() async {
        try {
          await dir.delete(recursive: true);
        } on FileSystemException {
          // ignore
        }
      });

      _createV1Database(file.path);

      // 以 schemaVersion=3 打开旧 v1 库，触发 onUpgrade（v1→v2→v3）。
      final db = AppDatabase(NativeDatabase(file));
      addTearDown(db.close);

      // 新表可用（能查询/插入）。
      await db
          .into(db.cachedMedia)
          .insert(
            CachedMediaCompanion.insert(
              cacheKey: 'key123',
              url: 'https://example.com/x.png',
              filePath: 'key123.png',
              byteSize: 0,
              cachedAt: 1,
              lastAccessedAt: 1,
            ),
          );
      final row = await (db.select(
        db.cachedMedia,
      )..where((t) => t.cacheKey.equals('key123'))).getSingle();
      expect(row.url, 'https://example.com/x.png');

      // #33：v3 新增 diagnostics_logs 表可用。
      await db
          .into(db.diagnosticsLogs)
          .insert(
            DiagnosticsLogsCompanion.insert(
              id: 'diag-1',
              timestamp: 1,
              level: 'info',
              tag: 'test',
              message: 'hello',
            ),
          );
      final diagRows = await db.select(db.diagnosticsLogs).get();
      expect(diagRows.single.message, 'hello');

      // 旧表仍可用（schemaVersion=1 的会话表在新程序里也能读写）。
      await db
          .into(db.cachedSessions)
          .insert(
            CachedSessionsCompanion.insert(
              sessionId: 's1',
              payload: '{}',
              cachedAt: 1,
            ),
          );
      final sessionRows = await db.select(db.cachedSessions).get();
      expect(sessionRows.single.sessionId, 's1');
    });

    test('v2 生产库升级到 v3：补建 diagnostics_logs 表且索引生效', () async {
      final dir = Directory.systemTemp.createTempSync('hermes_migrate_');
      final file = File('${dir.path}${Platform.pathSeparator}old_v2.sqlite');
      addTearDown(() async {
        try {
          await dir.delete(recursive: true);
        } on FileSystemException {
          // ignore
        }
      });

      _createV2Database(file.path);

      // 以 schemaVersion=3 打开旧 v2 库，触发 v2→v3 onUpgrade。
      final db = AppDatabase(NativeDatabase(file));
      addTearDown(db.close);

      // 新诊断表可用，且 timestamp 索引已创建。
      await db
          .into(db.diagnosticsLogs)
          .insert(
            DiagnosticsLogsCompanion.insert(
              id: 'diag-2',
              timestamp: 123456789,
              level: 'error',
              tag: 'sse',
              message: 'boom',
              errorKind: const Value('Timeout'),
            ),
          );
      final rows = await db.select(db.diagnosticsLogs).get();
      expect(rows.single.errorKind, 'Timeout');

      final indexRows = db.customSelect(
        "SELECT name FROM sqlite_master WHERE type = 'index' "
        "AND name = 'idx_diagnostics_logs_timestamp'",
      );
      final indexNames = (await indexRows.get())
          .map((r) => r.data['name'] as String)
          .toList();
      expect(indexNames, contains('idx_diagnostics_logs_timestamp'));

      // 既有三张表仍可用。
      await db
          .into(db.cachedSessions)
          .insert(
            CachedSessionsCompanion.insert(
              sessionId: 's1',
              payload: '{}',
              cachedAt: 1,
            ),
          );
      await db
          .into(db.cachedMedia)
          .insert(
            CachedMediaCompanion.insert(
              cacheKey: 'key2',
              url: 'https://example.com/y.png',
              filePath: 'key2.png',
              byteSize: 1,
              cachedAt: 1,
              lastAccessedAt: 1,
            ),
          );
      expect((await db.select(db.cachedSessions).get()).single.sessionId, 's1');
      expect((await db.select(db.cachedMedia).get()).single.cacheKey, 'key2');
    });
  });
}
