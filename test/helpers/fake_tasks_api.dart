import 'dart:async';

import 'package:hermex_flutter/core/models/cron.dart';
import 'package:hermex_flutter/features/tasks/tasks_api.dart';

/// 可配置的 [TasksApi] fake（测试注入，彻底绕开网络）。
///
/// 默认返回空任务列表；测试可按需配置 [jobs] / [mutationJob] / [outputResponse]
/// / 各方法抛错，并通过计数器与调用记录断言调用次数与参数。
class FakeTasksApi implements TasksApi {
  FakeTasksApi({List<CronJob>? jobs}) : jobs = jobs ?? [];

  /// `fetchJobs` 返回的任务列表。
  List<CronJob> jobs;

  /// `fetchJobs` 抛出的异常（非 null 时优先于 [jobs]）。
  Object? fetchError;

  /// 非 null 时 `fetchJobs` 挂起等待该 gate（测试加载态用）。
  Completer<void>? fetchGate;

  /// 非 null 时各变更方法挂起等待该 gate（测试 busy 态用）。
  Completer<void>? mutationGate;

  /// 变更方法返回的 job（非 null 时控制器直接采用；null → 控制器本地补丁）。
  CronJob? mutationJob;

  /// `fetchOutput` 返回的输出。
  CronOutputResponse outputResponse = const CronOutputResponse();

  /// 各方法抛出的异常（非 null 时模拟失败）。
  Object? createError;
  Object? updateError;
  Object? deleteError;
  Object? runError;
  Object? pauseError;
  Object? resumeError;
  Object? outputError;

  int fetchCount = 0;
  int createCount = 0;
  int updateCount = 0;
  int deleteCount = 0;
  int runCount = 0;
  int pauseCount = 0;
  int resumeCount = 0;
  int outputCount = 0;

  /// 已调用的操作记录（含参数）。
  final List<String> createCalls = [];
  final List<String> updateCalls = [];
  final List<String> deleteCalls = [];
  final List<String> runCalls = [];
  final List<String> pauseCalls = [];
  final List<String> resumeCalls = [];
  final List<String> outputCalls = [];

  @override
  Future<CronJobsResponse> fetchJobs() async {
    fetchCount++;
    final error = fetchError;
    if (error != null) throw error;
    final gate = fetchGate;
    if (gate != null) await gate.future;
    return CronJobsResponse(jobs: jobs);
  }

  @override
  Future<CronMutationResponse> createJob({
    required String prompt,
    required String schedule,
    String? name,
    bool toastNotifications = false,
  }) async {
    createCount++;
    createCalls.add('${name ?? ''}|$schedule|$prompt|$toastNotifications');
    await _waitMutationGate();
    final error = createError;
    if (error != null) throw error;
    return CronMutationResponse(ok: true, job: mutationJob);
  }

  @override
  Future<CronMutationResponse> updateJob({
    required String jobId,
    String? prompt,
    String? schedule,
    String? name,
    bool? toastNotifications,
  }) async {
    updateCount++;
    updateCalls.add(
      '$jobId|${name ?? ''}|${schedule ?? ''}|${prompt ?? ''}|'
      '${toastNotifications ?? false}',
    );
    await _waitMutationGate();
    final error = updateError;
    if (error != null) throw error;
    return CronMutationResponse(ok: true, job: mutationJob);
  }

  @override
  Future<CronMutationResponse> deleteJob(String jobId) async {
    deleteCount++;
    deleteCalls.add(jobId);
    await _waitMutationGate();
    final error = deleteError;
    if (error != null) throw error;
    return const CronMutationResponse(ok: true);
  }

  @override
  Future<CronMutationResponse> runJob(String jobId) async {
    runCount++;
    runCalls.add(jobId);
    await _waitMutationGate();
    final error = runError;
    if (error != null) throw error;
    return CronMutationResponse(ok: true, job: mutationJob);
  }

  @override
  Future<CronMutationResponse> pauseJob(String jobId) async {
    pauseCount++;
    pauseCalls.add(jobId);
    await _waitMutationGate();
    final error = pauseError;
    if (error != null) throw error;
    return CronMutationResponse(ok: true, job: mutationJob);
  }

  @override
  Future<CronMutationResponse> resumeJob(String jobId) async {
    resumeCount++;
    resumeCalls.add(jobId);
    await _waitMutationGate();
    final error = resumeError;
    if (error != null) throw error;
    return CronMutationResponse(ok: true, job: mutationJob);
  }

  @override
  Future<CronOutputResponse> fetchOutput(String jobId, {int? limit}) async {
    outputCount++;
    outputCalls.add('$jobId:${limit ?? 5}');
    final error = outputError;
    if (error != null) throw error;
    return outputResponse;
  }

  Future<void> _waitMutationGate() async {
    final gate = mutationGate;
    if (gate != null) await gate.future;
  }
}
