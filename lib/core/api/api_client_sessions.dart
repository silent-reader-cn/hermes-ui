import 'api_client.dart';
import 'endpoints.dart';

/// sessions 域方法（18 个端点）+ projects 域（4 个端点）。
///
/// 返回类型暂为 `Object?`（解码后的 JSON）；TODO(merge)：模型就绪后改为对应
/// 类型并 `return XxxResponse.fromJson(json)`。
extension ApiClientSessions on ApiClient {
  /// GET /api/sessions（`include_archived` 为 opt-in，`archived_limit` 仅随其发送）。
  Future<Object?> sessions({
    bool includeArchived = false,
    int? archivedLimit,
  }) => sendJson(
    Endpoint.sessions(
      includeArchived: includeArchived,
      archivedLimit: archivedLimit,
    ),
  );

  /// GET /api/sessions/search?q=&content=&depth= → SessionSearchResponse。
  Future<Object?> searchSessions({
    required String query,
    bool content = true,
    int depth = 5,
  }) => sendJson(
    Endpoint.sessionsSearch(query: query, content: content, depth: depth),
  );

  /// GET /api/session?session_id=&messages=… → SessionResponse {session}。
  Future<Object?> session({
    required String sessionId,
    bool includeMessages = true,
    int? messageLimit,
    int? messageBefore,
    bool expandRenderable = false,
  }) => sendJson(
    Endpoint.session(
      sessionId: sessionId,
      includeMessages: includeMessages,
      messageLimit: messageLimit,
      messageBefore: messageBefore,
      expandRenderable: expandRenderable,
    ),
  );

  /// GET /api/session/status?session_id= → SessionStatusResponse。
  Future<Object?> sessionStatus(String sessionId) =>
      sendJson(Endpoint.sessionStatus(sessionId));

  /// POST /api/session/new {workspace?, model?, model_provider?, profile?}。
  Future<Object?> createSession({
    String? workspace,
    String? model,
    String? modelProvider,
    String? profile,
  }) => sendJson(
    Endpoint.newSession,
    method: 'POST',
    body: {
      'workspace': ?workspace,
      'model': ?model,
      'model_provider': ?modelProvider,
      'profile': ?profile,
    },
  );

  Future<Object?> renameSession({
    required String sessionId,
    required String title,
  }) => sendJson(
    Endpoint.renameSession,
    method: 'POST',
    body: {'session_id': sessionId, 'title': title},
  );

  Future<Object?> deleteSession(String sessionId) => sendJson(
    Endpoint.deleteSession,
    method: 'POST',
    body: {'session_id': sessionId},
  );

  Future<Object?> pinSession({
    required String sessionId,
    required bool pinned,
  }) => sendJson(
    Endpoint.pinSession,
    method: 'POST',
    body: {'session_id': sessionId, 'pinned': pinned},
  );

  Future<Object?> archiveSession({
    required String sessionId,
    required bool archived,
  }) => sendJson(
    Endpoint.archiveSession,
    method: 'POST',
    body: {'session_id': sessionId, 'archived': archived},
  );

  Future<Object?> branchSession({
    required String sessionId,
    int? keepCount,
    String? title,
  }) => sendJson(
    Endpoint.branchSession,
    method: 'POST',
    body: {'session_id': sessionId, 'keep_count': ?keepCount, 'title': ?title},
  );

  Future<Object?> compressSession({
    required String sessionId,
    String? focusTopic,
  }) => sendJson(
    Endpoint.compressSession,
    method: 'POST',
    body: {'session_id': sessionId, 'focus_topic': ?focusTopic},
  );

  Future<Object?> undoSession(String sessionId) => sendJson(
    Endpoint.undoSession,
    method: 'POST',
    body: {'session_id': sessionId},
  );

  Future<Object?> retrySession(String sessionId) => sendJson(
    Endpoint.retrySession,
    method: 'POST',
    body: {'session_id': sessionId},
  );

  Future<Object?> truncateSession({
    required String sessionId,
    required int keepCount,
  }) => sendJson(
    Endpoint.truncateSession,
    method: 'POST',
    body: {'session_id': sessionId, 'keep_count': keepCount},
  );

  Future<Object?> updateSession({
    required String sessionId,
    String? workspace,
    String? model,
    String? modelProvider,
  }) => sendJson(
    Endpoint.updateSession,
    method: 'POST',
    body: {
      'session_id': sessionId,
      'workspace': ?workspace,
      'model': ?model,
      'model_provider': ?modelProvider,
    },
  );

