import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_exception.dart';
import '../../core/api/ws_client.dart';
import '../../core/connections/connection_providers.dart';
import '../../core/models/kanban.dart';
import 'kanban_api.dart';

/// 构建 [KanbanApi] 的工厂（测试可 override 注入 fake）。
typedef KanbanApiFactory = KanbanApi Function(ApiClient client);

final kanbanApiFactoryProvider = Provider<KanbanApiFactory>(
  (ref) => KanbanApiClient.new,
);

/// 看板页状态（AsyncNotifier 的 AsyncData 载荷）。
///
/// [boards] 为全部看板；[currentBoardSlug] 为当前选中看板；[snapshot] 为
/// 当前看板快照（按状态分列卡片）。行操作失败不改变列表，只设置
/// [actionError] 供 UI 弹窗提示。
class KanbanState {
  const KanbanState({
    this.boards = const [],
    this.currentBoardSlug,
    this.snapshot,
    this.actionError,
  });

  /// 全部看板（服务端顺序，含 isCurrent 标记）。
  final List<KanbanBoard> boards;

  /// 当前选中看板的 slug（null = 尚未选择）。
  final String? currentBoardSlug;

  /// 当前看板快照（按状态分列）。
  final KanbanBoardSnapshot? snapshot;

  /// 最近一次行操作错误（UI 弹窗展示后调用 [KanbanController.clearActionError] 清除）。
  final String? actionError;

  /// 当前看板对象（按 slug 从 [boards] 中查找）。
  KanbanBoard? get currentBoard {
    final slug = currentBoardSlug;
    if (slug == null) return null;
    for (final board in boards) {
      if (board.slug == slug) return board;
    }
    return null;
  }

  /// 当前看板按状态分列（列顺序即服务端顺序）。
  List<KanbanColumn> get columns => snapshot?.columns ?? const <KanbanColumn>[];

  /// 当前看板全部卡片（跨列展开）。
  List<KanbanCard> get cards {
    final result = <KanbanCard>[];
    for (final column in columns) {
      result.addAll(column.cards ?? const <KanbanCard>[]);
    }
    return result;
  }

  /// 是否只读（服务端快照声明 read_only 时禁止写操作）。
  bool get readOnly => snapshot?.readOnly == true;

  KanbanState copyWith({
    List<KanbanBoard>? boards,
    String? Function()? currentBoardSlug,
    KanbanBoardSnapshot? Function()? snapshot,
    String? Function()? actionError,
  }) {
    return KanbanState(
      boards: boards ?? this.boards,
      currentBoardSlug:
          currentBoardSlug != null ? currentBoardSlug() : this.currentBoardSlug,
      snapshot: snapshot != null ? snapshot() : this.snapshot,
      actionError: actionError != null ? actionError() : this.actionError,
    );
  }

  @override
  String toString() =>
      'KanbanState(boards: ${boards.length}, current: $currentBoardSlug, '
      'columns: ${columns.length}, actionError: $actionError)';
}

/// 看板控制器：加载看板列表 / 看板快照、订阅事件流刷新、切换看板、创建
/// 卡片、改卡片状态、加评论。
///
/// AsyncValue 语义：`AsyncData` 携带 [KanbanState]；初始加载与下拉刷新失败
/// → `AsyncError`（UI 展示错误态 + 重试）；行操作失败不改变列表，只设置
/// [KanbanState.actionError] 供弹窗提示（创建卡片/切换看板）或返回错误文案
/// 由详情页呈现（改状态/评论）。
final kanbanControllerProvider =
    AsyncNotifierProvider<KanbanController, KanbanState>(
  KanbanController.new,
);

class KanbanController extends AsyncNotifier<KanbanState> {
  /// 创建卡片默认 workspace kind（对齐 Hermex KanbanCardEditorState）。
  static const String defaultWorkspaceKind = 'scratch';

  /// 创建卡片允许的状态（对齐 Hermex KanbanCardEditorState.createStatuses）。
  static const List<String> createStatuses = ['triage', 'todo', 'ready'];

  KanbanApi? _api;

  /// 事件流订阅（基础版：加载时订阅，收到 events 帧刷新列表）。
  StreamSubscription<KanbanStreamFrame>? _eventsSub;

  /// 事件游标（续订/刷新用）。
  int _cursor = 0;

  /// 用户显式选择的看板（跨 build 重跑保留；null = 跟随服务端 current）。
  String? _userSelectedBoardSlug;

