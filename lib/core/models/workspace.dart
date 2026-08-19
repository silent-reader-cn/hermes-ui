import '../utils/equality.dart';
import '../utils/lossy_json.dart';
import '../utils/uuid.dart';

/// 工作区列表响应信封（Swift: WorkspacesResponse）。
class WorkspacesResponse {
  const WorkspacesResponse({this.workspaces, this.last});

  factory WorkspacesResponse.fromJson(Map<String, Object?> json) {
    return WorkspacesResponse(
      workspaces: optModelList(json, 'workspaces', WorkspaceRoot.fromJson),
      last: optString(json, 'last'),
    );
  }

  final List<WorkspaceRoot>? workspaces;
  final String? last;

  @override
  bool operator ==(Object other) =>
      other is WorkspacesResponse &&
      deepEquals(other.workspaces, workspaces) &&
      other.last == last;

  @override
  int get hashCode => Object.hash(deepHash(workspaces), last);

  @override
  String toString() => 'WorkspacesResponse(workspaces: ${workspaces?.length})';
}

/// 工作区建议响应信封（Swift: WorkspaceSuggestionsResponse）。
class WorkspaceSuggestionsResponse {
  const WorkspaceSuggestionsResponse({this.suggestions, this.prefix});

  factory WorkspaceSuggestionsResponse.fromJson(Map<String, Object?> json) {
    return WorkspaceSuggestionsResponse(
      suggestions: optStringList(json, 'suggestions'),
      prefix: optString(json, 'prefix'),
    );
  }

  final List<String>? suggestions;
  final String? prefix;

  @override
  bool operator ==(Object other) {
    return other is WorkspaceSuggestionsResponse &&
        _listEquals(other.suggestions, suggestions) &&
        other.prefix == prefix;
  }

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(suggestions ?? const []), prefix);

  @override
  String toString() => 'WorkspaceSuggestionsResponse(prefix: $prefix)';
}

/// 工作区根（Swift: WorkspaceRoot）。**支持裸字符串**：
/// 整个元素是字符串 → path = 该字符串, name = null。
class WorkspaceRoot {
  const WorkspaceRoot({this.path, this.name});

  factory WorkspaceRoot.fromJson(Object? json) {
    if (json is String) return WorkspaceRoot(path: json);
    if (json is! Map) return const WorkspaceRoot();
    final map = Map<String, Object?>.from(json);
    return WorkspaceRoot(
      path: optString(map, 'path'),
      name: optString(map, 'name'),
    );
  }

  final String? path;
  final String? name;

  @override
  bool operator ==(Object other) =>
      other is WorkspaceRoot && other.path == path && other.name == name;

  @override
  int get hashCode => Object.hash(path, name);

  @override
  String toString() => 'WorkspaceRoot(path: $path, name: $name)';
}

/// 工作区变更响应信封（Swift: WorkspaceMutationResponse）。
class WorkspaceMutationResponse {
  const WorkspaceMutationResponse({this.ok, this.workspaces, this.error});

  factory WorkspaceMutationResponse.fromJson(Map<String, Object?> json) {
    return WorkspaceMutationResponse(
      ok: lossyBool(json, 'ok'),
      workspaces: optModelList(json, 'workspaces', WorkspaceRoot.fromJson),
      error: lossyString(json, 'error'),
    );
  }

  final bool? ok;
  final List<WorkspaceRoot>? workspaces;
  final String? error;

  @override
  bool operator ==(Object other) {
    return other is WorkspaceMutationResponse &&
        other.ok == ok &&
        deepEquals(other.workspaces, workspaces) &&
        other.error == error;
  }

  @override
  int get hashCode => Object.hash(ok, deepHash(workspaces), error);

  @override
  String toString() => 'WorkspaceMutationResponse(ok: $ok)';
}

/// 工作区变更被拒（Swift `WorkspaceMutationRejection`，本地错误类型，无 JSON）。
class WorkspaceMutationRejection implements Exception {
  const WorkspaceMutationRejection({this.serverMessage});

  final String? serverMessage;

