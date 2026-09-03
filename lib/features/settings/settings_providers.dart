import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_client_extensions.dart';
import '../../core/api/api_client_mcp.dart';
import '../../core/api/api_client_server_panels.dart';
import '../../core/api/api_exception.dart';
import '../../core/api/custom_header.dart';
import '../../core/connections/connection_providers.dart';
import '../../core/models/auxiliary_model.dart';
import '../../core/models/extensions.dart';
import '../../core/models/mcp.dart';
import '../../core/models/server_catalog.dart';

/// 版本号平台通道异常/测试环境时的回退值（历史常量，避免空显示）。
const String appVersionFallback = '1.0.0+1';

/// 应用版本号（动态读取：package_info_plus 从系统取 pubspec `version`
/// 生成的 versionName + versionCode，如 `0.1.2+4`；平台通道不可用时
/// 回退 [appVersionFallback]）。
final appVersionProvider = FutureProvider<String>((ref) async {
  try {
    final info = await PackageInfo.fromPlatform();
    final version = info.version;
    final build = info.buildNumber;
    return (build.isEmpty || build == '0') ? version : '$version+$build';
  } catch (_) {
    return appVersionFallback;
  }
});

/// 设置页所需的最小服务器 API 面。
///
/// 生产实现 [SettingsApiClient] 包 [ApiClient]（模型在客户端解码）；测试注入
/// 纯 Dart fake，彻底绕开网络/事件循环（对齐 session_list / onboarding 的
/// 接口抽象 + 工厂注入模式）。
abstract interface class SettingsApi {
  /// GET /api/models → 缓存模型目录（groups / default_model / active_provider）。
  Future<ModelsResponse> models();

  /// GET /api/models/live → 实时未缓存模型列表（对齐 iOS overlayLiveModels）。
  Future<ModelsLiveResponse> modelsLive();

  /// POST /api/models/refresh {provider} → 刷新指定 provider（或当前 provider）的模型缓存。
  Future<ModelsRefreshResponse> refreshModels({String? provider});

  /// POST /api/default-model {model}。
  Future<DefaultModelResponse> saveDefaultModel(String model);

  /// GET /api/reasoning（model/provider 非空才发 query）。
  Future<ReasoningStatusResponse> reasoning({String? model, String? provider});

  /// POST /api/reasoning {effort}。
  Future<ReasoningStatusResponse> saveReasoningEffort(String effort);

  // ---------------------------------------------------------------------------
  // Extensions 生态（6 个方法）
  // ---------------------------------------------------------------------------

  /// GET /api/extensions/status → 获取已安装扩展状态。
  Future<ExtensionsStatusResponse> extensionsStatus();

  /// GET /api/extensions/registry → 获取可安装扩展源清单。
  Future<ExtensionsRegistryResponse> extensionsRegistry();

  /// POST /api/extensions/toggle {id, enabled} → 启用/停用指定扩展。
  Future<ExtensionToggleResponse> toggleExtension(String id, bool enabled);

  /// POST /api/extensions/install {id, download_url, sha256} → 安装扩展。
  Future<ExtensionInstallResponse> installExtension({
    required String id,
    required String downloadUrl,
    required String sha256,
  });

  /// POST /api/extensions/uninstall {id} → 卸载指定扩展。
  Future<ExtensionUninstallResponse> uninstallExtension(String id);

  /// POST /api/extensions/sidecar-proxy-consent {id, approved} → Sidecar 代理授权。
  Future<ExtensionConsentResponse> setExtensionSidecarConsent(
    String id,
    bool approved,
  );

  // ---------------------------------------------------------------------------
  // MCP 服务器管理（5 个方法）
  // ---------------------------------------------------------------------------

  /// GET /api/mcp/servers → 获取已配置 MCP 服务器列表。
  Future<McpServersResponse> mcpServers();

  /// GET /api/mcp/tools → 获取 MCP 服务器提供的工具清单。
  Future<McpToolsResponse> mcpTools();

