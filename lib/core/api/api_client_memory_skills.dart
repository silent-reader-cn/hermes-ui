import 'api_client.dart';
import 'endpoints.dart';

/// memory 域（2 个端点）+ skills 域（3 个端点）。
///
/// 返回类型暂为 `Object?`（解码后的 JSON）；TODO(merge)：模型就绪后改为对应
/// 类型并 `return XxxResponse.fromJson(json)`。
extension ApiClientMemorySkills on ApiClient {
  /// GET /api/memory。
  Future<Object?> memory() => sendJson(Endpoint.memory);

  /// POST /api/memory/write {section, content}（section 为字符串枚举，如
  /// profile/task/…，以 Swift MemorySection 为准）。
  Future<Object?> writeMemory({
    required String section,
    required String content,
  }) => sendJson(
    Endpoint.memoryWrite,
    method: 'POST',
    body: {'section': section, 'content': content},
  );

  /// GET /api/skills。
  Future<Object?> skills() => sendJson(Endpoint.skills);

  /// GET /api/skills/content?name=&file?=。
  Future<Object?> skillContent({required String name, String? file}) =>
      sendJson(Endpoint.skillContent(name: name, file: file));

  /// POST /api/skills/toggle {name, enabled}。
  Future<Object?> toggleSkill({required String name, required bool enabled}) =>
      sendJson(
        Endpoint.toggleSkill,
        method: 'POST',
        body: {'name': name, 'enabled': enabled},
      );
}
