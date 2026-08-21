import 'dart:async';

import 'package:hermex_flutter/core/models/workspace.dart';
import 'package:hermex_flutter/features/workspace_manager/workspace_manager_api.dart';

/// 可配置的 [WorkspaceManagerApi] fake（测试注入，彻底绕开网络）。
///
/// mutation 方法模拟服务端行为：把变更后的全量列表放进响应（含本次操作效果），
/// 便于断言「成功后列表已更新」；所有方法带调用记录与错误注入。
class FakeWorkspaceManagerApi implements WorkspaceManagerApi {
  FakeWorkspaceManagerApi({List<WorkspaceRoot>? workspaces, this.last})
    : workspaces = workspaces ?? [];

  /// 当前「服务器端」工作区列表（mutation 会就地更新）。
  List<WorkspaceRoot> workspaces;

  /// 上次激活工作区路径。
  String? last;

  /// `fetchWorkspaces` 抛出的异常（非 null 时模拟加载失败）。
  Object? fetchError;

  /// 各 mutation / 查询抛出的异常（非 null 时模拟失败）。
  Object? addError;
  Object? renameError;
  Object? removeError;
  Object? suggestionError;
  Object? sessionLookupError;

  /// prefix → 建议列表。
  final Map<String, List<String>> suggestionsByPrefix = {};

  /// `findSessionIdForWorkspace` 的返回值。
  String? sessionIdForWorkspace;

  /// 非 null 时 `addWorkspace` 挂起等待该 gate（测试 mutation 在途竞态）。
  Completer<void>? addGate;

  int fetchCount = 0;

  /// 调用记录。
  final List<String> fetchCalls = [];
  final List<String> addCalls = [];
  final List<String> renameCalls = [];
  final List<String> removeCalls = [];
  final List<String> suggestionCalls = [];
  final List<String> sessionLookupCalls = [];

  @override
  Future<WorkspacesResponse> fetchWorkspaces() async {
    fetchCount++;
    fetchCalls.add('fetch');
    final error = fetchError;
    if (error != null) throw error;
    return WorkspacesResponse(
      workspaces: List.of(workspaces),
      last: last,
      terminalRemoteBackend: false,
    );
  }

  @override
  Future<WorkspaceSuggestionsResponse> fetchSuggestions(String prefix) async {
    suggestionCalls.add(prefix);
    final error = suggestionError;
    if (error != null) throw error;
    return WorkspaceSuggestionsResponse(
      suggestions: suggestionsByPrefix[prefix] ?? const [],
      prefix: prefix,
    );
  }

  @override
  Future<WorkspaceMutationResponse> addWorkspace({
    required String path,
    String? name,
    bool? create,
  }) async {
    addCalls.add('$path|${name ?? ''}|${create ?? false}');
    final error = addError;
    if (error != null) throw error;
    final gate = addGate;
    if (gate != null) await gate.future;
    final root = WorkspaceRoot(path: path, name: name);
    if (!workspaces.any((w) => w.path == path)) {
      workspaces = [...workspaces, root];
    }
    return WorkspaceMutationResponse(ok: true, workspaces: List.of(workspaces));
  }

  @override
  Future<WorkspaceMutationResponse> renameWorkspace({
    required String path,
    required String name,
  }) async {
    renameCalls.add('$path|$name');
    final error = renameError;
    if (error != null) throw error;
    workspaces = [
      for (final w in workspaces)
        if (w.path == path) WorkspaceRoot(path: w.path, name: name) else w,
    ];
    return WorkspaceMutationResponse(ok: true, workspaces: List.of(workspaces));
  }

  @override
  Future<WorkspaceMutationResponse> removeWorkspace(String path) async {
    removeCalls.add(path);
    final error = removeError;
    if (error != null) throw error;
    workspaces = workspaces.where((w) => w.path != path).toList();
    return WorkspaceMutationResponse(ok: true, workspaces: List.of(workspaces));
  }

  @override
  Future<String?> findSessionIdForWorkspace(String workspacePath) async {
    sessionLookupCalls.add(workspacePath);
    final error = sessionLookupError;
    if (error != null) throw error;
    return sessionIdForWorkspace;
  }
}
