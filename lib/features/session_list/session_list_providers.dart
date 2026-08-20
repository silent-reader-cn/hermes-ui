import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_client_sessions.dart';
import '../../core/api/api_exception.dart';
import '../../core/api/custom_header.dart';
import '../../core/cache/cache_providers.dart';
import '../../core/connections/connection_providers.dart';
import '../../core/models/session.dart';
import '../onboarding/onboarding_providers.dart';

/// 会话列表所需的最小服务器 API 面（sessions 域 18 个端点中的 9 个）。
///
/// 生产实现 [SessionListApiClient] 包 [ApiClient]（模型在客户端解码）；
/// 测试注入纯 Dart fake，彻底绕开网络/事件循环（对齐 onboarding 的
/// `OnboardingServerApi` 模式）。
abstract interface class SessionListApi {
  /// GET /api/sessions → 全部会话（服务端一次全量返回，无分页参数）。
  Future<SessionsResponse> fetchSessions({
    bool includeArchived = false,
    int? archivedLimit,
  });

  /// GET /api/sessions/search?q=…（标题 + 内容搜索）。
  Future<SessionSearchResponse> searchSessions({required String query});

  /// POST /api/session/new → 新会话摘要。
  Future<SessionSummary> createSession();

  /// POST /api/session/pin {session_id, pinned}。
  Future<SessionMutationResponse> pinSession({
    required String sessionId,
    required bool pinned,
  });

  /// POST /api/session/archive {session_id, archived}。
  Future<SessionMutationResponse> archiveSession({
    required String sessionId,
    required bool archived,
  });

  /// POST /api/session/delete {session_id}。
  Future<SessionMutationResponse> deleteSession(String sessionId);

  /// POST /api/session/branch {session_id} → 新分支会话。
  Future<SessionBranchResponse> branchSession(String sessionId);

  /// POST /api/session/move {session_id, project_id}；project_id 为 null = 移出项目。
  Future<SessionMutationResponse> moveSession({
    required String sessionId,
    String? projectId,
  });
}

/// [SessionListApi] 的生产实现：包 [ApiClient]，把 `Object?` JSON 解码为模型。
class SessionListApiClient implements SessionListApi {
  SessionListApiClient(this._client);

  final ApiClient _client;

  @override
  Future<SessionsResponse> fetchSessions({
    bool includeArchived = false,
    int? archivedLimit,
  }) async {
    final json = await _client.sessions(
      includeArchived: includeArchived,
      archivedLimit: archivedLimit,
    );
    return SessionsResponse.fromJson(_asMap(json));
  }

  @override
  Future<SessionSearchResponse> searchSessions({required String query}) async {
    final json = await _client.searchSessions(query: query);
    return SessionSearchResponse.fromJson(_asMap(json));
  }

  @override
  Future<SessionSummary> createSession() async {
    final raw = await _client.createSession();
    final map = _asMap(raw);
    // 先按平坦 SessionDetail 试解（服务端常见 {session_id/id} 形态），
    // 失败再走兼容多形态的 SessionResponse。
    try {
      final flat = SessionDetail.fromJson(map);
      if (flat.sessionId != null && flat.sessionId!.trim().isNotEmpty) {
        return SessionSummary.fromDetail(flat);
      }
    } catch (_) {}
    try {
      final data = map['data'];
      if (data is Map) {
        final m = Map<String, Object?>.from(data);
        final inner = m['session'];
        if (inner is Map) {
          final d = SessionDetail.fromJson(Map<String, Object?>.from(inner));
          if (d.sessionId != null && d.sessionId!.trim().isNotEmpty) {
            return SessionSummary.fromDetail(d);
          }
        }
        try {
          final d2 = SessionDetail.fromJson(m);
          if (d2.sessionId != null && d2.sessionId!.trim().isNotEmpty) {
            return SessionSummary.fromDetail(d2);
          }
        } catch (_) {}
      }
    } catch (_) {}
    final response = SessionResponse.fromJson(map);
    final detail = response.session;
    return detail == null
        ? const SessionSummary()
        : SessionSummary.fromDetail(detail);
  }

  @override
  Future<SessionMutationResponse> pinSession({
    required String sessionId,
    required bool pinned,
  }) async {
    final json = await _client.pinSession(sessionId: sessionId, pinned: pinned);
    return SessionMutationResponse.fromJson(_asMap(json));
  }