  /// PUT /api/mcp/servers/{name} → 新增或更新 MCP 服务器。
  Future<McpServerWriteResponse> saveMcpServer(
    String name, {
    required String command,
    required List<String> args,
    Map<String, String>? env,
    bool enabled = true,
  });

  /// PATCH /api/mcp/servers/{name} {enabled} → 启用/停用指定 MCP 服务器。
  Future<McpServerToggleResponse> toggleMcpServer(String name, bool enabled);

  /// DELETE /api/mcp/servers/{name} → 删除指定 MCP 服务器。
  Future<McpServerDeleteResponse> deleteMcpServer(String name);

  // ---------------------------------------------------------------------------
  // 辅助模型（2 个方法）
  // ---------------------------------------------------------------------------

  /// GET /api/model/auxiliary → 获取 11 个 canonical tasks 绑定及主模型。
  Future<AuxiliaryModelsResponse> auxiliaryModels();

  /// POST /api/model/set {scope: 'auxiliary', task, provider, model, advanced} → 设置辅助模型。
  Future<ModelSetResponse> setAuxiliaryModel({
    required String task,
    required String provider,
    required String model,
    Map<String, dynamic>? advanced,
  });
}

/// [SettingsApi] 的生产实现：包 [ApiClient]。
///
/// ⚠️ 方法一律**透传** [ApiClient] 的 typed 结果：`ApiClientServerPanels`
/// 扩展（models / saveDefaultModel / reasoning / auxiliaryModels 等）及扩展/MCP 扩展
/// 已把 raw JSON 解码为模型，这里严禁 `fromJson(_asMap(...))` 二次解析
/// （2026-08 实锤 bug：二次解析会把已解码对象兜底成空 map 导致字段全失）。
class SettingsApiClient implements SettingsApi {
  SettingsApiClient(this._client);

  final ApiClient _client;

  @override
  Future<ModelsResponse> models() => _client.models();

  @override
  Future<ModelsLiveResponse> modelsLive() => _client.modelsLive();

  @override
  Future<ModelsRefreshResponse> refreshModels({String? provider}) =>
      _client.refreshModels(provider: provider);

  @override
  Future<DefaultModelResponse> saveDefaultModel(String model) =>
      _client.saveDefaultModel(model);

  @override
  Future<ReasoningStatusResponse> reasoning({
    String? model,
    String? provider,
  }) => _client.reasoning(model: model, provider: provider);

  @override
  Future<ReasoningStatusResponse> saveReasoningEffort(String effort) =>
      _client.saveReasoningEffort(effort);

  @override
  Future<ExtensionsStatusResponse> extensionsStatus() =>
      _client.extensionsStatus();

  @override
  Future<ExtensionsRegistryResponse> extensionsRegistry() =>
      _client.extensionsRegistry();

  @override
  Future<ExtensionToggleResponse> toggleExtension(String id, bool enabled) =>
      _client.toggleExtension(id, enabled);

  @override
  Future<ExtensionInstallResponse> installExtension({
    required String id,
    required String downloadUrl,
    required String sha256,
  }) => _client.installExtension(
    id: id,
    downloadUrl: downloadUrl,
    sha256: sha256,
  );

  @override
  Future<ExtensionUninstallResponse> uninstallExtension(String id) =>
      _client.uninstallExtension(id);

  @override
  Future<ExtensionConsentResponse> setExtensionSidecarConsent(
    String id,
    bool approved,
  ) => _client.setExtensionSidecarConsent(id, approved);

  @override
  Future<McpServersResponse> mcpServers() => _client.mcpServers();

  @override
  Future<McpToolsResponse> mcpTools() => _client.mcpTools();

  @override
  Future<McpServerWriteResponse> saveMcpServer(
    String name, {
    required String command,
    required List<String> args,
    Map<String, String>? env,
    bool enabled = true,
  }) => _client.saveMcpServer(
    name,
    command: command,
    args: args,
    env: env,
    enabled: enabled,
  );

  @override
  Future<McpServerToggleResponse> toggleMcpServer(String name, bool enabled) =>
      _client.toggleMcpServer(name, enabled);

