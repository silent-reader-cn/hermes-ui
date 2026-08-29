/// 系统健康状态响应模型（对应 GET /api/system/health）。
///
/// 后端 build_system_health_payload 产出：
/// {status, available, checked_at, cpu:{percent}, memory:{...}, disk:{...}, errors[]}
class SystemHealthResponse {
  const SystemHealthResponse({
    required this.status,
    required this.available,
    required this.checkedAt,
    required this.cpu,
    required this.memory,
    required this.disk,
    this.errors = const [],
  });

  /// 整体状态（'ok' / 'degraded' / 'unavailable'）。
  final String status;

  /// 服务是否可用。
  final bool available;

  /// 采样时间（ISO 8601）。
  final String checkedAt;

  /// CPU 信息。
  final SystemHealthCpu cpu;

  /// 内存信息。
  final SystemHealthMemory memory;

  /// 磁盘信息。
  final SystemHealthDisk disk;

  /// 错误列表（后端 try/except 产出）。
  final List<String> errors;

  /// 从 JSON 容错解析。未知字段忽略；字段缺失给安全默认值。
  factory SystemHealthResponse.fromJson(Map<String, Object?> json) {
    return SystemHealthResponse(
      status: json['status'] is String ? json['status'] as String : 'unknown',
      available: json['available'] is bool ? json['available'] as bool : false,
      checkedAt:
          json['checked_at'] is String ? json['checked_at'] as String : '',
      cpu: SystemHealthCpu.fromJson(
        json['cpu'] is Map ? Map<String, Object?>.from(json['cpu'] as Map) : {},
      ),
      memory: SystemHealthMemory.fromJson(
        json['memory'] is Map
            ? Map<String, Object?>.from(json['memory'] as Map)
            : {},
      ),
      disk: SystemHealthDisk.fromJson(
        json['disk'] is Map
            ? Map<String, Object?>.from(json['disk'] as Map)
            : {},
      ),
      errors: json['errors'] is List
          ? (json['errors'] as List)
              .whereType<String>()
              .toList()
          : const [],
    );
  }

  Map<String, Object?> toJson() => {
    'status': status,
    'available': available,
    'checked_at': checkedAt,
    'cpu': cpu.toJson(),
    'memory': memory.toJson(),
    'disk': disk.toJson(),
    'errors': errors,
  };
}

/// CPU 信息。
class SystemHealthCpu {
  const SystemHealthCpu({required this.percent});

  /// 使用率百分比（0-100），来自 _cpu_delta_percent 50ms 采样。
  final double percent;

  factory SystemHealthCpu.fromJson(Map<String, Object?> json) {
    return SystemHealthCpu(
      percent: _parsePercent(json['percent']),
    );
  }

  Map<String, Object?> toJson() => {'percent': percent};
}

/// 内存信息。
class SystemHealthMemory {
  const SystemHealthMemory({
    required this.percent,
    required this.usedBytes,
    required this.totalBytes,
  });

  /// 使用率百分比（0-100）。
  final double percent;

  /// 已用字节数。
  final int usedBytes;

  /// 总字节数。
  final int totalBytes;

  factory SystemHealthMemory.fromJson(Map<String, Object?> json) {
    return SystemHealthMemory(
      percent: _parsePercent(json['percent']),
      usedBytes: _parseInt(json['used_bytes']),
      totalBytes: _parseInt(json['total_bytes']),
    );
  }

  Map<String, Object?> toJson() => {
    'percent': percent,
    'used_bytes': usedBytes,
    'total_bytes': totalBytes,
  };
}

/// 磁盘信息（不绘制折线，仅展示数字）。
class SystemHealthDisk {
  const SystemHealthDisk({
    required this.percent,
    required this.usedBytes,
    required this.totalBytes,
  });

  /// 使用率百分比（0-100）。
  final double percent;

  /// 已用字节数。
  final int usedBytes;

  /// 总字节数。
  final int totalBytes;

  factory SystemHealthDisk.fromJson(Map<String, Object?> json) {
    return SystemHealthDisk(
      percent: _parsePercent(json['percent']),
      usedBytes: _parseInt(json['used_bytes']),
      totalBytes: _parseInt(json['total_bytes']),
    );
  }

  Map<String, Object?> toJson() => {
    'percent': percent,
    'used_bytes': usedBytes,
    'total_bytes': totalBytes,
  };
}

// ---------------------------------------------------------------------------
// 内部工具
// ---------------------------------------------------------------------------

/// 安全解析百分比（double，clamp 0-100）。
double _parsePercent(Object? value) {
  if (value is double) return value.clamp(0.0, 100.0);
  if (value is int) return value.toDouble().clamp(0.0, 100.0);
  if (value is num) return value.toDouble().clamp(0.0, 100.0);
  if (value is String) {
    final parsed = double.tryParse(value);
    if (parsed != null) return parsed.clamp(0.0, 100.0);
  }
  return 0.0;
}

/// 安全解析整型。
int _parseInt(Object? value) {
  if (value is int) return value;
  if (value is double) return value.toInt();
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}
