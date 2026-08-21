import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_exception.dart';
import '../../core/connections/connection_providers.dart';
import '../../core/models/workspace.dart';
import 'workspace_manager_api.dart';

/// 构建 [WorkspaceManagerApi] 的工厂（测试可 override 注入 fake）。
typedef WorkspaceManagerApiFactory = WorkspaceManagerApi Function(
  ApiClient client,
);

final workspaceManagerApiFactoryProvider = Provider<WorkspaceManagerApiFactory>(
  (ref) => WorkspaceManagerApiClient.new,
);

/// 工作区注册表状态（与文件浏览的 `WorkspaceState` 分离；对齐 Swift
/// `WorkspaceRegistryViewModel` 的 `isMutating` 竞态守卫语义）。
class WorkspaceManagerState {
  const WorkspaceManagerState({
    this.workspaces = const [],
    this.last,
    this.isRefreshing = false,
    this.isMutating = false,
    this.actionError,
    this.notice,
  });

  /// 已注册工作区（服务端顺序，`workspaces.json`）。
  final List<WorkspaceRoot> workspaces;

  /// 上次激活工作区路径（`last`；无激活历史时可能为 null/空串）。
  final String? last;

  /// 列表刷新中（保留旧列表供 UI 展示）。
  final bool isRefreshing;

  /// 任一 mutation（添加/重命名/移除）在途：UI 禁用列表操作防竞态。
  final bool isMutating;

  /// 最近一次操作错误（弹窗展示后调用
  /// [WorkspaceManagerController.clearActionError] 清除）。
  final String? actionError;

  /// 成功提示（弹窗展示后调用
  /// [WorkspaceManagerController.clearNotice] 清除）。
  final String? notice;

  /// 指定工作区是否为「当前激活」状态（`last` 非空才可判定，规格 §8.10）。
  bool isCurrent(WorkspaceRoot workspace) {
    final last = this.last;
    return last != null && last.isNotEmpty && workspace.path == last;
  }

  WorkspaceManagerState copyWith({
    List<WorkspaceRoot>? workspaces,
    String? Function()? last,
    bool? isRefreshing,
    bool? isMutating,
    String? Function()? actionError,
    String? Function()? notice,
  }) {
    return WorkspaceManagerState(
      workspaces: workspaces ?? this.workspaces,
      last: last != null ? last() : this.last,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      isMutating: isMutating ?? this.isMutating,
      actionError: actionError != null ? actionError() : this.actionError,
      notice: notice != null ? notice() : this.notice,
    );
  }

  @override
  String toString() =>
      'WorkspaceManagerState(workspaces: ${workspaces.length}, '
      'isMutating: $isMutating, actionError: $actionError)';
}

/// 工作区注册表控制器：加载 / 刷新 / 添加 / 重命名 / 移除 / 建议补全。
///
/// AsyncValue 语义：初始加载与下拉刷新失败 → `AsyncError`（UI 全屏错误态 +
/// 重试）；mutation 失败不改变列表，只设置 [WorkspaceManagerState.actionError]。
/// 每次 mutation 成功后直接用响应里的全量 `workspaces` 替换本地列表（省一次
/// GET，规格 §5 建议）。mutation 在途（[WorkspaceManagerState.isMutating]）
/// 时其他 mutation 直接拒绝（防并发竞态，对齐 Swift `isMutating`）。
final workspaceManagerControllerProvider =
    AsyncNotifierProvider<WorkspaceManagerController, WorkspaceManagerState>(
      WorkspaceManagerController.new,
    );

class WorkspaceManagerController extends AsyncNotifier<WorkspaceManagerState> {
  WorkspaceManagerApi get _api =>
      ref.read(workspaceManagerApiFactoryProvider)(ref.read(apiClientProvider));

  @override
  Future<WorkspaceManagerState> build() async {
    // watch：切换服务器（apiClientProvider 重建）或工厂被替换时自动重载。
    final api = ref.watch(workspaceManagerApiFactoryProvider)(
      ref.watch(apiClientProvider),
    );
    return _load(api);
  }

  Future<WorkspaceManagerState> _load(WorkspaceManagerApi api) async {
    final response = await api.fetchWorkspaces();
    final current = state.valueOrNull;
    return WorkspaceManagerState(
      workspaces: response.workspaces ?? const <WorkspaceRoot>[],
      last: response.last,
      isRefreshing: false,
      isMutating: current?.isMutating ?? false,
      actionError: current?.actionError,
      notice: current?.notice,
    );
  }

