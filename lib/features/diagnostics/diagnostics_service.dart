import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/utils/uuid.dart';
import 'diagnostics_models.dart';

/// 诊断模式持久化键（对齐 todo.md #9 规格）。
const String kDiagnosticsEnabledKey = 'diagnostics_enabled';

/// 诊断日志持久化键。
const String kDiagnosticsLogsStorageKey = 'diagnostics_logs_v1';

/// 诊断服务（内存环形缓冲 + 异步 7 天持久化 + 脱敏纪律）。
class DiagnosticsService {
  DiagnosticsService({
    SharedPreferences? customPrefs,
    this.maxCapacity = 1500,
  }) : _prefs = customPrefs;

  /// 单例实例。
  static final DiagnosticsService instance = DiagnosticsService();

  final SharedPreferences? _prefs;

  /// 内存环形缓冲最大容量（1000 - 2000 条）。
  final int maxCapacity;

  /// 7 天持久化超期保留阈值。
  static const Duration retentionDuration = Duration(days: 7);

  bool _initialized = false;
  bool _enabled = false;
  final List<DiagnosticsLogEntry> _buffer = [];
  final StreamController<List<DiagnosticsLogEntry>> _logStreamController =
      StreamController<List<DiagnosticsLogEntry>>.broadcast();

  Timer? _saveDebounceTimer;

  /// 是否启用了诊断日志采集。
  bool get enabled => _enabled;

  /// 诊断更新流。
  Stream<List<DiagnosticsLogEntry>> get logsStream =>
      _logStreamController.stream;

  /// 获取当前日志列表快照（只读副本，最新在后或最新在前均可转换）。
  List<DiagnosticsLogEntry> get logs => List.unmodifiable(_buffer);

  /// 初始化服务：加载开关状态与持久化日志。
  Future<void> init({SharedPreferences? prefs}) async {
    if (_initialized) return;
    try {
      final p = prefs ?? _prefs ?? await SharedPreferences.getInstance();
      _enabled = p.getBool(kDiagnosticsEnabledKey) ?? false;
      final rawLogs = p.getString(kDiagnosticsLogsStorageKey);
      if (rawLogs != null && rawLogs.isNotEmpty) {
        final decoded = jsonDecode(rawLogs);
        if (decoded is List) {
          final now = DateTime.now();
          final cutoff = now.subtract(retentionDuration);
          _buffer.clear();
          for (final item in decoded) {
            if (item is Map) {
              final entry = DiagnosticsLogEntry.fromJson(
                Map<String, Object?>.from(item),
              );
              // 仅保留近 7 天内的日志
              if (entry.timestamp.isAfter(cutoff)) {
                _buffer.add(entry);
              }
            }
          }
          _pruneBuffer();
        }
      }
    } catch (error) {
      debugPrint('DiagnosticsService.init failed: $error');
    } finally {
      _initialized = true;
      _logStreamController.add(List.unmodifiable(_buffer));
    }
  }

  /// 设置并持久化开关。
  Future<void> setEnabled(bool value, {SharedPreferences? prefs}) async {
    _enabled = value;
    try {
      final p = prefs ?? _prefs ?? await SharedPreferences.getInstance();
      await p.setBool(kDiagnosticsEnabledKey, value);
    } catch (_) {}
  }

  /// 记录一条诊断日志（仅在 [enabled] == true 时采集）。
  void log({
    required DiagnosticsLogLevel level,
    required String tag,
    required String message,
    Map<String, Object?>? details,
    int? durationMs,
    String? errorKind,
    DateTime? timestamp,
  }) {
    if (!_enabled) return;

    // 脱敏详情数据
    final sanitizedDetails = details != null
        ? sanitizeDataPayload(details) as Map<String, Object?>?
        : null;

    final entry = DiagnosticsLogEntry(
      id: uuidV4(),
      timestamp: timestamp ?? DateTime.now(),
      level: level,
      tag: tag,
      message: truncateText(message, 1000),
      details: sanitizedDetails,
      durationMs: durationMs,
      errorKind: errorKind,
    );

    _buffer.add(entry);
    _pruneBuffer();
    _logStreamController.add(List.unmodifiable(_buffer));
    _scheduleDebouncedSave();
  }

  /// 清空内存与磁盘上的所有日志。
  Future<void> clear({SharedPreferences? prefs}) async {
    _buffer.clear();
    _saveDebounceTimer?.cancel();
    _saveDebounceTimer = null;
    _logStreamController.add(const []);
    try {
      final p = prefs ?? _prefs ?? await SharedPreferences.getInstance();
      await p.remove(kDiagnosticsLogsStorageKey);
    } catch (_) {}
  }

  void _pruneBuffer() {
    if (_buffer.length > maxCapacity) {
      final overflow = _buffer.length - maxCapacity;
      _buffer.removeRange(0, overflow);
    }
  }

  void _scheduleDebouncedSave() {
    _saveDebounceTimer?.cancel();
    _saveDebounceTimer = Timer(const Duration(milliseconds: 500), () {
      _saveDebounceTimer = null;
      unawaited(_saveToStorage());
    });
  }

  Future<void> _saveToStorage({SharedPreferences? prefs}) async {
    try {
      final p = prefs ?? _prefs ?? await SharedPreferences.getInstance();
      final now = DateTime.now();
      final cutoff = now.subtract(retentionDuration);

      // 清理超过 7 天日志
      final validEntries =
          _buffer.where((e) => e.timestamp.isAfter(cutoff)).toList();
      final serialized = jsonEncode(validEntries.map((e) => e.toJson()).toList());
      await p.setString(kDiagnosticsLogsStorageKey, serialized);
    } catch (error) {
      debugPrint('DiagnosticsService._saveToStorage failed: $error');
    }
  }

  /// 生成导出的文件名 `Diagnostics_YYYYMMDD_HHmmss.txt`。
  static String generateExportFileName([DateTime? now]) {
    final dt = now ?? DateTime.now();
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return 'Diagnostics_$y$m${d}_$h$min$s.txt';
  }

  /// 生成完整大文本导出内容（UTF-8 纯文本）。
  static String formatExportText(List<DiagnosticsLogEntry> entries, [DateTime? now]) {
    final dt = now ?? DateTime.now();
    final sb = StringBuffer();
    sb.writeln('=' * 60);
    sb.writeln('Hermes Diagnostics Log Export');
    sb.writeln('Exported At: ${formatLogTimestamp(dt)}');
    sb.writeln('Total Entries: ${entries.length}');
    sb.writeln('=' * 60);
    sb.writeln();

    for (var i = 0; i < entries.length; i++) {
      sb.writeln(entries[i].toExportString());
      if (i < entries.length - 1) {
        sb.writeln('-' * 60);
      }
    }
    return sb.toString();
  }

  @visibleForTesting
  void clearMemoryOnly() {
    _buffer.clear();
    _saveDebounceTimer?.cancel();
    _saveDebounceTimer = null;
    _logStreamController.add(const []);
  }
}
