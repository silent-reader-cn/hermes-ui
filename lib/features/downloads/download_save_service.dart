import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// 文件保存异常。
class DownloadSaveException implements Exception {
  const DownloadSaveException(this.message);

  final String message;

  @override
  String toString() => 'DownloadSaveException: $message';
}

/// 跨平台用户 Downloads 目录保存服务。
///
/// 核心职责：
/// 1. **Windows 平台**：优先解析 `%USERPROFILE%\Downloads` 或 `%HOME%\Downloads`，
///    确保保存至真实用户 Downloads 目录，而不是内部沙盒；
/// 2. **Android 平台**：适配目标 SDK 37 / Android 11+ 规范，尝试公共 Downloads 目录。
///    若权限受限无法写入，**必须显式抛出 [DownloadSaveException] 失败**，严禁私写内部缓存并假冒成功；
/// 3. **macOS / Linux / iOS**：优先系统 Downloads，兜底文档目录子文件夹；
/// 4. **文件名清理**：自动移除路径分隔符、危险遍历序列（`../`）及非法字符；
/// 5. **冲突保护**：已存在同名文件时自动追加 `(1)`, `(2)` 后缀，绝不覆盖已有文件；
/// 6. **可测试性**：支持注入目标目录、写入器及平台覆盖。
class DownloadSaveService {
  DownloadSaveService({
    this.destinationDirOverride,
    this.isWindowsOverride,
    this.isAndroidOverride,
    this.environmentOverride,
    this.fileWriterOverride,
  });

  final Directory? destinationDirOverride;
  final bool? isWindowsOverride;
  final bool? isAndroidOverride;
  final Map<String, String>? environmentOverride;
  final Future<void> Function(File file, Uint8List bytes)? fileWriterOverride;

  bool get _isAndroid =>
      isAndroidOverride ??
      (isWindowsOverride == true ? false : Platform.isAndroid);

  bool get _isWindows =>
      isWindowsOverride ??
      (isAndroidOverride == true ? false : Platform.isWindows);

  Map<String, String> get _env => environmentOverride ?? Platform.environment;

  /// 将字节数据安全保存到平台的 Downloads 目录中。
  ///
  /// 返回保存成功的绝对文件路径；若保存失败则抛出 [DownloadSaveException]。
  Future<String> save({
    required String fileName,
    required Uint8List bytes,
    String? mimeType,
  }) async {
    final cleanName = sanitizeFileName(fileName, mimeType: mimeType);
    final targetDir = await resolveDestinationDirectory();

    final targetFile = resolveNonConflictingFile(targetDir, cleanName);

    try {
      if (fileWriterOverride != null) {
        await fileWriterOverride!(targetFile, bytes);
      } else {
        await targetFile.writeAsBytes(bytes, flush: true);
      }
      return targetFile.path;
    } on Object catch (error) {
      throw DownloadSaveException('写入文件失败 (${targetFile.path}): $error');
    }
  }

  /// 解析目标保存目录。
  Future<Directory> resolveDestinationDirectory() async {
    if (destinationDirOverride != null) {
      if (!destinationDirOverride!.existsSync()) {
        await destinationDirOverride!.create(recursive: true);
      }
      return destinationDirOverride!;
    }

    if (_isAndroid) {
      // Android 目标 SDK 37：尝试公共 Downloads 目录。
      // 若受 Android 11+ Scoped Storage / 权限限制无法写入，必须显式抛错，不得私写缓存。
      const publicDownloadPath = '/storage/emulated/0/Download';
      final publicDir = Directory(publicDownloadPath);
      try {
        if (publicDir.existsSync()) {
          // 探活探测是否可写
          final probeFile = File(
            '$publicDownloadPath/.probe_${DateTime.now().millisecondsSinceEpoch}',
          );
          try {
            await probeFile.writeAsString('probe', flush: true);
            await probeFile.delete();
            return publicDir;
          } catch (_) {
            throw const DownloadSaveException(
              'Android 目标 SDK 37 权限限制：无法写入公共 Downloads 目录',
            );
          }
        } else {
          throw const DownloadSaveException('Android 公共 Downloads 目录不存在且无权限创建');
        }
      } on DownloadSaveException {
        rethrow;
      } catch (error) {
        throw DownloadSaveException('无法写入 Android 公共 Downloads 目录: $error');
      }
    }

    if (_isWindows) {
      final userProfile = _env['USERPROFILE'];
      if (userProfile != null && userProfile.trim().isNotEmpty) {
        final winDownloads = Directory('$userProfile\\Downloads');
        if (winDownloads.existsSync()) return winDownloads;
        try {
          await winDownloads.create(recursive: true);
          return winDownloads;
        } catch (_) {}
      }

      final home = _env['HOME'];
      if (home != null && home.trim().isNotEmpty) {
        final homeDownloads = Directory('$home\\Downloads');
        if (homeDownloads.existsSync()) return homeDownloads;
        try {
          await homeDownloads.create(recursive: true);
          return homeDownloads;
        } catch (_) {}
      }

      try {
        final downloads = await getDownloadsDirectory();
        if (downloads != null) {
          if (!downloads.existsSync()) await downloads.create(recursive: true);
          return downloads;
        }
      } catch (_) {}

      throw const DownloadSaveException('Windows 无法定位或创建用户 Downloads 目录');
    }

    // macOS / Linux / iOS / 其他平台
    try {
      final downloads = await getDownloadsDirectory();
      if (downloads != null) {
        if (!downloads.existsSync()) await downloads.create(recursive: true);
        return downloads;
      }
    } catch (_) {}

    try {
      final docs = await getApplicationDocumentsDirectory();
      final downloadsSub = Directory('${docs.path}/Downloads');
      if (!downloadsSub.existsSync()) {
        await downloadsSub.create(recursive: true);
      }
      return downloadsSub;
    } catch (error) {
      throw DownloadSaveException('无法获取或创建保存目录: $error');
    }
  }