  String get errorDescription {
    if (serverMessage != null && serverMessage!.isNotEmpty) {
      return 'The server rejected the request: $serverMessage';
    }
    return 'The server rejected the request.';
  }

  @override
  String toString() => 'WorkspaceMutationRejection: $errorDescription';
}

/// 添加工作区请求（编码用；Swift: AddWorkspaceRequest）。
class AddWorkspaceRequest {
  const AddWorkspaceRequest({required this.path, this.name, this.create});

  final String path;
  final String? name;
  final bool? create;

  Map<String, Object?> toJson() => {
        'path': path,
        if (name != null) 'name': name,
        if (create != null) 'create': create,
      };

  @override
  bool operator ==(Object other) {
    return other is AddWorkspaceRequest &&
        other.path == path &&
        other.name == name &&
        other.create == create;
  }

  @override
  int get hashCode => Object.hash(path, name, create);

  @override
  String toString() => 'AddWorkspaceRequest(path: $path)';
}

/// 移除工作区请求（编码用；Swift: RemoveWorkspaceRequest）。
class RemoveWorkspaceRequest {
  const RemoveWorkspaceRequest({required this.path});

  final String path;

  Map<String, Object?> toJson() => {'path': path};

  @override
  bool operator ==(Object other) =>
      other is RemoveWorkspaceRequest && other.path == path;

  @override
  int get hashCode => Object.hashAll([path]);

  @override
  String toString() => 'RemoveWorkspaceRequest(path: $path)';
}

/// 重命名工作区请求（编码用；Swift: RenameWorkspaceRequest）。
class RenameWorkspaceRequest {
  const RenameWorkspaceRequest({required this.path, required this.name});

  final String path;
  final String name;

  Map<String, Object?> toJson() => {'path': path, 'name': name};

  @override
  bool operator ==(Object other) =>
      other is RenameWorkspaceRequest &&
      other.path == path &&
      other.name == name;

  @override
  int get hashCode => Object.hash(path, name);

  @override
  String toString() => 'RenameWorkspaceRequest(path: $path, name: $name)';
}

/// 工作区排序请求（编码用；Swift: ReorderWorkspacesRequest）。
class ReorderWorkspacesRequest {
  const ReorderWorkspacesRequest({required this.paths});

  final List<String> paths;

  Map<String, Object?> toJson() => {'paths': paths};

  @override
  bool operator ==(Object other) =>
      other is ReorderWorkspacesRequest && _listEquals(other.paths, paths);

  @override
  int get hashCode => Object.hashAll([Object.hashAll(paths)]);

  @override
  String toString() => 'ReorderWorkspacesRequest(paths: $paths)';
}

/// 目录列表响应信封（Swift: DirectoryListResponse）。
class DirectoryListResponse {
  const DirectoryListResponse({
    this.entries,
    this.path,
    this.workspace,
    this.error,
  });

  factory DirectoryListResponse.fromJson(Map<String, Object?> json) {
    return DirectoryListResponse(
      entries: optModelList(json, 'entries', WorkspaceEntry.fromJson),
      path: optString(json, 'path'),
      workspace: optString(json, 'workspace'),
      error: optString(json, 'error'),
    );
  }

  final List<WorkspaceEntry>? entries;
  final String? path;
  final String? workspace;
  final String? error;

  @override
  bool operator ==(Object other) {
    return other is DirectoryListResponse &&
        deepEquals(other.entries, entries) &&
        other.path == path &&
        other.workspace == workspace &&
        other.error == error;
  }

  @override
  int get hashCode => Object.hash(deepHash(entries), path, workspace, error);

  @override
  String toString() => 'DirectoryListResponse(path: $path)';
}

/// 工作区目录条目（Swift: WorkspaceEntry）。`id` = path ?? name ?? uuid；
/// `isBrowsableDirectory` = isDirectory==true || type=='dir'。
class WorkspaceEntry {
  const WorkspaceEntry({
    this.name,
    this.path,
    this.type,
    this.size,
    this.modified,
    this.isDirectory,
  });

