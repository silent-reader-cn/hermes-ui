import 'dart:typed_data';

import '../utils/lossy_json.dart';
import '../utils/uuid.dart';
import 'json_value.dart';

/// 上传响应（Swift: UploadResponse）。
class UploadResponse {
  const UploadResponse({
    this.filename,
    this.path,
    this.size,
    this.mime,
    this.isImage,
    this.error,
  });

  factory UploadResponse.fromJson(Map<String, Object?> json) {
    return UploadResponse(
      filename: lossyString(json, 'filename'),
      path: lossyString(json, 'path'),
      size: lossyInt(json, 'size'),
      mime: lossyString(json, 'mime'),
      isImage: lossyBool(json, 'is_image'),
      error: lossyString(json, 'error'),
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
    return other is UploadResponse &&
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
  String toString() => 'UploadResponse(filename: $filename, size: $size)';
}

/// 待发送附件（本地模型，无 fromJson；Swift: PendingAttachment）。
class PendingAttachment {
  PendingAttachment({
    String? id,
    required this.name,
    required this.path,
    required this.mime,
    this.size,
    this.isImage = false,
    this.thumbnailData,
  }) : id = id ?? uuidV4();

  /// 上传上限 20 MiB。
  static const int maximumUploadBytes = 20 * 1024 * 1024;
  static const String maximumUploadSizeDescription = '20 MB';

  final String id;
  final String name;
  final String path;
  final String mime;
  final int? size;
  final bool isImage;
  final Uint8List? thumbnailData;

  static String uploadTooLargeMessage(String filename) {
    return '$filename is too large. Attachments must be '
        '$maximumUploadSizeDescription or smaller.';
  }

  /// 聊天引用文本：path 空则用 name（两种分支一致）。
  String get chatReference => path.isEmpty ? name : path;

  /// 聊天发送用序列化：`{name, path, mime, size, is_image}`。
  JsonValue toJsonValue() {
    final object = <String, JsonValue>{
      'name': JsonString(name),
      'path': JsonString(path),
      'mime': JsonString(mime),
      if (size != null) 'size': JsonNumber(size!.toDouble()),
      'is_image': JsonBool(isImage),
    };
    return JsonObject(object);
  }

  /// 拼接 `[Attached files: …]` 后缀。
  static String chatMessageText(
    String draft,
    List<PendingAttachment> attachments,
  ) {
    final references = attachments
        .map((a) => a.chatReference.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (references.isEmpty) return draft;
    return '$draft\n\n[Attached files: ${references.join(', ')}]';
  }

  @override
  bool operator ==(Object other) {
    return other is PendingAttachment &&
        other.id == id &&
        other.name == name &&
        other.path == path &&
        other.mime == mime &&
        other.size == size &&
        other.isImage == isImage;
  }

  @override
  int get hashCode => Object.hash(id, name, path, mime, size, isImage);

  @override
  String toString() => 'PendingAttachment(name: $name, path: $path)';
}
