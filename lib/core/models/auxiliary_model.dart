import '../utils/equality.dart';
import '../utils/lossy_json.dart';

/// 辅助模型单个任务槽位行配置（11 个 canonical task）。
///
/// 后端 config.py AUXILIARY_TASK_CATALOG 对应：
/// vision / web_extract / compression / approval / mcp / title_generation /
/// skills_hub / curator / kanban_decomposer / profile_describer / triage_specifier
class AuxiliaryTaskRow {
  const AuxiliaryTaskRow({
    this.task = '',
    this.provider = 'auto',
    this.model = '',
    this.baseUrl = '',
    this.timeout = '',
    this.downloadTimeout = '',
    this.maxConcurrency = '',
    this.extraBody = const {},
    this.apiKeySet = false,
    this.label = '',
    this.description = '',
  });

  factory AuxiliaryTaskRow.fromJson(Map<String, Object?> json) {
    final rawExtra = json['extra_body'] ?? json['extraBody'];
    final extraBody = rawExtra is Map
        ? Map<String, dynamic>.from(rawExtra)
        : const <String, dynamic>{};

    return AuxiliaryTaskRow(
      task: lossyString(json, 'task') ?? '',
      provider: lossyString(json, 'provider') ?? 'auto',
      model: lossyString(json, 'model') ?? '',
      baseUrl: lossyString(json, 'base_url') ??
          lossyString(json, 'baseUrl') ??
          '',
      timeout: lossyString(json, 'timeout') ?? '',
      downloadTimeout: lossyString(json, 'download_timeout') ??
          lossyString(json, 'downloadTimeout') ??
          '',
      maxConcurrency: lossyString(json, 'max_concurrency') ??
          lossyString(json, 'maxConcurrency') ??
          '',
      extraBody: extraBody,
      apiKeySet: lossyBool(json, 'api_key_set') ??
          lossyBool(json, 'apiKeySet') ??
          false,
      label: lossyString(json, 'label') ?? '',
      description: lossyString(json, 'description') ?? '',
    );
  }

  final String task;
  final String provider;
  final String model;
  final String baseUrl;
  final String timeout;
  final String downloadTimeout;
  final String maxConcurrency;
  final Map<String, dynamic> extraBody;
  final bool apiKeySet;
  final String label;
  final String description;

  Map<String, Object?> toJson() => {
        'task': task,
        'provider': provider,
        'model': model,
        'base_url': baseUrl,
        'timeout': timeout,
        'download_timeout': downloadTimeout,
        'max_concurrency': maxConcurrency,
        if (extraBody.isNotEmpty) 'extra_body': extraBody,
        'api_key_set': apiKeySet,
        'label': label,
        'description': description,
      };

  @override
  bool operator ==(Object other) {
    return other is AuxiliaryTaskRow &&
        other.task == task &&
        other.provider == provider &&
        other.model == model &&
        other.baseUrl == baseUrl &&
        other.timeout == timeout &&
        other.downloadTimeout == downloadTimeout &&
        other.maxConcurrency == maxConcurrency &&
        deepEquals(other.extraBody, extraBody) &&
        other.apiKeySet == apiKeySet &&
        other.label == label &&
        other.description == description;
  }

  @override
  int get hashCode => Object.hash(
        task,
        provider,
        model,
        baseUrl,
        timeout,
        downloadTimeout,
        maxConcurrency,
        deepHash(extraBody),
        apiKeySet,
        label,
        description,
      );

  @override
  String toString() =>
      'AuxiliaryTaskRow(task: $task, provider: $provider, model: $model)';
}

/// 主模型信息（用于辅助模型面板顶层展示）。
class AuxMainModel {
  const AuxMainModel({
    this.provider = '',
    this.model = '',
    this.supportsFastTier = false,
    this.serviceTier = '',
    this.advanced = const {},
  });

