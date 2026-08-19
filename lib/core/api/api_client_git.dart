import 'api_client.dart';
import 'endpoints.dart';
import '../models/git_workspace.dart';

/// git 域方法（16 个端点，全部以 `session_id` 定位工作区）。
extension ApiClientGit on ApiClient {
  /// LLM commit-message 生成超时：120s（其余默认 60s）。
  static const commitMessageTimeout = Duration(seconds: 120);

  Future<GitInfoResponse> gitInfo(String sessionId) async {
    final json = await sendJson(Endpoint.gitInfo(sessionId));
    return GitInfoResponse.fromJson(_asMap(json));
  }

  Future<GitStatusResponse> gitStatus(String sessionId) async {
    final json = await sendJson(Endpoint.gitStatus(sessionId));
    return GitStatusResponse.fromJson(_asMap(json));
  }

  Future<GitBranchesResponse> gitBranches(String sessionId) async {
    final json = await sendJson(Endpoint.gitBranches(sessionId));
    return GitBranchesResponse.fromJson(_asMap(json));
  }

  Future<GitDiffResponse> gitDiff({
    required String sessionId,
    required String path,
    String kind = 'unstaged',
  }) async {
    final json = await sendJson(
      Endpoint.gitDiff(sessionId: sessionId, path: path, kind: kind),
    );
    return GitDiffResponse.fromJson(_asMap(json));
  }

  Future<GitRemoteActionResponse> gitFetch(String sessionId) async {
    final json = await sendJson(
      Endpoint.gitFetch,
      method: 'POST',
      body: {'session_id': sessionId},
    );
    return GitRemoteActionResponse.fromJson(_asMap(json));
  }

  Future<GitRemoteActionResponse> gitPull(String sessionId) async {
    final json = await sendJson(
      Endpoint.gitPull,
      method: 'POST',
      body: {'session_id': sessionId},
    );
    return GitRemoteActionResponse.fromJson(_asMap(json));
  }

  Future<GitRemoteActionResponse> gitPush(String sessionId) async {
    final json = await sendJson(
      Endpoint.gitPush,
      method: 'POST',
      body: {'session_id': sessionId},
    );
    return GitRemoteActionResponse.fromJson(_asMap(json));
  }

  /// POST /api/git/checkout — mode∈`local|remote|new`；本地 + new_branch 时自动用
  /// `new`；dirty_mode 固定发 `"block"`。
  Future<GitCheckoutResponse> gitCheckout({
    required String sessionId,
    required String ref,
    String mode = 'local',
    String? newBranch,
    bool track = false,
  }) async {
    final json = await sendJson(
      Endpoint.gitCheckout,
      method: 'POST',
      body: {
        'session_id': sessionId,
        'ref': ref,
        'mode': (mode == 'local' && newBranch != null) ? 'new' : mode,
        'new_branch': ?newBranch,
        if (track) 'track': true,
        'dirty_mode': 'block',
      },
    );
    return GitCheckoutResponse.fromJson(_asMap(json));
  }

  /// POST /api/git/stash-checkout — 与 gitCheckout 相同但**无 dirty_mode**。
  Future<GitCheckoutResponse> gitStashCheckout({
    required String sessionId,
    required String ref,
    String mode = 'local',
    String? newBranch,
    bool track = false,
  }) async {
    final json = await sendJson(
      Endpoint.gitStashCheckout,
      method: 'POST',
      body: {
        'session_id': sessionId,
        'ref': ref,
        'mode': (mode == 'local' && newBranch != null) ? 'new' : mode,
        'new_branch': ?newBranch,
        if (track) 'track': true,
      },
    );
    return GitCheckoutResponse.fromJson(_asMap(json));
  }

  Future<GitMutationResponse> gitStage({
    required String sessionId,
    required List<String> paths,
  }) async {
    final json = await sendJson(
      Endpoint.gitStage,
      method: 'POST',
      body: {'session_id': sessionId, 'paths': paths},
    );
    return GitMutationResponse.fromJson(_asMap(json));
  }

  Future<GitMutationResponse> gitUnstage({
    required String sessionId,
    required List<String> paths,
  }) async {
    final json = await sendJson(
      Endpoint.gitUnstage,
      method: 'POST',
      body: {'session_id': sessionId, 'paths': paths},
    );
    return GitMutationResponse.fromJson(_asMap(json));
  }

  Future<GitMutationResponse> gitDiscard({
    required String sessionId,
    required List<String> paths,
    bool deleteUntracked = false,
  }) async {
    final json = await sendJson(
      Endpoint.gitDiscard,
      method: 'POST',
      body: {
        'session_id': sessionId,
        'paths': paths,
        'delete_untracked': deleteUntracked,
      },
    );
    return GitMutationResponse.fromJson(_asMap(json));
  }

  Future<GitCommitResponse> gitCommit({
    required String sessionId,
    required String message,
  }) async {
    final json = await sendJson(
      Endpoint.gitCommit,
      method: 'POST',
      body: {'session_id': sessionId, 'message': message},
    );
    return GitCommitResponse.fromJson(_asMap(json));
  }

  Future<GitCommitResponse> gitCommitSelected({
    required String sessionId,
    required String message,
    required List<String> paths,
  }) async {
    final json = await sendJson(
      Endpoint.gitCommitSelected,
      method: 'POST',
      body: {'session_id': sessionId, 'message': message, 'paths': paths},
    );
    return GitCommitResponse.fromJson(_asMap(json));
  }

  /// POST /api/git/commit-message — LLM 生成，超时 120s。
  Future<GitCommitMessageResponse> gitCommitMessage(String sessionId) async {
    final json = await sendJson(
      Endpoint.gitCommitMessage,
      method: 'POST',
      body: {'session_id': sessionId},
      timeout: commitMessageTimeout,
    );
    return GitCommitMessageResponse.fromJson(_asMap(json));
  }

  /// POST /api/git/commit-message-selected — 超时 120s。
  Future<GitCommitMessageResponse> gitCommitMessageSelected({
    required String sessionId,
    required List<String> paths,
  }) async {
    final json = await sendJson(
      Endpoint.gitCommitMessageSelected,
      method: 'POST',
      body: {'session_id': sessionId, 'paths': paths},
      timeout: commitMessageTimeout,
    );
    return GitCommitMessageResponse.fromJson(_asMap(json));
  }
}

Map<String, Object?> _asMap(Object? json) =>
    json is Map<String, Object?>
        ? json
        : (json is Map ? Map<String, Object?>.from(json) : const <String, Object?>{});