  /// 下拉刷新 / 错误态重试；失败 → `AsyncError`。
  Future<void> refresh() async {
    try {
      final api = _api;
      final current = state.valueOrNull;
      state = AsyncData(
        (current ?? const WorkspaceManagerState()).copyWith(
          isRefreshing: true,
          actionError: () => null,
          notice: () => null,
        ),
      );
      state = AsyncData(await _load(api));
    } on Exception catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
    }
  }

  /// POST /api/workspaces/add（新建表单用）。
  ///
  /// 成功返回 null（列表已用响应全量替换）；失败返回错误消息（表单内联
  /// statusRedText 展示，**不弹窗打断**，对齐规格 §7.3）。mutation 在途或
  /// 状态未就绪时返回错误消息而非抛异常。
  Future<String?> addWorkspace({
    required String path,
    String? name,
    bool? create,
  }) async {
    final current = state.valueOrNull;
    if (current == null || current.isMutating) return '操作进行中，请稍候。';
    state = AsyncData(
      current.copyWith(isMutating: true, actionError: () => null),
    );
    try {
      final api = _api;
      final response = await api.addWorkspace(
        path: path,
        name: name,
        create: create,
      );
      final after = state.valueOrNull;
      if (after != null) {
        state = AsyncData(
          after.copyWith(
            workspaces: response.workspaces ?? after.workspaces,
            isMutating: false,
          ),
        );
      }
      return null;
    } on Exception catch (error) {
      final after = state.valueOrNull;
      if (after != null) {
        state = AsyncData(after.copyWith(isMutating: false));
      }
      return _messageOf(error);
    }
  }

  /// POST /api/workspaces/rename。成功 → 用响应列表替换 + notice。
  Future<bool> renameWorkspace({required String path, required String name}) {
    return _mutate(
      (api) => api.renameWorkspace(path: path, name: name),
      successNotice: () => '已重命名工作区为「$name」。',
    );
  }

  /// POST /api/workspaces/remove。成功 → 用响应列表替换 + notice。
  Future<bool> removeWorkspace(String path) {
    return _mutate(
      (api) => api.removeWorkspace(path),
      successNotice: () => '已从列表移除「${_basename(path)}」（磁盘文件未受影响）。',
    );
  }

  /// GET /api/workspaces/suggest?prefix=（新建弹窗内防抖调用）。
  ///
  /// 建议加载失败不打断流程，返回空列表（内联补全只是辅助能力）。
  Future<List<String>> loadSuggestions(String prefix) async {
    try {
      final response = await _api.fetchSuggestions(prefix);
      return response.suggestions ?? const <String>[];
    } on Exception {
      return const <String>[];
    }
  }

  /// 解析使用指定工作区的会话 ID（浏览文件用）；异常向上抛，由页面展示。
  Future<String?> findSessionIdForWorkspace(String workspacePath) {
    return _api.findSessionIdForWorkspace(workspacePath);
  }

  /// 清除行操作错误标记（UI 展示完弹窗后调用）。
  Future<void> clearActionError() async {
    final current = state.valueOrNull;
    if (current == null || current.actionError == null) return;
    state = AsyncData(current.copyWith(actionError: () => null));
  }

  /// 清除成功提示（UI 展示完弹窗后调用）。
  Future<void> clearNotice() async {
    final current = state.valueOrNull;
    if (current == null || current.notice == null) return;
    state = AsyncData(current.copyWith(notice: () => null));
  }

  // -------------------------------------------------------------------------
  // mutation 原语
  // -------------------------------------------------------------------------

  Future<bool> _mutate(
    Future<WorkspaceMutationResponse> Function(WorkspaceManagerApi api) run, {
    required String Function() successNotice,
  }) async {
    final current = state.valueOrNull;
    // mutation 在途时拒绝新操作（防并发竞态，对齐 Swift isMutating）。
    if (current == null || current.isMutating) return false;
    state = AsyncData(
      current.copyWith(isMutating: true, actionError: () => null),
    );
    try {
      final api = _api;
      final response = await run(api);
      final after = state.valueOrNull;
      if (after != null) {
        state = AsyncData(
          after.copyWith(
            workspaces: response.workspaces ?? after.workspaces,
            isMutating: false,
            notice: () => successNotice(),
          ),
        );
      }
      return true;
    } on Exception catch (error) {
      final after = state.valueOrNull;
      if (after != null) {
        state = AsyncData(
          after.copyWith(
            isMutating: false,
            actionError: () => _messageOf(error),
          ),
        );
      }
      return false;
    }
  }

  static String _messageOf(Object error) =>
      error is ApiException ? error.message : error.toString();

  static String _basename(String path) {
    final normalized = path.replaceAll('\\', '/');
    final trimmed = normalized.endsWith('/')
        ? normalized.substring(0, normalized.length - 1)
        : normalized;
    final idx = trimmed.lastIndexOf('/');
    if (idx < 0 || idx == trimmed.length - 1) return trimmed;
    return trimmed.substring(idx + 1);
  }
}
