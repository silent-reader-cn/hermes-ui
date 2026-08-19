import 'dart:convert';

import 'api_client.dart';
import 'api_exception.dart';
import 'endpoints.dart';
import '../models/kanban.dart';

/// kanban 域方法（23 个端点）+ §2.5 专属守卫。
extension ApiClientKanban on ApiClient {
  // -------------------------------------------------------------------------
  // 基元：kanbanJSON（校验 Content-Type 以 application/json 开头）
  // -------------------------------------------------------------------------

  /// kanban 专用请求：响应头 Content-Type 非 `application/json` 开头 →
  /// [KanbanNonJsonContentTypeException]。
  Future<Object?> kanbanJson(
    Endpoint endpoint, {
    String method = 'GET',
    Map<String, Object?>? body,
  }) async {
    final response = await sendDataReturningResponse(
      endpoint,
      method: method,
      body: body,
    );
    final contentType =
        response.headers.value('content-type')?.toLowerCase() ?? '';
    if (!contentType.startsWith('application/json')) {
      throw const KanbanNonJsonContentTypeException();
    }
    final text = utf8.decode(response.data, allowMalformed: true);
    if (text.isEmpty) return null;
    try {
      return jsonDecode(text);
    } on FormatException catch (error) {
      throw DecodingException('响应 JSON 解析失败：${error.message}');
    }
  }

  // -------------------------------------------------------------------------
  // 端点方法
  // -------------------------------------------------------------------------

  /// GET /api/kanban/config。
  Future<KanbanConfiguration> kanbanConfiguration() async {
    final json = await kanbanJson(Endpoint.kanbanConfig);
    return KanbanConfiguration.fromJson(_asMap(json));
  }

  /// GET /api/kanban/boards。
  Future<KanbanBoardsResponse> kanbanBoards() async {
    final json = await kanbanJson(Endpoint.kanbanBoards);
    return KanbanBoardsResponse.fromJson(_asMap(json));
  }

  /// POST /api/kanban/boards {slug, name, description, icon, color}。
  Future<KanbanBoardMutationEnvelope> createKanbanBoard({
    required String slug,
    required String name,
    required String description,
    required String icon,
    required String color,
  }) async {
    final json = await kanbanJson(
      Endpoint.kanbanCreateBoard,
      method: 'POST',
      body: {
        'slug': slug,
        'name': name,
        'description': description,
        'icon': icon,
        'color': color,
      },
    );
    return KanbanBoardMutationEnvelope.fromJson(_asMap(json));
  }

  /// PATCH /api/kanban/boards/{slug} {name, description, icon, color}（无 slug）。
  Future<KanbanBoardMutationEnvelope> editKanbanBoard({
    required String slug,
    required String name,
    required String description,
    required String icon,
    required String color,
  }) async {
    final json = await kanbanJson(
      Endpoint.kanbanEditBoard(slug),
      method: 'PATCH',
      body: {
        'name': name,
        'description': description,
        'icon': icon,
        'color': color,
      },
    );
    return KanbanBoardMutationEnvelope.fromJson(_asMap(json));
  }

  /// DELETE /api/kanban/boards/{slug}（无 body）。
  Future<KanbanBoardMutationEnvelope> archiveKanbanBoard(String slug) async {
    final json = await kanbanJson(
      Endpoint.kanbanArchiveBoard(slug),
      method: 'DELETE',
    );
    return KanbanBoardMutationEnvelope.fromJson(_asMap(json));
  }

  /// POST /api/kanban/boards/{slug}/switch（无 body）。
  Future<KanbanBoardMutationEnvelope> makeKanbanBoardActive(String slug) async {
    final json = await kanbanJson(
      Endpoint.kanbanMakeBoardActive(slug),
      method: 'POST',
    );
    return KanbanBoardMutationEnvelope.fromJson(_asMap(json));
  }

  /// POST /api/kanban/dispatch?board=&dry_run=&max=8 — 8 个计数全空 → 报错。
  Future<KanbanDispatchResult> dispatchKanban({
    required String board,
    bool dryRun = false,
  }) async {
    final json = await kanbanJson(
      Endpoint.kanbanDispatch(board: board, dryRun: dryRun),
      method: 'POST',
    );
    final map = _asMap(json);
    final result = KanbanDispatchResult.fromJson(map);
    if (!result.hasKnownCategory) {
      throw const KanbanDispatchMissingResultException();
    }
    return result;
  }

