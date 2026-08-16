import 'dart:async';

import 'package:hermex_flutter/core/api/ws_client.dart';
import 'package:hermex_flutter/core/models/kanban.dart';
import 'package:hermex_flutter/features/kanban/kanban_api.dart';

/// 可配置的 [KanbanApi] fake（测试注入，彻底绕开网络）。
///
/// 默认返回空看板；测试可按需配置 [boards] / [snapshots] / 各方法抛错 /
/// 详情信封，并通过计数器断言调用次数与参数。事件流通过 [emitFrame] 手动
/// 驱动（控制器收到 events 帧后刷新列表）。
class FakeKanbanApi implements KanbanApi {
  FakeKanbanApi({
    List<KanbanBoard>? boards,
    this.currentSlug,
    Map<String, KanbanBoardSnapshot>? snapshots,
    Map<String, KanbanCardDetailEnvelope>? details,
  })  : boards = boards ?? [],
        snapshots = snapshots ?? {},
        details = details ?? {};

  /// `fetchBoards` 返回的看板列表。
  List<KanbanBoard> boards;

  /// `fetchBoards` 响应的 `current`（服务端当前看板）。
  String? currentSlug;

  /// 各看板快照（slug → snapshot）。
  Map<String, KanbanBoardSnapshot> snapshots;

  /// 各卡片详情（cardId → envelope）。
  Map<String, KanbanCardDetailEnvelope> details;

  /// 最近一次 `createCard` 创建的卡片（未配置时按参数生成）。
  KanbanCard? createdCard;

  /// 各方法抛出的异常（非 null 时模拟失败）。
  Object? fetchBoardsError;
  Object? fetchBoardError;
  Object? fetchCardDetailError;
  Object? createCardError;
  Object? setStatusError;
  Object? addCommentError;
  Object? makeBoardActiveError;

  /// 非 null 时 `fetchBoards` 挂起等待该 gate（测试加载态用）。
  Completer<void>? fetchGate;

  /// 调用计数。
  int fetchBoardsCount = 0;
  int fetchBoardCount = 0;
  int fetchCardDetailCount = 0;
  int createCardCount = 0;
  int setStatusCount = 0;
  int addCommentCount = 0;
  int makeBoardActiveCount = 0;
  int streamSubscribeCount = 0;
  int fetchEventsCount = 0;

  /// 事件流订阅参数记录（`board:since`）。
  final List<String> streamSubscriptions = [];

  /// 最近一次 `setStatus` 的参数（`cardId:status`）。
  String? lastSetStatusCall;

  /// 已调用的 `makeBoardActive` slug 记录。
  final List<String> makeBoardActiveCalls = [];

  /// 最近一次 `createCard` 的 idempotency key。
  String? lastIdempotencyKey;

  /// 评论自动追加：`addComment` 成功后把评论插入 [details] 对应信封。
  bool autoAppendComment = true;

  /// 评论自动追加计数（生成 commentId 用）。
  int _commentSeq = 0;

  final StreamController<KanbanStreamFrame> _eventsController =
      StreamController<KanbanStreamFrame>.broadcast();

  /// 手动注入一帧事件（控制器收到 events 帧后刷新列表）。
  void emitFrame(KanbanStreamFrame frame) {
    if (!_eventsController.isClosed) _eventsController.add(frame);
  }

  /// 关闭事件流（模拟连接断开）。
  void closeStream() => _eventsController.close();

  /// 释放资源（测试 teardown 调用）。
  void dispose() => _eventsController.close();

  // -------------------------------------------------------------------------
  // KanbanApi 实现
  // -------------------------------------------------------------------------

  @override
  Future<KanbanConfiguration> fetchConfiguration() async {
    return const KanbanConfiguration();
  }

  @override
  Future<KanbanBoardsResponse> fetchBoards() async {
    fetchBoardsCount++;
    final error = fetchBoardsError;
    if (error != null) throw error;
    final gate = fetchGate;
    if (gate != null) await gate.future;
    return KanbanBoardsResponse(boards: boards, current: currentSlug);
  }