  @override
  Future<McpServerDeleteResponse> deleteMcpServer(String name) =>
      _client.deleteMcpServer(name);

  @override
  Future<AuxiliaryModelsResponse> auxiliaryModels() =>
      _client.auxiliaryModels();

  @override
  Future<ModelSetResponse> setAuxiliaryModel({
    required String task,
    required String provider,
    required String model,
    Map<String, dynamic>? advanced,
  }) => _client.setAuxiliaryModel(
    task: task,
    provider: provider,
    model: model,
    advanced: advanced,
  );
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
    this.isRefreshingModels = false,
    this.refreshError,
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

  /// 刷新中状态（防重入 + UI 加载指示器）。
  final bool isRefreshingModels;

  /// 最近一次模型刷新错误提示（UI 展示后清除）。
  final String? refreshError;

  /// 全部模型选项（展平各分组 models + extraModels，大小写归一去重保序）。
  List<ModelCatalogOption> get allModels {
    final result = <ModelCatalogOption>[];
    final seen = <String>{};
    for (final group in modelGroups) {
      for (final model in [...group.models, ...group.extraModels]) {
        final normId = model.id
            .toLowerCase()
            .replaceAll(' ', '-')
            .replaceAll('_', '-');
        final key = model.providerID == null
            ? normId
            : '${model.providerID!.toLowerCase()}/$normId';
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
    bool? isRefreshingModels,
    String? Function()? refreshError,
  }) {
    return SettingsState(
      modelGroups: modelGroups ?? this.modelGroups,
      defaultModel: defaultModel != null ? defaultModel() : this.defaultModel,
      activeProvider: activeProvider != null
          ? activeProvider()
          : this.activeProvider,
      reasoningEffort: reasoningEffort != null
          ? reasoningEffort()
          : this.reasoningEffort,
      supportedEfforts: supportedEfforts ?? this.supportedEfforts,
      supportsReasoningEffort:
          supportsReasoningEffort ?? this.supportsReasoningEffort,
      actionError: actionError != null ? actionError() : this.actionError,
      isRefreshingModels: isRefreshingModels ?? this.isRefreshingModels,
      refreshError: refreshError != null ? refreshError() : this.refreshError,
    );
  }

  @override
  String toString() =>
      'SettingsState(models: ${modelGroups.length}, defaultModel: $defaultModel, '
      'reasoningEffort: $reasoningEffort, isRefreshingModels: $isRefreshingModels)';
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
    final catalog = modelsResponse.catalogGroups;
    final merged = await _tryOverlayLiveModels(api, catalog);
    final reasoning = await _tryLoadReasoning(api);
    return SettingsState(
      modelGroups: merged,
      defaultModel: modelsResponse.defaultModel,
      activeProvider: modelsResponse.activeProvider,
      reasoningEffort: reasoning?.effectiveEffort,
      supportedEfforts: reasoning?.normalizedSupportedEfforts ?? const [],
      supportsReasoningEffort: reasoning?.supportsReasoningEffort ?? false,
    );
  }

