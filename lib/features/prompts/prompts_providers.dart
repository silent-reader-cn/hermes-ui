import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_client_prompts.dart';
import '../../core/connections/connection_providers.dart';
import '../../core/models/saved_prompt.dart';

/// 收藏提示词 API 工厂（测试可 override 注入 fake）。
abstract interface class PromptsApi {
  Future<SavedPromptsResponse> fetchPrompts();
  Future<SavePromptResponse> createPrompt({
    required String text,
    String? label,
  });
  Future<DeletePromptResponse> deletePrompt(String id);
}

/// [PromptsApi] 的生产实现，包 [ApiClient]。
class PromptsApiClient implements PromptsApi {
  PromptsApiClient(this._client);

  final ApiClient _client;

  @override
  Future<SavedPromptsResponse> fetchPrompts() => _client.fetchPrompts();

  @override
  Future<SavePromptResponse> createPrompt({
    required String text,
    String? label,
  }) => _client.createPrompt(text: text, label: label);

  @override
  Future<DeletePromptResponse> deletePrompt(String id) =>
      _client.deletePrompt(id);
}

typedef PromptsApiFactory = PromptsApi Function(ApiClient client);

final promptsApiFactoryProvider = Provider<PromptsApiFactory>(
  (ref) => PromptsApiClient.new,
);

/// 收藏提示词控制器（列表 CRUD）。
///
/// AsyncValue 语义：`AsyncData<List<SavedPrompt>>` 成功携带；`AsyncLoading`
/// 加载；`AsyncError` 展示错误态（重试走 [refresh]）。
/// - [create]：成功后尝试局部插入并重拉保证一致性，[ApiException] 透传不吞。
/// - [remove]：乐观删除，失败回滚并透传异常。
final savedPromptsControllerProvider =
    AsyncNotifierProvider<SavedPromptsController, List<SavedPrompt>>(
      SavedPromptsController.new,
    );

class SavedPromptsController extends AsyncNotifier<List<SavedPrompt>> {
  PromptsApi get _api =>
      ref.read(promptsApiFactoryProvider)(ref.read(apiClientProvider));

  @override
  Future<List<SavedPrompt>> build() async {
    // watch：切换服务器或工厂被替换时自动重载。
    final api = ref.watch(promptsApiFactoryProvider)(
      ref.watch(apiClientProvider),
    );
    final response = await api.fetchPrompts();
    return response.prompts ?? const <SavedPrompt>[];
  }

  /// 下拉/错误态重试：重新拉取。
  Future<void> refresh() async {
    try {
      final response = await _api.fetchPrompts();
      state = AsyncData(response.prompts ?? const <SavedPrompt>[]);
    } on Exception catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
    }
  }

  /// 收藏当前输入。
  ///
  /// 成功（`ok == true`）时局部插入返回的 prompt 并尝试重拉保证一致性；
  /// 失败（业务 `ok==false` 或抛 [ApiException]）透传给调用方，不吞异常。
  Future<SavedPrompt?> create({required String text, String? label}) async {
    final response = await _api.createPrompt(text: text, label: label);
    final prompt = response.prompt;
    if (response.ok == true && prompt != null) {
      final current = state.valueOrNull;
      if (current != null) {
        // 局部插入（服务端按追加序，重拉后以服务端为准）。
        state = AsyncData([...current, prompt]);
      }
      // 尝试重拉保证最终一致（失败不回滚，调用方已拿到 prompt）。
      try {
        final refreshed = await _api.fetchPrompts();
        state = AsyncData(refreshed.prompts ?? const <SavedPrompt>[]);
      } catch (_) {}
      return prompt;
    }
    // ok==false 的业务失败也返回 prompt（若有），由 UI 决定提示；
    // 真正的传输层失败由上层 catch ApiException。
    return prompt;
  }

  /// 删除指定 id（后端幂等），乐观删除 + 失败回滚并透传异常。
  Future<void> remove(String id) async {
    final previous = state.valueOrNull;
    if (previous != null) {
      state = AsyncData(previous.where((p) => p.id != id).toList());
    }
    try {
      final response = await _api.deletePrompt(id);
      if (response.ok == false) {
        if (previous != null) state = AsyncData(previous);
        return;
      }
      // 保证最终一致性：尝试重拉（失败也不回滚，幂等删除已生效）。
      try {
        final refreshed = await _api.fetchPrompts();
        state = AsyncData(refreshed.prompts ?? const <SavedPrompt>[]);
      } catch (_) {}
    } on Exception {
      if (previous != null) state = AsyncData(previous);
      rethrow;
    }
  }
}

/// 收藏数量派生（测试可注入性验证 + UI 角标用）。
final savedPromptsCountProvider = Provider<int>((ref) {
  return ref.watch(savedPromptsControllerProvider).valueOrNull?.length ?? 0;
});

/// 是否为空派生。
final savedPromptsIsEmptyProvider = Provider<bool>((ref) {
  final value = ref.watch(savedPromptsControllerProvider).valueOrNull;
  if (value == null) return true;
  return value.isEmpty;
});

/// 展示名：label 优先，空/缺失回落 text 的前 60 字符（同后端截断）。
String savedPromptDisplayLabel(SavedPrompt prompt) {
  final label = prompt.label?.trim();
  if (label != null && label.isNotEmpty) return label;
  final text = prompt.text ?? '';
  if (text.length <= 60) return text;
  return text.substring(0, 60);
}
