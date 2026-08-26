import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../connections/connection_providers.dart';
import '../models/session.dart';
import 'app_database.dart';
import 'cache_service.dart';
import 'media_cache_service.dart';

/// 单例持有：避免同名 `hermes_cache` 的 QueryExecutor 被实例化两次而争用
/// （main.dart 与 Provider 同时 new 会触发 drift 隔离冲突）。
AppDatabase? _appDatabaseInstance;

/// 生产离线缓存数据库（单例语义）
///
/// 默认使用内存库保证桌面/测试无插件时也能运行；宿主完成初始化后
/// 由 [main.dart] 在顶层创建唯一的 `AppDatabase.production()` 单例
/// 并以 `overrideWithValue` 注入。该 Provider 自身也做懒单例兜底。
///
/// **约束**：业务/测试代码不要直接 `AppDatabase.production()` 多次构造；
/// 如需持久库请改为 `ref.watch(appDatabaseProvider)` 或
/// `ref.watch(persistentAppDatabaseProvider)`（后者为本 Provider 的 alias），
/// 避免同名数据库二次打开导致崩溃。
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final database = _appDatabaseInstance ??= AppDatabase.memory();
  ref.onDispose(() async {
    if (identical(_appDatabaseInstance, database)) {
      _appDatabaseInstance = null;
      await database.close();
    }
  });
  return database;
});

/// 持久化数据库 Provider（alias）
///
/// 历史上曾独立 `AppDatabase.production()` 导致与 [appDatabaseProvider]
/// 同文件双实例争用；现重定向为别名，统一走单例语义。
final persistentAppDatabaseProvider = Provider<AppDatabase>(
  (ref) => ref.watch(appDatabaseProvider),
);

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
