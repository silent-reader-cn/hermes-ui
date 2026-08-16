import 'dart:convert';

import '../utils/equality.dart';

/// 通用 JSON 值。对应 Swift `enum JSONValue`。
///
/// 解析顺序与 Swift 完全一致：null → bool → number → string → array → object。
sealed class JsonValue {
  const JsonValue();

  factory JsonValue.fromJson(Object? json) {
    if (json == null) return const JsonNull();
    if (json is bool) return JsonBool(json);
    if (json is num) return JsonNumber(json.toDouble());
    if (json is String) return JsonString(json);
    if (json is List) {
      return JsonArray(json.map(JsonValue.fromJson).toList(growable: false));
    }
    if (json is Map) {
      return JsonObject(json.map(
        (k, v) => MapEntry(k.toString(), JsonValue.fromJson(v)),
      ));
    }
    return const JsonNull(); // 类型不符兜底，绝不 throw
  }

  Object? toJson();
}

/// JSON 字符串值。
final class JsonString extends JsonValue {
  const JsonString(this.value);

  final String value;

  @override
  Object? toJson() => value;

  @override
  bool operator ==(Object other) => other is JsonString && other.value == value;

  @override
  int get hashCode => Object.hash(JsonString, value);

  @override
  String toString() => 'JsonString($value)';
}

/// JSON 数字值（统一为 double）。
final class JsonNumber extends JsonValue {
  const JsonNumber(this.value);

  final double value;

  @override
  Object? toJson() => value;

  @override
  bool operator ==(Object other) => other is JsonNumber && other.value == value;

  @override
  int get hashCode => Object.hash(JsonNumber, value);

  @override
  String toString() => 'JsonNumber($value)';
}

/// JSON 布尔值。
final class JsonBool extends JsonValue {
  const JsonBool(this.value);

  final bool value;

  @override
  Object? toJson() => value;

  @override
  bool operator ==(Object other) => other is JsonBool && other.value == value;

  @override
  int get hashCode => Object.hash(JsonBool, value);

  @override
  String toString() => 'JsonBool($value)';
}

/// JSON 对象值。
final class JsonObject extends JsonValue {
  const JsonObject(this.value);

  final Map<String, JsonValue> value;

  @override
  Object? toJson() => value.map((k, v) => MapEntry(k, v.toJson()));

  @override
  bool operator ==(Object other) =>
      other is JsonObject && deepEquals(other.value, value);

  @override
  int get hashCode => Object.hash(JsonObject, deepHash(value));

  @override
  String toString() => 'JsonObject(${compactJsonString ?? value})';
}

/// JSON 数组值。
final class JsonArray extends JsonValue {
  const JsonArray(this.value);

  final List<JsonValue> value;

  @override
  Object? toJson() => value.map((e) => e.toJson()).toList(growable: false);

  @override
  bool operator ==(Object other) =>
      other is JsonArray && deepEquals(other.value, value);

  @override
  int get hashCode => Object.hash(JsonArray, deepHash(value));

  @override
  String toString() => 'JsonArray(${compactJsonString ?? value})';
}

/// JSON null 值。
final class JsonNull extends JsonValue {
  const JsonNull();

  @override
  Object? toJson() => null;

  @override
  bool operator ==(Object other) => other is JsonNull;

  @override
  int get hashCode => Object.hashAll([JsonNull]);

  @override
  String toString() => 'JsonNull()';
}

/// JsonValue 辅助方法（对应 Swift `private extension JSONValue`）。
extension JsonValueX on JsonValue {
  /// 尽力转 String：string 原样 / number 转字符串 / bool → 'true'|'false' / 其余 null。
  String? get stringValue {
    return switch (this) {
      JsonString(:final value) => value,
      JsonNumber(:final value) => value.toString(),
      JsonBool(:final value) => value ? 'true' : 'false',
      _ => null,
    };
  }

  /// 对应 Swift `lossyString` / `clarificationLossyString`
  /// （Approval / Clarification 数组元素转字符串）。
  String? get lossyString => stringValue;

  /// 紧凑 JSON 字符串（对应 Swift `compactJSONString`）。实现：jsonEncode(toJson())。
  String? get compactJsonString {
    try {
      return jsonEncode(toJson());
    } catch (_) {
      return null;
    }
  }

  /// 仅当自身是 object 时返回其字段表（对应 Swift `objectValue`）。
  Map<String, JsonValue>? get objectValue {
    return switch (this) {
      JsonObject(:final value) => value,
      _ => null,
    };
  }
}
