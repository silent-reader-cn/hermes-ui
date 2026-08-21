import 'api_client.dart';
import 'endpoints.dart';
import '../models/saved_prompt.dart';

/// 收藏提示词域（3 端点，同路径 `/api/prompts` 以方法区分）。
///
/// - GET  /api/prompts → [SavedPromptsResponse]
/// - POST /api/prompts {text, label?} → [SavePromptResponse]
/// - DELETE /api/prompts {id} → [DeletePromptResponse]
extension ApiClientPrompts on ApiClient {
  /// GET /api/prompts。
  Future<SavedPromptsResponse> fetchPrompts() async {
    final json = await sendJson(Endpoint.prompts);
    return SavedPromptsResponse.fromJson(_asMap(json));
  }

  /// POST /api/prompts。
  Future<SavePromptResponse> createPrompt({
    required String text,
    String? label,
  }) async {
    final json = await sendJson(
      Endpoint.prompts,
      method: 'POST',
      body: {
        'text': text,
        // ignore: use_null_aware_elements
        if (label != null) 'label': label,
      },
    );
    return SavePromptResponse.fromJson(_asMap(json));
  }

  /// DELETE /api/prompts。
  Future<DeletePromptResponse> deletePrompt(String id) async {
    final json = await sendJson(
      Endpoint.prompts,
      method: 'DELETE',
      body: {'id': id},
    );
    return DeletePromptResponse.fromJson(_asMap(json));
  }
}

Map<String, Object?> _asMap(Object? json) => json is Map<String, Object?>
    ? json
    : (json is Map
          ? Map<String, Object?>.from(json)
          : const <String, Object?>{});
