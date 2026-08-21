import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hermex_flutter/core/cache/app_database.dart';
import 'package:hermex_flutter/core/cache/cache_providers.dart';
import 'package:hermex_flutter/core/cache/media_cache_service.dart';

/// 一次假的媒体缓存装配（内存 drift + 系统临时目录），用于 widget 测试注入
/// `mediaCacheServiceProvider`。构造后记得在 tearDown 中 [FakeMediaCacheRig.dispose]。
FakeMediaCacheRig buildFakeMediaCache({
  Future<Uint8List> Function(Uri)? downloader,
  AppDatabase? database,
}) {
  final db = database ?? AppDatabase.memory();
  final root = Directory.systemTemp.createTempSync('hermex_media_test_');
  final service = MediaCacheService.withDownloader(
    database: db,
    downloader:
        downloader ?? (_) async => throw StateError('no downloader configured'),
    rootDir: root,
  );
  return FakeMediaCacheRig(service, db, root);
}

/// 假的媒体缓存装配结果。
class FakeMediaCacheRig {
  FakeMediaCacheRig(this.service, this.database, this.root);

  final MediaCacheService service;
  final AppDatabase database;
  final Directory root;

  /// 关闭内存库并清理临时缓存目录。
  Future<void> dispose() async {
    await database.close();
    try {
      await root.delete(recursive: true);
    } on FileSystemException {
      // 忽略清理失败，避免污染测试结果。
    }
  }
}

/// 以给定的假的媒体缓存替代 [mediaCacheServiceProvider] 的 ProviderScope 覆盖。
Override mediaCacheOverride(MediaCacheService service) =>
    mediaCacheServiceProvider.overrideWithValue(service);
