import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// 剪贴板安全写入结果。
sealed class SafeClipboardResult {
  const SafeClipboardResult();

  /// 是否成功写入系统剪贴板。
  bool get isClipboard => this is SafeClipboardSuccess;

  /// 是否降级/超限保存为本地文件。
  bool get isFileSaved => this is SafeClipboardFileSaved;

  /// 若为文件落盘，返回绝对文件路径；若写入剪贴板成功则返回 null。
  String? get filePath => switch (this) {
    SafeClipboardSuccess() => null,
    SafeClipboardFileSaved(:final filePath) => filePath,
  };
}

/// 写入系统剪贴板成功。
class SafeClipboardSuccess extends SafeClipboardResult {
  const SafeClipboardSuccess();
}

/// 超限或剪贴板异常降级落盘为本地文件。
class SafeClipboardFileSaved extends SafeClipboardResult {
  const SafeClipboardFileSaved(this.filePath);

  /// 保存的绝对文件路径。
  @override
  final String filePath;
}

/// 安全剪贴板工具类。
///
/// 针对 Android 剪贴板 ~1MB TransactionTooLargeException 崩溃隐患，
/// 提供「UTF-8 字节阈值判定 + 超限自动落盘 + PlatformException 兜底降级」能力。
abstract final class SafeClipboard {
  /// 默认剪贴板写入上限阈值：512KB (524,288 字节)。
  static const int maxClipboardBytes = 512 * 1024;

  @visibleForTesting
  static Directory? destinationDirOverride;

  @visibleForTesting
  static Future<void> Function(String text)? clipboardSetterOverride;

  @visibleForTesting
  static DateTime Function()? clockOverride;

  @visibleForTesting
  static int? maxBytesOverride;

  /// 重置所有测试覆盖项。
  @visibleForTesting
  static void resetOverridesForTesting() {
    destinationDirOverride = null;
    clipboardSetterOverride = null;
    clockOverride = null;
    maxBytesOverride = null;
  }

  /// 计算文本 UTF-8 编码后的字节数。
  static int getUtf8ByteLength(String text) => utf8.encode(text).length;

  /// 判定给定文本是否应走文件导出路径（UTF-8 字节数 > 阈值）。
  static bool shouldUseFileExport(String text, [int? maxBytes]) {
    final threshold = maxBytes ?? maxBytesOverride ?? maxClipboardBytes;
    return getUtf8ByteLength(text) > threshold;
  }

  /// 格式化导出文件名：`hermes_logs_export_<yyyyMMdd_HHmmss>.txt`。
  static String formatExportFileName(
    DateTime time, {
    String prefix = 'hermes_logs_export',
  }) {
    final y = time.year.toString().padLeft(4, '0');
    final m = time.month.toString().padLeft(2, '0');
    final d = time.day.toString().padLeft(2, '0');
    final h = time.hour.toString().padLeft(2, '0');
    final min = time.minute.toString().padLeft(2, '0');
    final s = time.second.toString().padLeft(2, '0');
    return '${prefix}_$y$m${d}_$h$min$s.txt';
  }

  /// 解析目标保存目录（Downloads 优先，Documents 次之，兜底 Temp）。
  static Future<Directory> resolveExportDirectory({
    Directory? overrideDir,
  }) async {
    final targetDir = overrideDir ?? destinationDirOverride;
    if (targetDir != null) {
      if (!targetDir.existsSync()) {
        await targetDir.create(recursive: true);
      }
      return targetDir;
    }

    // 1. 尝试 Downloads 目录（桌面端首选）
    try {
      final downloads = await getDownloadsDirectory();
      if (downloads != null) {
        if (!downloads.existsSync()) {
          await downloads.create(recursive: true);
        }
        return downloads;
      }
    } catch (_) {}

    // 2. 尝试 ApplicationDocuments 目录（移动端/通用首选）
    try {
      final docs = await getApplicationDocumentsDirectory();
      if (!docs.existsSync()) {
        await docs.create(recursive: true);
      }
      return docs;
    } catch (_) {}

    // 3. 兜底 Temporary 目录
    try {
      final temp = await getTemporaryDirectory();
      if (!temp.existsSync()) {
        await temp.create(recursive: true);
      }
      return temp;
    } catch (_) {}

    // 4. 极端兜底：系统临时目录
    return Directory.systemTemp;
  }

  /// 安全写入剪贴板或超限/异常时落盘为文件。
  ///
  /// - UTF-8 字节数 ≤ 512KB：尝试 [Clipboard.setData]；
  ///   - 成功返回 [SafeClipboardSuccess]；
  ///   - 抛出 [PlatformException] 则降级保存为本地文件并返回 [SafeClipboardFileSaved]；
  /// - UTF-8 字节数 > 512KB：直接保存为本地文件并返回 [SafeClipboardFileSaved]。
  static Future<SafeClipboardResult> copyOrSave(
    String text, {
    String fileNamePrefix = 'hermes_logs_export',
    Directory? destinationDir,
  }) async {
    if (shouldUseFileExport(text)) {
      return _saveToFile(
        text,
        fileNamePrefix: fileNamePrefix,
        destinationDir: destinationDir,
      );
    }

    try {
      if (clipboardSetterOverride != null) {
        await clipboardSetterOverride!(text);
      } else {
        await Clipboard.setData(ClipboardData(text: text));
      }
      return const SafeClipboardSuccess();
    } on PlatformException catch (e, stack) {
      developer.log(
        'Clipboard.setData failed with PlatformException, falling back to file export',
        name: 'SafeClipboard',
        error: e,
        stackTrace: stack,
      );
      return _saveToFile(
        text,
        fileNamePrefix: fileNamePrefix,
        destinationDir: destinationDir,
      );
    } catch (e, stack) {
      developer.log(
        'Clipboard.setData failed unexpectedly, falling back to file export',
        name: 'SafeClipboard',
        error: e,
        stackTrace: stack,
      );
      return _saveToFile(
        text,
        fileNamePrefix: fileNamePrefix,
        destinationDir: destinationDir,
      );
    }
  }

  static Future<SafeClipboardFileSaved> _saveToFile(
    String text, {
    required String fileNamePrefix,
    Directory? destinationDir,
  }) async {
    final dir = await resolveExportDirectory(overrideDir: destinationDir);
    final now = clockOverride != null ? clockOverride!() : DateTime.now();
    final fileName = formatExportFileName(now, prefix: fileNamePrefix);
    final file = _resolveNonConflictingFile(dir, fileName);
    file.writeAsStringSync(text, flush: true);
    return SafeClipboardFileSaved(file.path);
  }

  static File _resolveNonConflictingFile(Directory dir, String fileName) {
    final separator = dir.path.contains('\\') ? '\\' : '/';
    var candidate = File('${dir.path}$separator$fileName');
    if (!candidate.existsSync()) {
      return candidate;
    }

    final dotIndex = fileName.lastIndexOf('.');
    final base = dotIndex != -1 ? fileName.substring(0, dotIndex) : fileName;
    final ext = dotIndex != -1 ? fileName.substring(dotIndex) : '';

    var index = 1;
    while (candidate.existsSync()) {
      candidate = File('${dir.path}$separator$base ($index)$ext');
      index++;
    }
    return candidate;
  }
}
