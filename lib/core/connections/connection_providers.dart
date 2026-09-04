import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/onboarding/onboarding_providers.dart';
import '../../features/webui_sidecar/webui_sidecar_providers.dart';
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
        (c) =>
            c.kind != ConnectionKind.builtin &&
            c.baseUrl.trim().toLowerCase() ==
                connection.baseUrl.trim().toLowerCase(),
      );
      // 去重永不指向 builtin 行：否则同 baseUrl 的 remote 会顶替内置连接、
      // 绕过「builtin 不可删」铁律；builtin 与 remote 允许同 URL 并存。
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

  /// 新增或更新内置连接（总是落在列表首位、幂等）。
  Future<ServerConnection> upsertBuiltin(ServerConnection connection) async {
    final target = (connection.id == ServerConnection.builtinId &&
            connection.kind == ConnectionKind.builtin)
        ? connection
        : connection.copyWith(
            id: ServerConnection.builtinId,
            kind: ConnectionKind.builtin,
          );
    final store = ref.read(connectionStoreProvider);
    await store.save(target);
    var currentList = List<ServerConnection>.of(state);
    if (currentList.isEmpty) {
      final loaded = await store.loadAll();
      if (loaded.isNotEmpty) {
        currentList = List<ServerConnection>.of(loaded);
      }
    }
    currentList.removeWhere(
      (c) => c.id == target.id || c.kind == ConnectionKind.builtin,
    );
    currentList.insert(0, target);
    state = currentList;
    return target;
  }

  /// 新增或更新内置连接并将其设为激活连接。
  Future<ServerConnection> upsertBuiltinAndActivate(
    ServerConnection connection,
  ) async {
    final saved = await upsertBuiltin(connection);
    await ref.read(activeConnectionProvider.notifier).setActive(saved.id);
    return saved;
  }

  /// 启用或停用内置连接。
  ///
  /// 若停用对象当前处于激活状态，同时执行 [ActiveConnectionController.clear]（风险②裁定）。
  Future<void> setBuiltinEnabled(bool enabled) async {
    final store = ref.read(connectionStoreProvider);
    var all = List<ServerConnection>.of(state);
    var index = all.indexWhere((c) => c.kind == ConnectionKind.builtin);
    if (index < 0) {
      final loaded = await store.loadAll();
      index = loaded.indexWhere((c) => c.kind == ConnectionKind.builtin);
      if (index >= 0) {
        all = List<ServerConnection>.of(loaded);
      }
    }
    if (index < 0) return;
    final current = all[index];
    final updated = current.copyWith(enabled: enabled);
    await store.save(updated);

    all[index] = updated;
    state = all;

    // 决策4 联动：「停用」= 关 sidecar 开关并停止内置实例（否则进程照跑、
    // 下次启动仍自动拉起）；「启用」对称恢复开关并拉起。
    // 非 Windows/无内置包时 start() 自身置 failed，不抛错，联动安全。
    try {
      await ref.read(webuiSidecarConfigProvider.notifier).setEnabled(enabled);
      final controller = ref.read(webuiSidecarControllerProvider.notifier);
      if (enabled) {
        await controller.start();
      } else {
        await controller.stop();
      }
    } catch (_) {
      // 联动失败不回滚连接 enabled 态（列表语义为准；sidecar 状态页可见）。
    }
  }

  /// 删除连接；对 kind==builtin 抛 [StateError] 防护（模型层兜底）。
  /// 若删的是激活连接，store.delete 已连带清 active 指向，
  /// activeConnectionProvider 经 watch 自动重算。
  Future<void> remove(String id) async {
    if (id == ServerConnection.builtinId) {
      throw StateError('不能删除内置连接：$id');
    }
    final index = state.indexWhere((c) => c.id == id);
    if (index >= 0 && state[index].kind == ConnectionKind.builtin) {
      throw StateError('不能删除内置连接：$id');
    }
    final store = ref.read(connectionStoreProvider);
    await store.delete(id);
    state = state.where((c) => c.id != id).toList();
  }

  /// 别名方法，对齐 delete(id) 契约。
  Future<void> delete(String id) => remove(id);
}

/// 可切换/可激活的服务器连接列表（排除已停用的 builtin）。
final switchableConnectionsProvider = Provider<List<ServerConnection>>((ref) {
  final connections = ref.watch(connectionsProvider);
  return connections
      .where((c) => c.kind != ConnectionKind.builtin || c.enabled)
      .toList();
});

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
    if (active != null &&
        active.kind == ConnectionKind.builtin &&
        !active.enabled) {
      if (seq >= _userActionSeq) state = null;
      return;
    }
    if (seq >= _userActionSeq) state = active;
  }

  /// 切换激活连接（先落盘再更新内存态，保证路由守卫立即生效）。
  /// 若尝试激活已停用的内置连接，由 store.setActive 抛出 [StateError]。
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
