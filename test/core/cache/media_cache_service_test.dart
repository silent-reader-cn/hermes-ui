import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermex_flutter/core/cache/app_database.dart';
import 'package:hermex_flutter/core/cache/media_cache_service.dart';

/// 装配一个基于内存 drift + 系统临时目录的 [MediaCacheService]。
class _Rig {
  _Rig(this.db, this.root, this.service);

  final AppDatabase db;
  final Directory root;
  final MediaCacheService service;

  Future<void> dispose() async {
    await db.close();
    try {
      await root.delete(recursive: true);
    } on FileSystemException {
      // ignore
    }
  }
}

_Rig _build({
  Future<Uint8List> Function(Uri)? downloader,
  int maxBytes = kDefaultMaxMediaCacheBytes,
  Duration ttl = kDefaultMediaTtl,
}) {
  final db = AppDatabase.memory();
  final root = Directory.systemTemp.createTempSync('hermex_media_unit_');
  final service = MediaCacheService.withDownloader(
    database: db,
    downloader: downloader ?? (_) async => Uint8List.fromList([1, 2, 3]),
    rootDir: root,
    maxBytes: maxBytes,
    ttl: ttl,
  );
  return _Rig(db, root, service);
}

List<File> _filesIn(Directory dir) => dir.listSync().whereType<File>().toList();