  @override
  Future<SessionMutationResponse> archiveSession({
    required String sessionId,
    required bool archived,
  }) async {
    final json = await _client.archiveSession(
      sessionId: sessionId,
      archived: archived,
    );
    return SessionMutationResponse.fromJson(_asMap(json));
  }

  @override
  Future<SessionMutationResponse> deleteSession(String sessionId) async {
    final json = await _client.deleteSession(sessionId);
    return SessionMutationResponse.fromJson(_asMap(json));
  }

  @override
  Future<SessionBranchResponse> branchSession(String sessionId) async {
    final json = await _client.branchSession(sessionId: sessionId);
    return SessionBranchResponse.fromJson(_asMap(json));
  }

  @override
  Future<SessionMutationResponse> moveSession({
    required String sessionId,
    String? projectId,
  }) async {
    final json = await _client.moveSession(
      sessionId: sessionId,
      projectId: projectId,
    );
    return SessionMutationResponse.fromJson(_asMap(json));
  }

  static Map<String, Object?> _asMap(Object? json) =>
      json is Map<String, Object?> ? json : const <String, Object?>{};
}

/// 构建 [SessionListApi] 的工厂（测试可 override 注入 fake）。
typedef SessionListApiFactory = SessionListApi Function(ApiClient client);

final sessionListApiFactoryProvider = Provider<SessionListApiFactory>(
  (ref) => SessionListApiClient.new,
);

/// 会话列表分区（对齐 Hermex `SessionListSection.Kind`：pinned/today/yesterday/earlier）。
class SessionListSection {
  const SessionListSection({required this.title, required this.sessions});

  /// 分区标题（置顶 / 今天 / 昨天 / 更早；搜索模式为「搜索结果」）。
  final String title;

  /// 分区内的会话（已按时间倒序）。
  final List<SessionSummary> sessions;
}

/// 会话列表筛选模式：全部 / 已归档 / 来源标签 / 项目。
enum SessionListFilterMode { all, archived, source, project }

/// 会话列表状态（AsyncNotifier 的 AsyncData 载荷）。
///
/// 分页说明：服务端 `GET /api/sessions` 一次全量返回（无 offset/limit 参数，
/// Hermex 原生亦为一次拉取），因此「分页」在客户端做分块渲染——[visibleCount]
/// 是 [displaySessions] 前 N 条的可见窗口，[loadMore] 展开窗口，配合无限滚动。
class SessionListState {
  const SessionListState({
    this.sessions = const [],
    this.visibleCount = 0,
    this.searchQuery,
    this.searchResults,
    this.isSearching = false,
    this.actionError,
    this.filterMode = SessionListFilterMode.all,
    this.filterValue,
    this.archivedSessions = const [],
    this.archivedCount,
    this.selectedSessionIds = const {},
    this.isSelectionMode = false,
  });

  /// 普通模式全部已加载会话（服务端顺序：新的在前）。
  final List<SessionSummary> sessions;

  /// 分页窗口：`displaySessions` 前 [visibleCount] 条可见。
  final int visibleCount;

  /// 非空 = 搜索模式。
  final String? searchQuery;

  /// 远程搜索命中结果。
  final List<SessionSummary>? searchResults;

  /// 远程搜索请求进行中。
  final bool isSearching;

  /// 最近一次行操作/搜索错误（UI 弹窗展示后调用 [SessionListController.clearActionError] 清除）。
  final String? actionError;

  /// 当前筛选模式（默认全部）。
  final SessionListFilterMode filterMode;

  /// 筛选模式的对应值：来源筛选 = sourceLabel；项目筛选 = projectId；其余为 null。
  final String? filterValue;

  /// 归档会话（`fetchSessions(includeArchived: true)` 的结果，仅归档模式展示）。
  final List<SessionSummary> archivedSessions;

  /// 服务端归档总数（普通模式响应不返回 archived_count 时为 null，UI 不显示计数）。
  final int? archivedCount;

  /// 多选模式下已勾选的会话 ID 集合。
  final Set<String> selectedSessionIds;

  /// 是否处于多选模式（长按行进入）。
  final bool isSelectionMode;

  /// 客户端分块页大小。
  static const int pageSize = 50;

