import 'dart:async';

import 'package:hermes_ui/core/models/auxiliary_model.dart';
import 'package:hermes_ui/core/models/extensions.dart';
import 'package:hermes_ui/core/models/mcp.dart';
import 'package:hermes_ui/core/models/server_catalog.dart';
import 'package:hermes_ui/features/settings/settings_providers.dart';

/// 可配置的 [SettingsApi] fake（测试注入，彻底绕开网络）。
///
/// 默认返回空模型目录 + 无推理能力 + 空扩展/MCP/辅助模型；测试可按需配置
/// 各域响应 / 抛错，并通过计数器断言调用次数与参数。
class FakeSettingsApi implements SettingsApi {
  // ---------------------------------------------------------------------------
  // Models / Reasoning
  // ---------------------------------------------------------------------------

  /// `models()` 返回的模型目录。
  ModelsResponse modelsResponse = const ModelsResponse();

  /// `reasoning()` 返回的推理状态。
  ReasoningStatusResponse reasoningResponse = const ReasoningStatusResponse();

  /// `refreshModels()` 返回的响应。
  ModelsRefreshResponse refreshModelsResponse =
      const ModelsRefreshResponse(ok: true);

  /// 各方法抛出的异常（非 null 时优先于对应响应）。
  Object? modelsError;
  Object? reasoningError;
  Object? refreshModelsError;
  Object? saveDefaultModelError;
  Object? saveReasoningEffortError;

  /// 非 null 时 `models()` 挂起等待该 gate（测试加载态用）。
  Completer<void>? modelsGate;

  /// 非 null 时 `refreshModels()` 挂起等待该 gate（测试加载态用）。
  Completer<void>? refreshModelsGate;

  /// 非 null 时 `reasoning()` 挂起等待该 gate（测试加载态用）。
  Completer<void>? reasoningGate;

  int modelsCount = 0;
  int refreshModelsCount = 0;
  int reasoningCount = 0;
  int saveDefaultModelCount = 0;
  int saveReasoningEffortCount = 0;

  /// `refreshModels` 已收到的 provider（按调用顺序）。
  final List<String?> refreshModelsCalls = [];

  /// `saveDefaultModel` 已收到的模型 id（按调用顺序）。
  final List<String> defaultModelCalls = [];

  /// `saveReasoningEffort` 已收到的 effort（按调用顺序）。
  final List<String> reasoningEffortCalls = [];

  // ---------------------------------------------------------------------------
  // Extensions
  // ---------------------------------------------------------------------------

  ExtensionsStatusResponse extensionsStatusResponse =
      const ExtensionsStatusResponse();
  ExtensionsRegistryResponse extensionsRegistryResponse =
      const ExtensionsRegistryResponse();
  ExtensionToggleResponse extensionToggleResponse =
      const ExtensionToggleResponse(ok: true);
  ExtensionInstallResponse extensionInstallResponse =
      const ExtensionInstallResponse(ok: true);
  ExtensionUninstallResponse extensionUninstallResponse =
      const ExtensionUninstallResponse(ok: true);
  ExtensionConsentResponse extensionConsentResponse =
      const ExtensionConsentResponse(ok: true);

  Object? extensionsStatusError;
  Object? extensionsRegistryError;
  Object? toggleExtensionError;
  Object? installExtensionError;
  Object? uninstallExtensionError;
  Object? setExtensionSidecarConsentError;

  Completer<void>? extensionsStatusGate;

  int extensionsStatusCount = 0;
  int extensionsRegistryCount = 0;
  final List<(String id, bool enabled)> toggleExtensionCalls = [];
  final List<({String id, String downloadUrl, String sha256})>
      installExtensionCalls = [];
  final List<String> uninstallExtensionCalls = [];
  final List<(String id, bool approved)> setSidecarConsentCalls = [];

  // ---------------------------------------------------------------------------
  // MCP
  // ---------------------------------------------------------------------------

  McpServersResponse mcpServersResponse = const McpServersResponse();
  McpToolsResponse mcpToolsResponse = const McpToolsResponse();
  McpServerWriteResponse mcpServerWriteResponse =
      const McpServerWriteResponse(ok: true);
  McpServerToggleResponse mcpServerToggleResponse =
      const McpServerToggleResponse(ok: true);
  McpServerDeleteResponse mcpServerDeleteResponse =
      const McpServerDeleteResponse(ok: true);

  Object? mcpServersError;
  Object? mcpToolsError;
  Object? saveMcpServerError;
  Object? toggleMcpServerError;
  Object? deleteMcpServerError;

  Completer<void>? mcpServersGate;

  int mcpServersCount = 0;
  int mcpToolsCount = 0;
  final List<
      ({
        String name,
        String command,
        List<String> args,
        Map<String, String>? env,
        bool enabled,
      })> saveMcpServerCalls = [];
  final List<(String name, bool enabled)> toggleMcpServerCalls = [];
  final List<String> deleteMcpServerCalls = [];

  // ---------------------------------------------------------------------------
  // Auxiliary Models
  // ---------------------------------------------------------------------------

  AuxiliaryModelsResponse auxiliaryModelsResponse =
      const AuxiliaryModelsResponse();
  ModelSetResponse modelSetResponse = const ModelSetResponse(ok: true);

  Object? auxiliaryModelsError;
  Object? setAuxiliaryModelError;

  Completer<void>? auxiliaryModelsGate;

  int auxiliaryModelsCount = 0;
  final List<
      ({
        String task,
        String provider,
        String model,
        Map<String, dynamic>? advanced,
      })> setAuxiliaryModelCalls = [];