void main() {
  group('MediaCacheService 媒体本地缓存', () {
    test('未命中：下载落盘 + 写索引，返回存在的 File', () async {
      final rig = _build(
        downloader: (uri) async {
          expect(uri.toString(), 'https://example.com/a.png');
          return Uint8List.fromList([9, 9, 9]);
        },
      );
      addTearDown(rig.dispose);
      const url = 'https://example.com/a.png';

      final file = await rig.service.get(url);

      expect(await file.exists(), isTrue);
      expect(await file.readAsBytes(), [9, 9, 9]);
      // 索引已写入
      final row = await (rig.db.select(
        rig.db.cachedMedia,
      )..where((t) => t.url.equals(url))).getSingle();
      expect(row.cacheKey.length, 64); // sha256 hex
      expect(row.byteSize, 3);
      expect(row.filePath, isNotEmpty);
      // 文件名 = sha256 + 推断扩展名
      expect(row.filePath, endsWith('.png'));
    });

    test('命中：返回 File 且不重复下载，并刷新 lastAccessedAt', () async {
      var downloads = 0;
      final rig = _build(
        downloader: (_) async {
          downloads++;
          return Uint8List.fromList([1, 2, 3]);
        },
      );
      addTearDown(rig.dispose);
      const url = 'https://example.com/b.png';

      final f1 = await rig.service.get(url);
      expect(downloads, 1);
      final row1 =
          await (rig.db.select(rig.db.cachedMedia)..where(
                (t) =>
                    t.cacheKey.equals(f1.uri.pathSegments.last.split('.')[0]),
              ))
              .getSingle();

      // 再次取回 → 命中，不再下载
      final f2 = await rig.service.get(url);
      expect(downloads, 1);
      expect(f2.path, f1.path);

      final row2 =
          await (rig.db.select(rig.db.cachedMedia)..where(
                (t) =>
                    t.cacheKey.equals(f1.uri.pathSegments.last.split('.')[0]),
              ))
              .getSingle();
      expect(row2.lastAccessedAt, greaterThanOrEqualTo(row1.lastAccessedAt));
    });

    test('401/404（下载抛错）：不写缓存，抛错且目录为空', () async {
      final rig = _build(
        downloader: (_) async => throw StateError('401 for test'),
      );
      addTearDown(rig.dispose);
      const url = 'https://example.com/secret.png';

      await expectLater(rig.service.get(url), throwsA(isA<StateError>()));
      // 目录无新文件，索引无记录
      expect(_filesIn(rig.root), isEmpty);
      expect(
        await (rig.db.select(
          rig.db.cachedMedia,
        )..where((t) => t.url.equals(url))).get(),
        isEmpty,
      );
    });

    test('per-URL 并发合并：同一 URL 并发只下载一次', () async {
      var downloads = 0;
      final rig = _build(
        downloader: (_) async {
          downloads++;
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return Uint8List.fromList([5, 5, 5]);
        },
      );
      addTearDown(rig.dispose);
      const url = 'https://example.com/concurrent.png';

      final results = await Future.wait([
        rig.service.get(url),
        rig.service.get(url),
        rig.service.get(url),
      ]);

      expect(downloads, 1);
      expect(results[0].path, results[1].path);
      expect(results[0].path, results[2].path);
    });

    test('LRU 容量淘汰：超 maxBytes 后删除最久未访问的文件与索引', () async {
      // 每文件 1024 字节，maxBytes 只够放 2 个（不过 3 个）。
      final rig = _build(
        downloader: (_) async => Uint8List(1024),
        maxBytes: 2500,
      );
      addTearDown(rig.dispose);

      final f1 = await rig.service.get('https://example.com/lru_1.png');
      final f2 = await rig.service.get('https://example.com/lru_2.png');
      final f3 = await rig.service.get('https://example.com/lru_3.png');

      // 写第 3 个后触发淘汰，最早的 lru_1 被清理。
      expect(await f1.exists(), isFalse);
      expect(await f2.exists(), isTrue);
      expect(await f3.exists(), isTrue);
      expect(
        await (rig.db.select(rig.db.cachedMedia)..where(
              (t) => t.cacheKey.equals(f1.uri.pathSegments.last.split('.')[0]),
            ))
            .get(),
        isEmpty,
      );
    });

    test('TTL 过期：读命中时超期删除重下', () async {
      var downloads = 0;
      final rig = _build(
        downloader: (_) async {
          downloads++;
          return Uint8List.fromList([7, 7]);
        },
        ttl: const Duration(milliseconds: 50),
      );
      addTearDown(rig.dispose);
      const url = 'https://example.com/ttl.png';

      await rig.service.get(url);
      expect(downloads, 1);

      // 等待超过 TTL 后再次取回 → 视为过期重下。
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await rig.service.get(url);
      expect(downloads, 2);
    });

    test('孤儿清理：有文件无索引 → 删文件；有索引无文件 → 删索引', () async {
      final rig = _build();
      addTearDown(rig.dispose);

      // 1) 磁盘有文件、索引无记录 → 清理时删文件。
      final orphanFile = File(
        '${rig.root.path}${Platform.pathSeparator}orphan123.png',
      );
      await orphanFile.writeAsBytes([1, 2, 3]);

      // 2) 索引有记录、文件丢失 → 清理时删索引。
      await rig.db
          .into(rig.db.cachedMedia)
          .insert(
            CachedMediaCompanion.insert(
              cacheKey: 'deadbeef' * 8,
              url: 'https://example.com/lost.png',
              filePath: 'missing0000.png',
              byteSize: 4,
              cachedAt: 1,
              lastAccessedAt: 1,
            ),
          );

      await rig.service.cleanupOrphans();

      expect(await orphanFile.exists(), isFalse);
      expect(
        await (rig.db.select(
          rig.db.cachedMedia,
        )..where((t) => t.cacheKey.equals('deadbeef' * 8))).get(),
        isEmpty,
      );
    });

    test('文件在但索引缺失：取回时补索引，避免无谓重下', () async {
      var downloads = 0;
      final rig = _build(
        downloader: (_) async {
          downloads++;
          return Uint8List.fromList([1, 2, 3, 4]);
        },
      );
      addTearDown(rig.dispose);
      const url = 'https://example.com/adopt.png';

      final file = await rig.service.get(url);
      expect(downloads, 1);

      // 删除索引模拟“文件在、索引被外部清理”。
      final key = file.uri.pathSegments.last.split('.').first;
      await (rig.db.delete(
        rig.db.cachedMedia,
      )..where((t) => t.cacheKey.equals(key))).go();

      final file2 = await rig.service.get(url);
      expect(file2.path, file.path);
      // 补索引即命中，不再下载。
      expect(downloads, 1);
    });
  });
}