  /// GET /api/kanban/board?board=&tenant?=&assignee?=&include_archived?=&only_mine?=&since?=。
  Future<KanbanBoardSnapshot> kanbanBoard({
    required String board,
    String? tenant,
    String? assignee,
    bool includeArchived = false,
    bool onlyMine = false,
    String? since,
  }) async {
    final json = await kanbanJson(
      Endpoint.kanbanBoard(
        board: board,
        tenant: tenant,
        assignee: assignee,
        includeArchived: includeArchived,
        onlyMine: onlyMine,
        since: since,
      ),
    );
    return KanbanBoardSnapshot.fromJson(_asMap(json));
  }

  /// GET /api/kanban/stats?board=。
  Future<KanbanStats> kanbanStats(String board) async {
    final json = await kanbanJson(Endpoint.kanbanStats(board));
    return KanbanStats.fromJson(_asMap(json));
  }

  /// GET /api/kanban/assignees?board=。
  Future<KanbanAssigneeHistory> kanbanAssignees(String board) async {
    final json = await kanbanJson(Endpoint.kanbanAssignees(board));
    return KanbanAssigneeHistory.fromJson(_asMap(json));
  }

  /// GET /api/kanban/events?board=&since=&limit=（since max(0)，limit clamp 1–200）。
  Future<KanbanEventsEnvelope> kanbanEvents({
    required String board,
    required int since,
    int limit = 200,
  }) async {
    final json = await kanbanJson(
      Endpoint.kanbanEvents(board: board, since: since, limit: limit),
    );
    return KanbanEventsEnvelope.fromJson(_asMap(json));
  }

  /// GET /api/kanban/events/stream?board=&since=（独立帧协议 hello/events，SSE）。
  Uri kanbanEventsStreamUrl({required String board, required int since}) =>
      Endpoint.kanbanEventsStream(board: board, since: since).url(baseUrl);

  /// GET /api/kanban/tasks/{cardId}?board=。
  Future<KanbanCardDetailEnvelope> kanbanCardDetail({
    required String board,
    required String cardId,
  }) async {
    final json = await kanbanJson(
      Endpoint.kanbanCardDetail(board: board, cardId: cardId),
    );
    return KanbanCardDetailEnvelope.fromJson(_asMap(json));
  }

  /// GET /api/kanban/tasks/{cardId}/log?board=&tail=（tail 默认 65536，clamp 1–2M）。
  Future<KanbanWorkerLog> kanbanWorkerLog({
    required String board,
    required String cardId,
    int tail = 65536,
  }) async {
    final json = await kanbanJson(
      Endpoint.kanbanWorkerLog(board: board, cardId: cardId, tail: tail),
    );
    return KanbanWorkerLog.fromJson(_asMap(json));
  }

  /// POST /api/kanban/tasks/{cardId}/comments?board= {body}。
  Future<KanbanAddCommentResponse> addKanbanComment({
    required String board,
    required String cardId,
    required String body,
  }) async {
    final json = await kanbanJson(
      Endpoint.kanbanAddComment(board: board, cardId: cardId),
      method: 'POST',
      body: {'body': body},
    );
    return KanbanAddCommentResponse.fromJson(_asMap(json));
  }

  /// POST /api/kanban/tasks?board= — `parents` = `[prerequisiteId]`（有值时）。
  Future<KanbanCardMutationEnvelope> createKanbanCard({
    required String board,
    required String title,
    String? body,
    required String status,
    int? priority,
    String? assignee,
    String? tenant,
    required String workspaceKind,
    String? workspacePath,
    List<String>? skills,
    int? maxRuntimeSeconds,
    String? prerequisiteId,
    required String idempotencyKey,
  }) async {
    final json = await kanbanJson(
      Endpoint.kanbanCreateCard(board),
      method: 'POST',
      body: {
        'title': title,
        'body': ?body,
        'status': status,
        'priority': ?priority,
        'assignee': ?assignee,
        'tenant': ?tenant,
        'workspace_kind': workspaceKind,
        'workspace_path': ?workspacePath,
        'skills': ?skills,
        'max_runtime_seconds': ?maxRuntimeSeconds,
        if (prerequisiteId != null) 'parents': [prerequisiteId],
        'idempotency_key': idempotencyKey,
      },
    );
    return KanbanCardMutationEnvelope.fromJson(_asMap(json));
  }