  /// 来源标签的 distinct 列表（从普通模式列表收集，空标签剔除）。
  List<String> get sourceLabels {
    final seen = <String>{};
    final labels = <String>[];
    for (final session in sessions) {
      final label = session.sourceLabel?.trim();
      if (label == null || label.isEmpty || seen.contains(label)) continue;
      seen.add(label);
      labels.add(label);
    }
    return labels;
  }

  /// 当前展示的会话（搜索模式 = 搜索命中；否则按筛选模式取对应子集）。
  List<SessionSummary> get displaySessions {
    final query = searchQuery?.trim();
    if (query != null && query.isNotEmpty) {
      return searchResults ?? const [];
    }
    switch (filterMode) {
      case SessionListFilterMode.archived:
        return archivedSessions;
      case SessionListFilterMode.source:
        final label = filterValue;
        if (label == null || label.isEmpty) return sessions;
        return sessions.where((s) => s.sourceLabel?.trim() == label).toList();
      case SessionListFilterMode.project:
        final projectId = filterValue;
        if (projectId == null || projectId.isEmpty) return sessions;
        return sessions.where((s) => s.projectId == projectId).toList();
      case SessionListFilterMode.all:
        return sessions;
    }
  }

  /// 是否还有更多可分页内容。
  bool get hasMore => visibleCount < displaySessions.length;

  SessionListState copyWith({
    List<SessionSummary>? sessions,
    int? visibleCount,
    String? Function()? searchQuery,
    List<SessionSummary>? Function()? searchResults,
    bool? isSearching,
    String? Function()? actionError,
    SessionListFilterMode? filterMode,
    String? Function()? filterValue,
    List<SessionSummary>? archivedSessions,
    int? Function()? archivedCount,
    Set<String>? selectedSessionIds,
    bool? isSelectionMode,
  }) {
    return SessionListState(
      sessions: sessions ?? this.sessions,
      visibleCount: visibleCount ?? this.visibleCount,
      searchQuery: searchQuery != null ? searchQuery() : this.searchQuery,
      searchResults: searchResults != null
          ? searchResults()
          : this.searchResults,
      isSearching: isSearching ?? this.isSearching,
      actionError: actionError != null ? actionError() : this.actionError,
      filterMode: filterMode ?? this.filterMode,
      filterValue: filterValue != null ? filterValue() : this.filterValue,
      archivedSessions: archivedSessions ?? this.archivedSessions,
      archivedCount: archivedCount != null
          ? archivedCount()
          : this.archivedCount,
      selectedSessionIds: selectedSessionIds ?? this.selectedSessionIds,
      isSelectionMode: isSelectionMode ?? this.isSelectionMode,
    );
  }

  @override
  String toString() =>
      'SessionListState(sessions: ${sessions.length}, visibleCount: $visibleCount, '
      'searchQuery: $searchQuery, searchResults: ${searchResults?.length})';
}

/// 批量操作结果统计。
class BatchMutationResult {
  const BatchMutationResult({this.succeeded = 0, this.failed = 0});

  /// 成功操作数。
  final int succeeded;

  /// 失败操作数。
  final int failed;

  @override
  String toString() =>
      'BatchMutationResult(succeeded: $succeeded, failed: $failed)';
}

/// 会话列表控制器：加载 / 刷新 / 搜索 / 筛选 / 分页 / 行操作 / 批量操作。
///
/// AsyncValue 语义：`AsyncData` 携带 [SessionListState]；初始加载与下拉刷新
/// 失败 → `AsyncError`（UI 展示错误态 + 重试）；行操作失败不改变列表，
/// 只设置 [SessionListState.actionError] 供弹窗提示。
final sessionListControllerProvider =
    AsyncNotifierProvider<SessionListController, SessionListState>(
      SessionListController.new,
    );

class SessionListController extends AsyncNotifier<SessionListState> {
  /// 页大小（客户端分块）。
  static const int pageSize = SessionListState.pageSize;

  /// 自动重登进行中标记（防并发重复登录）。
  bool _reauthInFlight = false;

  SessionListApi get _api =>
      ref.read(sessionListApiFactoryProvider)(ref.read(apiClientProvider));

  @override
  Future<SessionListState> build() async {
    // watch：切换服务器（apiClientProvider 重建）或工厂被替换时自动重载。
    final api = ref.watch(sessionListApiFactoryProvider)(
      ref.watch(apiClientProvider),
    );
    return _loadFirstPage(api);
  }