  /// 活跃 provider 的实时列表覆盖缓存分组（对齐 iOS `overlayLiveModels` →
  /// `mergingLiveModels`；失败静默保留缓存，见 #236）。
  Future<List<ModelCatalogGroup>> _tryOverlayLiveModels(
    SettingsApi api,
    List<ModelCatalogGroup> cached,
  ) async {
    try {
      final live = await api.modelsLive();
      return cached.mergingLiveModels(live);
    } catch (_) {
      return cached;
    }
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

  /// 刷新模型目录（防重入 + 对接 POST /api/models/refresh + 错误提示不破坏既有数据状态）。
  Future<bool> refreshModels({String? provider}) async {
    final current = state.valueOrNull;
    if (current == null) return false;
    if (current.isRefreshingModels) return false;

    state = AsyncData(
      current.copyWith(
        isRefreshingModels: true,
        refreshError: () => null,
      ),
    );

    try {
      final targetProvider = provider ?? current.activeProvider;
      if (targetProvider != null && targetProvider.isNotEmpty) {
        await _api.refreshModels(provider: targetProvider);
      }
      final modelsResponse = await _api.models();
      final merged = await _tryOverlayLiveModels(
        _api,
        modelsResponse.catalogGroups,
      );
      final latest = state.valueOrNull ?? current;
      state = AsyncData(
        latest.copyWith(
          modelGroups: merged,
          defaultModel: () => modelsResponse.defaultModel,
          activeProvider: () => modelsResponse.activeProvider,
          isRefreshingModels: false,
          refreshError: () => null,
        ),
      );
      return true;
    } on ApiException catch (error) {
      final latest = state.valueOrNull ?? current;
      state = AsyncData(
        latest.copyWith(
          isRefreshingModels: false,
          refreshError: () => error.message,
        ),
      );
      return false;
    } catch (error) {
      final latest = state.valueOrNull ?? current;
      state = AsyncData(
        latest.copyWith(
          isRefreshingModels: false,
          refreshError: () => error.toString(),
        ),
      );
      return false;
    }
  }

  /// 清除模型刷新错误标记。
  void clearRefreshError() {
    final current = state.valueOrNull;
    if (current == null || current.refreshError == null) return;
    state = AsyncData(current.copyWith(refreshError: () => null));
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
          reasoningEffort: () =>
              saved == null || saved.isEmpty ? effort : saved,
          supportedEfforts: response.normalizedSupportedEfforts.isEmpty
              ? current.supportedEfforts
              : response.normalizedSupportedEfforts,
          supportsReasoningEffort:
              response.supportsReasoningEffort ??
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

// -----------------------------------------------------------------------------
// Extensions 控制器与状态
// -----------------------------------------------------------------------------

/// 扩展生态状态（AsyncNotifier 载荷）。
class ExtensionsState {
  const ExtensionsState({
    this.systemEnabled = false,
    this.extensions = const [],
    this.registry = const [],
    this.actionError,
  });

  /// 系统扩展总开关（只读展示）。
  final bool systemEnabled;

  /// 已安装扩展列表。
  final List<ExtensionInfo> extensions;

  /// 可安装扩展清单（注册表）。
  final List<ExtensionRegistryItem> registry;

  /// 最近一次操作错误。
  final String? actionError;

  ExtensionsState copyWith({
    bool? systemEnabled,
    List<ExtensionInfo>? extensions,
    List<ExtensionRegistryItem>? registry,
    String? Function()? actionError,
  }) {
    return ExtensionsState(
      systemEnabled: systemEnabled ?? this.systemEnabled,
      extensions: extensions ?? this.extensions,
      registry: registry ?? this.registry,
      actionError: actionError != null ? actionError() : this.actionError,
    );
  }

  @override
  String toString() =>
      'ExtensionsState(systemEnabled: $systemEnabled, extensions: ${extensions.length}, '
      'registry: ${registry.length}, actionError: $actionError)';
}

/// 扩展控制器 Provider。
final extensionsControllerProvider =
    AsyncNotifierProvider<ExtensionsController, ExtensionsState>(
      ExtensionsController.new,
    );

class ExtensionsController extends AsyncNotifier<ExtensionsState> {
  SettingsApi get _api =>
      ref.read(settingsApiFactoryProvider)(ref.read(apiClientProvider));

  @override
  Future<ExtensionsState> build() async {
    final api = ref.watch(settingsApiFactoryProvider)(
      ref.watch(apiClientProvider),
    );
    return _load(api);
  }

  Future<ExtensionsState> _load(SettingsApi api) async {
    final status = await api.extensionsStatus();
    final registry = await _tryLoadRegistry(api);
    return ExtensionsState(
      systemEnabled: status.enabled,
      extensions: status.extensions,
      registry: registry ?? const [],
    );
  }

  Future<List<ExtensionRegistryItem>?> _tryLoadRegistry(SettingsApi api) async {
    try {
      final res = await api.extensionsRegistry();
      return res.registry;
    } on ApiException {
      return null;
    }
  }

  /// 刷新扩展状态与注册表。
  Future<void> refresh() async {
    try {
      state = AsyncData(await _load(_api));
    } on Exception catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
    }
  }

  /// 启用/停用指定扩展。
  Future<bool> toggleExtension(String id, bool enabled) async {
    final current = state.valueOrNull;
    if (current == null) return false;
    try {
      await _api.toggleExtension(id, enabled);
      await refresh();
      return true;
    } on ApiException catch (error) {
      state = AsyncData(current.copyWith(actionError: () => error.message));
      return false;
    }
  }

  /// 安装扩展。
  Future<bool> installExtension({
    required String id,
    required String downloadUrl,
    required String sha256,
  }) async {
    final current = state.valueOrNull;
    if (current == null) return false;
    try {
      await _api.installExtension(
        id: id,
        downloadUrl: downloadUrl,
        sha256: sha256,
      );
      await refresh();
      return true;
    } on ApiException catch (error) {
      state = AsyncData(current.copyWith(actionError: () => error.message));
      return false;
    }
  }

  /// 卸载指定扩展。
  Future<bool> uninstallExtension(String id) async {
    final current = state.valueOrNull;
    if (current == null) return false;
    try {
      await _api.uninstallExtension(id);
      await refresh();
      return true;
    } on ApiException catch (error) {
      state = AsyncData(current.copyWith(actionError: () => error.message));
      return false;
    }
  }

  /// 设置指定扩展的 Sidecar 代理授权。
  Future<bool> setSidecarConsent(String id, bool approved) async {
    final current = state.valueOrNull;
    if (current == null) return false;
    try {
      await _api.setExtensionSidecarConsent(id, approved);
      await refresh();
      return true;
    } on ApiException catch (error) {
      state = AsyncData(current.copyWith(actionError: () => error.message));
      return false;
    }
  }

  /// 清除操作错误标记。
  Future<void> clearActionError() async {
    final current = state.valueOrNull;
    if (current == null || current.actionError == null) return;
    state = AsyncData(current.copyWith(actionError: () => null));
  }
}

// -----------------------------------------------------------------------------
// MCP 控制器与状态
// -----------------------------------------------------------------------------

/// MCP 服务器管理状态（AsyncNotifier 载荷）。
class McpState {
  const McpState({
    this.servers = const [],
    this.tools = const [],
    this.actionError,
  });

  /// 已配置 MCP 服务器列表。
  final List<McpServer> servers;

  /// 全部 MCP 工具清单。
  final List<McpTool> tools;

  /// 最近一次操作错误。
  final String? actionError;

  McpState copyWith({
    List<McpServer>? servers,
    List<McpTool>? tools,
    String? Function()? actionError,
  }) {
    return McpState(
      servers: servers ?? this.servers,
      tools: tools ?? this.tools,
      actionError: actionError != null ? actionError() : this.actionError,
    );
  }

  @override
  String toString() =>
      'McpState(servers: ${servers.length}, tools: ${tools.length}, actionError: $actionError)';
}

/// MCP 控制器 Provider。
final mcpControllerProvider = AsyncNotifierProvider<McpController, McpState>(
  McpController.new,
);

class McpController extends AsyncNotifier<McpState> {
  SettingsApi get _api =>
      ref.read(settingsApiFactoryProvider)(ref.read(apiClientProvider));

  @override
  Future<McpState> build() async {
    final api = ref.watch(settingsApiFactoryProvider)(
      ref.watch(apiClientProvider),
    );
    return _load(api);
  }

  Future<McpState> _load(SettingsApi api) async {
    final serversResponse = await api.mcpServers();
    final tools = await _tryLoadTools(api);
    return McpState(servers: serversResponse.servers, tools: tools ?? const []);
  }

  Future<List<McpTool>?> _tryLoadTools(SettingsApi api) async {
    try {
      final res = await api.mcpTools();
      return res.tools;
    } on ApiException {
      return null;
    }
  }

  /// 刷新 MCP 服务器与工具列表。
  Future<void> refresh() async {
    try {
      state = AsyncData(await _load(_api));
    } on Exception catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
    }
  }

  /// 启用/停用指定 MCP 服务器。
  Future<bool> toggleServer(String name, bool enabled) async {
    final current = state.valueOrNull;
    if (current == null) return false;
    try {
      await _api.toggleMcpServer(name, enabled);
      await refresh();
      return true;
    } on ApiException catch (error) {
      state = AsyncData(current.copyWith(actionError: () => error.message));
      return false;
    }
  }

  /// 保存（新增/更新）MCP 服务器。
  Future<bool> saveServer(
    String name, {
    required String command,
    required List<String> args,
    Map<String, String>? env,
    bool enabled = true,
  }) async {
    final current = state.valueOrNull;
    if (current == null) return false;
    try {
      await _api.saveMcpServer(
        name,
        command: command,
        args: args,
        env: env,
        enabled: enabled,
      );
      await refresh();
      return true;
    } on ApiException catch (error) {
      state = AsyncData(current.copyWith(actionError: () => error.message));
      return false;
    }
  }

  /// 删除指定 MCP 服务器。
  Future<bool> deleteServer(String name) async {
    final current = state.valueOrNull;
    if (current == null) return false;
    try {
      await _api.deleteMcpServer(name);
      await refresh();
      return true;
    } on ApiException catch (error) {
      state = AsyncData(current.copyWith(actionError: () => error.message));
      return false;
    }
  }

  /// 清除操作错误标记。
  Future<void> clearActionError() async {
    final current = state.valueOrNull;
    if (current == null || current.actionError == null) return;
    state = AsyncData(current.copyWith(actionError: () => null));
  }
}

// -----------------------------------------------------------------------------
// 辅助模型控制器与状态
// -----------------------------------------------------------------------------

/// 辅助模型状态（AsyncNotifier 载荷）。
class AuxiliaryModelsState {
  const AuxiliaryModelsState({
    this.tasks = const [],
    this.main = const AuxMainModel(),
    this.actionError,
  });