  /// 当前 API 实例（build 成功前不可用；仅在被 watch 的依赖变化导致
  /// build 重跑时由 [build] 重新赋值）。
  KanbanApi get _currentApi => _api!;

  @override
  Future<KanbanState> build() async {
    // watch：切换服务器（apiClientProvider 重建）或工厂被替换时自动重载。
    final api = ref.watch(kanbanApiFactoryProvider)(
      ref.watch(apiClientProvider),
    );
    _api = api;
    // build 重跑时先释放旧订阅，避免重复订阅事件流。
    _teardownEvents();
    ref.onDispose(_teardownEvents);

    final response = await api.fetchBoards();
    final boards = response.boards ?? const <KanbanBoard>[];
    final slug =
        _userSelectedBoardSlug ?? response.current ?? _firstBoardSlug(boards);
    KanbanBoardSnapshot? snapshot;
    if (slug != null && slug.isNotEmpty) {
      snapshot = await api.fetchBoard(board: slug);
    }
    _cursor = snapshot?.latestEventID ?? 0;
    _attachEvents(api, slug);
    return KanbanState(
      boards: boards,
      currentBoardSlug: slug,
      snapshot: snapshot,
    );
  }

  /// 下拉刷新 / 错误态重试：重载看板列表 + 当前看板快照，重订事件流。
  Future<void> refresh() async {
    try {
      final api = _currentApi;
      final current = state.valueOrNull;
      final slug =
          _userSelectedBoardSlug ?? current?.currentBoardSlug;
      final response = await api.fetchBoards();
      final boards = response.boards ?? const <KanbanBoard>[];
      KanbanBoardSnapshot? snapshot;
      final effectiveSlug = slug ?? _firstBoardSlug(boards);
      if (effectiveSlug != null) {
        snapshot = await api.fetchBoard(board: effectiveSlug);
      }
      _cursor = snapshot?.latestEventID ?? 0;
      _attachEvents(api, effectiveSlug);
      state = AsyncData(
        KanbanState(
          boards: boards,
          currentBoardSlug: effectiveSlug,
          snapshot: snapshot,
        ),
      );
    } on Exception catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
    }
  }

  /// 切换当前看板：服务器记录激活看板 → 重载列表 + 快照 → 重订事件流。
  ///
  /// 切换失败（网络/服务器）→ `AsyncError`（UI 展示错误态 + 重试）；
  /// `makeBoardActive` 单独失败不阻断浏览，仅设置 actionError 提示。
  Future<void> selectBoard(String slug) async {
    final current = state.valueOrNull;
    if (current == null || slug == current.currentBoardSlug) return;
    _userSelectedBoardSlug = slug;
    state = AsyncData(
      current.copyWith(currentBoardSlug: () => slug, snapshot: () => null),
    );
    try {
      final api = _currentApi;
      try {
        await api.makeBoardActive(slug);
      } on ApiException catch (error) {
        final now = state.valueOrNull;
        if (now != null) {
          state = AsyncData(now.copyWith(actionError: () => error.message));
        }
      }
      final boardsResponse = await api.fetchBoards();
      final snapshot = await api.fetchBoard(board: slug);
      _cursor = snapshot.latestEventID ?? 0;
      _attachEvents(api, slug);
      final now = state.valueOrNull;
      if (now == null || now.currentBoardSlug != slug) return; // 已再次切换
      state = AsyncData(
        now.copyWith(
          boards: boardsResponse.boards ?? now.boards,
          snapshot: () => snapshot,
        ),
      );
    } on ApiException catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
    }
  }

  /// 创建卡片；成功返回 true（UI 关闭表单页）。失败 → actionError。
  Future<bool> createCard({
    required String title,
    String? body,
    required String status,
    String? assignee,
  }) async {
    final current = state.valueOrNull;
    final slug = current?.currentBoardSlug;
    if (current == null || slug == null) {
      await _setActionError('尚未选择看板');
      return false;
    }
    if (title.trim().isEmpty) {
      await _setActionError('卡片标题不能为空');
      return false;
    }
    try {
      final card = await _currentApi.createCard(
        board: slug,
        title: title.trim(),
        body: body,
        status: status,
        assignee: _nonEmpty(assignee),
        workspaceKind: defaultWorkspaceKind,
        idempotencyKey: _newIdempotencyKey(),
      );
      if (card.cardID != null && card.cardID!.isNotEmpty) {
        await _insertCard(card);
      } else {
        // 服务器未回传卡片：重拉快照保持列表新鲜。
        await _refreshSnapshot();
      }
      return true;
    } on ApiException catch (error) {
      await _setActionError(error.message);
      return false;
    }
  }

  /// 改卡片状态（状态机：running 守卫 → 请求 → 本地换列）。
  ///
  /// - `running` 本地拦截，不发请求，返回守卫错误文案；
  /// - 请求失败返回错误文案，本地状态不变；
  /// - 成功：本地把卡片从原列移到新状态列，返回 null。
  Future<String?> setStatus({
    required String cardId,
    required String status,
  }) async {
    final current = state.valueOrNull;
    final slug = current?.currentBoardSlug;
    if (current == null || slug == null) return '尚未选择看板';
    final trimmed = status.trim();
    if (trimmed.toLowerCase() == 'running') {
      return 'running 状态只能由 dispatcher 设置';
    }
    try {
      final card = await _currentApi.setStatus(
        board: slug,
        cardId: cardId,
        status: trimmed,
      );
      await _moveCard(cardId, card);
      return null;
    } on ApiException catch (error) {
      return error.message;
    }
  }

  /// 添加评论；成功返回 null，失败返回错误文案（由详情控制器呈现）。
  Future<String?> addComment({
    required String cardId,
    required String body,
  }) async {
    final current = state.valueOrNull;
    final slug = current?.currentBoardSlug;
    if (current == null || slug == null) return '尚未选择看板';
    try {
      final response = await _currentApi.addComment(
        board: slug,
        cardId: cardId,
        body: body,
      );
      if (response.ok == false) return '添加评论失败，服务器未确认';
      await _bumpCommentCount(cardId);
      return null;
    } on ApiException catch (error) {
      return error.message;
    }
  }

  /// 清除行操作错误标记（UI 展示完弹窗后调用）。
  Future<void> clearActionError() async {
    final current = state.valueOrNull;
    if (current == null || current.actionError == null) return;
    state = AsyncData(current.copyWith(actionError: () => null));
  }

  // -------------------------------------------------------------------------
  // 事件流
  // -------------------------------------------------------------------------

  void _attachEvents(KanbanApi api, String? slug) {
    _teardownEvents();
    if (slug == null || slug.isEmpty) return;
    final stream = api.streamEvents(board: slug, since: _cursor);
    _eventsSub = stream.listen(
      _onStreamFrame,
      onError: (_) => _onStreamClosed(),
      onDone: _onStreamClosed,
    );
  }

  void _teardownEvents() {
    final sub = _eventsSub;
    _eventsSub = null;
    if (sub != null) unawaited(sub.cancel());
  }

  void _onStreamFrame(KanbanStreamFrame frame) {
    // 基础版：只认 events 帧且含事件时才刷新列表（hello/ignored/malformed 忽略）。
    if (frame is! KanbanEventsFrame || frame.events.isEmpty) return;
    if (frame.cursor > _cursor) _cursor = frame.cursor;
    unawaited(_refreshSnapshot());
  }

  void _onStreamClosed() {
    // 基础版：流断开不做自动重连，等用户手动刷新。
  }

  Future<void> _refreshSnapshot() async {
    final current = state.valueOrNull;
    final slug = current?.currentBoardSlug;
    if (current == null || slug == null) return;
    try {
      final snapshot = await _currentApi.fetchBoard(board: slug);
      final now = state.valueOrNull;
      if (now == null || now.currentBoardSlug != slug) return; // 已切换看板
      state = AsyncData(now.copyWith(snapshot: () => snapshot));
    } on ApiException {
      // 事件刷新失败保留现有数据（不打断浏览）。
    }
  }

  // -------------------------------------------------------------------------
  // 本地状态更新原语
  // -------------------------------------------------------------------------

  Future<void> _insertCard(KanbanCard card) async {
    final current = state.valueOrNull;
    final snapshot = current?.snapshot;
    if (current == null || snapshot == null) return;
    final statusName = card.status?.rawValue ?? '';
    final columns = snapshot.columns ?? const <KanbanColumn>[];
    var inserted = false;
    final nextColumns = <KanbanColumn>[];
    for (final column in columns) {
      if (!inserted && column.name == statusName) {
        nextColumns.add(
          KanbanColumn(
            name: column.name,
            cards: [card, ...(column.cards ?? const <KanbanCard>[])],
          ),
        );
        inserted = true;
      } else {
        nextColumns.add(column);
      }
    }
    if (!inserted) {
      nextColumns.add(KanbanColumn(name: statusName, cards: [card]));
    }
    state = AsyncData(
      current.copyWith(snapshot: () => _snapshotWithColumns(snapshot, nextColumns)),
    );
  }

  Future<void> _moveCard(String cardId, KanbanCard updated) async {
    final current = state.valueOrNull;
    final snapshot = current?.snapshot;
    if (current == null || snapshot == null) return;
    final columns = snapshot.columns ?? const <KanbanColumn>[];
    final newStatus = updated.status?.rawValue ?? '';
    // 1. 从原列移除。
    final without = <KanbanColumn>[
      for (final column in columns)
        KanbanColumn(
          name: column.name,
          cards: (column.cards ?? const <KanbanCard>[])
              .where((card) => card.cardID != cardId)
              .toList(),
        ),
    ];
    // 2. 插入到新状态列（列存在才插入；不存在则卡片从视图消失）。
    final nextColumns = <KanbanColumn>[
      for (final column in without)
        if (column.name == newStatus)
          KanbanColumn(
            name: column.name,
            cards: [...(column.cards ?? const <KanbanCard>[]), updated],
          )
        else
          column,
    ];
    state = AsyncData(
      current.copyWith(snapshot: () => _snapshotWithColumns(snapshot, nextColumns)),
    );
  }

  Future<void> _bumpCommentCount(String cardId) async {
    final current = state.valueOrNull;
    final snapshot = current?.snapshot;
    if (current == null || snapshot == null) return;
    final columns = snapshot.columns ?? const <KanbanColumn>[];
    var changed = false;
    final nextColumns = <KanbanColumn>[];
    for (final column in columns) {
      final cards = column.cards ?? const <KanbanCard>[];
      var columnChanged = false;
      final nextCards = <KanbanCard>[];
      for (final card in cards) {
        if (card.cardID == cardId) {
          nextCards.add(
            KanbanCard(
              cardID: card.cardID,
              title: card.title,
              status: card.status,
              assignee: card.assignee,
              body: card.body,
              tenant: card.tenant,
              priority: card.priority,
              commentCount: (card.commentCount ?? 0) + 1,
              linkCounts: card.linkCounts,
              ageSeconds: card.ageSeconds,
              createdAt: card.createdAt,
              updatedAt: card.updatedAt,
              workspaceKind: card.workspaceKind,
              workspacePath: card.workspacePath,
              skills: card.skills,
              maxRuntimeSeconds: card.maxRuntimeSeconds,
              currentRunID: card.currentRunID,
              claimLock: card.claimLock,
              claimExpires: card.claimExpires,
              workerID: card.workerID,
            ),
          );
          columnChanged = true;
          changed = true;
        } else {
          nextCards.add(card);
        }
      }
      nextColumns.add(
        KanbanColumn(
          name: column.name,
          cards: columnChanged ? nextCards : cards,
        ),
      );
    }
    if (!changed) return;
    state = AsyncData(
      current.copyWith(snapshot: () => _snapshotWithColumns(snapshot, nextColumns)),
    );
  }

  KanbanBoardSnapshot _snapshotWithColumns(
    KanbanBoardSnapshot snapshot,
    List<KanbanColumn> columns,
  ) {
    return KanbanBoardSnapshot(
      columns: columns,
      tenants: snapshot.tenants,
      assignees: snapshot.assignees,
      filters: snapshot.filters,
      changed: snapshot.changed,
      latestEventID: snapshot.latestEventID,
      readOnly: snapshot.readOnly,
    );
  }

  Future<void> _setActionError(String message) async {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData(current.copyWith(actionError: () => message));
  }

  static String? _nonEmpty(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  static String _newIdempotencyKey() =>
      'hermex-${DateTime.now().microsecondsSinceEpoch}';

  static String? _firstBoardSlug(List<KanbanBoard> boards) {
    for (final board in boards) {
      final slug = board.slug;
      if (slug != null && slug.isNotEmpty) return slug;
    }
    return null;
  }
}

