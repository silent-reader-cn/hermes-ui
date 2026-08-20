import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/onboarding/onboarding_providers.dart';
import '../api/api_client.dart';
import '../api/custom_header.dart';
import 'connection_store.dart';
import 'server_connection.dart';

/// 存储服务实例（测试可 override 注入内存版）。
final connectionStoreProvider = Provider<ConnectionStore>(
  (ref) => ConnectionStore(),
);

/// 全部服务器连接（app_shell_spec.md §5.3）。
///
/// 启动时从 [connectionStoreProvider] 异步加载；增删改后同步落盘。
final connectionsProvider = NotifierProvider<ConnectionsController,
    List<ServerConnection>>(ConnectionsController.new);

class ConnectionsController extends Notifier<List<ServerConnection>> {
  @override
  List<ServerConnection> build() {
    unawaited(_load());
    return const [];
  }

  Future<void> _load() async {
    final all = await ref.read(connectionStoreProvider).loadAll();
    // 仅当用户尚未写入任何连接时应用（避免异步加载覆盖用户操作）。
    if (state.isEmpty) state = all;
  }

  /// 新增或更新连接（按 id upsert）并落盘。
  ///
  /// 去重规则：同 id 直接替换；无 id 匹配但已有同 `baseUrl` 的连接时，
  /// **沿用旧连接的 id**（避免重复走 onboarding / 添加服务器产生多条
  /// 相同服务器记录），并保留旧 createdAt。
  ///
  /// 返回最终保存的 [ServerConnection]（调用方用返回值的 id 做 setActive
  /// 等后续操作，避免去重后 id 漂移）。
  Future<ServerConnection> upsert(ServerConnection connection) async {
    final store = ref.read(connectionStoreProvider);
    var target = connection;
    final index = state.indexWhere((c) => c.id == connection.id);
    if (index < 0) {
      final dup = state.indexWhere(
        (c) => c.baseUrl.trim().toLowerCase() ==
            connection.baseUrl.trim().toLowerCase(),
      );
      if (dup >= 0) {
        target = connection.copyWith(
          id: state[dup].id,
          createdAt: state[dup].createdAt,
        );
      }
    }
    await store.save(target);
    final idx = state.indexWhere((c) => c.id == target.id);
    final next = List<ServerConnection>.of(state);
    if (idx >= 0) {
      next[idx] = target;
    } else {
      next.add(target);
    }
    state = next;
    return target;
  }

  /// 删除连接；若删的是激活连接，store.delete 已连带清 active 指向，
  /// activeConnectionProvider 经 watch 自动重算。
  Future<void> remove(String id) async {
    final store = ref.read(connectionStoreProvider);
    await store.delete(id);
    state = state.where((c) => c.id != id).toList();
  }
}

/// 当前激活连接（app_shell_spec.md §5.3）。
///
/// 监听 [connectionsProvider]：连接列表变化时重算 active（删除/切换后保持同步）。
final activeConnectionProvider = NotifierProvider<ActiveConnectionController,
    ServerConnection?>(ActiveConnectionController.new);

class ActiveConnectionController extends Notifier<ServerConnection?> {
  /// 用户显式操作序号：_load 启动时快照，若期间用户 setActive/clear，
  /// 丢弃过期加载结果，避免异步覆盖用户操作。
  int _userActionSeq = 0;

  @override
  ServerConnection? build() {
    ref.watch(connectionsProvider);
    final seq = _userActionSeq;
    unawaited(_load(seq));
    return null;
  }

  Future<void> _load(int seq) async {
    final active = await ref.read(connectionStoreProvider).getActive();
    if (seq >= _userActionSeq) state = active;
  }

  /// 切换激活连接（先落盘再更新内存态，保证路由守卫立即生效）。
  Future<void> setActive(String id) async {
    _userActionSeq++;
    final store = ref.read(connectionStoreProvider);
    await store.setActive(id);
    final found = _findById(id);
    state = found ?? await store.getActive();
  }

  /// 清除激活连接（不删除连接本身）。
  Future<void> clear() async {
    _userActionSeq++;
    await ref.read(connectionStoreProvider).clearActive();
    state = null;
  }

  ServerConnection? _findById(String id) {
    for (final connection in ref.read(connectionsProvider)) {
      if (connection.id == id) return connection;
    }
    return null;
  }
}

/// ApiClient：跟随激活连接自动重建（app_shell_spec.md §5.3）。
///
/// 切换连接 → [activeConnectionProvider] 变化 → 本 Provider 重建，
/// 新的 baseUrl / 自定义头即时生效。无激活连接时抛 [StateError]
/// （路由守卫保证业务页面只在有连接时可达）。
final apiClientProvider = Provider<ApiClient>((ref) {
  final active = ref.watch(activeConnectionProvider);
  if (active == null) {
    throw StateError('尚未配置服务器连接');
  }
  return ApiClient(
    baseUrl: active.baseUrl,
    initialHeaders: [
      for (final entry in active.customHeaders.entries)
        CustomHeader(name: entry.key, value: entry.value),
    ],
    autoReauth: () async {
      final conn = ref.read(activeConnectionProvider);
      final password = conn?.password;
      if (password == null || password.isEmpty) return false;
      final factory = ref.read(onboardingApiFactoryProvider);
      final api = factory(conn!.baseUrl, [
        for (final entry in conn.customHeaders.entries)
          CustomHeader(name: entry.key, value: entry.value),
      ]);
      try {
        await api.login(password);
        return true;
      } on Exception {
        return false;
      }
    },
  );
});
