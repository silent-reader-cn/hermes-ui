import 'api_client.dart';
import 'endpoints.dart';
import '../models/cron.dart';

/// cron 域方法（10 个端点）。
extension ApiClientCron on ApiClient {
  /// GET /api/crons。
  Future<CronJobsResponse> crons() async {
    final json = await sendJson(Endpoint.crons);
    return CronJobsResponse.fromJson(_asMap(json));
  }

  /// POST /api/crons/create。
  Future<CronMutationResponse> createCron({
    required String prompt,
    required String schedule,
    String? name,
    String? deliver,
    List<String> skills = const [],
    String? model,
    String? provider,
    String? profile,
    required bool toastNotifications,
  }) async {
    final json = await sendJson(
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
    return CronMutationResponse.fromJson(_asMap(json));
  }

  /// POST /api/crons/update（全部字段可空）。
  Future<CronMutationResponse> updateCron({
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
  }) async {
    final json = await sendJson(
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
    return CronMutationResponse.fromJson(_asMap(json));
  }

  /// POST /api/crons/delete {job_id}（reason 传 nil 不发键）。
  Future<CronMutationResponse> deleteCron(String jobId) async {
    final json = await sendJson(
      Endpoint.cronDelete,
      method: 'POST',
      body: {'job_id': jobId},
    );
    return CronMutationResponse.fromJson(_asMap(json));
  }

  /// POST /api/crons/run {job_id}。
  Future<CronMutationResponse> runCron(String jobId) async {
    final json = await sendJson(
      Endpoint.cronRun,
      method: 'POST',
      body: {'job_id': jobId},
    );
    return CronMutationResponse.fromJson(_asMap(json));
  }

  /// POST /api/crons/pause {job_id, reason?}。
  Future<CronMutationResponse> pauseCron(String jobId, {String? reason}) async {
    final json = await sendJson(
      Endpoint.cronPause,
      method: 'POST',
      body: {'job_id': jobId, 'reason': ?reason},
    );
    return CronMutationResponse.fromJson(_asMap(json));
  }

  /// POST /api/crons/resume {job_id}。
  Future<CronMutationResponse> resumeCron(String jobId) async {
    final json = await sendJson(
      Endpoint.cronResume,
      method: 'POST',
      body: {'job_id': jobId},
    );
    return CronMutationResponse.fromJson(_asMap(json));
  }

  /// GET /api/crons/status（job_id 可选，nil 时不发）。
  Future<CronStatusResponse> cronStatus([String? jobId]) async {
    final json = await sendJson(Endpoint.cronStatus(jobId));
    return CronStatusResponse.fromJson(_asMap(json));
  }

  /// GET /api/crons/output?job_id=&limit?=（limit 默认 5）。
  Future<CronOutputResponse> cronOutput(String jobId, {int? limit = 5}) async {
    final json = await sendJson(
      Endpoint.cronOutput(jobId: jobId, limit: limit),
    );
    return CronOutputResponse.fromJson(_asMap(json));
  }

  /// GET /api/crons/delivery-options。
  Future<CronDeliveryOptionsResponse> cronDeliveryOptions() async {
    final json = await sendJson(Endpoint.cronDeliveryOptions);
    return CronDeliveryOptionsResponse.fromJson(_asMap(json));
  }
}

Map<String, Object?> _asMap(Object? json) =>
    json is Map<String, Object?>
        ? json
        : (json is Map ? Map<String, Object?>.from(json) : const <String, Object?>{});
