import 'dart:convert';

import 'api_client.dart';
import 'api_exception.dart';
import 'endpoints.dart';

/// kanban 域方法（23 个端点）+ §2.5 专属守卫。
///
/// 返回类型暂为 `Object?`（解码后的 JSON）；TODO(merge)：模型就绪后改为对应
/// 类型并 `return XxxResponse.fromJson(json)`。
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
  Future<Object?> kanbanConfiguration() => kanbanJson(Endpoint.kanbanConfig);

  /// GET /api/kanban/boards。
  Future<Object?> kanbanBoards() => kanbanJson(Endpoint.kanbanBoards);

  /// POST /api/kanban/boards {slug, name, description, icon, color}。
  Future<Object?> createKanbanBoard({
    required String slug,
    required String name,
    required String description,
    required String icon,
    required String color,
  }) => kanbanJson(
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

  /// PATCH /api/kanban/boards/{slug} {name, description, icon, color}（无 slug）。
  Future<Object?> editKanbanBoard({
    required String slug,
    required String name,
    required String description,
    required String icon,
    required String color,
  }) => kanbanJson(
    Endpoint.kanbanEditBoard(slug),
    method: 'PATCH',
    body: {
      'name': name,
      'description': description,
      'icon': icon,
      'color': color,
    },
  );

  /// DELETE /api/kanban/boards/{slug}（无 body）。
  Future<Object?> archiveKanbanBoard(String slug) =>
      kanbanJson(Endpoint.kanbanArchiveBoard(slug), method: 'DELETE');

  /// POST /api/kanban/boards/{slug}/switch（无 body）。
  Future<Object?> makeKanbanBoardActive(String slug) =>
      kanbanJson(Endpoint.kanbanMakeBoardActive(slug), method: 'POST');

  /// POST /api/kanban/dispatch?board=&dry_run=&max=8 — 8 个计数全空 → 报错。
  Future<Object?> dispatchKanban({
    required String board,
    bool dryRun = false,
  }) async {
    final json = await kanbanJson(
      Endpoint.kanbanDispatch(board: board, dryRun: dryRun),
      method: 'POST',
    );
    final map = json is Map<String, Object?> ? json : const <String, Object?>{};
    const keys = [
      'spawned',
      'promoted',
      'reclaimed',
      'skipped_unassigned',
      'skipped_nonspawnable',
      'auto_blocked',
      'timed_out',
      'crashed',
    ];
    final hasKnownCategory = keys.any((key) => map[key] != null);
    if (!hasKnownCategory) {
      throw const KanbanDispatchMissingResultException();
    }
    return json;
  }

  /// GET /api/kanban/board?board=&tenant?=&assignee?=&include_archived?=&only_mine?=&since?=。
  Future<Object?> kanbanBoard({
    required String board,
    String? tenant,
    String? assignee,
    bool includeArchived = false,
    bool onlyMine = false,
    String? since,
  }) => kanbanJson(
    Endpoint.kanbanBoard(
      board: board,
      tenant: tenant,
      assignee: assignee,
      includeArchived: includeArchived,
      onlyMine: onlyMine,
      since: since,
    ),
  );

  /// GET /api/kanban/stats?board=。
  Future<Object?> kanbanStats(String board) =>
      kanbanJson(Endpoint.kanbanStats(board));

  /// GET /api/kanban/assignees?board=。
  Future<Object?> kanbanAssignees(String board) =>
      kanbanJson(Endpoint.kanbanAssignees(board));

  /// GET /api/kanban/events?board=&since=&limit=（since max(0)，limit clamp 1–200）。
  Future<Object?> kanbanEvents({
    required String board,
    required int since,
    int limit = 200,
  }) => kanbanJson(
    Endpoint.kanbanEvents(board: board, since: since, limit: limit),
  );

  /// GET /api/kanban/events/stream?board=&since=（独立帧协议 hello/events，SSE）。
  Uri kanbanEventsStreamUrl({required String board, required int since}) =>
      Endpoint.kanbanEventsStream(board: board, since: since).url(baseUrl);

  /// GET /api/kanban/tasks/{cardId}?board=。
  Future<Object?> kanbanCardDetail({
    required String board,
    required String cardId,
  }) => kanbanJson(Endpoint.kanbanCardDetail(board: board, cardId: cardId));

  /// GET /api/kanban/tasks/{cardId}/log?board=&tail=（tail 默认 65536，clamp 1–2M）。
  Future<Object?> kanbanWorkerLog({
    required String board,
    required String cardId,
    int tail = 65536,
  }) => kanbanJson(
    Endpoint.kanbanWorkerLog(board: board, cardId: cardId, tail: tail),
  );

  /// POST /api/kanban/tasks/{cardId}/comments?board= {body}。
  Future<Object?> addKanbanComment({
    required String board,
    required String cardId,
    required String body,
  }) => kanbanJson(
    Endpoint.kanbanAddComment(board: board, cardId: cardId),
    method: 'POST',
    body: {'body': body},
  );

  /// POST /api/kanban/tasks?board= — `parents` = `[prerequisiteId]`（有值时）。
  Future<Object?> createKanbanCard({
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
  }) => kanbanJson(
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

  /// POST /api/kanban/tasks/bulk?board= — 四选一：archive / status / assignee /
  /// priority（assignee 空串当无）。
  Future<Object?> performKanbanBulkAction({
    required String board,
    required List<String> ids,
    bool? archive,
    String? status,
    String? assignee,
    int? priority,
  }) => kanbanJson(
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

  /// PATCH /api/kanban/tasks/{cardId}?board= — tenant/assignee 可显式 null
  /// （键照发，值为 null）；status 有值才发。
  Future<Object?> editKanbanCard({
    required String board,
    required String cardId,
    required String title,
    required String body,
    required Object? tenant,
    required int priority,
    required Object? assignee,
    String? status,
  }) => kanbanJson(
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

  /// PATCH /api/kanban/tasks/{cardId}?board= {status} — **status≠running 守卫**
  /// （running 只能由 dispatcher 设置，本地拦截不发请求）。
  Future<Object?> setKanbanCardStatus({
    required String board,
    required String cardId,
    required String status,
  }) async {
    if (status.trim().toLowerCase() == 'running') {
      throw const KanbanRunningStatusRequiresDispatcherException();
    }
    return kanbanJson(
      Endpoint.kanbanCardStatus(board: board, cardId: cardId),
      method: 'PATCH',
      body: {'status': status},
    );
  }

  /// POST /api/kanban/tasks/{cardId}/block?board= {reason?}。
  Future<Object?> blockKanbanCard({
    required String board,
    required String cardId,
    String? reason,
  }) => kanbanJson(
    Endpoint.kanbanBlockCard(board: board, cardId: cardId),
    method: 'POST',
    body: {'reason': ?reason},
  );

  /// POST /api/kanban/tasks/{cardId}/unblock?board= {}（reason 传 nil 不发键）。
  Future<Object?> unblockKanbanCard({
    required String board,
    required String cardId,
  }) => kanbanJson(
    Endpoint.kanbanUnblockCard(board: board, cardId: cardId),
    method: 'POST',
    body: <String, Object?>{},
  );

  /// POST /api/kanban/links?board= {parent_id, child_id}。
  Future<Object?> addKanbanDependency({
    required String board,
    required String parentId,
    required String childId,
  }) => kanbanJson(
    Endpoint.kanbanAddDependency(board),
    method: 'POST',
    body: {'parent_id': parentId, 'child_id': childId},
  );

  /// POST /api/kanban/links/delete?board= {parent_id, child_id}。
  Future<Object?> removeKanbanDependency({
    required String board,
    required String parentId,
    required String childId,
  }) => kanbanJson(
    Endpoint.kanbanRemoveDependency(board),
    method: 'POST',
    body: {'parent_id': parentId, 'child_id': childId},
  );
}
