import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_client_server_panels.dart';
import '../../core/api/api_exception.dart';
import '../../core/connections/connection_providers.dart';
import '../../core/models/server_catalog.dart';

/// 应用版本号（与 pubspec.yaml `version` 保持同步）。
const String appVersion = '1.0.0+1';

/// 设置页所需的最小服务器 API 面（models 域 4 个端点 + reasoning 双方法）。
///
/// 生产实现 [SettingsApiClient] 包 [ApiClient]（模型在客户端解码）；测试注入
/// 纯 Dart fake，彻底绕开网络/事件循环（对齐 session_list / onboarding 的
/// 接口抽象 + 工厂注入模式）。
abstract interface class SettingsApi {
  /// GET /api/models → 缓存模型目录（groups / default_model / active_provider）。
  Future<ModelsResponse> models();

  /// POST /api/default-model {model}。
  Future<DefaultModelResponse> saveDefaultModel(String model);

  /// GET /api/reasoning（model/provider 非空才发 query）。
  Future<ReasoningStatusResponse> reasoning({String? model, String? provider});

  /// POST /api/reasoning {effort}。
  Future<ReasoningStatusResponse> saveReasoningEffort(String effort);
}

/// [SettingsApi] 的生产实现：包 [ApiClient]，把 `Object?` JSON 解码为模型。
class SettingsApiClient implements SettingsApi {
  SettingsApiClient(this._client);

  final ApiClient _client;

  @override
  Future<ModelsResponse> models() async {
    final json = await _client.models();
    return ModelsResponse.fromJson(_asMap(json));
  }

  @override
  Future<DefaultModelResponse> saveDefaultModel(String model) async {
    final json = await _client.saveDefaultModel(model);
    return DefaultModelResponse.fromJson(_asMap(json));
  }

  @override
  Future<ReasoningStatusResponse> reasoning({
    String? model,
    String? provider,
  }) async {
    final json = await _client.reasoning(model: model, provider: provider);
    return ReasoningStatusResponse.fromJson(_asMap(json));
  }

  @override
  Future<ReasoningStatusResponse> saveReasoningEffort(String effort) async {
    final json = await _client.saveReasoningEffort(effort);
    return ReasoningStatusResponse.fromJson(_asMap(json));
  }

  static Map<String, Object?> _asMap(Object? json) =>
      json is Map<String, Object?> ? json : const <String, Object?>{};
}

/// 构建 [SettingsApi] 的工厂（测试可 override 注入 fake）。
typedef SettingsApiFactory = SettingsApi Function(ApiClient client);

final settingsApiFactoryProvider = Provider<SettingsApiFactory>(
  (ref) => SettingsApiClient.new,
);

/// 设置页状态（AsyncNotifier 的 AsyncData 载荷）。
class SettingsState {
  const SettingsState({
    this.modelGroups = const [],
    this.defaultModel,
    this.activeProvider,
    this.reasoningEffort,
    this.supportedEfforts = const [],
    this.supportsReasoningEffort = false,
    this.actionError,
  });

  /// 模型目录分组（来自 GET /api/models 的 groups，按 provider 分组）。
  final List<ModelCatalogGroup> modelGroups;

  /// 服务端默认模型 id。
  final String? defaultModel;

  /// 服务端回显的活跃 provider id。
  final String? activeProvider;

  /// 当前推理强度（reasoning_effort ?? effort）。
  final String? reasoningEffort;

  /// 服务器支持的推理强度列表（normalized；为空 = 服务器未下发）。
  final List<String> supportedEfforts;

  /// 当前默认模型是否支持推理强度调节（false = 隐藏设置项）。
  final bool supportsReasoningEffort;

  /// 最近一次保存操作错误（UI 弹窗展示后调用
  /// [SettingsController.clearActionError] 清除）。
  final String? actionError;

  /// 全部模型选项（展平各分组 models + extraModels，去重保序）。
  List<ModelCatalogOption> get allModels {
    final result = <ModelCatalogOption>[];
    final seen = <String>{};
    for (final group in modelGroups) {
      for (final model in [...group.models, ...group.extraModels]) {
        final key = model.providerID == null
            ? model.id
            : '${model.providerID}/${model.id}';
        if (seen.add(key)) result.add(model);
      }
    }
    return result;
  }

  /// 默认模型的显示名（目录中找不到时回退为 id 本身）。
  String? get defaultModelLabel {
    final id = defaultModel;
    if (id == null || id.isEmpty) return null;
    for (final option in allModels) {
      if (option.id == id) return option.displayName;
    }
    return id;
  }

