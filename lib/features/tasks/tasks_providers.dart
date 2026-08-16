import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_exception.dart';
import '../../core/connections/connection_providers.dart';
import '../../core/models/cron.dart';
import 'tasks_api.dart';

/// 构建 [TasksApi] 的工厂（测试可 override 注入 fake）。
typedef TasksApiFactory = TasksApi Function(ApiClient client);

final tasksApiFactoryProvider = Provider<TasksApiFactory>(
  (ref) => TasksApiClient.new,
);

/// 定时任务列表状态（AsyncNotifier 的 AsyncData 载荷）。
class TasksState {
  const TasksState({
    this.jobs = const [],
    this.busyJobIds = const {},
    this.actionError,
  });

  /// 全部定时任务（服务端顺序）。
  final List<CronJob> jobs;

  /// 正在执行变更（运行/暂停/恢复/删除）的任务 ID（UI 用 ActivityIndicator
  /// 替换对应行的操作按钮）。
  final Set<String> busyJobIds;

  /// 最近一次行操作/表单错误（UI 弹窗展示后调用 [TasksController.clearActionError] 清除）。
  final String? actionError;

  /// 指定任务是否正在执行变更。
  bool isBusy(String jobId) => busyJobIds.contains(jobId);

  TasksState copyWith({
    List<CronJob>? jobs,
    Set<String>? busyJobIds,
    String? Function()? actionError,
  }) {
    return TasksState(
      jobs: jobs ?? this.jobs,
      busyJobIds: busyJobIds ?? this.busyJobIds,
      actionError: actionError != null ? actionError() : this.actionError,
    );
  }

  @override
  String toString() =>
      'TasksState(jobs: ${jobs.length}, busy: ${busyJobIds.length}, '
      'actionError: $actionError)';
}

/// 定时任务控制器：加载 / 刷新 / 运行 / 暂停 / 恢复 / 删除 / 新建 / 编辑 /
/// 查看输出。
///
/// AsyncValue 语义：`AsyncData` 携带 [TasksState]；初始加载与下拉刷新失败 →
/// `AsyncError`（UI 展示错误态 + 重试）；行操作失败不改变列表，只设置
/// [TasksState.actionError] 供弹窗提示。
final tasksControllerProvider =
    AsyncNotifierProvider<TasksController, TasksState>(TasksController.new);

class TasksController extends AsyncNotifier<TasksState> {
  TasksApi get _api =>
      ref.read(tasksApiFactoryProvider)(ref.read(apiClientProvider));

  @override
  Future<TasksState> build() async {
    // watch：切换服务器（apiClientProvider 重建）或工厂被替换时自动重载。
    final api = ref.watch(tasksApiFactoryProvider)(
      ref.watch(apiClientProvider),
    );
    return _load(api);
  }

  Future<TasksState> _load(TasksApi api) async {
    final response = await api.fetchJobs();
    return TasksState(jobs: response.jobs ?? const <CronJob>[]);
  }

