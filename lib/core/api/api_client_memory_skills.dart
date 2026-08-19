import 'api_client.dart';
import 'endpoints.dart';
import '../models/memory.dart';
import '../models/skills.dart';

/// memory 域（2 个端点）+ skills 域（3 个端点）。
extension ApiClientMemorySkills on ApiClient {
  /// GET /api/memory。
  Future<MemoryResponse> memory() async {
    final json = await sendJson(Endpoint.memory);
    return MemoryResponse.fromJson(_asMap(json));
  }

  /// POST /api/memory/write {section, content}（section 为字符串枚举，如
  /// profile/task/…，以 Swift MemorySection 为准）。
  Future<MemoryWriteResponse> writeMemory({
    required String section,
    required String content,
  }) async {
    final json = await sendJson(
      Endpoint.memoryWrite,
      method: 'POST',
      body: {'section': section, 'content': content},
    );
    return MemoryWriteResponse.fromJson(_asMap(json));
  }

  /// GET /api/skills。
  Future<SkillsResponse> skills() async {
    final json = await sendJson(Endpoint.skills);
    return SkillsResponse.fromJson(_asMap(json));
  }

  /// GET /api/skills/content?name=&file?=。
  Future<SkillDetailResponse> skillContent({
    required String name,
    String? file,
  }) async {
    final json = await sendJson(Endpoint.skillContent(name: name, file: file));
    return SkillDetailResponse.fromJson(_asMap(json));
  }

  /// POST /api/skills/toggle {name, enabled}。
  Future<ToggleSkillResponse> toggleSkill({
    required String name,
    required bool enabled,
  }) async {
    final json = await sendJson(
      Endpoint.toggleSkill,
      method: 'POST',
      body: {'name': name, 'enabled': enabled},
    );
    return ToggleSkillResponse.fromJson(_asMap(json));
  }
}

Map<String, Object?> _asMap(Object? json) =>
    json is Map<String, Object?>
        ? json
        : (json is Map ? Map<String, Object?>.from(json) : const <String, Object?>{});