  /// 11 个 canonical tasks 绑定槽位行。
  final List<AuxiliaryTaskRow> tasks;

  /// 主模型信息。
  final AuxMainModel main;

  /// 最近一次操作错误。
  final String? actionError;

  AuxiliaryModelsState copyWith({
    List<AuxiliaryTaskRow>? tasks,
    AuxMainModel? main,
    String? Function()? actionError,
  }) {
    return AuxiliaryModelsState(
      tasks: tasks ?? this.tasks,
      main: main ?? this.main,
      actionError: actionError != null ? actionError() : this.actionError,
    );
  }

  @override
  String toString() =>
      'AuxiliaryModelsState(tasks: ${tasks.length}, main: ${main.model}, actionError: $actionError)';
}

/// 辅助模型控制器 Provider。
final auxiliaryModelsControllerProvider =
    AsyncNotifierProvider<AuxiliaryModelsController, AuxiliaryModelsState>(
      AuxiliaryModelsController.new,
    );

class AuxiliaryModelsController extends AsyncNotifier<AuxiliaryModelsState> {
  SettingsApi get _api =>
      ref.read(settingsApiFactoryProvider)(ref.read(apiClientProvider));

  @override
  Future<AuxiliaryModelsState> build() async {
    final api = ref.watch(settingsApiFactoryProvider)(
      ref.watch(apiClientProvider),
    );
    return _load(api);
  }

