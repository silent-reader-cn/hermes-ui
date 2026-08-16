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
