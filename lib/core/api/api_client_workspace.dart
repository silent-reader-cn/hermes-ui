import 'dart:typed_data';

import 'api_client.dart';
import 'endpoints.dart';

/// workspace 域方法（10 个端点）+ 外部媒体下载（remoteTranscriptMediaData）。
///
/// 返回类型暂为 `Object?`（解码后的 JSON）；TODO(merge)：模型就绪后改为对应
/// 类型并 `return XxxResponse.fromJson(json)`。
extension ApiClientWorkspace on ApiClient {
  /// GET /api/workspaces。
  Future<Object?> workspaces() => sendJson(Endpoint.workspaces);

  /// GET /api/workspaces/suggest?prefix=。
  Future<Object?> workspaceSuggestions(String prefix) =>
      sendJson(Endpoint.workspaceSuggestions(prefix));

  /// POST /api/workspaces/add {path, name?, create?}。
  Future<Object?> addWorkspace({
    required String path,
    String? name,
    bool? create,
  }) => sendJson(
    Endpoint.workspaceAdd,
    method: 'POST',
    body: {'path': path, 'name': ?name, 'create': ?create},
  );

  /// POST /api/workspaces/remove {path}。
  Future<Object?> removeWorkspace(String path) =>
      sendJson(Endpoint.workspaceRemove, method: 'POST', body: {'path': path});

  /// POST /api/workspaces/rename {path, name}。
  Future<Object?> renameWorkspace({
    required String path,
    required String name,
  }) => sendJson(
    Endpoint.workspaceRename,
    method: 'POST',
    body: {'path': path, 'name': name},
  );

  /// POST /api/workspaces/reorder {paths: [String]}。
  Future<Object?> reorderWorkspaces(List<String> paths) => sendJson(
    Endpoint.workspaceReorder,
    method: 'POST',
    body: {'paths': paths},
  );

  /// GET /api/list?session_id=&path?=。
  Future<Object?> directoryList({required String sessionId, String? path}) =>
      sendJson(Endpoint.directoryList(sessionId: sessionId, path: path));

  /// GET /api/file?session_id=&path=（文本内容 JSON）。
  Future<Object?> file({required String sessionId, required String path}) =>
      sendJson(Endpoint.file(sessionId: sessionId, path: path));

  /// GET /api/file/raw?session_id=&path= — 原始字节。
  Future<Uint8List> rawFileData({
    required String sessionId,
    required String path,
  }) => sendData(Endpoint.rawFile(sessionId: sessionId, path: path));

  /// GET /api/media?session_id=&path= — 原始字节（图片/媒体）。
  Future<Uint8List> mediaData({
    required String sessionId,
    required String path,
  }) => sendData(Endpoint.media(sessionId: sessionId, path: path));

  /// 外部（跨域）媒体 URL 下载：**不带**自定义头、**不带** cookie（裸会话）；
  /// 同域 URL 走带 header 的正常会话（[ApiClient.downloadData] 自动分流）。
  Future<Uint8List> remoteTranscriptMediaData(Uri url) => downloadData(url);
}
