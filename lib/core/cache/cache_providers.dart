import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/session.dart';
import 'app_database.dart';
import 'cache_service.dart';

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

class CachedSessionData {
  const CachedSessionData(this.sessions);
  final List<SessionSummary> sessions;
}