  Future<AuxiliaryModelsState> _load(SettingsApi api) async {
    final response = await api.auxiliaryModels();
    return AuxiliaryModelsState(tasks: response.tasks, main: response.main);
  }

  /// 刷新辅助模型配置。
  Future<void> refresh() async {
    try {
      state = AsyncData(await _load(_api));
    } on Exception catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
    }
  }

  /// 设置指定 task 的辅助模型绑定。
  Future<bool> setAuxiliaryModel({
    required String task,
    required String provider,
    required String model,
    Map<String, dynamic>? advanced,
  }) async {
    final current = state.valueOrNull;
    if (current == null) return false;
    try {
      await _api.setAuxiliaryModel(
        task: task,
        provider: provider,
        model: model,
        advanced: advanced,
      );
      await refresh();
      return true;
    } on ApiException catch (error) {
      state = AsyncData(current.copyWith(actionError: () => error.message));
      return false;
    }
  }

  /// 全部任务重置为自动。
  Future<bool> resetAllToAuto() async {
    final current = state.valueOrNull;
    if (current == null) return false;
    try {
      await _api.setAuxiliaryModel(
        task: '__reset__',
        provider: 'auto',
        model: '',
      );
      await refresh();
      return true;
    } on ApiException catch (error) {
      state = AsyncData(current.copyWith(actionError: () => error.message));
      return false;
    }
  }