  /// 加载第一页；401 时自动用保存的密码重登一次再重试
  /// （防递归：`[allowAutoReauth]` 只放行一轮）。
  Future<SessionListState> _loadFirstPage(
    SessionListApi api, {
    bool allowAutoReauth = true,
  }) async {
    try {
      final response = await api.fetchSessions();
      final sessions = response.sessions ?? const <SessionSummary>[];
      try {
        await ref.read(cacheServiceProvider).writeSessions(sessions);
      } on Exception {
        // 缓存不可用（例如测试环境没有 path_provider）不阻塞在线列表。
      }
      return SessionListState(
        sessions: sessions,
        visibleCount: min(pageSize, sessions.length),
        // 普通模式响应不返回 archived_count 时为 null（UI 不显示计数）。
        archivedCount: response.archivedCount,
      );
    } on UnauthorizedException {
      // 会话过期/未登录：有保存密码时自动重登一次，成功后重试。
      // 重登失败或重试仍 401 → 直接抛错（不递归），UI 展示错误 + 重试。
      if (allowAutoReauth && await _tryAutoReauth()) {
        return _loadFirstPage(api, allowAutoReauth: false);
      }
      rethrow;
    } on ApiException catch (error, stackTrace) {
      if (ApiException.shouldUseCache(error)) {
        List<SessionSummary> cached = const [];
        try {
          cached = await ref.read(cacheServiceProvider).readSessions();
        } on Exception {
          // 缓存不可用时继续抛出原网络错误。
        }
        if (cached.isNotEmpty) {
          return SessionListState(
            sessions: cached,
            visibleCount: min(pageSize, cached.length),
            actionError: '离线缓存：当前显示最近缓存的会话',
          );
        }
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  /// 用当前激活连接的已保存密码重新登录（种新 cookie）。
  ///
  /// 无密码 / 登录失败 / 已有重登在进行 → 返回 false（不做自动重登）。
  Future<bool> _tryAutoReauth() async {
    if (_reauthInFlight) return false;
    final connection = ref.read(activeConnectionProvider);
    if (connection == null) return false;
    final password = connection.password;
    if (password == null || password.isEmpty) return false;
    _reauthInFlight = true;
    try {
      final factory = ref.read(onboardingApiFactoryProvider);
      final api = factory(connection.baseUrl, [
        for (final entry in connection.customHeaders.entries)
          CustomHeader(name: entry.key, value: entry.value),
      ]);
      await api.login(password);
      return true;
    } on Exception {
      return false;
    } finally {
      _reauthInFlight = false;
    }
  }

  /// 下拉刷新 / 错误态重试：重新加载第一页并重置分页窗口。
  Future<void> refresh() async {
    try {
      final api = _api;
      state = AsyncData(await _loadFirstPage(api));
    } on Exception catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
    }
  }

  /// 分页加载：展开可见窗口（客户端分块；服务端无分页参数）。
  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (current == null || !current.hasMore) return;
    final next = current.visibleCount + pageSize;
    state = AsyncData(
      current.copyWith(
        visibleCount: next < current.displaySessions.length
            ? next
            : current.displaySessions.length,
      ),
    );
  }

  /// 搜索（UI 已做防抖）：query 为空 → 退出搜索模式恢复普通列表。
  Future<void> search(String query) async {
    final current = state.valueOrNull;
    if (current == null) return;
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      state = AsyncData(
        current.copyWith(
          searchQuery: () => null,
          searchResults: () => null,
          isSearching: false,
          visibleCount: min(pageSize, current.sessions.length),
        ),
      );
      return;
    }
    state = AsyncData(
      current.copyWith(searchQuery: () => trimmed, isSearching: true),
    );
    try {
      final response = await _api.searchSessions(query: trimmed);
      final results = response.sessions ?? const <SessionSummary>[];
      state = AsyncData(
        current.copyWith(
          searchQuery: () => trimmed,
          searchResults: () => results,
          isSearching: false,
          visibleCount: min(pageSize, results.length),
        ),
      );
    } on ApiException catch (error) {
      state = AsyncData(
        current.copyWith(
          searchQuery: () => trimmed,
          searchResults: () => const <SessionSummary>[],
          isSearching: false,
          actionError: () => error.message,
        ),
      );
    }
  }

  /// 清除行操作错误标记（UI 展示完弹窗后调用）。
  Future<void> clearActionError() async {
    final current = state.valueOrNull;
    if (current == null || current.actionError == null) return;
    state = AsyncData(current.copyWith(actionError: () => null));
  }

