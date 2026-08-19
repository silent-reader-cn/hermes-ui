import 'api_client.dart';
import 'endpoints.dart';
import '../models/approval.dart';
import '../models/clarification.dart';
import '../models/goal.dart';
import '../models/server_catalog.dart';

/// chat 域（9 个端点）+ approval 域（3 个）+ clarify 域（3 个）。
extension ApiClientChat on ApiClient {
  /// POST /api/chat/start — attachments 元素形状
  /// `{name, path, mime, size?, is_image}`（UploadResponse 透传）。
  Future<ChatStartResponse> startChat({
    required String sessionId,
    required String message,
    String? workspace,
    String? model,
    String? modelProvider,
    String? profile,
    bool explicitModelPick = false,
    List<Map<String, Object?>>? attachments,
  }) async {
    final json = await sendJson(
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
    return ChatStartResponse.fromJson(_asMap(json));
  }

  /// GET /api/chat/stream?stream_id=（重放时追加 replay=1&after_seq=N）。
  Uri chatStreamUrl(String streamId, {int? replayAfterSeq}) {
    if (replayAfterSeq == null) {
      return Endpoint.chatStream(streamId).url(baseUrl);
    }
    return Endpoint.chatStreamReplay(streamId, replayAfterSeq).url(baseUrl);
  }

  /// GET /api/chat/cancel?stream_id=（⚠️ GET 不是 POST）。
  Future<ChatCancelResponse> cancelChat(String streamId) async {
    final json = await sendJson(Endpoint.chatCancel(streamId), method: 'GET');
    return ChatCancelResponse.fromJson(_asMap(json));
  }

  /// GET /api/chat/stream/status?stream_id=。
  Future<ChatStreamStatusResponse> chatStreamStatus(String streamId) async {
    final json = await sendJson(Endpoint.chatStreamStatus(streamId));
    return ChatStreamStatusResponse.fromJson(_asMap(json));
  }

  /// POST /api/chat/steer {session_id, text}。
  Future<ChatSteerResponse> steerChat({
    required String sessionId,
    required String text,
  }) async {
    final json = await sendJson(
      Endpoint.chatSteer,
      method: 'POST',
      body: {'session_id': sessionId, 'text': text},
    );
    return ChatSteerResponse.fromJson(_asMap(json));
  }

  /// POST /api/goal {session_id, args, workspace?, model?, model_provider?, profile?}。
  Future<GoalSubmissionResponse> submitGoal({
    required String sessionId,
    required String args,
    String? workspace,
    String? model,
    String? modelProvider,
    String? profile,
  }) async {
    final json = await sendJson(
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
    return GoalSubmissionResponse.fromJson(_asMap(json));
  }

  /// POST /api/btw {session_id, question}。
  Future<BtwStartResponse> startBtw({
    required String sessionId,
    required String question,
  }) async {
    final json = await sendJson(
      Endpoint.btw,
      method: 'POST',
      body: {'session_id': sessionId, 'question': question},
    );
    return BtwStartResponse.fromJson(_asMap(json));
  }

  /// POST /api/background {session_id, prompt}。
  Future<BackgroundStartResponse> startBackground({
    required String sessionId,
    required String prompt,
  }) async {
    final json = await sendJson(
      Endpoint.background,
      method: 'POST',
      body: {'session_id': sessionId, 'prompt': prompt},
    );
    return BackgroundStartResponse.fromJson(_asMap(json));
  }

  /// GET /api/background/status?session_id=。
  Future<BackgroundStatusResponse> backgroundStatus(String sessionId) async {
    final json = await sendJson(Endpoint.backgroundStatus(sessionId));
    return BackgroundStatusResponse.fromJson(_asMap(json));
  }

  // -------------------------------------------------------------------------
  // approval（1.5）— 3 个
  // -------------------------------------------------------------------------

  /// GET /api/approval/pending?session_id=。
  Future<ApprovalPendingResponse> approvalPending(String sessionId) async {
    final json = await sendJson(Endpoint.approvalPending(sessionId));
    return ApprovalPendingResponse.fromJson(_asMap(json));
  }

  /// GET /api/approval/stream?session_id=（SSE，initial/approval 事件）。
  Uri approvalStreamUrl(String sessionId) =>
      Endpoint.approvalStream(sessionId).url(baseUrl);

  /// POST /api/approval/respond {session_id, choice, approval_id?}；
  /// 409 + `{stale:true}` → HttpException.indicatesExpiredPendingPrompt。
  Future<ApprovalRespondResponse> respondApproval({
    required String sessionId,
    required String choice,
    String? approvalId,
  }) async {
    final json = await sendJson(
      Endpoint.approvalRespond,
      method: 'POST',
      body: {
        'session_id': sessionId,
        'choice': choice,
        'approval_id': ?approvalId,
      },
    );
    return ApprovalRespondResponse.fromJson(_asMap(json));
  }

  // -------------------------------------------------------------------------
  // clarify（1.6）— 3 个
  // -------------------------------------------------------------------------

  /// GET /api/clarify/pending?session_id=。
  Future<ClarificationPendingResponse> clarifyPending(String sessionId) async {
    final json = await sendJson(Endpoint.clarifyPending(sessionId));
    return ClarificationPendingResponse.fromJson(_asMap(json));
  }

  /// GET /api/clarify/stream?session_id=（SSE，initial/clarify 事件）。
  Uri clarifyStreamUrl(String sessionId) =>
      Endpoint.clarifyStream(sessionId).url(baseUrl);

  /// POST /api/clarify/respond {session_id, response, clarify_id?}。
  Future<ClarificationRespondResponse> respondClarification({
    required String sessionId,
    required String response,
    String? clarifyId,
  }) async {
    final json = await sendJson(
      Endpoint.clarifyRespond,
      method: 'POST',
      body: {
        'session_id': sessionId,
        'response': response,
        'clarify_id': ?clarifyId,
      },
    );
    return ClarificationRespondResponse.fromJson(_asMap(json));
  }
}

Map<String, Object?> _asMap(Object? json) =>
    json is Map<String, Object?>
        ? json
        : (json is Map ? Map<String, Object?>.from(json) : const <String, Object?>{});
