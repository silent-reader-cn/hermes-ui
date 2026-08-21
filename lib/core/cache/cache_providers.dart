import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../connections/connection_providers.dart';
import '../models/session.dart';
import 'app_database.dart';
import 'cache_service.dart';
import 'media_cache_service.dart';

/// 生产离线缓存数据库。
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  // 先使用内存数据库保证桌面/测试无插件时也能运行；宿主完成
  // path_provider 初始化后可 override 为 AppDatabase.production()。
  final database = AppDatabase.memory();
  ref.onDispose(database.close);
  return database;
});

/// 持久化数据库 Provider，供正式宿主在插件初始化后 override 使用。
final persistentAppDatabaseProvider = Provider<AppDatabase>((ref) {
  final database = AppDatabase.production();
  ref.onDispose(database.close);
  return database;
});

/// 缓存服务（测试可 override database/service）。
final cacheServiceProvider = Provider<CacheService>((ref) {
  return CacheService(ref.watch(appDatabaseProvider));
});

final offlineCacheEnabledProvider = Provider<bool>((ref) => true);

/// 媒体本地缓存服务（依赖激活连接 ApiClient + 与现有缓存同库）。
///
/// 经 [ApiClient.downloadData] 下载（dio 带 cookie + 自定义头 + autoReauth），
/// 文件落盘 + drift `cached_media` 索引，渲染改用 Image.file（P2）。
final mediaCacheServiceProvider = Provider<MediaCacheService>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final client = ref.watch(apiClientProvider);
  return MediaCacheService(database: db, client: client);
});

class CachedSessionData {
  const CachedSessionData(this.sessions);
  final List<SessionSummary> sessions;
}
