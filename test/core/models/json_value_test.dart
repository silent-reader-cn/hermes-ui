import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermex_flutter/core/models/json_value.dart';

void main() {
  group('JsonValue.fromJson 解析顺序与类型', () {
    test('null → JsonNull', () {
      expect(JsonValue.fromJson(null), isA<JsonNull>());
      expect(JsonValue.fromJson(null).toJson(), isNull);
    });

    test('bool → JsonBool（先于 num，Swift 顺序）', () {
      expect(JsonValue.fromJson(true), const JsonBool(true));
      expect(JsonValue.fromJson(false).toJson(), false);
    });

    test('num → JsonNumber（统一 double）', () {
      final value = JsonValue.fromJson(42);
      expect(value, isA<JsonNumber>());
      expect((value as JsonNumber).value, 42.0);
      expect(JsonValue.fromJson(3.14), const JsonNumber(3.14));
    });

    test('String → JsonString', () {
      expect(JsonValue.fromJson('hi'), const JsonString('hi'));
    });

    test('List → JsonArray（递归）', () {
      final value = JsonValue.fromJson([1, 'a', null, true]);
      expect(value, isA<JsonArray>());
      final array = value as JsonArray;
      expect(array.value.length, 4);
      expect(array.value[0], const JsonNumber(1));
      expect(array.value[1], const JsonString('a'));
      expect(array.value[2], isA<JsonNull>());
      expect(array.value[3], const JsonBool(true));
    });

    test('Map → JsonObject（递归，key 转字符串）', () {
      final value = JsonValue.fromJson(const {'lines': 42, 'tags': ['x']});
      expect(value, isA<JsonObject>());
      final object = value as JsonObject;
      expect(object.value['lines'], const JsonNumber(42));
      expect(object.value['tags'], isA<JsonArray>());
    });

    test('未知类型（如任意对象）→ JsonNull 兜底，绝不 throw', () {
      final value = JsonValue.fromJson(Object());
      expect(value, isA<JsonNull>());
    });

    test('示例：完整混合 JSON 解析', () {
      final json = jsonDecode(
        '{"name": "write_file", "path": "/tmp/a.txt", "lines": 42, '
        '"overwrite": true, "tags": ["x", null]}',
      );
      final value = JsonValue.fromJson(json);
      expect(value, isA<JsonObject>());
      final object = value as JsonObject;
      expect(object.value['name'], const JsonString('write_file'));
      expect(object.value['lines'], const JsonNumber(42.0));
      expect(object.value['overwrite'], const JsonBool(true));
      final tags = object.value['tags'] as JsonArray;
      expect(tags.value, [const JsonString('x'), isA<JsonNull>()]);
    });
  });

  group('toJson 往返', () {
    test('JsonObject 往返 jsonEncode', () {
      const original = JsonObject({
        'a': JsonNumber(1.5),
        'b': JsonArray([JsonString('x'), JsonNull()]),
      });
      final encoded = jsonEncode(original.toJson());
      final decoded = JsonValue.fromJson(jsonDecode(encoded));
      expect(decoded, original);
    });
  });

  group('辅助方法（JsonValueX）', () {
    test('stringValue：string 原样 / number 转字符串 / bool → true|false / 其余 null', () {
      expect(const JsonString('a').stringValue, 'a');
      expect(const JsonNumber(42.5).stringValue, '42.5');
      expect(const JsonBool(true).stringValue, 'true');
      expect(const JsonBool(false).stringValue, 'false');
      expect(const JsonNull().stringValue, isNull);
      expect(const JsonArray([]).stringValue, isNull);
      expect(const JsonObject({}).stringValue, isNull);
    });

    test('lossyString 别名 = stringValue', () {
      expect(const JsonNumber(7).lossyString, '7.0');
    });

    test('compactJsonString：紧凑 JSON / 永不 throw', () {
      expect(
        const JsonObject({'k': JsonNumber(1.0)}).compactJsonString,
        '{"k":1.0}',
      );
    });

    test('objectValue：仅 object 返回字段表', () {
      const object = JsonObject({'x': JsonString('y')});
      expect(object.objectValue, {'x': const JsonString('y')});
      expect(const JsonString('s').objectValue, isNull);
    });
  });

  group('== / hashCode', () {
    test('同值不同实例相等，哈希一致', () {
      const a = JsonObject({'k': JsonNumber(1.0)});
      const b = JsonObject({'k': JsonNumber(1.0)});
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(const JsonArray([JsonString('x')]), const JsonArray([JsonString('x')]));
    });

    test('不同值不相等', () {
      expect(const JsonNumber(1), isNot(const JsonNumber(2)));
      expect(const JsonObject({'a': JsonString('1')}),
          isNot(const JsonObject({'a': JsonString('2')})));
    });
  });
}
