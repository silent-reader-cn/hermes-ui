import 'dart:typed_data';

import 'api_client.dart';
import 'endpoints.dart';
import '../models/workspace.dart';

/// workspace 域方法（10 个端点）+ 文件操作（delete/rename）+ 外部媒体下载
/// （remoteTranscriptMediaData）。
extension ApiClientWorkspace on ApiClient {
  /// GET /api/workspaces。
  Future<WorkspacesResponse> workspaces() async {
    final json = await sendJson(Endpoint.workspaces);
    return WorkspacesResponse.fromJson(_asMap(json));
  }

  /// GET /api/workspaces/suggest?prefix=。
  Future<WorkspaceSuggestionsResponse> workspaceSuggestions(String prefix) async {
    final json = await sendJson(Endpoint.workspaceSuggestions(prefix));
    return WorkspaceSuggestionsResponse.fromJson(_asMap(json));
  }

  /// POST /api/workspaces/add {path, name?, create?}。
  Future<WorkspaceMutationResponse> addWorkspace({
    required String path,
    String? name,
    bool? create,
  }) async {
    final json = await sendJson(
      Endpoint.workspaceAdd,
      method: 'POST',
      body: {'path': path, 'name': ?name, 'create': ?create},
    );
    return WorkspaceMutationResponse.fromJson(_asMap(json));
  }

  /// POST /api/workspaces/remove {path}。
  Future<WorkspaceMutationResponse> removeWorkspace(String path) async {
    final json = await sendJson(
      Endpoint.workspaceRemove,
      method: 'POST',
      body: {'path': path},
    );
    return WorkspaceMutationResponse.fromJson(_asMap(json));
  }

  /// POST /api/workspaces/rename {path, name}。
  Future<WorkspaceMutationResponse> renameWorkspace({
    required String path,
    required String name,
  }) async {
    final json = await sendJson(
      Endpoint.workspaceRename,
      method: 'POST',
      body: {'path': path, 'name': name},
    );
    return WorkspaceMutationResponse.fromJson(_asMap(json));
  }

  /// POST /api/workspaces/reorder {paths: [String]}。
  Future<WorkspaceMutationResponse> reorderWorkspaces(List<String> paths) async {
    final json = await sendJson(
      Endpoint.workspaceReorder,
      method: 'POST',
      body: {'paths': paths},
    );
    return WorkspaceMutationResponse.fromJson(_asMap(json));
  }

  /// GET /api/list?session_id=&path?=。
  Future<DirectoryListResponse> directoryList({
    required String sessionId,
    String? path,
  }) async {
    final json = await sendJson(
      Endpoint.directoryList(sessionId: sessionId, path: path),
    );
    return DirectoryListResponse.fromJson(_asMap(json));
  }

  /// GET /api/file?session_id=&path=（文本内容 JSON）。
  Future<FileResponse> file({
    required String sessionId,
    required String path,
  }) async {
    final json = await sendJson(
      Endpoint.file(sessionId: sessionId, path: path),
    );
    return FileResponse.fromJson(_asMap(json));
  }

  /// GET /api/file/raw?session_id=&path= — 原始字节。
  Future<Uint8List> rawFileData({
    required String sessionId,
    required String path,
  }) => sendData(Endpoint.rawFile(sessionId: sessionId, path: path));

  /// POST /api/file/delete {session_id, path, recursive?} → {ok, path}。
  Future<FileDeleteResponse> deleteFile({
    required String sessionId,
    required String path,
    bool recursive = false,
  }) async {
    final json = await sendJson(
      Endpoint.fileDelete,
      method: 'POST',
      body: {
        'session_id': sessionId,
        'path': path,
        'recursive': recursive,
      },
    );
    return FileDeleteResponse.fromJson(_asMap(json));
  }

  /// POST /api/file/rename {session_id, path, new_name} → {ok, old_path, new_path}。
  Future<FileRenameResponse> renameFile({
    required String sessionId,
    required String path,
    required String newName,
  }) async {
    final json = await sendJson(
      Endpoint.fileRename,
      method: 'POST',
      body: {'session_id': sessionId, 'path': path, 'new_name': newName},
    );
    return FileRenameResponse.fromJson(_asMap(json));
  }

  /// GET /api/media?session_id=&path= — 原始字节（图片/媒体）。
  Future<Uint8List> mediaData({
    required String sessionId,
    required String path,
  }) => sendData(Endpoint.media(sessionId: sessionId, path: path));

  /// 外部（跨域）媒体 URL 下载：**不带**自定义头、**不带** cookie（裸会话）；
  /// 同域 URL 走带 header 的正常会话（[ApiClient.downloadData] 自动分流）。
  Future<Uint8List> remoteTranscriptMediaData(Uri url) => downloadData(url);
}

Map<String, Object?> _asMap(Object? json) =>
    json is Map<String, Object?>
        ? json
        : (json is Map ? Map<String, Object?>.from(json) : const <String, Object?>{});