import 'dart:async';

import 'package:hermex_flutter/core/models/server_catalog.dart';
import 'package:hermex_flutter/features/settings/settings_providers.dart';

/// 可配置的 [SettingsApi] fake（测试注入，彻底绕开网络）。
///
/// 默认返回空模型目录 + 无推理能力；测试可按需配置
/// [modelsResponse] / [reasoningResponse] / 各方法抛错，并通过计数器断言
/// 调用次数与参数。
class FakeSettingsApi implements SettingsApi {
  /// `models()` 返回的模型目录。
  ModelsResponse modelsResponse = const ModelsResponse();

  /// `reasoning()` 返回的推理状态。
  ReasoningStatusResponse reasoningResponse = const ReasoningStatusResponse();

  /// 各方法抛出的异常（非 null 时优先于对应响应）。
  Object? modelsError;
  Object? reasoningError;
  Object? saveDefaultModelError;
  Object? saveReasoningEffortError;

  /// 非 null 时 `models()` 挂起等待该 gate（测试加载态用）。
  Completer<void>? modelsGate;

  /// 非 null 时 `reasoning()` 挂起等待该 gate（测试加载态用）。
  Completer<void>? reasoningGate;

  int modelsCount = 0;
  int reasoningCount = 0;
  int saveDefaultModelCount = 0;
  int saveReasoningEffortCount = 0;

  /// `saveDefaultModel` 已收到的模型 id（按调用顺序）。
  final List<String> defaultModelCalls = [];

  /// `saveReasoningEffort` 已收到的 effort（按调用顺序）。
  final List<String> reasoningEffortCalls = [];

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
}