  factory AuxMainModel.fromJson(Map<String, Object?> json) {
    final rawAdv = json['advanced'];
    final advanced = rawAdv is Map
        ? Map<String, dynamic>.from(rawAdv)
        : const <String, dynamic>{};

    return AuxMainModel(
      provider: lossyString(json, 'provider') ?? '',
      model: lossyString(json, 'model') ?? '',
      supportsFastTier: lossyBool(json, 'supports_fast_tier') ??
          lossyBool(json, 'supportsFastTier') ??
          false,
      serviceTier: lossyString(json, 'service_tier') ??
          lossyString(json, 'serviceTier') ??
          '',
      advanced: advanced,
    );
  }

  final String provider;
  final String model;
  final bool supportsFastTier;
  final String serviceTier;
  final Map<String, dynamic> advanced;

  Map<String, Object?> toJson() => {
        'provider': provider,
        'model': model,
        'supports_fast_tier': supportsFastTier,
        'service_tier': serviceTier,
        if (advanced.isNotEmpty) 'advanced': advanced,
      };

  @override
  bool operator ==(Object other) {
    return other is AuxMainModel &&
        other.provider == provider &&
        other.model == model &&
        other.supportsFastTier == supportsFastTier &&
        other.serviceTier == serviceTier &&
        deepEquals(other.advanced, advanced);
  }

  @override
  int get hashCode => Object.hash(
        provider,
        model,
        supportsFastTier,
        serviceTier,
        deepHash(advanced),
      );

  @override
  String toString() =>
      'AuxMainModel(provider: $provider, model: $model, serviceTier: $serviceTier)';
}

/// 辅助模型全量响应（GET /api/model/auxiliary）。
class AuxiliaryModelsResponse {
  const AuxiliaryModelsResponse({
    this.tasks = const [],
    this.main = const AuxMainModel(),
  });

  factory AuxiliaryModelsResponse.fromJson(Map<String, Object?> json) {
    final rawTasks = json['tasks'];
    final tasks = <AuxiliaryTaskRow>[];
    if (rawTasks is List) {
      for (final item in rawTasks) {
        if (item is Map) {
          tasks.add(
            AuxiliaryTaskRow.fromJson(Map<String, Object?>.from(item)),
          );
        }
      }
    }

    final rawMain = json['main'];
    final main = rawMain is Map
        ? AuxMainModel.fromJson(Map<String, Object?>.from(rawMain))
        : const AuxMainModel();

    return AuxiliaryModelsResponse(
      tasks: tasks,
      main: main,
    );
  }

  final List<AuxiliaryTaskRow> tasks;
  final AuxMainModel main;

  Map<String, Object?> toJson() => {
        'tasks': tasks.map((t) => t.toJson()).toList(),
        'main': main.toJson(),
      };

  @override
  bool operator ==(Object other) =>
      other is AuxiliaryModelsResponse &&
      deepEquals(other.tasks, tasks) &&
      other.main == main;

  @override
  int get hashCode => Object.hash(deepHash(tasks), main);

  @override
  String toString() =>
      'AuxiliaryModelsResponse(tasks: ${tasks.length}, main: $main)';
}

/// 设置模型响应（POST /api/model/set）。
class ModelSetResponse {
  const ModelSetResponse({
    this.ok = false,
    this.task = '',
    this.provider = '',
    this.model = '',
  });

  factory ModelSetResponse.fromJson(Map<String, Object?> json) {
    return ModelSetResponse(
      ok: lossyBool(json, 'ok') ?? false,
      task: lossyString(json, 'task') ?? '',
      provider: lossyString(json, 'provider') ?? '',
      model: lossyString(json, 'model') ?? '',
    );
  }

  final bool ok;
  final String task;
  final String provider;
  final String model;

  Map<String, Object?> toJson() => {
        'ok': ok,
        'task': task,
        'provider': provider,
        'model': model,
      };

  @override
  bool operator ==(Object other) {
    return other is ModelSetResponse &&
        other.ok == ok &&
        other.task == task &&
        other.provider == provider &&
        other.model == model;
  }

  @override
  int get hashCode => Object.hash(ok, task, provider, model);

  @override
  String toString() =>
      'ModelSetResponse(ok: $ok, task: $task, provider: $provider, model: $model)';
}
