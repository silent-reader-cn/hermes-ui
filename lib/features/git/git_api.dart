import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_client_git.dart';
import '../../core/models/git_workspace.dart';

/// Git 面板所需的最小服务器 API 面（git 域 16 个端点中的 11 个，全部以
/// `session_id` 定位工作区）。
///
/// 生产实现 [GitApiClient] 包 [ApiClient]（模型在客户端解码）；测试注入
/// 纯 Dart fake，彻底绕开网络（对齐 session_list 的 `SessionListApi` 模式）。
abstract interface class GitApi {
  /// GET /api/git/status → 工作区变更状态。
  Future<GitStatusResponse> fetchStatus(String sessionId);

  /// GET /api/git/branches → 本地 / 远程分支列表。
  Future<GitBranchesResponse> fetchBranches(String sessionId);

  /// GET /api/git/diff → 指定文件 diff（kind ∈ staged | unstaged）。
  Future<GitDiffResponse> fetchDiff({
    required String sessionId,
    required String path,
    String kind = 'unstaged',
  });

  /// POST /api/git/stage {session_id, paths}。
  Future<GitMutationResponse> stage({
    required String sessionId,
    required List<String> paths,
  });

  /// POST /api/git/unstage {session_id, paths}。
  Future<GitMutationResponse> unstage({
    required String sessionId,
    required List<String> paths,
  });

  /// POST /api/git/discard {session_id, paths, delete_untracked}。
  Future<GitMutationResponse> discard({
    required String sessionId,
    required List<String> paths,
    bool deleteUntracked = false,
  });

  /// POST /api/git/commit {session_id, message}。
  Future<GitCommitResponse> commit({
    required String sessionId,
    required String message,
  });

  /// POST /api/git/checkout {session_id, ref, mode, new_branch?, track?}。
  Future<GitCheckoutResponse> checkout({
    required String sessionId,
    required String ref,
    String mode = 'local',
    String? newBranch,
    bool track = false,
  });

  /// POST /api/git/fetch {session_id}。
  Future<GitRemoteActionResponse> fetch(String sessionId);

  /// POST /api/git/pull {session_id}。
  Future<GitRemoteActionResponse> pull(String sessionId);

  /// POST /api/git/push {session_id}。
  Future<GitRemoteActionResponse> push(String sessionId);
}

/// [GitApi] 的生产实现：包 [ApiClient]，把 `Object?` JSON 解码为模型。
class GitApiClient implements GitApi {
  GitApiClient(this._client);

  final ApiClient _client;

  @override
  Future<GitStatusResponse> fetchStatus(String sessionId) async {
    final json = await _client.gitStatus(sessionId);
    return GitStatusResponse.fromJson(_asMap(json));
  }

  @override
  Future<GitBranchesResponse> fetchBranches(String sessionId) async {
    final json = await _client.gitBranches(sessionId);
    return GitBranchesResponse.fromJson(_asMap(json));
  }

  @override
  Future<GitDiffResponse> fetchDiff({
    required String sessionId,
    required String path,
    String kind = 'unstaged',
  }) async {
    final json = await _client.gitDiff(
      sessionId: sessionId,
      path: path,
      kind: kind,
    );
    return GitDiffResponse.fromJson(_asMap(json));
  }

  @override
  Future<GitMutationResponse> stage({
    required String sessionId,
    required List<String> paths,
  }) async {
    final json = await _client.gitStage(sessionId: sessionId, paths: paths);
    return GitMutationResponse.fromJson(_asMap(json));
  }

  @override
  Future<GitMutationResponse> unstage({
    required String sessionId,
    required List<String> paths,
  }) async {
    final json = await _client.gitUnstage(sessionId: sessionId, paths: paths);
    return GitMutationResponse.fromJson(_asMap(json));
  }

  @override
  Future<GitMutationResponse> discard({
    required String sessionId,
    required List<String> paths,
    bool deleteUntracked = false,
  }) async {
    final json = await _client.gitDiscard(
      sessionId: sessionId,
      paths: paths,
      deleteUntracked: deleteUntracked,
    );
    return GitMutationResponse.fromJson(_asMap(json));
  }

  @override
  Future<GitCommitResponse> commit({
    required String sessionId,
    required String message,
  }) async {
    final json = await _client.gitCommit(
      sessionId: sessionId,
      message: message,
    );
    return GitCommitResponse.fromJson(_asMap(json));
  }

  @override
  Future<GitCheckoutResponse> checkout({
    required String sessionId,
    required String ref,
    String mode = 'local',
    String? newBranch,
    bool track = false,
  }) async {
    final json = await _client.gitCheckout(
      sessionId: sessionId,
      ref: ref,
      mode: mode,
      newBranch: newBranch,
      track: track,
    );
    return GitCheckoutResponse.fromJson(_asMap(json));
  }

  @override
  Future<GitRemoteActionResponse> fetch(String sessionId) async {
    final json = await _client.gitFetch(sessionId);
    return GitRemoteActionResponse.fromJson(_asMap(json));
  }

  @override
  Future<GitRemoteActionResponse> pull(String sessionId) async {
    final json = await _client.gitPull(sessionId);
    return GitRemoteActionResponse.fromJson(_asMap(json));
  }

  @override
  Future<GitRemoteActionResponse> push(String sessionId) async {
    final json = await _client.gitPush(sessionId);
    return GitRemoteActionResponse.fromJson(_asMap(json));
  }

  static Map<String, Object?> _asMap(Object? json) =>
      json is Map<String, Object?> ? json : const <String, Object?>{};
}

/// 构建 [GitApi] 的工厂（测试可 override 注入 fake）。
typedef GitApiFactory = GitApi Function(ApiClient client);

final gitApiFactoryProvider = Provider<GitApiFactory>(
  (ref) => GitApiClient.new,
);