  factory WorkspaceEntry.fromJson(Map<String, Object?> json) {
    return WorkspaceEntry(
      name: optString(json, 'name'),
      path: optString(json, 'path'),
      type: optString(json, 'type'),
      size: optInt(json, 'size'),
      modified: optDouble(json, 'modified'),
      isDirectory: firstKey(json, ['is_directory', 'is_dir'], optBool),
    );
  }

  final String? name;
  final String? path;
  final String? type;
  final int? size;
  final double? modified;
  final bool? isDirectory;

  String get id => path ?? name ?? uuidV4();

  bool get isBrowsableDirectory => isDirectory == true || type == 'dir';

  @override
  bool operator ==(Object other) {
    return other is WorkspaceEntry &&
        other.name == name &&
        other.path == path &&
        other.type == type &&
        other.size == size &&
        other.modified == modified &&
        other.isDirectory == isDirectory;
  }

  @override
  int get hashCode => Object.hash(name, path, type, size, modified, isDirectory);

  @override
  String toString() => 'WorkspaceEntry(name: $name, path: $path)';
}

/// 文件响应（Swift: FileResponse）。
class FileResponse {
  const FileResponse({
    this.content,
    this.path,
    this.name,
    this.language,
    this.size,
    this.lines,
    this.error,
  });

  factory FileResponse.fromJson(Map<String, Object?> json) {
    return FileResponse(
      content: optString(json, 'content'),
      path: optString(json, 'path'),
      name: optString(json, 'name'),
      language: optString(json, 'language'),
      size: lossyInt(json, 'size'),
      lines: lossyInt(json, 'lines'),
      error: optString(json, 'error'),
    );
  }

  final String? content;
  final String? path;
  final String? name;
  final String? language;
  final int? size;
  final int? lines;
  final String? error;

  @override
  bool operator ==(Object other) {
    return other is FileResponse &&
        other.content == content &&
        other.path == path &&
        other.name == name &&
        other.language == language &&
        other.size == size &&
        other.lines == lines &&
        other.error == error;
  }

  @override
  int get hashCode =>
      Object.hash(content, path, name, language, size, lines, error);

  @override
  String toString() => 'FileResponse(path: $path, size: $size)';
}

/// 文件删除响应（`/api/file/delete` 返回形状）。
class FileDeleteResponse {
  const FileDeleteResponse({this.ok, this.path, this.error});

  factory FileDeleteResponse.fromJson(Map<String, Object?> json) {
    return FileDeleteResponse(
      ok: lossyBool(json, 'ok'),
      path: optString(json, 'path'),
      error: optString(json, 'error'),
    );
  }

  final bool? ok;
  final String? path;
  final String? error;

  @override
  bool operator ==(Object other) {
    return other is FileDeleteResponse &&
        other.ok == ok &&
        other.path == path &&
        other.error == error;
  }

  @override
  int get hashCode => Object.hash(ok, path, error);

  @override
  String toString() => 'FileDeleteResponse(ok: $ok, path: $path)';
}

/// 文件重命名响应（`/api/file/rename` 返回形状）。
class FileRenameResponse {
  const FileRenameResponse({
    this.ok,
    this.oldPath,
    this.newPath,
    this.error,
  });

  factory FileRenameResponse.fromJson(Map<String, Object?> json) {
    return FileRenameResponse(
      ok: lossyBool(json, 'ok'),
      oldPath: firstKey(json, ['old_path', 'oldPath'], optString),
      newPath: firstKey(json, ['new_path', 'newPath'], optString),
      error: optString(json, 'error'),
    );
  }

  final bool? ok;
  final String? oldPath;
  final String? newPath;
  final String? error;

  @override
  bool operator ==(Object other) {
    return other is FileRenameResponse &&
        other.ok == ok &&
        other.oldPath == oldPath &&
        other.newPath == newPath &&
        other.error == error;
  }

  @override
  int get hashCode => Object.hash(ok, oldPath, newPath, error);

  @override
  String toString() =>
      'FileRenameResponse(ok: $ok, oldPath: $oldPath, newPath: $newPath)';
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

