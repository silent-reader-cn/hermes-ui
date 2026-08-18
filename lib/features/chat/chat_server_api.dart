import '../../core/api/api_client.dart';
import '../../core/api/api_client_chat.dart';
import '../../core/api/api_client_sessions.dart';
import '../../core/api/sse_client.dart';

/// 聊天模块所需的最小服务器 API 面。
///
/// 生产实现 [ChatApiClient] 包 [ApiClient] + [SseClient]；测试可注入纯 Dart
/// fake，彻底绕开网络/事件循环（对齐 onboarding 的 `OnboardingServerApi` 模式）。
abstract interface class ChatServerApi {
  /// POST /api/chat/start → `{stream_id, session_id?}`。
  Future<Object?> startChat({
    required String sessionId,
    required String message,
    String? workspace,
    String? model,
    String? modelProvider,
    String? profile,
    bool explicitModelPick = false,
    List<Map<String, Object?>>? attachments,
  });

  /// POST /api/chat/steer {session_id, text} → `{accepted}`。
  Future<Object?> steerChat({required String sessionId, required String text});

  /// GET /api/chat/cancel?stream_id= → `{ok}`。
  Future<Object?> cancelChat(String streamId);

  /// GET /api/chat/stream/status?stream_id= → ChatStreamStatus。
  Future<Object?> chatStreamStatus(String streamId);

  /// POST /api/approval/respond {session_id, choice, approval_id?}。
  Future<Object?> respondApproval({
    required String sessionId,
    required String choice,
    String? approvalId,
  });

  /// POST /api/clarify/respond {session_id, response, clarify_id?}。
  Future<Object?> respondClarification({
    required String sessionId,
    required String response,
    String? clarifyId,
  });

  /// GET /api/session（messages=1 时带 transcript；无消息 = 补拉标题）。
  Future<Object?> session({
    required String sessionId,
    bool includeMessages = true,
    int? messageLimit,
    int? messageBefore,
    bool expandRenderable = false,
  });

  /// POST /api/session/rename {session_id, title} → SessionMutationResponse。
  Future<Object?> renameSession({required String sessionId, required String title});

  /// POST /api/session/pin {session_id, pinned} → SessionMutationResponse。
  Future<Object?> pinSession({required String sessionId, required bool pinned});

  /// POST /api/session/archive {session_id, archived} → SessionMutationResponse。
  Future<Object?> archiveSession({required String sessionId, required bool archived});

  /// POST /api/session/delete {session_id} → SessionMutationResponse。
  Future<Object?> deleteSession(String sessionId);

  /// POST /api/session/branch {session_id} → SessionBranchResponse。
  Future<Object?> branchSession(String sessionId);

  /// POST /api/session/truncate {session_id, keep_count} → `{ok, session:{messages}}`。
  ///
  /// [keepCount] 为从开头保留的消息条数（0 = 清空）。
  Future<Object?> truncateSession({
    required String sessionId,
    required int keepCount,
  });

  /// POST /api/session/compress {session_id, focus_topic?} → SessionCompressResponse。
  Future<Object?> compressSession({
    required String sessionId,
    String? focusTopic,
  });

  /// POST /api/session/undo {session_id} → SessionUndoResponse（删最后一轮）。
  Future<Object?> undoSession(String sessionId);

  /// POST /api/session/retry {session_id} → SessionRetryResponse（text=最后一轮用户消息原文）。
  Future<Object?> retrySession(String sessionId);

  /// POST /api/session/update {session_id, workspace?, model?, model_provider?}
  /// → SessionMutationResponse（只读导入会话返回 403）。
  Future<Object?> updateSession({
    required String sessionId,
    String? workspace,
    String? model,
    String? modelProvider,
  });

  /// GET /api/session/yolo?session_id= → `{ok, yolo_enabled}`（容错）。
  Future<Object?> getYolo(String sessionId);

  /// POST /api/session/yolo {session_id, enabled} → `{ok, yolo_enabled}`。
  Future<Object?> setYolo({
    required String sessionId,
    required bool enabled,
  });

  /// 建立 SSE 连接并持续派发解码后的事件；流自然结束/出错后返回。
  ///
  /// [onEventId] 在收到事件 `id:` 字段时回调（lastEventID 跟踪用）。
  /// [onTransportError] / [onClosed] 分别对应传输错误与连接关闭。
  Future<void> startStream(
    String streamId, {
    int? replayAfterSeq,
    required void Function(SseEvent event) onEvent,
    void Function(String eventId)? onEventId,
    required void Function(String message) onTransportError,
    required void Function() onClosed,
  });

  /// 主动断开当前 SSE 连接（静默，不触发 onTransportError）。
  void stopStream();
}

