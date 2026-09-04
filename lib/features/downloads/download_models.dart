import '../../core/utils/lossy_json.dart';

/// 下载状态枚举。
enum DownloadStatus {
  queued,
  downloading,
  completed,
  failed,
  cancelled;

  /// 从字符串安全解析（容错未知/null）。
  static DownloadStatus fromString(String? value) {
    if (value == null) return DownloadStatus.queued;
    for (final status in DownloadStatus.values) {
      if (status.name == value) return status;
    }
    return DownloadStatus.queued;
  }
}

/// 下载来源类型。
enum DownloadSourceType {
  url,
  bytes;

  /// 从字符串安全解析（容错未知/null）。
  static DownloadSourceType fromString(String? value) {
    if (value == 'bytes') return DownloadSourceType.bytes;
    return DownloadSourceType.url;
  }
}

/// 下载任务数据模型。
class DownloadTask {
  const DownloadTask({
    required this.id,
    required this.sourceUrl,
    required this.fileName,
    this.mimeType,
    this.expectedBytes,
    this.receivedBytes = 0,
    this.status = DownloadStatus.queued,
    this.savedPath,
    required this.createdAt,
    this.completedAt,
    this.failureMessage,
    this.sessionId,
    this.sourceType = DownloadSourceType.url,
  });

  /// 任务唯一标识符（UUID）。
  final String id;

  /// 远程下载源 URL（或 bytes 占位源）。
  final String sourceUrl;

  /// 目标文件名。
  final String fileName;

  /// 来源类型（URL 或直接内存字节）。
  final DownloadSourceType sourceType;

  /// MIME 内容类型。
  final String? mimeType;

  /// 预期总字节数（Content-Length；未知为 null）。
  final int? expectedBytes;

  /// 已接收字节数。
  final int receivedBytes;

  /// 当前下载状态。
  final DownloadStatus status;

  /// 本地已保存的绝对路径（下载完成前为 null）。
  final String? savedPath;

  /// 创建时间戳（epoch 毫秒）。
  final int createdAt;

  /// 完成/终止时间戳（epoch 毫秒；未终止为 null）。
  final int? completedAt;

  /// 失败原因说明（成功/进行中为 null）。
  final String? failureMessage;

  /// 关联会话 ID（可选）。
  final String? sessionId;

  /// 下载进度（0.0 .. 1.0；若预期总大小未知或 <= 0 则返回 null）。
  double? get progress {
    if (expectedBytes != null && expectedBytes! > 0) {
      return (receivedBytes / expectedBytes!).clamp(0.0, 1.0);
    }
    return null;
  }

  /// 是否处于活跃状态（排队中或正在下载）。
  bool get isActive =>
      status == DownloadStatus.queued || status == DownloadStatus.downloading;

  /// 是否处于终态（完成、失败或已取消）。
  bool get isTerminal =>
      status == DownloadStatus.completed ||
      status == DownloadStatus.failed ||
      status == DownloadStatus.cancelled;

  static const Object _sentinel = Object();

  /// 创建不可变副本并替换指定属性（支持将可空字段显式置为 null）。
  DownloadTask copyWith({
    String? id,
    String? sourceUrl,
    String? fileName,
    String? mimeType,
    Object? expectedBytes = _sentinel,
    int? receivedBytes,
    DownloadStatus? status,
    Object? savedPath = _sentinel,
    int? createdAt,
    Object? completedAt = _sentinel,
    Object? failureMessage = _sentinel,
    Object? sessionId = _sentinel,
    DownloadSourceType? sourceType,
  }) {
    return DownloadTask(
      id: id ?? this.id,
      sourceUrl: sourceUrl ?? this.sourceUrl,
      fileName: fileName ?? this.fileName,
      mimeType: mimeType ?? this.mimeType,
      expectedBytes: expectedBytes == _sentinel
          ? this.expectedBytes
          : expectedBytes as int?,
      receivedBytes: receivedBytes ?? this.receivedBytes,
      status: status ?? this.status,
      savedPath: savedPath == _sentinel ? this.savedPath : savedPath as String?,
      createdAt: createdAt ?? this.createdAt,
      completedAt: completedAt == _sentinel
          ? this.completedAt
          : completedAt as int?,
      failureMessage: failureMessage == _sentinel
          ? this.failureMessage
          : failureMessage as String?,
      sessionId: sessionId == _sentinel ? this.sessionId : sessionId as String?,
      sourceType: sourceType ?? this.sourceType,
    );
  }

