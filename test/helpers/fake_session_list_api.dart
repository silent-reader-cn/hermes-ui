import 'dart:async';

import 'package:hermex_flutter/core/models/session.dart';
import 'package:hermex_flutter/features/session_list/session_list_providers.dart';

/// 可配置的 [SessionListApi] fake（测试注入，彻底绕开网络）。
///
/// 默认返回空会话；测试可按需配置 [sessions] / [searchResults] / 各方法抛错，
/// 并通过计数器断言调用次数与参数。
class FakeSessionListApi implements SessionListApi {
  FakeSessionListApi({List<SessionSummary>? sessions})
    : sessions = sessions ?? [];

  /// `fetchSessions` 返回的会话（普通模式列表）。
  List<SessionSummary> sessions;

  /// `fetchSessions` 抛出的异常（非 null 时优先于 [sessions]）。
  Object? fetchError;

  /// 控制 [fetchError] 抛出的次数上限（-1 = 无限，默认保持经典行为）。
  ///
  /// 用于自动重登用例：先抛 1 次 401 触发重登，重登后恢复正常——
  /// 例如 `fetchErrorCap = 1` 时首次 fetch 抛错、第二次起成功。
  int fetchErrorCap = -1;

  int _fetchErrorsThrown = 0;

  /// 非 null 时 `fetchSessions` 挂起等待该 gate（测试加载态用）。
  Completer<void>? fetchGate;

  /// 远程搜索命中表（query → 结果）。
  final Map<String, List<SessionSummary>> searchResults = {};

  /// `searchSessions` 抛出的异常。
  Object? searchError;

  /// `createSession` 返回的新会话（sessionId 为空 → 模拟服务器未返回 ID）。
  SessionSummary createdSession = const SessionSummary(
    sessionId: 'new-1',
    title: '新会话',
  );

  /// `branchSession` 返回的结果（sessionId 为空 → 模拟失败）。
  SessionBranchResponse branchResponse = const SessionBranchResponse(
    sessionId: 'branch-1',
    title: '分支副本',
  );

  /// 各变更方法抛出的异常（非 null 时模拟失败）。
  Object? pinError;
  Object? archiveError;
  Object? deleteError;
  Object? branchError;
  Object? createError;

  int fetchCount = 0;
  int searchCount = 0;
  int createCount = 0;

  /// 已调用的变更操作记录（含参数，如 `pin s1:true`）。
  final List<String> pinCalls = [];
  final List<String> archiveCalls = [];
  final List<String> deleteCalls = [];
  final List<String> branchCalls = [];
  final List<String> searchQueries = [];
  final List<String> moveCalls = [];

  /// `fetchSessions` 是否最近一次以 includeArchived=true 调用。
  bool lastFetchedArchived = false;

  /// `moveSession` 抛出的异常。
  Object? moveError;

  @override
  Future<SessionsResponse> fetchSessions({
    bool includeArchived = false,
    int? archivedLimit,
  }) async {
    fetchCount++;
    lastFetchedArchived = includeArchived;
    final error = fetchError;
    if (error != null &&
        (fetchErrorCap < 0 || _fetchErrorsThrown < fetchErrorCap)) {
      _fetchErrorsThrown++;
      throw error;
    }
    final gate = fetchGate;
    if (gate != null) await gate.future;
    final list = includeArchived
        ? sessions.where((s) => s.archived == true).toList()
        : sessions.where((s) => s.archived != true).toList();
    return SessionsResponse(
      sessions: list,
      archivedCount: sessions.where((s) => s.archived == true).length,
    );
  }

  @override
  Future<SessionSearchResponse> searchSessions({required String query}) async {
    searchCount++;
    searchQueries.add(query);
    final error = searchError;
    if (error != null) throw error;
    return SessionSearchResponse(
      sessions: searchResults[query] ?? const [],
      query: query,
      count: (searchResults[query] ?? const []).length,
    );
  }

  @override
  Future<SessionSummary> createSession() async {
    createCount++;
    final error = createError;
    if (error != null) throw error;
    return createdSession;
  }

  @override
  Future<SessionMutationResponse> pinSession({
    required String sessionId,
    required bool pinned,
  }) async {
    pinCalls.add('$sessionId:$pinned');
    final error = pinError;
    if (error != null) throw error;
    return const SessionMutationResponse(ok: true);
  }

  @override
  Future<SessionMutationResponse> archiveSession({
    required String sessionId,
    required bool archived,
  }) async {
    archiveCalls.add('$sessionId:$archived');
    final error = archiveError;
    if (error != null) throw error;
    return const SessionMutationResponse(ok: true);
  }

  @override
  Future<SessionMutationResponse> deleteSession(String sessionId) async {
    deleteCalls.add(sessionId);
    final error = deleteError;
    if (error != null) throw error;
    return const SessionMutationResponse(ok: true);
  }

  @override
  Future<SessionMutationResponse> moveSession({
    required String sessionId,
    String? projectId,
  }) async {
    moveCalls.add('$sessionId:${projectId ?? 'null'}');
    final error = moveError;
    if (error != null) throw error;
    return const SessionMutationResponse(ok: true);
  }

  @override
  Future<SessionBranchResponse> branchSession(String sessionId) async {
    branchCalls.add(sessionId);
    final error = branchError;
    if (error != null) throw error;
    return branchResponse;
  }
}