/// [ChatServerApi] 的生产实现（包 [ApiClient]，SSE 复用其 dio 继承 header/cookie）。
class ChatApiClient implements ChatServerApi {
  ChatApiClient(this._client)
      : _sseClient = SseClient(
          dio: _client.dio,
          baseUrl: _client.baseUrl,
        );

  final ApiClient _client;
  final SseClient _sseClient;

  @override
  Future<Object?> startChat({
    required String sessionId,
    required String message,
    String? workspace,
    String? model,
    String? modelProvider,
    String? profile,
    bool explicitModelPick = false,
    List<Map<String, Object?>>? attachments,
  }) {
    return _client.startChat(
      sessionId: sessionId,
      message: message,
      workspace: workspace,
      model: model,
      modelProvider: modelProvider,
      profile: profile,
      explicitModelPick: explicitModelPick,
      attachments: attachments,
    );
  }

  @override
  Future<Object?> steerChat({
    required String sessionId,
    required String text,
  }) {
    return _client.steerChat(sessionId: sessionId, text: text);
  }

  @override
  Future<Object?> cancelChat(String streamId) =>
      _client.cancelChat(streamId);

  @override
  Future<Object?> chatStreamStatus(String streamId) =>
      _client.chatStreamStatus(streamId);

  @override
  Future<Object?> respondApproval({
    required String sessionId,
    required String choice,
    String? approvalId,
  }) {
    return _client.respondApproval(
      sessionId: sessionId,
      choice: choice,
      approvalId: approvalId,
    );
  }

  @override
  Future<Object?> respondClarification({
    required String sessionId,
    required String response,
    String? clarifyId,
  }) {
    return _client.respondClarification(
      sessionId: sessionId,
      response: response,
      clarifyId: clarifyId,
    );
  }

  @override
  Future<Object?> session({
    required String sessionId,
    bool includeMessages = true,
    int? messageLimit,
    int? messageBefore,
    bool expandRenderable = false,
  }) {
    return _client.session(
      sessionId: sessionId,
      includeMessages: includeMessages,
      messageLimit: messageLimit,
      messageBefore: messageBefore,
      expandRenderable: expandRenderable,
    );
  }

  @override
  Future<Object?> renameSession({
    required String sessionId,
    required String title,
  }) {
    return _client.renameSession(sessionId: sessionId, title: title);
  }

  @override
  Future<Object?> pinSession({
    required String sessionId,
    required bool pinned,
  }) {
    return _client.pinSession(sessionId: sessionId, pinned: pinned);
  }

  @override
  Future<Object?> archiveSession({
    required String sessionId,
    required bool archived,
  }) {
    return _client.archiveSession(sessionId: sessionId, archived: archived);
  }

  @override
  Future<Object?> deleteSession(String sessionId) =>
      _client.deleteSession(sessionId);

  @override
  Future<Object?> branchSession(String sessionId) =>
      _client.branchSession(sessionId: sessionId);

  @override
  Future<Object?> truncateSession({
    required String sessionId,
    required int keepCount,
  }) {
    return _client.truncateSession(sessionId: sessionId, keepCount: keepCount);
  }

  @override
  Future<Object?> compressSession({
    required String sessionId,
    String? focusTopic,
  }) {
    return _client.compressSession(
      sessionId: sessionId,
      focusTopic: focusTopic,
    );
  }

  @override
  Future<Object?> undoSession(String sessionId) =>
      _client.undoSession(sessionId);

  @override
  Future<Object?> retrySession(String sessionId) =>
      _client.retrySession(sessionId);

  @override
  Future<Object?> updateSession({
    required String sessionId,
    String? workspace,
    String? model,
    String? modelProvider,
  }) {
    return _client.updateSession(
      sessionId: sessionId,
      workspace: workspace,
      model: model,
      modelProvider: modelProvider,
    );
  }

  @override
  Future<Object?> getYolo(String sessionId) => _client.sessionYolo(sessionId);

  @override
  Future<Object?> setYolo({
    required String sessionId,
    required bool enabled,
  }) {
    return _client.setSessionYolo(sessionId: sessionId, enabled: enabled);
  }

  @override
  Future<void> startStream(
    String streamId, {
    int? replayAfterSeq,
    required void Function(SseEvent event) onEvent,
    void Function(String eventId)? onEventId,
    required void Function(String message) onTransportError,
    required void Function() onClosed,
  }) async {
    final url = _client.chatStreamUrl(
      streamId,
      replayAfterSeq: replayAfterSeq,
    );
    await _sseClient.start(
      url,
      onEvent: onEvent,
      onEventId: onEventId,
      onTransportError: onTransportError,
      onClosed: onClosed,
    );
  }

  @override
  void stopStream() => _sseClient.stop();
}