  /// 切换筛选模式；来源/项目筛选为本地过滤（无需新请求），
  /// 归档模式触发 [fetchArchived] 拉取归档会话。切换时重置分页窗口并退出多选。
  Future<void> setFilter(SessionListFilterMode mode, {String? value}) async {
    final current = state.valueOrNull;
    if (current == null) return;
    final filtered = current.copyWith(
      filterMode: mode,
      filterValue: () => value,
      selectedSessionIds: const {},
      isSelectionMode: false,
    );
    state = AsyncData(
      filtered.copyWith(
        visibleCount: min(pageSize, filtered.displaySessions.length),
      ),
    );
    if (mode == SessionListFilterMode.archived) {
      await fetchArchived();
    }
  }

  /// 拉取归档会话（`fetchSessions(includeArchived: true)`）并保存归档列表与计数；
  /// 失败时仅设置 [SessionListState.actionError]，保留旧归档数据。
  Future<void> fetchArchived() async {
    final current = state.valueOrNull;
    if (current == null) return;
    try {
      final response = await _api.fetchSessions(includeArchived: true);
      final archived = response.sessions ?? const <SessionSummary>[];
      state = AsyncData(
        current.copyWith(
          archivedSessions: archived,
          archivedCount: () => response.archivedCount ?? current.archivedCount,
          visibleCount: min(pageSize, archived.length),
        ),
      );
    } on ApiException catch (error) {
      state = AsyncData(current.copyWith(actionError: () => error.message));
    }
  }

  /// 切换某会话的勾选状态；首个勾选进入多选模式，最后一个取消时退出多选模式。
  void toggleSelection(String sessionId) {
    final current = state.valueOrNull;
    if (current == null) return;
    final selected = {...current.selectedSessionIds};
    var isSelectionMode = current.isSelectionMode;
    if (selected.contains(sessionId)) {
      selected.remove(sessionId);
      if (selected.isEmpty) isSelectionMode = false;
    } else {
      selected.add(sessionId);
      isSelectionMode = true;
    }
    state = AsyncData(
      current.copyWith(
        selectedSessionIds: selected,
        isSelectionMode: isSelectionMode,
      ),
    );
  }

  /// 全选当前筛选视图内的全部会话（进入多选模式）。
  void selectAllInSection() {
    final current = state.valueOrNull;
    if (current == null) return;
    final ids = current.displaySessions
        .map((s) => s.sessionId)
        .whereType<String>()
        .toSet();
    state = AsyncData(
      current.copyWith(selectedSessionIds: ids, isSelectionMode: true),
    );
  }

  /// 退出多选模式并清空勾选。
  void clearSelection() {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData(
      current.copyWith(selectedSessionIds: const {}, isSelectionMode: false),
    );
  }

  /// 批量归档选中的会话（[archived] 为 false 时 = 恢复归档）；
  /// 成功项从当前视图移除，失败项计入 [BatchMutationResult.failed]
  /// 并设置 [SessionListState.actionError]。操作结束清空勾选。
  Future<BatchMutationResult> batchArchive({bool archived = true}) async {
    final current = state.valueOrNull;
    if (current == null) return const BatchMutationResult();
    final ids = current.selectedSessionIds.toList();
    if (ids.isEmpty) return const BatchMutationResult();
    var succeeded = 0;
    var failed = 0;
    final successIds = <String>[];
    for (final id in ids) {
      try {
        await _api.archiveSession(sessionId: id, archived: archived);
        succeeded++;
        successIds.add(id);
      } on ApiException {
        failed++;
      }
    }
    await _applyBatchChanges(successIds: successIds, removeFromLists: true);
    if (failed > 0) {
      await _setActionError('批量${archived ? '归档' : '恢复'}：$failed 个会话操作失败');
    }
    return BatchMutationResult(succeeded: succeeded, failed: failed);
  }

  /// 批量删除选中的会话；成功项从列表移除，清空勾选。
  Future<BatchMutationResult> batchDelete() async {
    final current = state.valueOrNull;
    if (current == null) return const BatchMutationResult();
    final ids = current.selectedSessionIds.toList();
    if (ids.isEmpty) return const BatchMutationResult();
    var succeeded = 0;
    var failed = 0;
    final successIds = <String>[];
    for (final id in ids) {
      try {
        await _api.deleteSession(id);
        succeeded++;
        successIds.add(id);
      } on ApiException {
        failed++;
      }
    }
    await _applyBatchChanges(successIds: successIds, removeFromLists: true);
    if (failed > 0) {
      await _setActionError('批量删除：$failed 个会话失败');
    }
    return BatchMutationResult(succeeded: succeeded, failed: failed);
  }

