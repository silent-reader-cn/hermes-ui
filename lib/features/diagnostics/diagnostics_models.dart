import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';

import '../../app/theme/status_colors.dart';

/// 诊断日志级别（五档）。
enum DiagnosticsLogLevel {
  verbose('V', 'VERBOSE'),
  debug('D', 'DEBUG'),
  info('I', 'INFO'),
  warn('W', 'WARN'),
  error('E', 'ERROR');

  const DiagnosticsLogLevel(this.code, this.label);

  /// 简短单字符代号（V/D/I/W/E）。
  final String code;

  /// 全称标签。
  final String label;

  /// 解析字符串为日志级别（大小写不敏感，默认 INFO）。
  static DiagnosticsLogLevel fromString(String? raw) {
    if (raw == null) return DiagnosticsLogLevel.info;
    final lower = raw.trim().toLowerCase();
    switch (lower) {
      case 'v':
      case 'verbose':
        return DiagnosticsLogLevel.verbose;
      case 'd':
      case 'debug':
        return DiagnosticsLogLevel.debug;
      case 'i':
      case 'info':
        return DiagnosticsLogLevel.info;
      case 'w':
      case 'warn':
      case 'warning':
        return DiagnosticsLogLevel.warn;
      case 'e':
      case 'error':
        return DiagnosticsLogLevel.error;
      default:
        return DiagnosticsLogLevel.info;
    }
  }

  /// 获取对应的 Cupertino 状态文字颜色（WCAG AA 达标）。
  CupertinoDynamicColor get textColor {
    switch (this) {
      case DiagnosticsLogLevel.verbose:
        return statusGreyText;
      case DiagnosticsLogLevel.debug:
        return _statusDebugText;
      case DiagnosticsLogLevel.info:
        return statusBlueText;
      case DiagnosticsLogLevel.warn:
        return statusOrangeText;
      case DiagnosticsLogLevel.error:
        return statusRedText;
    }
  }
}

/// 调试/蓝灰级别文字色（白底/黑底对比度均达标）。
const CupertinoDynamicColor _statusDebugText =
    CupertinoDynamicColor.withBrightnessAndContrast(
  color: Color(0xFF4A6B82),
  darkColor: Color(0xFF7AA5C2),
  highContrastColor: Color(0xFF2C4D64),
  darkHighContrastColor: Color(0xFF99C2DF),
);

/// 时间筛选范围。
enum DiagnosticsTimeFilter {
  all,
  today,
  last7Days,
  custom,
}

/// 诊断日志项数据模型。
class DiagnosticsLogEntry {
  const DiagnosticsLogEntry({
    required this.id,
    required this.timestamp,
    required this.level,
    required this.tag,
    required this.message,
    this.details,
    this.durationMs,
    this.errorKind,
  });

  /// 唯一标识。
  final String id;

  /// 时间戳（本地/UTC 统一保存）。
  final DateTime timestamp;

  /// 日志级别。
  final DiagnosticsLogLevel level;

  /// 来源标签（dio / sse / chat / global_error / app 等）。
  final String tag;

  /// 主消息摘要。
  final String message;

  /// 结构化详情（已脱敏）。
  final Map<String, Object?>? details;

  /// 耗时（毫秒）。
  final int? durationMs;

  /// 错误类型分类。
  final String? errorKind;

  /// 格式化后的 JSON 详情字符串。
  String get detailsJson {
    if (details == null || details!.isEmpty) return '';
    try {
      return const JsonEncoder.withIndent('  ').convert(details);
    } catch (_) {
      return details.toString();
    }
  }

  /// 序列化为 JSON Map。
  Map<String, Object?> toJson() {
    return {
      'id': id,
      'timestamp': timestamp.toIso8601String(),
      'level': level.name,
      'tag': tag,
      'message': message,
      if (details != null) 'details': details,
      if (durationMs != null) 'duration_ms': durationMs,
      if (errorKind != null) 'error_kind': errorKind,
    };
  }

  /// 从 JSON Map 容错反序列化。
  factory DiagnosticsLogEntry.fromJson(Map<String, Object?> json) {
    return DiagnosticsLogEntry(
      id: json['id'] as String? ?? '',
      timestamp:
          DateTime.tryParse(json['timestamp'] as String? ?? '') ??
          DateTime.now(),
      level: DiagnosticsLogLevel.fromString(json['level'] as String?),
      tag: json['tag'] as String? ?? '',
      message: json['message'] as String? ?? '',
      details: json['details'] is Map
          ? Map<String, Object?>.from(json['details'] as Map)
          : null,
      durationMs: (json['duration_ms'] as num?)?.toInt(),
      errorKind: json['error_kind'] as String?,
    );
  }

  /// 格式化单条文本（复制或导出）。
  String toExportString() {
    final sb = StringBuffer();
    final tsStr = formatLogTimestamp(timestamp);
    sb.write('[$tsStr] [${level.label.padRight(7)}] [$tag] $message');
    if (durationMs != null) {
      sb.write(' (${durationMs}ms)');
    }
    if (errorKind != null && errorKind!.isNotEmpty) {
      sb.write(' [error: $errorKind]');
    }
    if (details != null && details!.isNotEmpty) {
      sb.writeln();
      sb.write('Details:\n$detailsJson');
    }
    return sb.toString();
  }

