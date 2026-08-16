import '../utils/lossy_json.dart';

/// 记忆分区（Swift: MemorySection）。未知字符串 → null。
enum MemorySection { memory, user, soul }

/// 解析记忆分区：字符串匹配，未知 → null。
MemorySection? memorySectionFromJson(Object? value) {
  if (value is! String) return null;
  switch (value) {
    case 'memory':
      return MemorySection.memory;
    case 'user':
      return MemorySection.user;
    case 'soul':
      return MemorySection.soul;
    default:
      return null;
  }
}

/// 记忆响应（Swift: MemoryResponse，17 字段全可空）。
class MemoryResponse {
  const MemoryResponse({
    this.memory,
    this.user,
    this.soul,
    this.memoryPath,
    this.userPath,
    this.soulPath,
    this.memoryMtime,
    this.userMtime,
    this.soulMtime,
    this.projectContext,
    this.projectContextName,
    this.projectContextPath,
    this.projectContextWorkspace,
    this.projectContextMtime,
    this.projectContextShadowed,
    this.externalNotesEnabled,
  });

  factory MemoryResponse.fromJson(Map<String, Object?> json) {
    return MemoryResponse(
      memory: optString(json, 'memory'),
      user: optString(json, 'user'),
      soul: optString(json, 'soul'),
      memoryPath: optString(json, 'memory_path'),
      userPath: optString(json, 'user_path'),
      soulPath: optString(json, 'soul_path'),
      memoryMtime: flexibleDouble(json, 'memory_mtime'),
      userMtime: flexibleDouble(json, 'user_mtime'),
      soulMtime: flexibleDouble(json, 'soul_mtime'),
      projectContext: optString(json, 'project_context'),
      projectContextName: optString(json, 'project_context_name'),
      projectContextPath: optString(json, 'project_context_path'),
      projectContextWorkspace: optString(json, 'project_context_workspace'),
      projectContextMtime: flexibleDouble(json, 'project_context_mtime'),
      // 特殊：bool 原样；否则若为 List → (list.isNotEmpty)；否则 null。
      projectContextShadowed: _decodeShadowed(json['project_context_shadowed']),
      externalNotesEnabled: optBool(json, 'external_notes_enabled'),
    );
  }

  final String? memory;
  final String? user;
  final String? soul;
  final String? memoryPath;
  final String? userPath;
  final String? soulPath;
  final double? memoryMtime;
  final double? userMtime;
  final double? soulMtime;
  final String? projectContext;
  final String? projectContextName;
  final String? projectContextPath;
  final String? projectContextWorkspace;
  final double? projectContextMtime;
  final bool? projectContextShadowed;
  final bool? externalNotesEnabled;

  static bool? _decodeShadowed(Object? value) {
    if (value is bool) return value;
    if (value is List) return value.isNotEmpty;
    return null;
  }

  @override
  bool operator ==(Object other) {
    return other is MemoryResponse &&
        other.memory == memory &&
        other.user == user &&
        other.soul == soul &&
        other.memoryPath == memoryPath &&
        other.userPath == userPath &&
        other.soulPath == soulPath &&
        other.memoryMtime == memoryMtime &&
        other.userMtime == userMtime &&
        other.soulMtime == soulMtime &&
        other.projectContext == projectContext &&
        other.projectContextName == projectContextName &&
        other.projectContextPath == projectContextPath &&
        other.projectContextWorkspace == projectContextWorkspace &&
        other.projectContextMtime == projectContextMtime &&
        other.projectContextShadowed == projectContextShadowed &&
        other.externalNotesEnabled == externalNotesEnabled;
  }

  @override
  int get hashCode {
    return Object.hash(
      memory,
      user,
      soul,
      memoryPath,
      userPath,
      soulPath,
      memoryMtime,
      userMtime,
      soulMtime,
      projectContext,
      projectContextName,
      projectContextPath,
      projectContextWorkspace,
      projectContextMtime,
      projectContextShadowed,
      externalNotesEnabled,
    );
  }

  @override
  String toString() => 'MemoryResponse(memory: ${memory?.length})';
}

/// 记忆写入响应（Swift: MemoryWriteResponse）。
class MemoryWriteResponse {
  const MemoryWriteResponse({this.ok, this.section, this.path, this.error});

  factory MemoryWriteResponse.fromJson(Map<String, Object?> json) {
    return MemoryWriteResponse(
      ok: optBool(json, 'ok'),
      section: memorySectionFromJson(json['section']),
      path: optString(json, 'path'),
      error: optString(json, 'error'),
    );
  }

  final bool? ok;
  final MemorySection? section;
  final String? path;
  final String? error;

  @override
  bool operator ==(Object other) {
    return other is MemoryWriteResponse &&
        other.ok == ok &&
        other.section == section &&
        other.path == path &&
        other.error == error;
  }

  @override
  int get hashCode => Object.hash(ok, section, path, error);

  @override
  String toString() => 'MemoryWriteResponse(ok: $ok, section: $section)';
}
