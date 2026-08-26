import '../../core/api/api_client.dart';
import '../../core/api/api_client_sessions.dart';
import '../../core/api/api_client_workspace.dart';
import '../../core/api/api_exception.dart';
import '../../core/models/session.dart';
import '../../core/models/workspace.dart';

/// 工作区注册表域所需的最小服务器 API 面。
///
/// 生产实现 [WorkspaceManagerApiClient] 包 [ApiClient]（模型在客户端解码）；
/// 测试注入纯 Dart fake，彻底绕开网络（对齐 workspace 的 `WorkspaceApi` 模式）。
abstract interface class WorkspaceManagerApi {
  /// GET /api/workspaces → 全部已注册工作区 + last。
  Future<WorkspacesResponse> fetchWorkspaces();

  /// GET /api/workspaces/suggest?prefix= → 路径补全建议（最多 12 条）。
  Future<WorkspaceSuggestionsResponse> fetchSuggestions(String prefix);

  /// POST /api/workspaces/add {path, name?, create?} → 变更后全量列表。
  Future<WorkspaceMutationResponse> addWorkspace({
    required String path,
    String? name,
    bool? create,
  });

  /// POST /api/workspaces/rename {path, name} → 变更后全量列表。
  Future<WorkspaceMutationResponse> renameWorkspace({
    required String path,
    required String name,
  });

  /// POST /api/workspaces/remove {path} → 变更后全量列表。
  Future<WorkspaceMutationResponse> removeWorkspace(String path);

  /// 找到工作区路径对应的可用会话 ID（文件浏览端点以 session_id 定位工作区根）。
  ///
  /// 服务器文件域（/api/list、/api/file*）没有「按绝对路径浏览」的端点，必须
  /// 借用一个 `workspace == path` 的会话。先做字面匹配，再做 Windows 大小写/
  /// 反斜杠规范化匹配；无匹配会话返回 null。
  Future<String?> findSessionIdForWorkspace(String workspacePath);
}

/// [WorkspaceManagerApi] 的生产实现：包 [ApiClient]，把 typed 响应原样透传
/// （**严禁二次 `fromJson(_asMap(...))`**——扩展层已解码，二次解析会丢字段，
/// 见 hermes-ui-codebase skill 的「双层解析陷阱」）。
///
/// 容错点（规格 §8.2）：服务器 worker 池过载时返回**裸 503**（空 body），
/// 与 JSON 503 语义不同；[fetchWorkspaces] / 3 个 mutation 在裸 503 时重试一次。
class WorkspaceManagerApiClient implements WorkspaceManagerApi {
  WorkspaceManagerApiClient(this._client);

  final ApiClient _client;

  @override
  Future<WorkspacesResponse> fetchWorkspaces() {
    return _withOverloadRetry(() => _client.workspaces());
  }

  @override
  Future<WorkspaceSuggestionsResponse> fetchSuggestions(String prefix) {
    return _client.workspaceSuggestions(prefix);
  }

  @override
  Future<WorkspaceMutationResponse> addWorkspace({
    required String path,
    String? name,
    bool? create,
  }) {
    return _withOverloadRetry(
      () => _client.addWorkspace(path: path, name: name, create: create),
    );
  }

  @override
  Future<WorkspaceMutationResponse> renameWorkspace({
    required String path,
    required String name,
  }) {
    return _withOverloadRetry(
      () => _client.renameWorkspace(path: path, name: name),
    );
  }

  @override
  Future<WorkspaceMutationResponse> removeWorkspace(String path) {
    return _withOverloadRetry(() => _client.removeWorkspace(path));
  }

  @override
  Future<String?> findSessionIdForWorkspace(String workspacePath) async {
    final response = await _client.sessions();
    final sessions = response.sessions ?? const <SessionSummary>[];
    final target = _normalize(workspacePath);
    for (final session in sessions) {
      final workspace = session.workspace;
      if (workspace == null || workspace.isEmpty) continue;
      if (workspace == workspacePath || _normalize(workspace) == target) {
        return session.sessionId;
      }
    }
    return null;
  }

  /// 服务器 worker 池过载（server.py:124-129）：裸 `503` + 空 body。与
  /// `{"error": ...}` 的 JSON 503 区分（后者如 office 依赖缺失，重试无意义）。
  Future<T> _withOverloadRetry<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on HttpException catch (error) {
      final bareBody = error.body == null || error.body!.trim().isEmpty;
      if (error.statusCode == 503 && bareBody) {
        return await run();
      }
      rethrow;
    }
  }

  /// Windows 路径规范化（反斜杠 → 斜杠、去尾斜杠、小写），用于会话匹配。
  static String _normalize(String path) {
    var normalized = path.trim().replaceAll('\\', '/');
    while (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized.toLowerCase();
  }
}
