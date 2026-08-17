import 'dart:typed_data';

import 'package:file_picker/file_picker.dart' as fp;

/// 文件选择结果（跨平台封装）。
///
/// 来自 [FilePickerService.pickFile]；`bytes` 为完整文件内容，
/// `size` 为其字节数（与 `bytes.length` 一致）。
class FilePickerResult {
  const FilePickerResult({
    required this.name,
    required this.bytes,
  });

  /// 文件名（含扩展名，如 `report.pdf`）。
  final String name;

  /// 文件二进制内容。
  final Uint8List bytes;

  /// 文件大小（字节）。
  int get size => bytes.length;
}

/// 跨平台文件选择器抽象。
///
/// 生产实现 [PlatformFilePickerService] 走 `file_picker` 包；
/// 测试注入 [FakeFilePickerService] 或自定义 fake，避免碰平台通道。
abstract interface class FilePickerService {
  /// 弹出系统文件选择器，返回所选文件；用户取消返回 null。
  Future<FilePickerResult?> pickFile({List<String>? allowedExtensions});
}

/// 生产实现：包装 `file_picker` 包（^12 静态 API）。
class PlatformFilePickerService implements FilePickerService {
  const PlatformFilePickerService();

  @override
  Future<FilePickerResult?> pickFile({List<String>? allowedExtensions}) async {
    final file = await fp.FilePicker.pickFile(
      type: allowedExtensions == null ? fp.FileType.any : fp.FileType.custom,
      allowedExtensions: allowedExtensions,
    );
    if (file == null || file.name.isEmpty) return null;
    final bytes = await file.readAsBytes();
    return FilePickerResult(name: file.name, bytes: bytes);
  }
}

/// 测试用：固定返回一个文件（或抛错/返回 null 模拟取消/失败）。
class FakeFilePickerService implements FilePickerService {
  FakeFilePickerService({this.result, this.error});

  /// 要返回的结果；null 表示用户取消。
  final FilePickerResult? result;

  /// 若设置，pickFile 直接抛此异常（模拟平台失败）。
  final Object? error;

  @override
  Future<FilePickerResult?> pickFile({List<String>? allowedExtensions}) async {
    if (error != null) throw error!;
    return result;
  }
}