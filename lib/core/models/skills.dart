import '../utils/equality.dart';
import '../utils/lossy_json.dart';
import '../utils/uuid.dart';
import 'json_value.dart';

/// 技能列表响应信封（Swift: SkillsResponse）。
class SkillsResponse {
  const SkillsResponse({this.skills});

  factory SkillsResponse.fromJson(Map<String, Object?> json) {
    return SkillsResponse(
      skills: optModelList(json, 'skills', SkillSummary.fromJson),
    );
  }

  final List<SkillSummary>? skills;

  @override
  bool operator ==(Object other) =>
      other is SkillsResponse && deepEquals(other.skills, skills);

  @override
  int get hashCode => Object.hashAll([deepHash(skills)]);

  @override
  String toString() => 'SkillsResponse(skills: ${skills?.length})';
}

/// 技能摘要（Swift: SkillSummary）。`id` = name ?? uuid。
class SkillSummary {
  const SkillSummary({
    this.name,
    this.category,
    this.description,
    this.path,
    this.disabled,
    this.tags,
    this.relatedSkills,
  });

  factory SkillSummary.fromJson(Map<String, Object?> json) {
    return SkillSummary(
      name: optString(json, 'name'),
      category: optString(json, 'category'),
      description: optString(json, 'description'),
      path: optString(json, 'path'),
      disabled: optBool(json, 'disabled'),
      tags: optStringList(json, 'tags'),
      relatedSkills: optStringList(json, 'related_skills'),
    );
  }

  final String? name;
  final String? category;
  final String? description;
  final String? path;
  final bool? disabled;
  final List<String>? tags;
  final List<String>? relatedSkills;

  String get id => name ?? uuidV4();

  @override
  bool operator ==(Object other) {
    return other is SkillSummary &&
        other.name == name &&
        other.category == category &&
        other.description == description &&
        other.path == path &&
        other.disabled == disabled &&
        _listEquals(other.tags, tags) &&
        _listEquals(other.relatedSkills, relatedSkills);
  }

  @override
  int get hashCode => Object.hash(
        name,
        category,
        description,
        path,
        disabled,
        Object.hashAll(tags ?? const []),
        Object.hashAll(relatedSkills ?? const []),
      );

  @override
  String toString() => 'SkillSummary(name: $name, category: $category)';
}

/// 切换技能请求（编码用，toJson 输出 snake_case；Swift: ToggleSkillRequest）。
class ToggleSkillRequest {
  const ToggleSkillRequest({required this.name, required this.enabled});

  final String name;
  final bool enabled;

  Map<String, Object?> toJson() => {'name': name, 'enabled': enabled};

  @override
  bool operator ==(Object other) =>
      other is ToggleSkillRequest &&
      other.name == name &&
      other.enabled == enabled;

  @override
  int get hashCode => Object.hash(name, enabled);

  @override
  String toString() => 'ToggleSkillRequest(name: $name, enabled: $enabled)';
}

/// 切换技能响应（Swift: ToggleSkillResponse）。
class ToggleSkillResponse {
  const ToggleSkillResponse({this.ok, this.name, this.enabled});

  factory ToggleSkillResponse.fromJson(Map<String, Object?> json) {
    return ToggleSkillResponse(
      ok: lossyBool(json, 'ok'),
      name: lossyString(json, 'name'),
      enabled: lossyBool(json, 'enabled'),
    );
  }

  final bool? ok;
  final String? name;
  final bool? enabled;

  @override
  bool operator ==(Object other) {
    return other is ToggleSkillResponse &&
        other.ok == ok &&
        other.name == name &&
        other.enabled == enabled;
  }

  @override
  int get hashCode => Object.hash(ok, name, enabled);

  @override
  String toString() => 'ToggleSkillResponse(ok: $ok, name: $name)';
}

/// 技能详情响应（Swift: SkillDetailResponse）。linkedFiles 特殊多形态。
class SkillDetailResponse {
  const SkillDetailResponse({this.name, this.content, this.linkedFiles});

  factory SkillDetailResponse.fromJson(Map<String, Object?> json) {
    return SkillDetailResponse(
      name: optString(json, 'name'),
      content: optString(json, 'content'),
      linkedFiles: _decodeLinkedFiles(json['linked_files']),
    );
  }

  final String? name;
  final String? content;
  final List<String>? linkedFiles;

  /// linkedFiles 解码（对齐 Swift `decodeLinkedFiles`）：
  /// 1. 先试 `Map<String, String>` → keys 排序后列表（空 → null）；
  /// 2. 否则试 JsonValue → 递归收集字符串名（string→自身；array→逐项递归；
  ///    object→每个 key：值是 array/其他 → 递归收集，值是 string → 取 key 本身），
  ///    去重排序；
  /// 3. 都没有 → null。
  static List<String>? _decodeLinkedFiles(Object? raw) {
    if (raw is Map) {
      final flat = Map<String, Object?>.from(raw);
      if (flat.values.every((v) => v is String)) {
        final names = flat.keys.toList()..sort();
        return names.isEmpty ? null : names;
      }
    }

    final value = JsonValue.fromJson(raw);
    if (value is JsonNull) return null;
    final names = _linkedFileNames(value).toSet().toList()..sort();
    return names.isEmpty ? null : names;
  }

  static List<String> _linkedFileNames(JsonValue value) {
    switch (value) {
      case JsonString(:final value):
        final trimmed = value.trim();
        return trimmed.isEmpty ? const [] : [trimmed];
      case JsonArray(:final value):
        return value.expand(_linkedFileNames).toList();
      case JsonObject(:final value):
        return value.entries.expand((entry) {
          switch (entry.value) {
            case JsonString():
              return <String>[entry.key];
            default:
              return _linkedFileNames(entry.value);
          }
        }).toList();
      case JsonNumber() || JsonBool() || JsonNull():
        return const [];
    }
  }

  @override
  bool operator ==(Object other) {
    return other is SkillDetailResponse &&
        other.name == name &&
        other.content == content &&
        _listEquals(other.linkedFiles, linkedFiles);
  }

  @override
  int get hashCode =>
      Object.hash(name, content, Object.hashAll(linkedFiles ?? const []));

  @override
  String toString() => 'SkillDetailResponse(name: $name)';
}

/// 技能链接文件响应（Swift: SkillLinkedFileResponse）。
class SkillLinkedFileResponse {
  const SkillLinkedFileResponse({this.content, this.path});

  factory SkillLinkedFileResponse.fromJson(Map<String, Object?> json) {
    return SkillLinkedFileResponse(
      content: optString(json, 'content'),
      path: optString(json, 'path'),
    );
  }

  final String? content;
  final String? path;

  @override
  bool operator ==(Object other) {
    return other is SkillLinkedFileResponse &&
        other.content == content &&
        other.path == path;
  }

  @override
  int get hashCode => Object.hash(content, path);

  @override
  String toString() => 'SkillLinkedFileResponse(path: $path)';
}

bool _listEquals(List<String>? a, List<String>? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return false;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
