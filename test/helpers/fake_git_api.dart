import 'dart:async';

import 'package:hermex_flutter/core/models/git_workspace.dart';
import 'package:hermex_flutter/features/git/git_api.dart';

/// 可配置的 [GitApi] fake（测试注入，彻底绕开网络）。
///
/// 默认返回空仓库状态；测试可按需配置各方法返回值 / 抛错 / gate，
/// 并通过调用记录断言参数与次数。
class FakeGitApi implements GitApi {
  FakeGitApi({GitStatus? status})
    : statusResponse = GitStatusResponse(git: status ?? _emptyStatus());

  static GitStatus _emptyStatus() => const GitStatus(isGit: true);

  /// `fetchStatus` 返回的响应（可变，模拟操作后的状态刷新）。
  GitStatusResponse statusResponse;

  /// `fetchStatus` 抛出的异常（非 null 时优先于 [statusResponse]）。
  Object? statusError;

  /// 非 null 时 `fetchStatus` 挂起等待该 gate（测试加载态用）。
  Completer<void>? statusGate;

  /// `fetchBranches` 返回的分支响应。
  GitBranchesResponse branchesResponse = const GitBranchesResponse(
    branches: GitBranches(
      isGit: true,
      current: 'main',
      local: [
        GitBranchRef(name: 'main'),
        GitBranchRef(name: 'dev'),
      ],
    ),
  );

  /// `fetchBranches` 抛出的异常。
  Object? branchesError;

  /// `fetchDiff` 返回的 diff（可变）。
  GitDiffResponse diffResponse = const GitDiffResponse(
    diff: GitDiff(path: 'a.txt', diff: 'diff --git a/a.txt b/a.txt'),
  );

  /// `fetchDiff` 抛出的异常。
  Object? diffError;

  /// stage / unstage / discard / commit 返回的变更响应（可变）。
  GitMutationResponse mutationResponse = const GitMutationResponse(ok: true);

  /// 各写方法抛出的异常（非 null 时模拟失败）。
  Object? stageError;
  Object? unstageError;
  Object? discardError;
  Object? commitError;
  Object? checkoutError;
  Object? fetchError;
  Object? pullError;
  Object? pushError;

  /// commit 返回的提交响应（可变）。
  GitCommitResponse commitResponse = const GitCommitResponse(
    ok: true,
    commit: 'abc1234',
  );

  /// checkout 返回的检出响应（可变）。
  GitCheckoutResponse checkoutResponse = const GitCheckoutResponse(ok: true);

  /// fetch / pull / push 返回的远程响应（可变）。
  GitRemoteActionResponse remoteResponse = const GitRemoteActionResponse(
    ok: true,
    message: '完成',
  );

  int statusCount = 0;
  int branchesCount = 0;
  int diffCount = 0;

  /// 已调用的写操作记录（含参数，如 `stage [a.txt]` / `commit msg`）。
  final List<String> stageCalls = [];
  final List<String> unstageCalls = [];
  final List<String> discardCalls = [];
  final List<String> commitCalls = [];
  final List<String> checkoutCalls = [];
  final List<String> fetchCalls = [];
  final List<String> pullCalls = [];
  final List<String> pushCalls = [];
  final List<String> diffCalls = [];

  @override
  Future<GitStatusResponse> fetchStatus(String sessionId) async {
    statusCount++;
    final error = statusError;
    if (error != null) throw error;
    final gate = statusGate;
    if (gate != null) await gate.future;
    return statusResponse;
  }

  @override
  Future<GitBranchesResponse> fetchBranches(String sessionId) async {
    branchesCount++;
    final error = branchesError;
    if (error != null) throw error;
    return branchesResponse;
  }

  @override
  Future<GitDiffResponse> fetchDiff({
    required String sessionId,
    required String path,
    String kind = 'unstaged',
  }) async {
    diffCount++;
    diffCalls.add('$path:$kind');
    final error = diffError;
    if (error != null) throw error;
    return diffResponse;
  }

  @override
  Future<GitMutationResponse> stage({
    required String sessionId,
    required List<String> paths,
  }) async {
    stageCalls.add(paths.join(','));
    final error = stageError;
    if (error != null) throw error;
    return mutationResponse;
  }

  @override
  Future<GitMutationResponse> unstage({
    required String sessionId,
    required List<String> paths,
  }) async {
    unstageCalls.add(paths.join(','));
    final error = unstageError;
    if (error != null) throw error;
    return mutationResponse;
  }

  @override
  Future<GitMutationResponse> discard({
    required String sessionId,
    required List<String> paths,
    bool deleteUntracked = false,
  }) async {
    discardCalls.add(paths.join(','));
    final error = discardError;
    if (error != null) throw error;
    return mutationResponse;
  }

  @override
  Future<GitCommitResponse> commit({
    required String sessionId,
    required String message,
  }) async {
    commitCalls.add(message);
    final error = commitError;
    if (error != null) throw error;
    return commitResponse;
  }

  @override
  Future<GitCheckoutResponse> checkout({
    required String sessionId,
    required String ref,
    String mode = 'local',
    String? newBranch,
    bool track = false,
  }) async {
    checkoutCalls.add('$ref:$mode');
    final error = checkoutError;
    if (error != null) throw error;
    return checkoutResponse;
  }

  @override
  Future<GitRemoteActionResponse> fetch(String sessionId) async {
    fetchCalls.add(sessionId);
    final error = fetchError;
    if (error != null) throw error;
    return remoteResponse;
  }

  @override
  Future<GitRemoteActionResponse> pull(String sessionId) async {
    pullCalls.add(sessionId);
    final error = pullError;
    if (error != null) throw error;
    return remoteResponse;
  }

  @override
  Future<GitRemoteActionResponse> push(String sessionId) async {
    pushCalls.add(sessionId);
    final error = pushError;
    if (error != null) throw error;
    return remoteResponse;
  }
}