  /// 下拉刷新 / 错误态重试：重新加载任务列表。
  Future<void> refresh() async {
    try {
      final api = _api;
      state = AsyncData(await _load(api));
    } on Exception catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
    }
  }

  /// 手动触发一次执行；成功后本地标记 `state == 'running'`（或采用服务器返回的任务）。
  Future<bool> run(CronJob job) => _mutate(job, _api.runJob, patch: _asRunning);

  /// 暂停任务；成功后本地标记 `state == 'paused'` / `enabled == false`。
  Future<bool> pause(CronJob job) =>
      _mutate(job, _api.pauseJob, patch: _asPaused);

  /// 恢复任务；成功后本地清除 paused 标记并 `enabled = true`。
  Future<bool> resume(CronJob job) =>
      _mutate(job, _api.resumeJob, patch: _asResumed);

  /// 删除任务；成功后从列表移除。
  Future<bool> delete(CronJob job) async {
    final id = job.jobId;
    if (id == null || id.isEmpty) {
      await _setActionError('服务器未提供任务 ID');
      return false;
    }
    await _setBusy(id, true);
    try {
      final response = await _api.deleteJob(id);
      if (response.ok == false) {
        await _setActionError(response.error ?? '删除失败，服务器未确认');
        return false;
      }
      await _removeJob(id);
      return true;
    } on ApiException catch (error) {
      await _setActionError(error.message);
      return false;
    } finally {
      await _setBusy(id, false);
    }
  }

  /// 新建任务；成功返回 true（UI 关闭表单页）。
  Future<bool> create({
    required String name,
    required String schedule,
    required String prompt,
    bool toastNotifications = false,
  }) async {
    try {
      final response = await _api.createJob(
        prompt: prompt,
        schedule: schedule,
        name: _nonEmpty(name),
        toastNotifications: toastNotifications,
      );
      if (response.ok == false) {
        await _setActionError(response.error ?? '创建失败，服务器未确认');
        return false;
      }
      final job = response.job;
      if (job == null) {
        // 服务器未回传任务详情：重新拉取保持列表新鲜。
        await _reloadAfterMutation();
      } else {
        await _insertJob(job);
      }
      return true;
    } on ApiException catch (error) {
      await _setActionError(error.message);
      return false;
    }
  }

  /// 保存编辑（更新已有任务）；成功返回 true（UI 关闭表单页）。
  ///
  /// 注意：命名 `save` 而非 `update`——`AsyncNotifierBase` 自带 `update`
  /// 方法，同名会构成非法 override。
  Future<bool> save(
    CronJob job, {
    required String name,
    required String schedule,
    required String prompt,
    required bool toastNotifications,
  }) async {
    final id = job.jobId;
    if (id == null || id.isEmpty) {
      await _setActionError('服务器未提供任务 ID');
      return false;
    }
    try {
      final response = await _api.updateJob(
        jobId: id,
        name: _nonEmpty(name),
        schedule: schedule,
        prompt: prompt,
        toastNotifications: toastNotifications,
      );
      if (response.ok == false) {
        await _setActionError(response.error ?? '保存失败，服务器未确认');
        return false;
      }
      final serverJob = response.job;
      if (serverJob != null && serverJob.jobId != null) {
        await _replaceJob(id, serverJob);
      } else {
        await _replaceJob(
          id,
          _withEditedFields(
            job,
            name: name,
            schedule: schedule,
            prompt: prompt,
            toastNotifications: toastNotifications,
          ),
        );
      }
      return true;
    } on ApiException catch (error) {
      await _setActionError(error.message);
      return false;
    }
  }

  /// 拉取任务最近输出（UI 展示；失败置 [TasksState.actionError] 并返回 null）。
  Future<CronOutputResponse?> fetchOutput(CronJob job, {int? limit = 5}) async {
    final id = job.jobId;
    if (id == null || id.isEmpty) {
      await _setActionError('服务器未提供任务 ID');
      return null;
    }
    try {
      return await _api.fetchOutput(id, limit: limit);
    } on ApiException catch (error) {
      await _setActionError(error.message);
      return null;
    }
  }

  /// 清除行操作错误标记（UI 展示完弹窗后调用）。
  Future<void> clearActionError() async {
    final current = state.valueOrNull;
    if (current == null || current.actionError == null) return;
    state = AsyncData(current.copyWith(actionError: () => null));
  }

  // -------------------------------------------------------------------------
  // 变更流程 / 本地状态更新原语
  // -------------------------------------------------------------------------

  /// 运行 / 暂停 / 恢复共用流程：busy 标记 → API → 服务器 job 优先，
  /// 否则本地补丁；失败只置 [TasksState.actionError]，列表不变。
  Future<bool> _mutate(
    CronJob job,
    Future<CronMutationResponse> Function(String jobId) call, {
    required CronJob Function(CronJob) patch,
  }) async {
    final id = job.jobId;
    if (id == null || id.isEmpty) {
      await _setActionError('服务器未提供任务 ID');
      return false;
    }
    await _setBusy(id, true);
    try {
      final response = await call(id);
      if (response.ok == false) {
        await _setActionError(response.error ?? '操作失败，服务器未确认');
        return false;
      }
      final serverJob = response.job;
      if (serverJob != null && serverJob.jobId != null) {
        await _replaceJob(id, serverJob);
      } else {
        await _replaceJob(id, patch(job));
      }
      return true;
    } on ApiException catch (error) {
      await _setActionError(error.message);
      return false;
    } finally {
      await _setBusy(id, false);
    }
  }

  /// 变更成功但服务器未返回任务详情时兜底：重新拉取；失败静默保留旧列表
  /// （变更本身已成功，不打断用户，下拉刷新可再同步）。
  Future<void> _reloadAfterMutation() async {
    try {
      final next = await _load(_api);
      state = AsyncData(next);
    } on Exception catch (error) {
      // 显式消费异常，避免空 catch（列表保留旧数据）。
      final _ = error;
    }
  }

  Future<void> _setBusy(String jobId, bool busy) async {
    final current = state.valueOrNull;
    if (current == null) return;
    final next = Set<String>.of(current.busyJobIds);
    if (busy) {
      next.add(jobId);
    } else {
      next.remove(jobId);
    }
    state = AsyncData(current.copyWith(busyJobIds: next));
  }

  Future<void> _setActionError(String message) async {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData(current.copyWith(actionError: () => message));
  }

  Future<void> _replaceJob(String jobId, CronJob replacement) async {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData(
      current.copyWith(
        jobs: [
          for (final job in current.jobs)
            job.jobId == jobId ? replacement : job,
        ],
      ),
    );
  }

  Future<void> _removeJob(String jobId) async {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData(
      current.copyWith(jobs: current.jobs.where((j) => j.jobId != jobId).toList()),
    );
  }

  Future<void> _insertJob(CronJob job) async {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData(current.copyWith(jobs: [job, ...current.jobs]));
  }

  static String? _nonEmpty(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static CronJob _asPaused(CronJob job) =>
      _withRunFields(job, state: 'paused', enabled: false);

  static CronJob _asResumed(CronJob job) =>
      _withRunFields(job, state: null, enabled: true);

  static CronJob _asRunning(CronJob job) =>
      _withRunFields(job, state: 'running', enabled: true);

  /// 保留其余字段，仅覆盖运行态字段（state / enabled）。
  static CronJob _withRunFields(
    CronJob job, {
    required String? state,
    required bool enabled,
  }) {
    return CronJob(
      jobId: job.jobId,
      name: job.name,
      prompt: job.prompt,
      schedule: job.schedule,
      scheduleDisplay: job.scheduleDisplay,
      enabled: enabled,
      state: state,
      nextRunAt: job.nextRunAt,
      lastRunAt: job.lastRunAt,
      lastStatus: job.lastStatus,
      lastError: job.lastError,
      lastDeliveryError: job.lastDeliveryError,
      repeatInfo: job.repeatInfo,
      deliver: job.deliver,
      skills: job.skills,
      model: job.model,
      provider: job.provider,
      profile: job.profile,
      toastNotifications: job.toastNotifications,
    );
  }

  /// 保留其余字段，仅覆盖编辑字段（name / schedule / prompt / toastNotifications）。
  static CronJob _withEditedFields(
    CronJob job, {
    required String name,
    required String schedule,
    required String prompt,
    required bool toastNotifications,
  }) {
    return CronJob(
      jobId: job.jobId,
      name: _nonEmpty(name),
      prompt: prompt,
      schedule: CronSchedule(expression: schedule),
      scheduleDisplay: schedule,
      enabled: job.enabled,
      state: job.state,
      nextRunAt: job.nextRunAt,
      lastRunAt: job.lastRunAt,
      lastStatus: job.lastStatus,
      lastError: job.lastError,
      lastDeliveryError: job.lastDeliveryError,
      repeatInfo: job.repeatInfo,
      deliver: job.deliver,
      skills: job.skills,
      model: job.model,
      provider: job.provider,
      profile: job.profile,
      toastNotifications: toastNotifications,
    );
  }
}

/// 派生：任务总数。
final tasksJobCountProvider = Provider<int>((ref) {
  return ref.watch(tasksControllerProvider).valueOrNull?.jobs.length ?? 0;
});

/// 派生：当前运行中（`state == 'running'`）的任务。
final tasksRunningJobsProvider = Provider<List<CronJob>>((ref) {
  final jobs = ref.watch(tasksControllerProvider).valueOrNull?.jobs ??
      const <CronJob>[];
  return [
    for (final job in jobs)
      if (job.state == 'running') job,
  ];
});
