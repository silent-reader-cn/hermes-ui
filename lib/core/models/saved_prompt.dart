import '../utils/equality.dart';
import '../utils/lossy_json.dart';

/// 收藏提示词（SavedPrompt，Swift 无类，对齐 routes.py 持久化 JSON）。
///
/// - 后端字段：{id, label, text, created_at}（snake_case + double 秒时间戳）。
/// - Dart 风格：[createdAt] camelCase，toJson 归一为 snake_case。
/// - 容错：字段可空、缺失/类型不符绝不 throw。
class SavedPrompt {
  const SavedPrompt({this.id, this.label, this.text, this.createdAt});

  factory SavedPrompt.fromJson(Map<String, Object?> json) {
    return SavedPrompt(
      id: optString(json, 'id'),
      label: lossyString(json, 'label'),
      text: lossyString(json, 'text'),
      createdAt: flexibleDouble(json, 'created_at'),
    );
  }

  final String? id;
  final String? label;
  final String? text;
  final double? createdAt;

  SavedPrompt copyWith({
    String? id,
    String? label,
    String? text,
    double? createdAt,
  }) {
    return SavedPrompt(
      id: id ?? this.id,
      label: label ?? this.label,
      text: text ?? this.text,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, Object?> toJson() => {
    // ignore: use_null_aware_elements
    if (id != null) 'id': id,
    // ignore: use_null_aware_elements
    if (label != null) 'label': label,
    // ignore: use_null_aware_elements
    if (text != null) 'text': text,
    // ignore: use_null_aware_elements
    if (createdAt != null) 'created_at': createdAt,
  };

  @override
  bool operator ==(Object other) =>
      other is SavedPrompt &&
      other.id == id &&
      other.label == label &&
      other.text == text &&
      other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(id, label, text, createdAt);

  @override
  String toString() => 'SavedPrompt(id: $id, label: $label)';
}

/// GET /api/prompts → {prompts: [SavedPrompt]}。
class SavedPromptsResponse {
  const SavedPromptsResponse({this.prompts});

  factory SavedPromptsResponse.fromJson(Map<String, Object?> json) {
    // 容错：null/非 List→null；元素非 Map→skip；逐项托底
    final raw = json['prompts'];
    if (raw == null) return const SavedPromptsResponse(prompts: null);
    if (raw is! List) return const SavedPromptsResponse(prompts: null);
    final result = <SavedPrompt>[];
    for (final element in raw) {
      if (element is! Map) continue;
      try {
        result.add(SavedPrompt.fromJson(Map<String, Object?>.from(element)));
      } catch (_) {
        continue;
      }
    }
    return SavedPromptsResponse(prompts: result);
  }

  final List<SavedPrompt>? prompts;

  @override
  bool operator ==(Object other) =>
      other is SavedPromptsResponse && deepEquals(other.prompts, prompts);

  @override
  int get hashCode => deepHash(prompts);

  @override
  String toString() => 'SavedPromptsResponse(prompts: ${prompts?.length})';

  /// 测试辅助：用 tolerant 方式将可选模型数组解码为 `List<SavedPrompt>?`。
  // ignore: unused_element
  static List<SavedPrompt>? _decodePromptsTolerant(Object? raw) {
    if (raw is! List) return null;
    final list = <SavedPrompt>[];
    for (final element in raw) {
      if (element is! Map) continue;
      try {
        list.add(SavedPrompt.fromJson(Map<String, Object?>.from(element)));
      } catch (_) {
        continue;
      }
    }
    return list;
  }
}

/// POST /api/prompts → {ok, prompt} 或 {ok, error}。
class SavePromptResponse {
  const SavePromptResponse({this.ok, this.prompt, this.error});

  factory SavePromptResponse.fromJson(Map<String, Object?> json) {
    return SavePromptResponse(
      ok: lossyBool(json, 'ok') ?? optBool(json, 'ok'),
      prompt: optModel(json, 'prompt', SavedPrompt.fromJson),
      error: lossyString(json, 'error') ?? optString(json, 'error'),
    );
  }

  final bool? ok;
  final SavedPrompt? prompt;
  final String? error;

  @override
  bool operator ==(Object other) =>
      other is SavePromptResponse &&
      other.ok == ok &&
      other.prompt == prompt &&
      other.error == error;

  @override
  int get hashCode => Object.hash(ok, prompt, error);

  @override
  String toString() => 'SavePromptResponse(ok: $ok, error: $error)';
}

/// DELETE /api/prompts → {ok, error?}。
class DeletePromptResponse {
  const DeletePromptResponse({this.ok, this.error});

  factory DeletePromptResponse.fromJson(Map<String, Object?> json) {
    return DeletePromptResponse(
      ok: lossyBool(json, 'ok') ?? optBool(json, 'ok'),
      error: lossyString(json, 'error') ?? optString(json, 'error'),
    );
  }

  final bool? ok;
  final String? error;

  @override
  bool operator ==(Object other) =>
      other is DeletePromptResponse && other.ok == ok && other.error == error;

  @override
  int get hashCode => Object.hash(ok, error);

  @override
  String toString() => 'DeletePromptResponse(ok: $ok)';
}

/// 私有 Map 容错：未直接使用，模型层已容错；为后续扩展预留。
// ignore: unused_element
Map<String, Object?> _asMap(Object? json) {
  if (json is Map<String, Object?>) return json;
  if (json is Map) return Map<String, Object?>.from(json);
  return const <String, Object?>{};
}
