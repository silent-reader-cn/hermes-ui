import 'api_client.dart';
import 'endpoints.dart';

/// git 域方法（16 个端点，全部以 `session_id` 定位工作区）。
///
/// 返回类型暂为 `Object?`（解码后的 JSON）；TODO(merge)：模型就绪后改为对应
/// 类型并 `return XxxResponse.fromJson(json)`。
extension ApiClientGit on ApiClient {
  /// LLM commit-message 生成超时：120s（其余默认 60s）。
  static const commitMessageTimeout = Duration(seconds: 120);

  Future<Object?> gitInfo(String sessionId) =>
      sendJson(Endpoint.gitInfo(sessionId));

  Future<Object?> gitStatus(String sessionId) =>
      sendJson(Endpoint.gitStatus(sessionId));

  Future<Object?> gitBranches(String sessionId) =>
      sendJson(Endpoint.gitBranches(sessionId));

  Future<Object?> gitDiff({
    required String sessionId,
    required String path,
    String kind = 'unstaged',
  }) =>
      sendJson(Endpoint.gitDiff(sessionId: sessionId, path: path, kind: kind));

  Future<Object?> gitFetch(String sessionId) => sendJson(
    Endpoint.gitFetch,
    method: 'POST',
    body: {'session_id': sessionId},
  );

  Future<Object?> gitPull(String sessionId) => sendJson(
    Endpoint.gitPull,
    method: 'POST',
    body: {'session_id': sessionId},
  );

  Future<Object?> gitPush(String sessionId) => sendJson(
    Endpoint.gitPush,
    method: 'POST',
    body: {'session_id': sessionId},
  );

  /// POST /api/git/checkout — mode∈`local|remote|new`；本地 + new_branch 时自动用
  /// `new`；dirty_mode 固定发 `"block"`。
  Future<Object?> gitCheckout({
    required String sessionId,
    required String ref,
    String mode = 'local',
    String? newBranch,
    bool track = false,
  }) => sendJson(
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

  /// POST /api/git/stash-checkout — 与 gitCheckout 相同但**无 dirty_mode**。
  Future<Object?> gitStashCheckout({
    required String sessionId,
    required String ref,
    String mode = 'local',
    String? newBranch,
    bool track = false,
  }) => sendJson(
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

  Future<Object?> gitStage({
    required String sessionId,
    required List<String> paths,
  }) => sendJson(
    Endpoint.gitStage,
    method: 'POST',
    body: {'session_id': sessionId, 'paths': paths},
  );

  Future<Object?> gitUnstage({
    required String sessionId,
    required List<String> paths,
  }) => sendJson(
    Endpoint.gitUnstage,
    method: 'POST',
    body: {'session_id': sessionId, 'paths': paths},
  );

  Future<Object?> gitDiscard({
    required String sessionId,
    required List<String> paths,
    bool deleteUntracked = false,
  }) => sendJson(
    Endpoint.gitDiscard,
    method: 'POST',
    body: {
      'session_id': sessionId,
      'paths': paths,
      'delete_untracked': deleteUntracked,
    },
  );

  Future<Object?> gitCommit({
    required String sessionId,
    required String message,
  }) => sendJson(
    Endpoint.gitCommit,
    method: 'POST',
    body: {'session_id': sessionId, 'message': message},
  );

  Future<Object?> gitCommitSelected({
    required String sessionId,
    required String message,
    required List<String> paths,
  }) => sendJson(
    Endpoint.gitCommitSelected,
    method: 'POST',
    body: {'session_id': sessionId, 'message': message, 'paths': paths},
  );

  /// POST /api/git/commit-message — LLM 生成，超时 120s。
  Future<Object?> gitCommitMessage(String sessionId) => sendJson(
    Endpoint.gitCommitMessage,
    method: 'POST',
    body: {'session_id': sessionId},
    timeout: commitMessageTimeout,
  );

  /// POST /api/git/commit-message-selected — 超时 120s。
  Future<Object?> gitCommitMessageSelected({
    required String sessionId,
    required List<String> paths,
  }) => sendJson(
    Endpoint.gitCommitMessageSelected,
    method: 'POST',
    body: {'session_id': sessionId, 'paths': paths},
    timeout: commitMessageTimeout,
  );
}
