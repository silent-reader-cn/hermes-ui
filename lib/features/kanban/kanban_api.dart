import 'dart:async';

import '../../core/api/api_client.dart';
import '../../core/api/api_client_kanban.dart';
import '../../core/api/ws_client.dart';
import '../../core/models/kanban.dart';

/// Kanban 页所需的最小服务器 API 面（kanban 域 23 个端点中的核心读写子集）。
///
/// 生产实现 [KanbanApiClient] 包 [ApiClient]（模型在客户端解码）；
/// 测试注入纯 Dart fake，彻底绕开网络/事件循环（对齐 session_list 的
/// `SessionListApi` 模式）。事件流以 `Stream<KanbanStreamFrame>` 暴露，
/// 由控制器订阅（fake 可手动注入帧驱动刷新）。
abstract interface class KanbanApi {
  /// GET /api/kanban/config → 桥配置（列 / assignees / readOnly 等）。
  Future<KanbanConfiguration> fetchConfiguration();

  /// GET /api/kanban/boards → 看板列表 + 当前看板。
  Future<KanbanBoardsResponse> fetchBoards();

  /// GET /api/kanban/board → 看板快照（按状态分列卡片）。
  Future<KanbanBoardSnapshot> fetchBoard({
    required String board,
    String? tenant,
    String? assignee,
    bool includeArchived = false,
    bool onlyMine = false,
  });

  /// GET /api/kanban/tasks/{cardId} → 卡片详情信封（卡片 + 评论等）。
  Future<KanbanCardDetailEnvelope> fetchCardDetail({
    required String board,
    required String cardId,
  });

  /// POST /api/kanban/tasks → 创建卡片，返回新卡片。
  Future<KanbanCard> createCard({
    required String board,
    required String title,
    String? body,
    required String status,
    String? assignee,
    String? tenant,
    required String workspaceKind,
    String? workspacePath,
    required String idempotencyKey,
  });

  /// POST /api/kanban/tasks/{cardId}/comments → 添加评论。
  Future<KanbanAddCommentResponse> addComment({
    required String board,
    required String cardId,
    required String body,
  });

  /// PATCH /api/kanban/tasks/{cardId} {status} → 改卡片状态
  /// （**status≠running 守卫**由 ApiClient 层保证）。
  Future<KanbanCard> setStatus({
    required String board,
    required String cardId,
    required String status,
  });

  /// POST /api/kanban/boards/{slug}/switch → 切换当前看板。
  Future<void> makeBoardActive(String slug);

  /// GET /api/kanban/events/stream（SSE 独立帧协议）→ 事件流。
  ///
  /// 返回的流以 [KanbanHelloFrame] / [KanbanEventsFrame] / 忽略 / 畸形帧
  /// 形式推送；连接失败或断开时流正常结束（`done`）。取消订阅即断开连接。
  Stream<KanbanStreamFrame> streamEvents({
    required String board,
    required int since,
  });

  /// GET /api/kanban/events → 拉取事件（流中断后的兜底刷新用）。
  Future<KanbanEventsEnvelope> fetchEvents({
    required String board,
    required int since,
    int limit = 200,
  });
}

/// [KanbanApi] 的生产实现：包 [ApiClient]，把 `Object?` JSON 解码为模型。
class KanbanApiClient implements KanbanApi {
  KanbanApiClient(this._client);

  final ApiClient _client;

  @override
  Future<KanbanConfiguration> fetchConfiguration() async {
    return _client.kanbanConfiguration();
  }

  @override
  Future<KanbanBoardsResponse> fetchBoards() async {
    return _client.kanbanBoards();
  }

  @override
  Future<KanbanBoardSnapshot> fetchBoard({
    required String board,
    String? tenant,
    String? assignee,
    bool includeArchived = false,
    bool onlyMine = false,
  }) async {
    return _client.kanbanBoard(
      board: board,
      tenant: tenant,
      assignee: assignee,
      includeArchived: includeArchived,
      onlyMine: onlyMine,
    );
  }

  @override
  Future<KanbanCardDetailEnvelope> fetchCardDetail({
    required String board,
    required String cardId,
  }) async {
    return _client.kanbanCardDetail(board: board, cardId: cardId);
  }

  @override
  Future<KanbanCard> createCard({
    required String board,
    required String title,
    String? body,
    required String status,
    String? assignee,
    String? tenant,
    required String workspaceKind,
    String? workspacePath,
    required String idempotencyKey,
  }) async {
    final response = await _client.createKanbanCard(
      board: board,
      title: title,
      body: body,
      status: status,
      assignee: assignee,
      tenant: tenant,
      workspaceKind: workspaceKind,
      workspacePath: workspacePath,
      idempotencyKey: idempotencyKey,
    );
    // ⚠️ 2026-08：_client.createKanbanCard() 已返回 typed
    // KanbanCardMutationEnvelope，直接取 .card；曾用 _asMap(json) 二次解析
    // （json 非 Map → 空 map）导致新建卡片恒返回空 KanbanCard。
    return response.card ?? const KanbanCard();
  }

  @override
  Future<KanbanAddCommentResponse> addComment({
    required String board,
    required String cardId,
    required String body,
  }) async {
    return _client.addKanbanComment(
      board: board,
      cardId: cardId,
      body: body,
    );
  }

  @override
  Future<KanbanCard> setStatus({
    required String board,
    required String cardId,
    required String status,
  }) async {
    final response = await _client.setKanbanCardStatus(
      board: board,
      cardId: cardId,
      status: status,
    );
    return response.card ?? const KanbanCard();
  }

  @override
  Future<void> makeBoardActive(String slug) async {
    await _client.makeKanbanBoardActive(slug);
  }

  @override
  Stream<KanbanStreamFrame> streamEvents({
    required String board,
    required int since,
  }) {
    final controller = StreamController<KanbanStreamFrame>();
    final streamClient = KanbanEventStreamClient(
      dio: _client.dio,
      baseUrl: _client.baseUrl,
    );
    unawaited(
      streamClient
          .start(
            _client.kanbanEventsStreamUrl(board: board, since: since),
            onFrame: (frame) {
              if (!controller.isClosed) controller.add(frame);
            },
            onFailure: () {
              if (!controller.isClosed) unawaited(controller.close());
            },
          )
          .catchError((Object _) {
            if (!controller.isClosed) unawaited(controller.close());
          }),
    );
    controller.onCancel = streamClient.stop;
    return controller.stream;
  }

  @override
  Future<KanbanEventsEnvelope> fetchEvents({
    required String board,
    required int since,
    int limit = 200,
  }) async {
    return _client.kanbanEvents(
      board: board,
      since: since,
      limit: limit,
    );
  }
}