  /// 容错 JSON 反序列化。
  factory DownloadTask.fromJson(Object? json) {
    if (json is! Map) {
      return const DownloadTask(
        id: '',
        sourceUrl: '',
        fileName: '',
        createdAt: 0,
      );
    }
    Map<String, Object?> map;
    try {
      map = Map<String, Object?>.from(json);
    } catch (_) {
      return const DownloadTask(
        id: '',
        sourceUrl: '',
        fileName: '',
        createdAt: 0,
      );
    }

    final rawStatus =
        lossyString(map, 'status') ?? lossyString(map, 'download_status');
    final rawSourceType =
        lossyString(map, 'source_type') ?? lossyString(map, 'sourceType');
    return DownloadTask(
      id: lossyString(map, 'id') ?? '',
      sourceUrl:
          lossyString(map, 'source_url') ?? lossyString(map, 'sourceUrl') ?? '',
      fileName:
          lossyString(map, 'file_name') ?? lossyString(map, 'fileName') ?? '',
      mimeType: lossyString(map, 'mime_type') ?? lossyString(map, 'mimeType'),
      expectedBytes:
          lossyInt(map, 'expected_bytes') ?? lossyInt(map, 'expectedBytes'),
      receivedBytes:
          lossyInt(map, 'received_bytes') ??
          lossyInt(map, 'receivedBytes') ??
          0,
      status: DownloadStatus.fromString(rawStatus),
      savedPath:
          lossyString(map, 'saved_path') ?? lossyString(map, 'savedPath'),
      createdAt: lossyInt(map, 'created_at') ?? lossyInt(map, 'createdAt') ?? 0,
      completedAt:
          lossyInt(map, 'completed_at') ?? lossyInt(map, 'completedAt'),
      failureMessage:
          lossyString(map, 'failure_message') ??
          lossyString(map, 'failureMessage'),
      sessionId:
          lossyString(map, 'session_id') ?? lossyString(map, 'sessionId'),
      sourceType: DownloadSourceType.fromString(rawSourceType),
    );
  }