  /// 批量把选中的会话移动到 [projectId]（null = 移出项目）；
  /// 成功项本地刷新 projectId，清空勾选。
  Future<BatchMutationResult> batchMove(String? projectId) async {
    final current = state.valueOrNull;
    if (current == null) return const BatchMutationResult();
    final ids = current.selectedSessionIds.toList();
    if (ids.isEmpty) return const BatchMutationResult();
    var succeeded = 0;
    var failed = 0;
    final successIds = <String>[];
    for (final id in ids) {
      try {
        await _api.moveSession(sessionId: id, projectId: projectId);
        succeeded++;
        successIds.add(id);
      } on ApiException {
        failed++;
      }
    }
    await _applyBatchChanges(
      successIds: successIds,
      projectId: projectId,
      updateProjectId: true,
    );
    if (failed > 0) {
      await _setActionError('批量移动：$failed 个会话失败');
    }
    return BatchMutationResult(succeeded: succeeded, failed: failed);
  }

  /// 移动单个会话到项目（null = 移出项目）；成功后本地刷新该行 projectId。
  Future<bool> moveToProject(SessionSummary session, String? projectId) async {
    final id = session.sessionId;
    if (id == null || id.isEmpty) {
      await _setActionError('服务器未提供会话 ID');
      return false;
    }
    try {
      await _api.moveSession(sessionId: id, projectId: projectId);
      await _updateSession(
        id,
        (s) => _replaced(s, projectId: projectId, updateProjectId: true),
      );
      return true;
    } on ApiException catch (error) {
      await _setActionError(error.message);
      return false;
    }
  }

  /// 置顶 / 取消置顶；成功后本地更新该行（自动归入「置顶」分区）。
  Future<bool> setPinned(SessionSummary session, bool pinned) async {
    final id = session.sessionId;
    if (id == null || id.isEmpty) {
      await _setActionError('服务器未提供会话 ID');
      return false;
    }
    try {
      await _api.pinSession(sessionId: id, pinned: pinned);
      await _updateSession(id, (s) => _replaced(s, pinned: pinned));
      return true;
    } on ApiException catch (error) {
      await _setActionError(error.message);
      return false;
    }
  }

  /// 归档 / 取消归档；归档成功后从普通列表移除该行（列表默认不含已归档会话），
  /// 取消归档后从归档视图移除该行并更新普通列表。
  Future<bool> setArchived(SessionSummary session, bool archived) async {
    final id = session.sessionId;
    if (id == null || id.isEmpty) {
      await _setActionError('服务器未提供会话 ID');
      return false;
    }
    try {
      await _api.archiveSession(sessionId: id, archived: archived);
      if (archived) {
        await _removeSession(id);
        await _adjustArchivedCount(1);
      } else {
        await _updateSession(id, (s) => _replaced(s, archived: false));
        await _removeArchived(id);
        await _adjustArchivedCount(-1);
      }
      return true;
    } on ApiException catch (error) {
      await _setActionError(error.message);
      return false;
    }
  }

  /// 删除会话；成功后从列表移除。
  Future<bool> delete(SessionSummary session) async {
    final id = session.sessionId;
    if (id == null || id.isEmpty) {
      await _setActionError('服务器未提供会话 ID');
      return false;
    }
    try {
      await _api.deleteSession(id);
      await _removeSession(id);
      return true;
    } on ApiException catch (error) {
      await _setActionError(error.message);
      return false;
    }
  }

  /// 分支（复制）会话；成功返回新会话 ID（UI 跳转 /chat/:id）并插入列表顶部。
  Future<String?> branch(SessionSummary session) async {
    final id = session.sessionId;
    if (id == null || id.isEmpty) {
      await _setActionError('服务器未提供会话 ID');
      return null;
    }
    try {
      final response = await _api.branchSession(id);
      final newId = response.sessionId;
      if (newId == null || newId.isEmpty) {
        await _setActionError(response.error ?? '服务器未返回分支会话 ID');
        return null;
      }
      final hasTitle =
          response.title != null && response.title!.trim().isNotEmpty;
      await _insertSession(
        SessionSummary(
          sessionId: newId,
          title: hasTitle ? response.title : session.title,
        ),
      );
      return newId;
    } on ApiException catch (error) {
      await _setActionError(error.message);
      return null;
    }
  }

