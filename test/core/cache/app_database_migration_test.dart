import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/cache/app_database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

/// 构造一个「旧版 schemaVersion=1」的 SQLite 文件库（两张旧表 + user_version=1），
/// 用于验证 schemaVersion=4 打开时 v1→v2→v3→v4 的 onUpgrade 能依次补建
/// `cached_media`、`diagnostics_logs` 与 `download_records` 表。
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
/// 用于验证 v2→v3→v4 迁移补建 `diagnostics_logs` 与 `download_records` 表。
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

/// 构造一个「schemaVersion=3」的 SQLite 文件库（四张表 + user_version=3），
/// 用于验证 v3→v4 迁移补建 `download_records` 下载记录表。
void _createV3Database(String path) {
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
    db.execute(
      'CREATE TABLE diagnostics_logs ('
      'id TEXT NOT NULL PRIMARY KEY,'
      'timestamp INTEGER NOT NULL,'
      'level TEXT NOT NULL,'
      'tag TEXT NOT NULL,'
      'message TEXT NOT NULL,'
      'details TEXT,'
      'duration_ms INTEGER,'
      'error_kind TEXT)',
    );
    db.execute(
      'CREATE INDEX idx_diagnostics_logs_timestamp '
      'ON diagnostics_logs (timestamp)',
    );
    db.execute('PRAGMA user_version = 3');
  } finally {
    db.close();
  }
}

void main() {
  group('AppDatabase drift schema 迁移', () {
    test('v1 生产库升级到 v4：补建 cached_media, diagnostics_logs 与 download_records 表且旧表可用', () async {
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

      // 以 schemaVersion=4 打开旧 v1 库，触发 onUpgrade（v1→v2→v3→v4）。
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

      // #33：v3 diagnostics_logs 表可用。
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

      // v4 download_records 表可用。
      await db
          .into(db.downloadRecords)
          .insert(
            DownloadRecordsCompanion.insert(
              id: 'dl-1',
              sourceUrl: 'https://example.com/file.zip',
              fileName: 'file.zip',
              status: 'queued',
              createdAt: 100,
            ),
          );
      final dlRows = await db.select(db.downloadRecords).get();
      expect(dlRows.single.fileName, 'file.zip');

      // 旧表仍可用。
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

    test('v2 生产库升级到 v4：补建 diagnostics_logs 与 download_records 且全部生效', () async {
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

      final db = AppDatabase(NativeDatabase(file));
      addTearDown(db.close);

      // 新诊断表可用
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

      // 新下载表可用
      await db
          .into(db.downloadRecords)
          .insert(
            DownloadRecordsCompanion.insert(
              id: 'dl-2',
              sourceUrl: 'https://example.com/doc.pdf',
              fileName: 'doc.pdf',
              status: 'completed',
              createdAt: 200,
              savedPath: const Value('/downloads/doc.pdf'),
            ),
          );
      final dl = await db.select(db.downloadRecords).get();
      expect(dl.single.savedPath, '/downloads/doc.pdf');
    });

    test('v3 生产库升级到 v4：补建 download_records 下载记录表且所有已有数据保留', () async {
      final dir = Directory.systemTemp.createTempSync('hermes_migrate_');
      final file = File('${dir.path}${Platform.pathSeparator}old_v3.sqlite');
      addTearDown(() async {
        try {
          await dir.delete(recursive: true);
        } on FileSystemException {
          // ignore
        }
      });

      _createV3Database(file.path);

      // 以 schemaVersion=4 打开旧 v3 库，触发 v3→v4 增量迁移
      final db = AppDatabase(NativeDatabase(file));
      addTearDown(db.close);

      // 验证新增表可用
      await db
          .into(db.downloadRecords)
          .insert(
            DownloadRecordsCompanion.insert(
              id: 'dl-3',
              sourceUrl: 'https://example.com/img.png',
              fileName: 'img.png',
              mimeType: const Value('image/png'),
              status: 'downloading',
              createdAt: 300,
              expectedBytes: const Value(1024),
              receivedBytes: const Value(512),
            ),
          );

      final dlRows = await (db.select(
        db.downloadRecords,
      )..where((t) => t.id.equals('dl-3'))).get();
      expect(dlRows.single.fileName, 'img.png');
      expect(dlRows.single.mimeType, 'image/png');
      expect(dlRows.single.receivedBytes, 512);

      // 既有数据读写正常
      await db
          .into(db.cachedSessions)
          .insert(
            CachedSessionsCompanion.insert(
              sessionId: 's3',
              payload: '{}',
              cachedAt: 3,
            ),
          );
      expect((await db.select(db.cachedSessions).get()).single.sessionId, 's3');
    });
  });
}