  /// 序列化为 Map。
  Map<String, Object?> toJson() {
    return {
      'id': id,
      'source_url': sourceUrl,
      'file_name': fileName,
      'source_type': sourceType.name,
      if (mimeType != null) 'mime_type': mimeType,
      if (expectedBytes != null) 'expected_bytes': expectedBytes,
      'received_bytes': receivedBytes,
      'status': status.name,
      if (savedPath != null) 'saved_path': savedPath,
      'created_at': createdAt,
      if (completedAt != null) 'completed_at': completedAt,
      if (failureMessage != null) 'failure_message': failureMessage,
      if (sessionId != null) 'session_id': sessionId,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DownloadTask &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          sourceUrl == other.sourceUrl &&
          fileName == other.fileName &&
          mimeType == other.mimeType &&
          expectedBytes == other.expectedBytes &&
          receivedBytes == other.receivedBytes &&
          status == other.status &&
          savedPath == other.savedPath &&
          createdAt == other.createdAt &&
          completedAt == other.completedAt &&
          failureMessage == other.failureMessage &&
          sessionId == other.sessionId &&
          sourceType == other.sourceType;

  @override
  int get hashCode => Object.hash(
    id,
    sourceUrl,
    fileName,
    mimeType,
    expectedBytes,
    receivedBytes,
    status,
    savedPath,
    createdAt,
    completedAt,
    failureMessage,
    sessionId,
    sourceType,
  );

  @override
  String toString() =>
      'DownloadTask(id: $id, fileName: $fileName, status: ${status.name}, '
      'sourceType: ${sourceType.name}, received: $receivedBytes, '
      'expected: $expectedBytes, savedPath: $savedPath)';
}

/// 文件类型分类。
enum DownloadFileType { image, audio, video, document, archive, code, other }

/// 根据文件名或 MIME 推断文件类型分类（纯函数）。
DownloadFileType getDownloadFileType({String? fileName, String? mimeType}) {
  final mime = mimeType?.toLowerCase().trim() ?? '';
  if (mime.startsWith('image/')) return DownloadFileType.image;
  if (mime.startsWith('audio/')) return DownloadFileType.audio;
  if (mime.startsWith('video/')) return DownloadFileType.video;
  if (mime == 'application/pdf' ||
      mime.contains('msword') ||
      mime.contains('wordprocessingml') ||
      mime.contains('presentation') ||
      mime.contains('spreadsheet') ||
      mime.startsWith('text/plain')) {
    return DownloadFileType.document;
  }
  if (mime.contains('zip') ||
      mime.contains('tar') ||
      mime.contains('compressed') ||
      mime.contains('7z') ||
      mime.contains('rar')) {
    return DownloadFileType.archive;
  }
  if (mime.contains('json') ||
      mime.contains('javascript') ||
      mime.contains('typescript') ||
      mime.contains('xml') ||
      mime.contains('yaml')) {
    return DownloadFileType.code;
  }

  if (fileName != null && fileName.isNotEmpty) {
    final ext = extractFileExtension(fileName);
    if (const {
      'jpg',
      'jpeg',
      'png',
      'gif',
      'webp',
      'heic',
      'heif',
      'bmp',
      'svg',
      'ico',
      'avif',
    }.contains(ext)) {
      return DownloadFileType.image;
    }
    if (const {
      'mp3',
      'wav',
      'ogg',
      'm4a',
      'aac',
      'flac',
      'wma',
      'opus',
    }.contains(ext)) {
      return DownloadFileType.audio;
    }
    if (const {
      'mp4',
      'mkv',
      'mov',
      'avi',
      'webm',
      'flv',
      'm4v',
    }.contains(ext)) {
      return DownloadFileType.video;
    }
    if (const {
      'pdf',
      'doc',
      'docx',
      'xls',
      'xlsx',
      'ppt',
      'pptx',
      'txt',
      'md',
      'rtf',
      'csv',
    }.contains(ext)) {
      return DownloadFileType.document;
    }
    if (const {
      'zip',
      'rar',
      '7z',
      'tar',
      'gz',
      'bz2',
      'xz',
      'apk',
      'iso',
    }.contains(ext)) {
      return DownloadFileType.archive;
    }
    if (const {
      'dart',
      'js',
      'ts',
      'py',
      'java',
      'c',
      'cpp',
      'h',
      'go',
      'rs',
      'swift',
      'kt',
      'html',
      'css',
      'json',
      'yaml',
      'yml',
      'xml',
      'sql',
      'sh',
      'bat',
      'ps1',
    }.contains(ext)) {
      return DownloadFileType.code;
    }
  }

  return DownloadFileType.other;
}

/// 提取文件名的扩展名（小写，不带前导点）。
String extractFileExtension(String fileName) {
  var clean = fileName.split('?').first.split('#').first;
  clean = clean.replaceAll(RegExp(r'[.,;:!?]+$'), '');
  final lastSlash = clean.lastIndexOf(RegExp(r'[/\\]'));
  final nameOnly = lastSlash == -1 ? clean : clean.substring(lastSlash + 1);
  final dot = nameOnly.lastIndexOf('.');
  if (dot == -1 || dot == nameOnly.length - 1) return '';
  return nameOnly.substring(dot + 1).toLowerCase();
}

/// 格式化字节数大小为人类可读字符串（纯函数）。
String formatDownloadByteSize(int bytes) {
  if (bytes <= 0) return '0 B';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}