  /// 清除操作错误标记。
  Future<void> clearActionError() async {
    final current = state.valueOrNull;
    if (current == null || current.actionError == null) return;
    state = AsyncData(current.copyWith(actionError: () => null));
  }
}

/// 服务器编辑页所需的 API 工厂：根据 baseUrl 与 customHeaders 构造 [ApiClient]
/// （测试可 override 注入自定义 client / fake）。
typedef ServerEditorApiClientFactory = ApiClient Function(
  String baseUrl,
  List<CustomHeader> headers,
);

final serverEditorApiClientFactoryProvider =
    Provider<ServerEditorApiClientFactory>(
      (ref) =>
          (baseUrl, headers) =>
              ApiClient(baseUrl: baseUrl, initialHeaders: headers),
    );

// -----------------------------------------------------------------------------
// 新建会话自动打开上下文指示器弹窗开关与临时会话跟踪
// -----------------------------------------------------------------------------

/// 新建会话自动打开上下文指示器弹窗偏好设置键。
const String kAutoOpenContextOnNewSessionKey =
    'settings.autoOpenContextOnNewSession';

/// 新建会话自动打开上下文指示器弹窗偏好设置 Provider（持久化到 shared_preferences，默认关闭）。
final autoOpenContextOnNewSessionProvider =
    NotifierProvider<AutoOpenContextOnNewSessionController, bool>(
      AutoOpenContextOnNewSessionController.new,
    );

/// 新建会话自动打开上下文指示器弹窗控制器。
class AutoOpenContextOnNewSessionController extends Notifier<bool> {
  static const String keyAutoOpenContext = kAutoOpenContextOnNewSessionKey;

  static Future<bool> loadPref({SharedPreferences? customPrefs}) async {
    try {
      final prefs = customPrefs ?? await SharedPreferences.getInstance();
      return prefs.getBool(keyAutoOpenContext) ?? false;
    } catch (_) {
      return false;
    }
  }

  bool _hasCustomState = false;

  @override
  bool build() {
    _hasCustomState = false;
    unawaited(_load());
    return false;
  }

  Future<void> _load() async {
    try {
      final value = await loadPref();
      if (!_hasCustomState) {
        state = value;
      }
    } catch (_) {
      // Ignored in unit test environments.
    }
  }

  Future<void> load() => _load();

  Future<void> setEnabled(bool value) async {
    _hasCustomState = true;
    state = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(keyAutoOpenContext, value);
    } catch (_) {
      // Ignored in unit test environments.
    }
  }
}

/// 最近新建会话 ID Provider（用于通知 ChatInputBar 首次进入时自动打开上下文弹窗；消费后立即置空）。
final recentlyCreatedSessionIdProvider =
    NotifierProvider<RecentlyCreatedSessionIdController, String?>(
      RecentlyCreatedSessionIdController.new,
    );

/// 最近新建会话 ID 控制器。
class RecentlyCreatedSessionIdController extends Notifier<String?> {
  @override
  String? build() => null;

  void markCreated(String sessionId) {
    state = sessionId;
  }

  void clear() {
    state = null;
  }
}