  /// 新建会话（POST /api/session/new）；成功返回新会话 ID（UI 跳转 /chat/:id）。
  Future<String?> createSession() async {
    try {
      final session = await _api.createSession();
      final id = session.sessionId;
      if (id == null || id.isEmpty) {
        await _setActionError('服务器未返回会话 ID');
        return null;
      }
      await _insertSession(session);
      return id;
    } on ApiException catch (error) {
      await _setActionError(error.message);
      return null;
    }
  }

  // -------------------------------------------------------------------------
  // 本地状态更新原语
  // -------------------------------------------------------------------------

  Future<void> _updateSession(
    String id,
    SessionSummary Function(SessionSummary) transform,
  ) async {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData(
      current.copyWith(
        sessions: [
          for (final s in current.sessions)
            s.sessionId == id ? transform(s) : s,
        ],
        searchResults: current.searchResults == null
            ? null
            : () => [
                for (final s in current.searchResults!)
                  s.sessionId == id ? transform(s) : s,
              ],
        archivedSessions: [
          for (final s in current.archivedSessions)
            s.sessionId == id ? transform(s) : s,
        ],
      ),
    );
  }

  Future<void> _removeSession(String id) async {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData(
      current.copyWith(
        sessions: current.sessions.where((s) => s.sessionId != id).toList(),
        searchResults: current.searchResults == null
            ? null
            : () => current.searchResults!
                  .where((s) => s.sessionId != id)
                  .toList(),
        archivedSessions: current.archivedSessions
            .where((s) => s.sessionId != id)
            .toList(),
        selectedSessionIds: {...current.selectedSessionIds}..remove(id),
      ),
    );
  }

  /// 从归档视图移除指定会话（取消归档后调用）。
  Future<void> _removeArchived(String id) async {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData(
      current.copyWith(
        archivedSessions: current.archivedSessions
            .where((s) => s.sessionId != id)
            .toList(),
      ),
    );
  }

  /// 本地增/减归档计数（服务端未返回 archived_count 时为 null，不显示计数）。
  Future<void> _adjustArchivedCount(int delta) async {
    final current = state.valueOrNull;
    if (current == null || current.archivedCount == null) return;
    state = AsyncData(
      current.copyWith(
        archivedCount: () => max(0, current.archivedCount! + delta),
      ),
    );
  }

  /// 批量操作收尾：对成功项执行本地更新（移除列表项或刷新 projectId），
  /// 并清空勾选退出多选模式（失败项保留在列表中，由 actionError 提示）。
  Future<void> _applyBatchChanges({
    required List<String> successIds,
    bool removeFromLists = false,
    String? projectId,
    bool updateProjectId = false,
  }) async {
    final current = state.valueOrNull;
    if (current == null) return;
    final successSet = successIds.toSet();
    List<SessionSummary> Function(List<SessionSummary>) apply;
    if (removeFromLists) {
      apply = (list) =>
          list.where((s) => !successSet.contains(s.sessionId)).toList();
    } else if (updateProjectId) {
      apply = (list) => [
        for (final s in list)
          successSet.contains(s.sessionId)
              ? _replaced(s, projectId: projectId, updateProjectId: true)
              : s,
      ];
    } else {
      return;
    }
    state = AsyncData(
      current.copyWith(
        sessions: apply(current.sessions),
        searchResults: current.searchResults == null
            ? null
            : () => apply(current.searchResults!),
        archivedSessions: apply(current.archivedSessions),
        selectedSessionIds: const {},
        isSelectionMode: false,
      ),
    );
  }

  Future<void> _insertSession(SessionSummary session) async {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData(
      current.copyWith(
        sessions: [session, ...current.sessions],
        visibleCount: current.visibleCount + 1,
      ),
    );
  }

  Future<void> _setActionError(String message) async {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData(current.copyWith(actionError: () => message));
  }