/// 卡片详情状态（AsyncNotifier 的 AsyncData 载荷）。
class KanbanDetailState {
  const KanbanDetailState({
    this.envelope,
    this.isSubmittingComment = false,
    this.actionError,
  });

  /// 卡片详情信封（卡片 + 评论等）。
  final KanbanCardDetailEnvelope? envelope;

  /// 评论提交进行中（UI 禁用提交按钮并显示指示器）。
  final bool isSubmittingComment;

  /// 最近一次详情操作错误（UI 弹窗展示后调用
  /// [KanbanDetailController.clearActionError] 清除）。
  final String? actionError;

  KanbanCard? get card => envelope?.card;

  List<KanbanComment> get comments =>
      envelope?.comments ?? const <KanbanComment>[];

  KanbanDetailState copyWith({
    KanbanCardDetailEnvelope? Function()? envelope,
    bool? isSubmittingComment,
    String? Function()? actionError,
  }) {
    return KanbanDetailState(
      envelope: envelope != null ? envelope() : this.envelope,
      isSubmittingComment: isSubmittingComment ?? this.isSubmittingComment,
      actionError: actionError != null ? actionError() : this.actionError,
    );
  }

  @override
  String toString() => 'KanbanDetailState(card: ${card?.cardID})';
}

/// 卡片详情控制器（按 cardId 家族化）：加载详情 / 刷新 / 提交评论 / 清错误。
///
/// 状态变更由看板控制器执行（[KanbanController.setStatus]），成功后本控制器
/// 的 [refresh] 重新拉取详情保持一致。
final kanbanDetailControllerProvider =
    AsyncNotifierProvider.family<KanbanDetailController, KanbanDetailState,
        String>(
  KanbanDetailController.new,
);