  Future<Object?> moveSession({required String sessionId, String? projectId}) =>
      sendJson(
        Endpoint.moveSession,
        method: 'POST',
        body: {'session_id': sessionId, 'project_id': ?projectId},
      );

  /// GET /api/session/yolo（查状态，session_id 可选）。
  Future<Object?> sessionYolo([String? sessionId]) =>
      sendJson(Endpoint.sessionYolo(sessionId));

  /// POST /api/session/yolo {session_id, enabled}（设状态，无 query）。
  Future<Object?> setSessionYolo({
    required String sessionId,
    required bool enabled,
  }) => sendJson(
    Endpoint.sessionYolo(),
    method: 'POST',
    body: {'session_id': sessionId, 'enabled': enabled},
  );

  /// GET /api/session/export?session_id=&format=html|json — 文件下载（非 JSON），
  /// Accept=`*/*`；文件名由调用方用 [SessionExportFilename] 从响应头解析。
  Future<ApiByteResponse> exportSession({
    required String sessionId,
    required String format,
    Duration? timeout,
  }) => sendDataReturningResponse(
    Endpoint.exportSession(sessionId: sessionId, format: format),
    method: 'GET',
    accept: '*/*',
    timeout: timeout,
  );

  // -------------------------------------------------------------------------
  // projects（1.3）— 4 个
  // -------------------------------------------------------------------------

  Future<Object?> projects() => sendJson(Endpoint.projects);

  Future<Object?> createProject({required String name, String? color}) =>
      sendJson(
        Endpoint.createProject,
        method: 'POST',
        body: {'name': name, 'color': ?color},
      );

  Future<Object?> renameProject({
    required String projectId,
    required String name,
    String? color,
  }) => sendJson(
    Endpoint.renameProject,
    method: 'POST',
    body: {'project_id': projectId, 'name': name, 'color': ?color},
  );

  Future<Object?> deleteProject(String projectId) => sendJson(
    Endpoint.deleteProject,
    method: 'POST',
    body: {'project_id': projectId},
  );
}

/// 从 `Content-Disposition` 解析导出文件名（对齐 SessionExportFile.filename）。
///
/// 优先级：`filename="…"`（或裸 token）→ 会话标题（净化）+ 扩展名 →
/// `hermes-<session-id>.<ext>`。
class SessionExportFilename {
  const SessionExportFilename._();

  static String resolve({
    required String? contentDisposition,
    required String? fallbackTitle,
    required String sessionId,
    required String format,
  }) {
    final fromHeader = _filenameParameter(contentDisposition);
    final sanitized = fromHeader == null ? null : _sanitizeFilename(fromHeader);
    if (sanitized != null) return sanitized;

    final titleStem = fallbackTitle == null
        ? null
        : _sanitizeFilenameStem(fallbackTitle);
    if (titleStem != null) return '$titleStem.$format';

    final idStem = _sanitizeFilenameStem(sessionId) ?? 'session';
    return 'hermes-$idStem.$format';
  }

  static String? _filenameParameter(String? contentDisposition) {
    if (contentDisposition == null) return null;
    for (final rawParameter in contentDisposition.split(';').skip(1)) {
      final parameter = rawParameter.trim();
      final eq = parameter.indexOf('=');
      if (eq <= 0) continue;
      final key = parameter.substring(0, eq).trim().toLowerCase();
      if (key != 'filename') continue;
      var value = parameter.substring(eq + 1).trim();
      if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
        value = value.substring(1, value.length - 1);
      }
      if (value.isNotEmpty) return value;
    }
    return null;
  }

  static String? _sanitizeFilename(String raw) {
    final normalized = raw.replaceAll('\\', '/');
    final lastComponent = normalized.split('/').last;
    final cleaned = _replaceUnsafeCharacters(lastComponent);
    if (cleaned.isEmpty || cleaned == '.' || cleaned == '..') return null;
    return cleaned;
  }

  static String? _sanitizeFilenameStem(String raw) {
    final cleaned = _replaceUnsafeCharacters(raw);
    if (cleaned.isEmpty) return null;
    return cleaned.length <= 80 ? cleaned : cleaned.substring(0, 80);
  }

  static String _replaceUnsafeCharacters(String raw) {
    final buffer = StringBuffer();
    for (final rune in raw.runes) {
      final ch = String.fromCharCode(rune);
      final isUnsafe =
          ch == '/' || ch == '\\' || ch == ':' || ch == '\n' || ch == '\r';
      buffer.write(isUnsafe ? ' ' : ch);
    }
    return buffer
        .toString()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .join(' ');
  }
}