  // ---------------------------------------------------------------------------
  // SettingsApi 方法实现
  // ---------------------------------------------------------------------------

  @override
  Future<ModelsResponse> models() async {
    modelsCount++;
    final error = modelsError;
    if (error != null) throw error;
    final gate = modelsGate;
    if (gate != null) await gate.future;
    return modelsResponse;
  }

  @override
  Future<ModelsRefreshResponse> refreshModels({String? provider}) async {
    refreshModelsCount++;
    refreshModelsCalls.add(provider);
    final error = refreshModelsError;
    if (error != null) throw error;
    final gate = refreshModelsGate;
    if (gate != null) await gate.future;
    return refreshModelsResponse;
  }

  @override
  Future<ReasoningStatusResponse> reasoning({
    String? model,
    String? provider,
  }) async {
    reasoningCount++;
    final error = reasoningError;
    if (error != null) throw error;
    final gate = reasoningGate;
    if (gate != null) await gate.future;
    return reasoningResponse;
  }

  @override
  Future<DefaultModelResponse> saveDefaultModel(String model) async {
    saveDefaultModelCount++;
    defaultModelCalls.add(model);
    final error = saveDefaultModelError;
    if (error != null) throw error;
    return const DefaultModelResponse(ok: true);
  }

  @override
  Future<ReasoningStatusResponse> saveReasoningEffort(String effort) async {
    saveReasoningEffortCount++;
    reasoningEffortCalls.add(effort);
    final error = saveReasoningEffortError;
    if (error != null) throw error;
    return const ReasoningStatusResponse(
      ok: true,
      effort: '',
      reasoningEffort: '',
    );
  }

  @override
  Future<ExtensionsStatusResponse> extensionsStatus() async {
    extensionsStatusCount++;
    final error = extensionsStatusError;
    if (error != null) throw error;
    final gate = extensionsStatusGate;
    if (gate != null) await gate.future;
    return extensionsStatusResponse;
  }

  @override
  Future<ExtensionsRegistryResponse> extensionsRegistry() async {
    extensionsRegistryCount++;
    final error = extensionsRegistryError;
    if (error != null) throw error;
    return extensionsRegistryResponse;
  }

  @override
  Future<ExtensionToggleResponse> toggleExtension(
    String id,
    bool enabled,
  ) async {
    toggleExtensionCalls.add((id, enabled));
    final error = toggleExtensionError;
    if (error != null) throw error;
    return extensionToggleResponse;
  }

  @override
  Future<ExtensionInstallResponse> installExtension({
    required String id,
    required String downloadUrl,
    required String sha256,
  }) async {
    installExtensionCalls.add(
      (id: id, downloadUrl: downloadUrl, sha256: sha256),
    );
    final error = installExtensionError;
    if (error != null) throw error;
    return extensionInstallResponse;
  }

  @override
  Future<ExtensionUninstallResponse> uninstallExtension(String id) async {
    uninstallExtensionCalls.add(id);
    final error = uninstallExtensionError;
    if (error != null) throw error;
    return extensionUninstallResponse;
  }

  @override
  Future<ExtensionConsentResponse> setExtensionSidecarConsent(
    String id,
    bool approved,
  ) async {
    setSidecarConsentCalls.add((id, approved));
    final error = setExtensionSidecarConsentError;
    if (error != null) throw error;
    return extensionConsentResponse;
  }

  @override
  Future<McpServersResponse> mcpServers() async {
    mcpServersCount++;
    final error = mcpServersError;
    if (error != null) throw error;
    final gate = mcpServersGate;
    if (gate != null) await gate.future;
    return mcpServersResponse;
  }

  @override
  Future<McpToolsResponse> mcpTools() async {
    mcpToolsCount++;
    final error = mcpToolsError;
    if (error != null) throw error;
    return mcpToolsResponse;
  }

  @override
  Future<McpServerWriteResponse> saveMcpServer(
    String name, {
    required String command,
    required List<String> args,
    Map<String, String>? env,
    bool enabled = true,
  }) async {
    saveMcpServerCalls.add((
      name: name,
      command: command,
      args: args,
      env: env,
      enabled: enabled,
    ));
    final error = saveMcpServerError;
    if (error != null) throw error;
    return mcpServerWriteResponse;
  }

  @override
  Future<McpServerToggleResponse> toggleMcpServer(
    String name,
    bool enabled,
  ) async {
    toggleMcpServerCalls.add((name, enabled));
    final error = toggleMcpServerError;
    if (error != null) throw error;
    return mcpServerToggleResponse;
  }

  @override
  Future<McpServerDeleteResponse> deleteMcpServer(String name) async {
    deleteMcpServerCalls.add(name);
    final error = deleteMcpServerError;
    if (error != null) throw error;
    return mcpServerDeleteResponse;
  }

  @override
  Future<AuxiliaryModelsResponse> auxiliaryModels() async {
    auxiliaryModelsCount++;
    final error = auxiliaryModelsError;
    if (error != null) throw error;
    final gate = auxiliaryModelsGate;
    if (gate != null) await gate.future;
    return auxiliaryModelsResponse;
  }

  @override
  Future<ModelSetResponse> setAuxiliaryModel({
    required String task,
    required String provider,
    required String model,
    Map<String, dynamic>? advanced,
  }) async {
    setAuxiliaryModelCalls.add((
      task: task,
      provider: provider,
      model: model,
      advanced: advanced,
    ));
    final error = setAuxiliaryModelError;
    if (error != null) throw error;
    return modelSetResponse;
  }
}