class KanbanDetailController extends FamilyAsyncNotifier<KanbanDetailState, String> {
  String get _cardId => arg;

  KanbanApi get _api =>
      ref.read(kanbanApiFactoryProvider)(ref.read(apiClientProvider));

  String? get _boardSlug =>
      ref.read(kanbanControllerProvider).valueOrNull?.currentBoardSlug;

  @override
  Future<KanbanDetailState> build(String cardId) async {
    // watch：切换服务器（apiClientProvider 重建）或工厂被替换时自动重载。
    final api = ref.watch(kanbanApiFactoryProvider)(
      ref.watch(apiClientProvider),
    );
    final slug = _boardSlug;
    if (slug == null || slug.isEmpty) {
      throw StateError('尚未选择看板');
    }
    final envelope = await api.fetchCardDetail(board: slug, cardId: cardId);
    return KanbanDetailState(envelope: envelope);
  }

  /// 重新拉取详情（改状态 / 评论成功后保持一致）。
  Future<void> refresh() async {
    try {
      final api = _api;
      final slug = _boardSlug;
      if (slug == null || slug.isEmpty) return;
      final envelope = await api.fetchCardDetail(
        board: slug,
        cardId: _cardId,
      );
      state = AsyncData(KanbanDetailState(envelope: envelope));
    } on Exception catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
    }
  }

  /// 提交评论；成功返回 true（详情自动刷新含新评论）。失败 → actionError。
  Future<bool> submitComment(String body) async {
    final trimmed = body.trim();
    if (trimmed.isEmpty) return false;
    final current = state.valueOrNull;
    if (current == null) return false;
    state = AsyncData(current.copyWith(isSubmittingComment: true));
    try {
      final error = await ref
          .read(kanbanControllerProvider.notifier)
          .addComment(cardId: _cardId, body: trimmed);
      if (error != null) {
        await _setActionError(error);
        return false;
      }
      await refresh();
      return true;
    } finally {
      final now = state.valueOrNull;
      if (now != null) {
        state = AsyncData(now.copyWith(isSubmittingComment: false));
      }
    }
  }

  /// 清除详情操作错误标记（UI 展示完弹窗后调用）。
  Future<void> clearActionError() async {
    final current = state.valueOrNull;
    if (current == null || current.actionError == null) return;
    state = AsyncData(current.copyWith(actionError: () => null));
  }

  Future<void> _setActionError(String message) async {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData(current.copyWith(actionError: () => message));
  }
}

/// 派生：当前看板对象（看板切换器高亮选中项用）。
final kanbanCurrentBoardProvider = Provider<KanbanBoard?>((ref) {
  return ref.watch(kanbanControllerProvider).valueOrNull?.currentBoard;
});

/// 派生：当前看板按状态分列（看板视图渲染用）。
final kanbanColumnsProvider = Provider<List<KanbanColumn>>((ref) {
  return ref.watch(kanbanControllerProvider).valueOrNull?.columns ??
      const <KanbanColumn>[];
});