  @override
  Future<KanbanBoardSnapshot> fetchBoard({
    required String board,
    String? tenant,
    String? assignee,
    bool includeArchived = false,
    bool onlyMine = false,
  }) async {
    fetchBoardCount++;
    final error = fetchBoardError;
    if (error != null) throw error;
    return snapshots[board] ?? const KanbanBoardSnapshot();
  }

  @override
  Future<KanbanCardDetailEnvelope> fetchCardDetail({
    required String board,
    required String cardId,
  }) async {
    fetchCardDetailCount++;
    final error = fetchCardDetailError;
    if (error != null) throw error;
    return details[cardId] ??
        KanbanCardDetailEnvelope(
          card: KanbanCard(cardID: cardId, title: '卡片 $cardId'),
        );
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
    createCardCount++;
    lastIdempotencyKey = idempotencyKey;
    final error = createCardError;
    if (error != null) throw error;
    final card = createdCard ??
        KanbanCard(
          cardID: 'new-$createCardCount',
          title: title,
          body: body,
          status: KanbanStatus(status),
          assignee: assignee,
          tenant: tenant,
        );
    return card;
  }

  @override
  Future<KanbanAddCommentResponse> addComment({
    required String board,
    required String cardId,
    required String body,
  }) async {
    addCommentCount++;
    final error = addCommentError;
    if (error != null) throw error;
    if (autoAppendComment) {
      final envelope = details[cardId];
      if (envelope != null) {
        _commentSeq++;
        final comment = KanbanComment(
          commentID: 'c$_commentSeq',
          cardID: cardId,
          author: 'me',
          body: body,
          createdAt: '2026-08-16T10:00:0$_commentSeq',
        );
        details[cardId] = KanbanCardDetailEnvelope(
          card: envelope.card,
          comments: [...(envelope.comments ?? const []), comment],
          events: envelope.events,
          links: envelope.links,
          runs: envelope.runs,
          readOnly: envelope.readOnly,
        );
      }
    }
    return const KanbanAddCommentResponse(ok: true, commentID: 'c-new');
  }

  @override
  Future<KanbanCard> setStatus({
    required String board,
    required String cardId,
    required String status,
  }) async {
    setStatusCount++;
    lastSetStatusCall = '$cardId:$status';
    final error = setStatusError;
    if (error != null) throw error;
    final envelope = details[cardId];
    final currentCard = envelope?.card ??
        _findCardInSnapshots(cardId) ??
        KanbanCard(cardID: cardId);
    final updated = currentCard.replacingStatus(status);
    // 同步详情信封中的卡片，保证后续 fetchCardDetail 返回新状态。
    if (details.containsKey(cardId)) {
      details[cardId] = KanbanCardDetailEnvelope(
        card: updated,
        comments: envelope?.comments,
        events: envelope?.events,
        links: envelope?.links,
        runs: envelope?.runs,
        readOnly: envelope?.readOnly,
      );
    }
    return updated;
  }

  @override
  Future<void> makeBoardActive(String slug) async {
    makeBoardActiveCount++;
    makeBoardActiveCalls.add(slug);
    final error = makeBoardActiveError;
    if (error != null) throw error;
    currentSlug = slug;
  }

  @override
  Stream<KanbanStreamFrame> streamEvents({
    required String board,
    required int since,
  }) {
    streamSubscribeCount++;
    streamSubscriptions.add('$board:$since');
    return _eventsController.stream;
  }

  @override
  Future<KanbanEventsEnvelope> fetchEvents({
    required String board,
    required int since,
    int limit = 200,
  }) async {
    fetchEventsCount++;
    return const KanbanEventsEnvelope();
  }

  // -------------------------------------------------------------------------
  // 辅助
  // -------------------------------------------------------------------------

  KanbanCard? _findCardInSnapshots(String cardId) {
    for (final snapshot in snapshots.values) {
      for (final column in snapshot.columns ?? const <KanbanColumn>[]) {
        for (final card in column.cards ?? const <KanbanCard>[]) {
          if (card.cardID == cardId) return card;
        }
      }
    }
    return null;
  }
}