  DiagnosticsLogEntry copyWith({
    String? id,
    DateTime? timestamp,
    DiagnosticsLogLevel? level,
    String? tag,
    String? message,
    Map<String, Object?>? details,
    int? durationMs,
    String? errorKind,
  }) {
    return DiagnosticsLogEntry(
      id: id ?? this.id,
      timestamp: timestamp ?? this.timestamp,
      level: level ?? this.level,
      tag: tag ?? this.tag,
      message: message ?? this.message,
      details: details ?? this.details,
      durationMs: durationMs ?? this.durationMs,
      errorKind: errorKind ?? this.errorKind,
    );
  }
}

/// 格式化日志时间戳 `YYYY-MM-DD HH:mm:ss.SSS`。
String formatLogTimestamp(DateTime dt) {
  final y = dt.year.toString().padLeft(4, '0');
  final m = dt.month.toString().padLeft(2, '0');
  final d = dt.day.toString().padLeft(2, '0');
  final h = dt.hour.toString().padLeft(2, '0');
  final min = dt.minute.toString().padLeft(2, '0');
  final s = dt.second.toString().padLeft(2, '0');
  final ms = dt.millisecond.toString().padLeft(3, '0');
  return '$y-$m-$d $h:$min:$s.$ms';
}

/// 格式化时间 `HH:mm:ss.SSS`。
String formatLogTimeOnly(DateTime dt) {
  final h = dt.hour.toString().padLeft(2, '0');
  final min = dt.minute.toString().padLeft(2, '0');
  final s = dt.second.toString().padLeft(2, '0');
  final ms = dt.millisecond.toString().padLeft(3, '0');
  return '$h:$min:$s.$ms';
}

/// 敏感 Header / Key 判定。
bool isSensitiveHeaderName(String headerName) {
  final lower = headerName.trim().toLowerCase();
  return lower == 'authorization' ||
      lower == 'cookie' ||
      lower == 'set-cookie' ||
      lower == 'proxy-authorization' ||
      lower.contains('token') ||
      lower.contains('secret') ||
      lower.contains('password') ||
      lower.contains('api-key') ||
      lower.contains('api_key') ||
      lower.contains('apikey') ||
      lower.contains('key') ||
      lower.contains('auth');
}

/// 过滤/脱敏请求 Headers。
Map<String, dynamic> sanitizeHeaders(Map<String, dynamic>? headers) {
  if (headers == null || headers.isEmpty) return const {};
  final sanitized = <String, dynamic>{};
  for (final entry in headers.entries) {
    if (isSensitiveHeaderName(entry.key)) {
      sanitized[entry.key] = '***';
    } else {
      sanitized[entry.key] = entry.value?.toString();
    }
  }
  return sanitized;
}

/// 递归脱敏 JSON 数据对象。
Object? sanitizeDataPayload(Object? data) {
  if (data == null) return null;
  if (data is Map) {
    final sanitizedMap = <String, Object?>{};
    for (final entry in data.entries) {
      final keyStr = entry.key.toString();
      if (isSensitiveHeaderName(keyStr)) {
        sanitizedMap[keyStr] = '***';
      } else {
        sanitizedMap[keyStr] = sanitizeDataPayload(entry.value);
      }
    }
    return sanitizedMap;
  }
  if (data is List) {
    return data.map(sanitizeDataPayload).toList();
  }
  if (data is String) {
    return truncateText(data, 3000);
  }
  return data;
}

/// 截断文本（超过 [maxLength] 附带截断标识）。
String truncateText(String text, int maxLength) {
  if (text.length <= maxLength) return text;
  final remaining = text.length - maxLength;
  return '${text.substring(0, maxLength)}... [truncated $remaining chars]';
}

/// 截断响应 Body 为字符串（最大 3000 字符）。
String? truncateResponseBody(Object? data, [int maxLength = 3000]) {
  if (data == null) return null;
  String text;
  if (data is Uint8List) {
    try {
      text = utf8.decode(data, allowMalformed: true);
    } catch (_) {
      return '<binary ${data.length} bytes>';
    }
  } else if (data is String) {
    text = data;
  } else {
    try {
      text = jsonEncode(data);
    } catch (_) {
      text = data.toString();
    }
  }
  return truncateText(text, maxLength);
}

/// 诊断页筛选条件状态。
class DiagnosticsFilterState {
  const DiagnosticsFilterState({
    this.selectedLevels = const {
      DiagnosticsLogLevel.verbose,
      DiagnosticsLogLevel.debug,
      DiagnosticsLogLevel.info,
      DiagnosticsLogLevel.warn,
      DiagnosticsLogLevel.error,
    },
    this.timeFilter = DiagnosticsTimeFilter.all,
    this.customStartDate,
    this.customEndDate,
    this.searchQuery = '',
  });

  /// 选中的级别集合。
  final Set<DiagnosticsLogLevel> selectedLevels;

  /// 时间筛选模式。
  final DiagnosticsTimeFilter timeFilter;

  /// 自定义起始时间。
  final DateTime? customStartDate;

  /// 自定义结束时间。
  final DateTime? customEndDate;

  /// 全文搜索关键词。
  final String searchQuery;

  DiagnosticsFilterState copyWith({
    Set<DiagnosticsLogLevel>? selectedLevels,
    DiagnosticsTimeFilter? timeFilter,
    DateTime? customStartDate,
    DateTime? customEndDate,
    bool clearCustomDates = false,
    String? searchQuery,
  }) {
    return DiagnosticsFilterState(
      selectedLevels: selectedLevels ?? this.selectedLevels,
      timeFilter: timeFilter ?? this.timeFilter,
      customStartDate: clearCustomDates
          ? null
          : (customStartDate ?? this.customStartDate),
      customEndDate: clearCustomDates
          ? null
          : (customEndDate ?? this.customEndDate),
      searchQuery: searchQuery ?? this.searchQuery,
    );
  }
}