  SettingsState copyWith({
    List<ModelCatalogGroup>? modelGroups,
    String? Function()? defaultModel,
    String? Function()? activeProvider,
    String? Function()? reasoningEffort,
    List<String>? supportedEfforts,
    bool? supportsReasoningEffort,
    String? Function()? actionError,
  }) {
    return SettingsState(
      modelGroups: modelGroups ?? this.modelGroups,
      defaultModel: defaultModel != null ? defaultModel() : this.defaultModel,
      activeProvider:
          activeProvider != null ? activeProvider() : this.activeProvider,
      reasoningEffort:
          reasoningEffort != null ? reasoningEffort() : this.reasoningEffort,
      supportedEfforts: supportedEfforts ?? this.supportedEfforts,
      supportsReasoningEffort:
          supportsReasoningEffort ?? this.supportsReasoningEffort,
      actionError: actionError != null ? actionError() : this.actionError,
    );
  }

  @override
  String toString() =>
      'SettingsState(models: ${modelGroups.length}, defaultModel: $defaultModel, '
      'reasoningEffort: $reasoningEffort)';
}

/// 设置页控制器：加载模型目录 / 默认模型 / 推理强度，保存默认模型与推理强度。
///
/// AsyncValue 语义：初始加载与 [refresh] 失败 → `AsyncError`（UI 展示错误态 +
/// 重试）；`reasoning` 加载失败不视为整体失败（旧服务器无该端点 → 隐藏推理
/// 设置项）；保存失败不改变主体状态，只设置 [SettingsState.actionError]。
final settingsControllerProvider =
    AsyncNotifierProvider<SettingsController, SettingsState>(
  SettingsController.new,
);

class SettingsController extends AsyncNotifier<SettingsState> {
  SettingsApi get _api =>
      ref.read(settingsApiFactoryProvider)(ref.read(apiClientProvider));

  @override
  Future<SettingsState> build() async {
    // watch：切换服务器（apiClientProvider 重建）或工厂被替换时自动重载。
    final api = ref.watch(settingsApiFactoryProvider)(
      ref.watch(apiClientProvider),
    );
    return _load(api);
  }

  Future<SettingsState> _load(SettingsApi api) async {
    final modelsResponse = await api.models();
    final reasoning = await _tryLoadReasoning(api);
    return SettingsState(
      modelGroups: modelsResponse.catalogGroups,
      defaultModel: modelsResponse.defaultModel,
      activeProvider: modelsResponse.activeProvider,
      reasoningEffort: reasoning?.effectiveEffort,
      supportedEfforts: reasoning?.normalizedSupportedEfforts ?? const [],
      supportsReasoningEffort: reasoning?.supportsReasoningEffort ?? false,
    );
  }

  /// reasoning 状态加载失败 → 返回 null（旧服务器无 /api/reasoning 或未配置
  /// 模型时服务端 4xx，设置页隐藏推理项，不阻断整体加载）。
  Future<ReasoningStatusResponse?> _tryLoadReasoning(SettingsApi api) async {
    try {
      return await api.reasoning();
    } on ApiException {
      return null;
    }
  }

  /// 下拉刷新 / 错误态重试：重新加载模型目录与推理状态。
  Future<void> refresh() async {
    try {
      state = AsyncData(await _load(_api));
    } on Exception catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
    }
  }

  /// 保存默认模型；成功后用服务器回显（缺失时回退请求值）更新状态。
  Future<bool> setDefaultModel(String model) async {
    final current = state.valueOrNull;
    if (current == null) return false;
    try {
      final response = await _api.saveDefaultModel(model);
      final saved = response.model == null || response.model!.isEmpty
          ? model
          : response.model!;
      state = AsyncData(current.copyWith(defaultModel: () => saved));
      return true;
    } on ApiException catch (error) {
      state = AsyncData(current.copyWith(actionError: () => error.message));
      return false;
    }
  }

  /// 保存推理强度；成功后用响应回显更新 supportedEfforts / supports。
  Future<bool> setReasoningEffort(String effort) async {
    final current = state.valueOrNull;
    if (current == null) return false;
    try {
      final response = await _api.saveReasoningEffort(effort);
      final saved = response.effectiveEffort;
      state = AsyncData(
        current.copyWith(
          reasoningEffort: () => saved == null || saved.isEmpty
              ? effort
              : saved,
          supportedEfforts: response.normalizedSupportedEfforts.isEmpty
              ? current.supportedEfforts
              : response.normalizedSupportedEfforts,
          supportsReasoningEffort: response.supportsReasoningEffort ??
              current.supportsReasoningEffort,
        ),
      );
      return true;
    } on ApiException catch (error) {
      state = AsyncData(current.copyWith(actionError: () => error.message));
      return false;
    }
  }

  /// 清除保存错误标记（UI 展示完弹窗后调用）。
  Future<void> clearActionError() async {
    final current = state.valueOrNull;
    if (current == null || current.actionError == null) return;
    state = AsyncData(current.copyWith(actionError: () => null));
  }
}

/// 全部模型选项（展平分组；供模型选择器使用）。
final settingsModelOptionsProvider = Provider<List<ModelCatalogOption>>((ref) {
  final state = ref.watch(settingsControllerProvider).valueOrNull;
  if (state == null) return const [];
  return state.allModels;
});