  static SessionSummary _replaced(
    SessionSummary session, {
    bool? pinned,
    bool? archived,
    String? projectId,
    bool updateProjectId = false,
  }) {
    return SessionSummary(
      sessionId: session.sessionId,
      title: session.title,
      workspace: session.workspace,
      model: session.model,
      modelProvider: session.modelProvider,
      messageCount: session.messageCount,
      createdAt: session.createdAt,
      updatedAt: session.updatedAt,
      lastMessageAt: session.lastMessageAt,
      pinned: pinned ?? session.pinned,
      archived: archived ?? session.archived,
      projectId: updateProjectId ? projectId : session.projectId,
      profile: session.profile,
      inputTokens: session.inputTokens,
      outputTokens: session.outputTokens,
      estimatedCost: session.estimatedCost,
      activeStreamId: session.activeStreamId,
      isStreaming: session.isStreaming,
      isCliSession: session.isCliSession,
      userMessageCount: session.userMessageCount,
      hasPendingUserMessage: session.hasPendingUserMessage,
      pendingStartedAt: session.pendingStartedAt,
      worktreePath: session.worktreePath,
      sourceTag: session.sourceTag,
      rawSource: session.rawSource,
      sessionSource: session.sessionSource,
      sourceLabel: session.sourceLabel,
      parentSessionId: session.parentSessionId,
      relationshipType: session.relationshipType,
      readOnly: session.readOnly,
      isReadOnly: session.isReadOnly,
      matchType: session.matchType,
    );
  }
}

/// 当前分页窗口内的可见会话（普通模式 = 分块；搜索模式 = 命中结果分块）。
final sessionListVisibleSessionsProvider = Provider<List<SessionSummary>>((
  ref,
) {
  final state = ref.watch(sessionListControllerProvider).valueOrNull;
  if (state == null) return const [];
  final all = state.displaySessions;
  final end = state.visibleCount < all.length ? state.visibleCount : all.length;
  return all.sublist(0, end);
});

/// 会话分区（置顶 / 今天 / 昨天 / 更早）；搜索模式为单个「搜索结果」分区。
final sessionListSectionsProvider = Provider<List<SessionListSection>>((ref) {
  final visible = ref.watch(sessionListVisibleSessionsProvider);
  final query = ref
      .watch(sessionListControllerProvider)
      .valueOrNull
      ?.searchQuery;
  final isSearching = query != null && query.trim().isNotEmpty;
  if (isSearching) {
    return [SessionListSection(title: '搜索结果', sessions: visible)];
  }
  return buildSessionSections(visible);
});

/// 按时间把会话分组为 置顶 / 今天 / 昨天 / 更早（对齐 Hermex
/// `SessionListViewModel.sections`），组内时间倒序；空组剔除。
///
/// [now] 仅供测试注入固定参考时间；生产使用 [DateTime.now]。
List<SessionListSection> buildSessionSections(
  List<SessionSummary> sessions, {
  DateTime? now,
}) {
  final reference = now ?? DateTime.now();
  final sorted = [...sessions]
    ..sort((a, b) => _sortTimestamp(b).compareTo(_sortTimestamp(a)));
  final pinned = <SessionSummary>[];
  final today = <SessionSummary>[];
  final yesterday = <SessionSummary>[];
  final earlier = <SessionSummary>[];
  for (final session in sorted) {
    if (session.pinned == true) {
      pinned.add(session);
      continue;
    }
    final timestamp = _timestamp(session);
    if (timestamp == null) {
      earlier.add(session);
      continue;
    }
    final date = DateTime.fromMillisecondsSinceEpoch(
      (timestamp * 1000).round(),
    );
    if (_isSameDay(date, reference)) {
      today.add(session);
    } else if (_isSameDay(date, reference.subtract(const Duration(days: 1)))) {
      yesterday.add(session);
    } else {
      earlier.add(session);
    }
  }
  return [
    if (pinned.isNotEmpty) SessionListSection(title: '置顶', sessions: pinned),
    if (today.isNotEmpty) SessionListSection(title: '今天', sessions: today),
    if (yesterday.isNotEmpty)
      SessionListSection(title: '昨天', sessions: yesterday),
    if (earlier.isNotEmpty) SessionListSection(title: '更早', sessions: earlier),
  ];
}

/// 会话时间戳：lastMessageAt ?? updatedAt ?? createdAt（秒）。
double? _timestamp(SessionSummary session) =>
    session.lastMessageAt ?? session.updatedAt ?? session.createdAt;

/// 排序用时间戳：缺失按 0（最旧）处理。
double _sortTimestamp(SessionSummary session) => _timestamp(session) ?? 0;

bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
