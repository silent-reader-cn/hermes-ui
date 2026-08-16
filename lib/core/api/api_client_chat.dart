import 'api_client.dart';
import 'endpoints.dart';

/// chat 域（9 个端点）+ approval 域（3 个）+ clarify 域（3 个）。
///
/// 返回类型暂为 `Object?`（解码后的 JSON）；TODO(merge)：模型就绪后改为对应
/// 类型并 `return XxxResponse.fromJson(json)`。
extension ApiClientChat on ApiClient {
  /// POST /api/chat/start — attachments 元素形状
  /// `{name, path, mime, size?, is_image}`（UploadResponse 透传）。
  Future<Object?> startChat({
    required String sessionId,
    required String message,
    String? workspace,
    String? model,
    String? modelProvider,
    String? profile,
    bool explicitModelPick = false,
    List<Map<String, Object?>>? attachments,
  }) => sendJson(
    Endpoint.chatStart,
    method: 'POST',
    body: {
      'session_id': sessionId,
      'message': message,
      'workspace': ?workspace,
      'model': ?model,
      'model_provider': ?modelProvider,
      'profile': ?profile,
      if (explicitModelPick) 'explicit_model_pick': true,
      'attachments': ?attachments,
    },
  );

  /// GET /api/chat/stream?stream_id=（重放时追加 replay=1&after_seq=N）。
  Uri chatStreamUrl(String streamId, {int? replayAfterSeq}) {
    if (replayAfterSeq == null) {
      return Endpoint.chatStream(streamId).url(baseUrl);
    }
    return Endpoint.chatStreamReplay(streamId, replayAfterSeq).url(baseUrl);
  }

  /// GET /api/chat/cancel?stream_id=（⚠️ GET 不是 POST）。
  Future<Object?> cancelChat(String streamId) =>
      sendJson(Endpoint.chatCancel(streamId), method: 'GET');

  /// GET /api/chat/stream/status?stream_id=。
  Future<Object?> chatStreamStatus(String streamId) =>
      sendJson(Endpoint.chatStreamStatus(streamId));

  /// POST /api/chat/steer {session_id, text}。
  Future<Object?> steerChat({
    required String sessionId,
    required String text,
  }) => sendJson(
    Endpoint.chatSteer,
    method: 'POST',
    body: {'session_id': sessionId, 'text': text},
  );

  /// POST /api/goal {session_id, args, workspace?, model?, model_provider?, profile?}。
  Future<Object?> submitGoal({
    required String sessionId,
    required String args,
    String? workspace,
    String? model,
    String? modelProvider,
    String? profile,
  }) => sendJson(
    Endpoint.submitGoal,
    method: 'POST',
    body: {
      'session_id': sessionId,
      'args': args,
      'workspace': ?workspace,
      'model': ?model,
      'model_provider': ?modelProvider,
      'profile': ?profile,
    },
  );

  /// POST /api/btw {session_id, question}。
  Future<Object?> startBtw({
    required String sessionId,
    required String question,
  }) => sendJson(
    Endpoint.btw,
    method: 'POST',
    body: {'session_id': sessionId, 'question': question},
  );

  /// POST /api/background {session_id, prompt}。
  Future<Object?> startBackground({
    required String sessionId,
    required String prompt,
  }) => sendJson(
    Endpoint.background,
    method: 'POST',
    body: {'session_id': sessionId, 'prompt': prompt},
  );

  /// GET /api/background/status?session_id=。
  Future<Object?> backgroundStatus(String sessionId) =>
      sendJson(Endpoint.backgroundStatus(sessionId));

  // -------------------------------------------------------------------------
  // approval（1.5）— 3 个
  // -------------------------------------------------------------------------

  /// GET /api/approval/pending?session_id=。
  Future<Object?> approvalPending(String sessionId) =>
      sendJson(Endpoint.approvalPending(sessionId));

  /// GET /api/approval/stream?session_id=（SSE，initial/approval 事件）。
  Uri approvalStreamUrl(String sessionId) =>
      Endpoint.approvalStream(sessionId).url(baseUrl);

  /// POST /api/approval/respond {session_id, choice, approval_id?}；
  /// 409 + `{stale:true}` → HttpException.indicatesExpiredPendingPrompt。
  Future<Object?> respondApproval({
    required String sessionId,
    required String choice,
    String? approvalId,
  }) => sendJson(
    Endpoint.approvalRespond,
    method: 'POST',
    body: {
      'session_id': sessionId,
      'choice': choice,
      'approval_id': ?approvalId,
    },
  );

  // -------------------------------------------------------------------------
  // clarify（1.6）— 3 个
  // -------------------------------------------------------------------------

  /// GET /api/clarify/pending?session_id=。
  Future<Object?> clarifyPending(String sessionId) =>
      sendJson(Endpoint.clarifyPending(sessionId));

  /// GET /api/clarify/stream?session_id=（SSE，initial/clarify 事件）。
  Uri clarifyStreamUrl(String sessionId) =>
      Endpoint.clarifyStream(sessionId).url(baseUrl);

  /// POST /api/clarify/respond {session_id, response, clarify_id?}。
  Future<Object?> respondClarification({
    required String sessionId,
    required String response,
    String? clarifyId,
  }) => sendJson(
    Endpoint.clarifyRespond,
    method: 'POST',
    body: {
      'session_id': sessionId,
      'response': response,
      'clarify_id': ?clarifyId,
    },
  );
}