  /// POST /api/kanban/tasks/bulk?board= — 四选一：archive / status / assignee /
  /// priority（assignee 空串当无）。
  Future<KanbanBulkActionEnvelope> performKanbanBulkAction({
    required String board,
    required List<String> ids,
    bool? archive,
    String? status,
    String? assignee,
    int? priority,
  }) async {
    final json = await kanbanJson(
      Endpoint.kanbanBulkAction(board),
      method: 'POST',
      body: {
        'ids': ids,
        'archive': ?archive,
        'status': ?status,
        if (assignee != null && assignee.isNotEmpty) 'assignee': assignee,
        'priority': ?priority,
      },
    );
    return KanbanBulkActionEnvelope.fromJson(_asMap(json));
  }

  /// PATCH /api/kanban/tasks/{cardId}?board= — tenant/assignee 可显式 null
  /// （键照发，值为 null）；status 有值才发。
  Future<KanbanCardMutationEnvelope> editKanbanCard({
    required String board,
    required String cardId,
    required String title,
    required String body,
    required Object? tenant,
    required int priority,
    required Object? assignee,
    String? status,
  }) async {
    final json = await kanbanJson(
      Endpoint.kanbanEditCard(board: board, cardId: cardId),
      method: 'PATCH',
      body: {
        'title': title,
        'body': body,
        'tenant': tenant,
        'priority': priority,
        'assignee': assignee,
        'status': ?status,
      },
    );
    return KanbanCardMutationEnvelope.fromJson(_asMap(json));
  }

  /// PATCH /api/kanban/tasks/{cardId}?board= {status} — **status≠running 守卫**
  /// （running 只能由 dispatcher 设置，本地拦截不发请求）。
  Future<KanbanCardMutationEnvelope> setKanbanCardStatus({
    required String board,
    required String cardId,
    required String status,
  }) async {
    if (status.trim().toLowerCase() == 'running') {
      throw const KanbanRunningStatusRequiresDispatcherException();
    }
    final json = await kanbanJson(
      Endpoint.kanbanCardStatus(board: board, cardId: cardId),
      method: 'PATCH',
      body: {'status': status},
    );
    return KanbanCardMutationEnvelope.fromJson(_asMap(json));
  }

  /// POST /api/kanban/tasks/{cardId}/block?board= {reason?}。
  Future<KanbanCardMutationEnvelope> blockKanbanCard({
    required String board,
    required String cardId,
    String? reason,
  }) async {
    final json = await kanbanJson(
      Endpoint.kanbanBlockCard(board: board, cardId: cardId),
      method: 'POST',
      body: {'reason': ?reason},
    );
    return KanbanCardMutationEnvelope.fromJson(_asMap(json));
  }

  /// POST /api/kanban/tasks/{cardId}/unblock?board= {}（reason 传 nil 不发键）。
  Future<KanbanCardMutationEnvelope> unblockKanbanCard({
    required String board,
    required String cardId,
  }) async {
    final json = await kanbanJson(
      Endpoint.kanbanUnblockCard(board: board, cardId: cardId),
      method: 'POST',
      body: <String, Object?>{},
    );
    return KanbanCardMutationEnvelope.fromJson(_asMap(json));
  }

  /// POST /api/kanban/links?board= {parent_id, child_id}。
  Future<KanbanDependencyMutationEnvelope> addKanbanDependency({
    required String board,
    required String parentId,
    required String childId,
  }) async {
    final json = await kanbanJson(
      Endpoint.kanbanAddDependency(board),
      method: 'POST',
      body: {'parent_id': parentId, 'child_id': childId},
    );
    return KanbanDependencyMutationEnvelope.fromJson(_asMap(json));
  }

  /// POST /api/kanban/links/delete?board= {parent_id, child_id}。
  Future<KanbanDependencyMutationEnvelope> removeKanbanDependency({
    required String board,
    required String parentId,
    required String childId,
  }) async {
    final json = await kanbanJson(
      Endpoint.kanbanRemoveDependency(board),
      method: 'POST',
      body: {'parent_id': parentId, 'child_id': childId},
    );
    return KanbanDependencyMutationEnvelope.fromJson(_asMap(json));
  }
}

Map<String, Object?> _asMap(Object? json) =>
    json is Map<String, Object?>
        ? json
        : (json is Map ? Map<String, Object?>.from(json) : const <String, Object?>{});
