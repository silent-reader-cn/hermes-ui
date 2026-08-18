import 'dart:typed_data';

import '../../core/api/api_client.dart';
import '../../core/api/api_client_upload.dart';
import '../../core/api/api_client_workspace.dart';
import '../../core/models/workspace.dart';
import '../../core/utils/lossy_json.dart';

/// 上传响应（对齐 UploadResponse.swift：`/api/upload` 返回形状）。
///
/// 键名照抄服务端：`filename` / `path` / `size` / `mime` / `is_image` / `error`。
/// 容错解码：字段缺失/类型不符 → 安全默认值，绝不 crash。
class WorkspaceUploadResult {
  const WorkspaceUploadResult({
    this.filename,
    this.path,
    this.size,
    this.mime,
    this.isImage,
    this.error,
  });

  factory WorkspaceUploadResult.fromJson(Map<String, Object?> json) {
    return WorkspaceUploadResult(
      filename: optString(json, 'filename'),
      path: optString(json, 'path'),
      size: optInt(json, 'size'),
      mime: optString(json, 'mime'),
      isImage: optBool(json, 'is_image'),
      error: optString(json, 'error'),
    );
  }

  final String? filename;
  final String? path;
  final int? size;
  final String? mime;
  final bool? isImage;
  final String? error;

  @override
  bool operator ==(Object other) {
    return other is WorkspaceUploadResult &&
        other.filename == filename &&
        other.path == path &&
        other.size == size &&
        other.mime == mime &&
        other.isImage == isImage &&
        other.error == error;
  }

  @override
  int get hashCode => Object.hash(filename, path, size, mime, isImage, error);

  @override
  String toString() =>
      'WorkspaceUploadResult(filename: $filename, size: $size)';
}

/// workspace 文件浏览所需的最小服务器 API 面。
///
/// 生产实现 [WorkspaceApiClient] 包 [ApiClient]（模型在客户端解码）；
/// 测试注入纯 Dart fake，彻底绕开网络（对齐 session_list 的
/// `SessionListApi` 模式）。
abstract interface class WorkspaceApi {
  /// GET /api/list?session_id=&path= → 目录条目列表。
  Future<DirectoryListResponse> fetchDirectory({
    required String sessionId,
    required String path,
  });

  /// POST /api/upload（multipart：`session_id` + `file`）→ 上传文件到会话工作区。
  Future<WorkspaceUploadResult> uploadFile({
    required String sessionId,
    required String filename,
    required Uint8List data,
  });

  /// GET /api/file/raw?session_id=&path= → 下载文件原始字节。
  Future<Uint8List> downloadFile({
    required String sessionId,
    required String path,
  });

  /// 删除文件/目录（目录需 `recursive=true`）。成功返回后调用方应刷新列表。
  Future<void> deleteFile({
    required String sessionId,
    required String path,
    bool recursive = false,
  });

  /// 重命名文件/目录（`newName` 仅限直接文件名，不能含路径分隔符）。
  Future<void> renameFile({
    required String sessionId,
    required String path,
    required String newName,
  });
}

/// [WorkspaceApi] 的生产实现：包 [ApiClient]，把 `Object?` JSON 解码为模型。
class WorkspaceApiClient implements WorkspaceApi {
  WorkspaceApiClient(this._client);

  final ApiClient _client;

  @override
  Future<DirectoryListResponse> fetchDirectory({
    required String sessionId,
    required String path,
  }) async {
    final json = await _client.directoryList(sessionId: sessionId, path: path);
    return DirectoryListResponse.fromJson(_asMap(json));
  }

  @override
  Future<WorkspaceUploadResult> uploadFile({
    required String sessionId,
    required String filename,
    required Uint8List data,
  }) async {
    final json = await _client.uploadFile(
      sessionId: sessionId,
      filename: filename,
      data: data,
    );
    return WorkspaceUploadResult.fromJson(_asMap(json));
  }

  @override
  Future<Uint8List> downloadFile({
    required String sessionId,
    required String path,
  }) => _client.rawFileData(sessionId: sessionId, path: path);

  @override
  Future<void> deleteFile({
    required String sessionId,
    required String path,
    bool recursive = false,
  }) async {
    await _client.deleteFile(
      sessionId: sessionId,
      path: path,
      recursive: recursive,
    );
  }

  @override
  Future<void> renameFile({
    required String sessionId,
    required String path,
    required String newName,
  }) async {
    await _client.renameFile(
      sessionId: sessionId,
      path: path,
      newName: newName,
    );
  }

  static Map<String, Object?> _asMap(Object? json) =>
      json is Map<String, Object?> ? json : const <String, Object?>{};
}
