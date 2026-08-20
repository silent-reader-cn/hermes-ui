import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_client_sessions.dart';
import '../../core/api/api_exception.dart';
import '../../core/connections/connection_providers.dart';
import '../../core/models/session.dart';

/// 项目（projects 域 4 个端点）所需的最小服务器 API 面。
///
/// 生产实现 [ProjectApiClient] 包 [ApiClient]（模型在客户端解码）；
/// 测试注入纯 Dart fake，彻底绕开网络/事件循环。
abstract interface class ProjectApi {
  /// GET /api/projects → {projects: […]}.
  Future<ProjectsResponse> fetchProjects();

  /// POST /api/projects/create {name, color?}；成功返回 {ok, project} 或 {project}。
  Future<ProjectMutationResponse> createProject({
    required String name,
    String? color,
  });

  /// POST /api/projects/rename {project_id, name, color?}。
  Future<ProjectMutationResponse> renameProject({
    required String projectId,
    required String name,
    String? color,
  });

  /// POST /api/projects/delete {project_id}。
  Future<ProjectMutationResponse> deleteProject(String projectId);
}

/// [ProjectApi] 的生产实现：包 [ApiClient]，把 `Object?` JSON 解码为模型。
class ProjectApiClient implements ProjectApi {
  ProjectApiClient(this._client);

  final ApiClient _client;

  @override
  Future<ProjectsResponse> fetchProjects() async {
    return _client.projects();
  }

  @override
  Future<ProjectMutationResponse> createProject({
    required String name,
    String? color,
  }) async {
    return _client.createProject(name: name, color: color);
  }

  @override
  Future<ProjectMutationResponse> renameProject({
    required String projectId,
    required String name,
    String? color,
  }) async {
    return _client.renameProject(
      projectId: projectId,
      name: name,
      color: color,
    );
  }

  @override
  Future<ProjectMutationResponse> deleteProject(String projectId) async {
    return _client.deleteProject(projectId);
  }
}

/// 构建 [ProjectApi] 的工厂（测试可 override 注入 fake）。
typedef ProjectApiFactory = ProjectApi Function(ApiClient client);

final projectApiFactoryProvider = Provider<ProjectApiFactory>(
  (ref) => ProjectApiClient.new,
);

/// 项目列表控制器：加载 / 新建 / 重命名 / 删除。
///
/// AsyncValue 语义：`AsyncData` 携带项目列表；初始加载失败 → `AsyncError`
/// （UI 展示错误态 + 重试）；变更操作失败返回 null/false 且不改变列表。
final projectsProvider =
    AsyncNotifierProvider<ProjectsController, List<ProjectSummary>>(
  ProjectsController.new,
);

class ProjectsController extends AsyncNotifier<List<ProjectSummary>> {
  ProjectApi get _api =>
      ref.read(projectApiFactoryProvider)(ref.read(apiClientProvider));

  @override
  Future<List<ProjectSummary>> build() async {
    // watch：切换服务器（apiClientProvider 重建）或工厂被替换时自动重载。
    final api = ref.watch(projectApiFactoryProvider)(
      ref.watch(apiClientProvider),
    );
    final response = await api.fetchProjects();
    return response.projects ?? const <ProjectSummary>[];
  }

  /// 刷新项目列表（错误态「重试」入口）。
  Future<void> refresh() async {
    final api = _api;
    try {
      final response = await api.fetchProjects();
      state = AsyncData(response.projects ?? const <ProjectSummary>[]);
    } on Exception catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
    }
  }

  /// 新建项目；成功返回新项目（供 picker 直接选中），失败返回 null。
  Future<ProjectSummary?> createProject({
    required String name,
    String? color,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return null;
    final current = state.valueOrNull ?? const <ProjectSummary>[];
    try {
      final response = await _api.createProject(name: trimmed, color: color);
      if (response.ok == false) return null;
      final project = response.project;
      if (project == null) return null;
      final exists = current.any((p) => p.id == project.id);
      state = AsyncData(
        exists
            ? [
                for (final p in current)
                  p.id == project.id ? project : p,
              ]
            : [...current, project],
      );
      return project;
    } on ApiException {
      return null;
    }
  }

  /// 重命名项目（可一并改色）；成功返回 true。
  Future<bool> renameProject({
    required String projectId,
    required String name,
    String? color,
  }) async {
    final current = state.valueOrNull;
    try {
      final response = await _api.renameProject(
        projectId: projectId,
        name: name.trim(),
        color: color,
      );
      if (response.ok == false) return false;
      final updated = response.project;
      if (updated != null && current != null) {
        state = AsyncData(
          [
            for (final p in current)
              p.id == updated.id ? updated : p,
          ],
        );
      }
      return true;
    } on ApiException {
      return false;
    }
  }

  /// 删除项目；成功返回 true。
  Future<bool> deleteProject(String projectId) async {
    final current = state.valueOrNull;
    try {
      final response = await _api.deleteProject(projectId);
      if (response.ok == false) return false;
      if (current != null) {
        state = AsyncData(
          current.where((p) => p.id != projectId).toList(),
        );
      }
      return true;
    } on ApiException {
      return false;
    }
  }
}