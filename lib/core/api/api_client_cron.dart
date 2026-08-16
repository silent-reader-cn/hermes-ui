import 'api_client.dart';
import 'endpoints.dart';

/// cron 域方法（10 个端点）。
///
/// 返回类型暂为 `Object?`（解码后的 JSON）；TODO(merge)：模型就绪后改为对应
/// 类型并 `return XxxResponse.fromJson(json)`。
extension ApiClientCron on ApiClient {
  /// GET /api/crons。
  Future<Object?> crons() => sendJson(Endpoint.crons);

  /// POST /api/crons/create。
  Future<Object?> createCron({
    required String prompt,
    required String schedule,
    String? name,
    String? deliver,
    List<String> skills = const [],
    String? model,
    String? provider,
    String? profile,
    required bool toastNotifications,
  }) => sendJson(
    Endpoint.cronCreate,
    method: 'POST',
    body: {
      'prompt': prompt,
      'schedule': schedule,
      'name': ?name,
      'deliver': ?deliver,
      'skills': skills,
      'model': ?model,
      'provider': ?provider,
      'profile': ?profile,
      'toast_notifications': toastNotifications,
    },
  );

  /// POST /api/crons/update（全部字段可空）。
  Future<Object?> updateCron({
    required String jobId,
    String? prompt,
    String? schedule,
    String? name,
    String? deliver,
    List<String>? skills,
    String? model,
    String? provider,
    String? profile,
    bool? toastNotifications,
  }) => sendJson(
    Endpoint.cronUpdate,
    method: 'POST',
    body: {
      'job_id': jobId,
      'prompt': ?prompt,
      'schedule': ?schedule,
      'name': ?name,
      'deliver': ?deliver,
      'skills': ?skills,
      'model': ?model,
      'provider': ?provider,
      'profile': ?profile,
      'toast_notifications': ?toastNotifications,
    },
  );

  /// POST /api/crons/delete {job_id}（reason 传 nil 不发键）。
  Future<Object?> deleteCron(String jobId) =>
      sendJson(Endpoint.cronDelete, method: 'POST', body: {'job_id': jobId});

  /// POST /api/crons/run {job_id}。
  Future<Object?> runCron(String jobId) =>
      sendJson(Endpoint.cronRun, method: 'POST', body: {'job_id': jobId});

  /// POST /api/crons/pause {job_id, reason?}。
  Future<Object?> pauseCron(String jobId, {String? reason}) => sendJson(
    Endpoint.cronPause,
    method: 'POST',
    body: {'job_id': jobId, 'reason': ?reason},
  );

  /// POST /api/crons/resume {job_id}。
  Future<Object?> resumeCron(String jobId) =>
      sendJson(Endpoint.cronResume, method: 'POST', body: {'job_id': jobId});

  /// GET /api/crons/status（job_id 可选，nil 时不发）。
  Future<Object?> cronStatus([String? jobId]) =>
      sendJson(Endpoint.cronStatus(jobId));

  /// GET /api/crons/output?job_id=&limit?=（limit 默认 5）。
  Future<Object?> cronOutput(String jobId, {int? limit = 5}) =>
      sendJson(Endpoint.cronOutput(jobId: jobId, limit: limit));

  /// GET /api/crons/delivery-options。
  Future<Object?> cronDeliveryOptions() =>
      sendJson(Endpoint.cronDeliveryOptions);
}
