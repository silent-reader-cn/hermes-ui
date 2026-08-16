import '../models/json_value.dart';

/// 容错解码工具集（Swift `KeyedDecodingContainer` lossy 扩展的 Dart 等价）。
///
/// 对应 models_spec.md 第 2 节：Dart 无容器概念，等价物为 `Map<String, Object?>`
/// 上的顶层函数。所有函数对 key 缺失返回 null；值为 null 时一律返回 null；
/// 类型不符时做宽容转换，转换失败返回 null，**绝不 throw**。
///
/// Dart 特有坑（规格 2.2）：`jsonDecode` 把整数解为 `int`，因此
/// [lossyDouble] / [flexibleDouble] 必须显式补 int → double 分支；
/// [lossyInt] 必须做 int64 溢出检查（超大 double / 字符串 → null 而非 crash）。

/// === decodeLossyStringIfPresent ===
/// 顺序：String 原样 → int → '\\(v)' → double → '\\(v)' → bool → 'true'/'false' → 其余 null。
String? lossyString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is String) return value;
  if (value is int) return value.toString();
  if (value is double) return value.toString();
  if (value is bool) return value ? 'true' : 'false';
  return null;
}

/// === decodeLossyDoubleIfPresent ===
/// 顺序：double 原样 → int → toDouble() → String(trim) → double.tryParse → 其余 null。
double? lossyDouble(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is double) return value;
  if (value is int) return value.toDouble();
  if (value is String) {
    return double.tryParse(value.trim());
  }
  return null;
}

/// === decodeFlexibleDoubleIfPresent（Cron.swift / Memory.swift 用）===
/// 顺序与 [lossyDouble] 一致：double 原样 → int → String(trim) → double.tryParse。
double? flexibleDouble(Map<String, Object?> json, String key) =>
    lossyDouble(json, key);

/// int64 范围检查：值必须不小于 -2^63 且严格小于 2^63。
bool _fitsInt64(double value) =>
    value >= -9223372036854775808.0 && value < 9223372036854775808.0;

/// === decodeLossyIntIfPresent ===
/// 顺序：int 原样 → double（有限，截断向零 + int64 溢出检查）→ String(trim)：
/// int.tryParse 优先，失败则 double.tryParse 再截断 + 溢出检查 → 其余 null。
int? lossyInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is int) return value;
  if (value is double) {
    if (!value.isFinite || !_fitsInt64(value)) return null;
    return value.truncate().toInt();
  }
  if (value is String) {
    final trimmed = value.trim();
    final parsed = int.tryParse(trimmed);
    if (parsed != null) return parsed;
    final parsedDouble = double.tryParse(trimmed);
    if (parsedDouble == null || !parsedDouble.isFinite || !_fitsInt64(parsedDouble)) {
      return null;
    }
    return parsedDouble.truncate().toInt();
  }
  return null;
}

/// === decodeLossyBoolIfPresent ===
/// 顺序：bool 原样 → int：0→false / 1→true / 其他→null →
/// String(trim+lowercase)：'true'|'1'|'yes'→true，'false'|'0'|'no'→false，其他→null。
bool? lossyBool(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is bool) return value;
  if (value is int) {
    switch (value) {
      case 0:
        return false;
      case 1:
        return true;
      default:
        return null;
    }
  }
  if (value is String) {
    switch (value.trim().toLowerCase()) {
      case 'true':
      case '1':
      case 'yes':
        return true;
      case 'false':
      case '0':
      case 'no':
        return false;
      default:
        return null;
    }
  }
  return null;
}

/// 多键顺序尝试：依次对 keys 调用 fn，返回第一个非 null（对应 Swift `A ?? B` 模式）。
/// 用法：`firstKey(json, ['kickoff_prompt', 'kickoffPrompt'], lossyString)`。
T? firstKey<T>(
  Map<String, Object?> json,
  List<String> keys,
  T? Function(Map<String, Object?>, String) fn,
) {
  for (final key in keys) {
    final value = fn(json, key);
    if (value != null) return value;
  }
  return null;
}

/// === decodeStringArray（Approval / Clarification 的私有等价）===
/// 按 keys 顺序尝试：1) `List<String>` 原样；2) `List<JsonValue>` → 逐元素 lossyString
/// 过滤 null；3) 单个字符串 → 包装成单元素数组；全部失败 → null。
List<String>? lossyStringArray(Map<String, Object?> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value is List) {
      if (value.every((e) => e is String)) {
        return value.cast<String>();
      }
      return value
          .map((e) => e is JsonValue
              ? e.lossyString
              : JsonValue.fromJson(e).lossyString)
          .whereType<String>()
          .toList(growable: false);
    }
    if (value is String) {
      return [value];
    }
  }
  return null;
}

/// 普通可选字符串读取（对应 decodeIfPresent 无转换路径）：类型不符返回 null。
String? optString(Map<String, Object?> json, String key) {
  final value = json[key];
  return value is String ? value : null;
}

/// 普通可选 int 读取：仅接受 int（Dart jsonDecode 的整数字面量即 int）。
int? optInt(Map<String, Object?> json, String key) {
  final value = json[key];
  return value is int ? value : null;
}

/// 普通可选 double 读取：接受 double；整数（int）宽容转为 double
/// （对齐 Swift `decodeIfPresent(Double)` 能吃下整数字面量）。
double? optDouble(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is double) return value;
  if (value is int) return value.toDouble();
  return null;
}

/// 普通可选 bool 读取：类型不符返回 null。
bool? optBool(Map<String, Object?> json, String key) {
  final value = json[key];
  return value is bool ? value : null;
}

/// T? 嵌套模型读取（对应 `try? decodeIfPresent(T.self)`）：解码失败返回 null。
T? optModel<T>(
  Map<String, Object?> json,
  String key,
  T Function(Map<String, Object?>) fromJson,
) {
  final value = json[key];
  if (value is! Map) return null;
  try {
    return fromJson(Map<String, Object?>.from(value));
  } catch (_) {
    return null;
  }
}

/// `List<T>`? 嵌套数组读取：任一元素不是对象 → 整数组解码失败返回 null
/// （注意：不等价于逐项兜底，逐项兜底见各模型的 decodeXxxTolerantly 模式）。
List<T>? optModelList<T>(
  Map<String, Object?> json,
  String key,
  T Function(Map<String, Object?>) fromJson,
) {
  final value = json[key];
  if (value is! List) return null;
  try {
    final result = <T>[];
    for (final element in value) {
      if (element is! Map) return null;
      result.add(fromJson(Map<String, Object?>.from(element)));
    }
    return result;
  } catch (_) {
    return null;
  }
}

/// `List<JsonValue>`? 读取（规格中 `optModelList(JsonValue.fromJson)` 的等价物）：
/// 数组元素可以是任意 JSON 类型（字符串 / 数字 / 对象……），逐项经
/// [JsonValue.fromJson] 转换，绝不 throw。
List<JsonValue>? optJsonValueList(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! List) return null;
  return value.map(JsonValue.fromJson).toList(growable: false);
}

/// `List<String>`? 读取（对应 `try? decodeIfPresent([String].self)`）：
/// 任一元素不是 String → 返回 null。
List<String>? optStringList(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! List) return null;
  if (value.every((e) => e is String)) return value.cast<String>();
  return null;
}