  /// 清理文件名，移除非法字符与路径分隔符。
  static String sanitizeFileName(String rawName, {String? mimeType}) {
    var name = rawName.trim();

    // 如果传入的是完整 URL，提取其路径最后一段
    if (name.startsWith('http://') || name.startsWith('https://')) {
      try {
        final uri = Uri.parse(name);
        name = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : name;
      } catch (_) {}
    } else {
      // 若带有 query/hash（如 archive.tar.gz?v=2#sec），仅在包含 = 或 & 时剥离 query
      if (name.contains('?') && (name.contains('=') || name.contains('&'))) {
        name = name.split('?').first;
      }
      if (name.contains('#')) {
        name = name.split('#').first;
      }
    }

    // 移除路径分隔符，只保留最后一段
    name = name.replaceAll(RegExp(r'[\\/]+'), '/');
    if (name.contains('/')) {
      name = name.substring(name.lastIndexOf('/') + 1);
    }

    // 移除 Windows / 常见文件系统非法字符: < > : " / \ | ? * 以及控制字符
    name = name.replaceAll(RegExp(r'[\x00-\x1F\x7F<>:"/\\|?*]'), '_');

    // 移除前导与尾随的点号与空白
    name = name.replaceAll(RegExp(r'^[.\s]+|[.\s]+$'), '');

    if (name.isEmpty) {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final ext = _defaultExtensionForMime(mimeType);
      return ext.isNotEmpty
          ? 'download_$timestamp.$ext'
          : 'download_$timestamp';
    }

    return name;
  }

  /// 在目标目录中寻找不冲突的文件对象（同名生成 `name (1).ext`, `name (2).ext`）。
  static File resolveNonConflictingFile(
    Directory directory,
    String cleanFileName,
  ) {
    final separator = directory.path.contains('\\') ? '\\' : '/';
    final initialPath = '${directory.path}$separator$cleanFileName';
    final initialFile = File(initialPath);
    if (!initialFile.existsSync()) {
      return initialFile;
    }

    final dotIndex = cleanFileName.lastIndexOf('.');
    final String baseName;
    final String extension;
    if (dotIndex != -1 && dotIndex > 0) {
      baseName = cleanFileName.substring(0, dotIndex);
      extension = cleanFileName.substring(dotIndex); // 包含点号，如 ".pdf"
    } else {
      baseName = cleanFileName;
      extension = '';
    }

    var index = 1;
    while (true) {
      final candidateName = '$baseName ($index)$extension';
      final candidatePath = '${directory.path}$separator$candidateName';
      final candidateFile = File(candidatePath);
      if (!candidateFile.existsSync()) {
        return candidateFile;
      }
      index++;
    }
  }

  static String _defaultExtensionForMime(String? mimeType) {
    if (mimeType == null || mimeType.isEmpty) return '';
    final mime = mimeType.toLowerCase();
    if (mime.contains('image/png')) return 'png';
    if (mime.contains('image/jpeg')) return 'jpg';
    if (mime.contains('image/webp')) return 'webp';
    if (mime.contains('image/gif')) return 'gif';
    if (mime.contains('application/pdf')) return 'pdf';
    if (mime.contains('application/zip')) return 'zip';
    if (mime.contains('text/plain')) return 'txt';
    if (mime.contains('application/json')) return 'json';
    return '';
  }
}
