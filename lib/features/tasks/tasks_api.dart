import '../../core/api/api_client.dart';
import '../../core/api/api_client_cron.dart';
import '../../core/models/cron.dart';

/// 定时任务页所需的最小服务器 API 面（cron 域 10 个端点中的 8 个）。
///
/// 生产实现 [TasksApiClient] 包 [ApiClient]（模型在客户端解码）；
/// 测试注入纯 Dart fake，彻底绕开网络/事件循环（对齐 session_list 的
/// `SessionListApi` 模式）。
abstract interface class TasksApi {
  /// GET /api/crons → 全部定时任务（服务端一次全量返回）。
  Future<CronJobsResponse> fetchJobs();

  /// POST /api/crons/create → 新建任务。
  Future<CronMutationResponse> createJob({
    required String prompt,
    required String schedule,
    String? name,
    bool toastNotifications = false,
  });

  /// POST /api/crons/update → 保存编辑（全部字段可空）。
  Future<CronMutationResponse> updateJob({
    required String jobId,
    String? prompt,
    String? schedule,
    String? name,
    bool? toastNotifications,
  });

  /// POST /api/crons/delete → 删除任务。
  Future<CronMutationResponse> deleteJob(String jobId);

  /// POST /api/crons/run → 手动触发一次执行。
  Future<CronMutationResponse> runJob(String jobId);

  /// POST /api/crons/pause → 暂停任务。
  Future<CronMutationResponse> pauseJob(String jobId);

  /// POST /api/crons/resume → 恢复任务。
  Future<CronMutationResponse> resumeJob(String jobId);

  /// GET /api/crons/output → 最近一次执行输出。
  Future<CronOutputResponse> fetchOutput(String jobId, {int? limit});
}

/// [TasksApi] 的生产实现：包 [ApiClient]，把 `Object?` JSON 解码为模型。
class TasksApiClient implements TasksApi {
  TasksApiClient(this._client);

  final ApiClient _client;

  @override
  Future<CronJobsResponse> fetchJobs() async {
    final json = await _client.crons();
    return CronJobsResponse.fromJson(_asMap(json));
  }

  @override
  Future<CronMutationResponse> createJob({
    required String prompt,
    required String schedule,
    String? name,
    bool toastNotifications = false,
  }) async {
    final json = await _client.createCron(
      prompt: prompt,
      schedule: schedule,
      name: name,
      toastNotifications: toastNotifications,
    );
    return CronMutationResponse.fromJson(_asMap(json));
  }

  @override
  Future<CronMutationResponse> updateJob({
    required String jobId,
    String? prompt,
    String? schedule,
    String? name,
    bool? toastNotifications,
  }) async {
    final json = await _client.updateCron(
      jobId: jobId,
      prompt: prompt,
      schedule: schedule,
      name: name,
      toastNotifications: toastNotifications,
    );
    return CronMutationResponse.fromJson(_asMap(json));
  }

  @override
  Future<CronMutationResponse> deleteJob(String jobId) async {
    final json = await _client.deleteCron(jobId);
    return CronMutationResponse.fromJson(_asMap(json));
  }

  @override
  Future<CronMutationResponse> runJob(String jobId) async {
    final json = await _client.runCron(jobId);
    return CronMutationResponse.fromJson(_asMap(json));
  }

  @override
  Future<CronMutationResponse> pauseJob(String jobId) async {
    final json = await _client.pauseCron(jobId);
    return CronMutationResponse.fromJson(_asMap(json));
  }

  @override
  Future<CronMutationResponse> resumeJob(String jobId) async {
    final json = await _client.resumeCron(jobId);
    return CronMutationResponse.fromJson(_asMap(json));
  }

  @override
  Future<CronOutputResponse> fetchOutput(String jobId, {int? limit}) async {
    final json = await _client.cronOutput(jobId, limit: limit);
    return CronOutputResponse.fromJson(_asMap(json));
  }

  static Map<String, Object?> _asMap(Object? json) =>
      json is Map<String, Object?> ? json : const <String, Object?>{};
}
