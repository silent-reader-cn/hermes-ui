import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/cache/app_database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

/// 构造一个「旧版 schemaVersion=1」的 SQLite 文件库（两张旧表 + user_version=1），
/// 用于验证 2.x 打开时 v1→v2 的 onUpgrade 能补建 `cached_media` 表（drift 默认
/// 升级无 onUpgrade 会直接抛异常，见 migration.dart 的 _defaultOnUpdate）。
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

void main() {
  group('AppDatabase drift schema 迁移', () {
    test('v1 生产库升级到 v2：补建 cached_media 表且旧表可用', () async {
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

      // 以 schemaVersion=2 打开旧 v1 库，触发 onUpgrade。
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
  });
}
