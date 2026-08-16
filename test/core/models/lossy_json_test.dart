import 'package:flutter_test/flutter_test.dart';
import 'package:hermex_flutter/core/models/json_value.dart';
import 'package:hermex_flutter/core/utils/lossy_json.dart';

Map<String, Object?> map(Object? raw) {
  // 模拟 jsonDecode 后的 Map<String, dynamic>。
  return Map<String, Object?>.from(raw as Map);
}

void main() {
  group('lossyString', () {
    test('String 原样', () {
      expect(lossyString(map({'k': 'v'}), 'k'), 'v');
    });
    test('int → 字符串', () {
      expect(lossyString(map({'k': 42}), 'k'), '42');
    });
    test('double → 字符串', () {
      expect(lossyString(map({'k': 4.5}), 'k'), '4.5');
    });
    test('bool → true|false', () {
      expect(lossyString(map({'k': true}), 'k'), 'true');
      expect(lossyString(map({'k': false}), 'k'), 'false');
    });
    test('缺失 / null / 对象 / 数组 → null', () {
      expect(lossyString(map({}), 'k'), isNull);
      expect(lossyString(map({'k': null}), 'k'), isNull);
      expect(lossyString(map({'k': {'a': 1}}), 'k'), isNull);
      expect(lossyString(map({'k': [1]}), 'k'), isNull);
    });
  });

  group('lossyDouble / flexibleDouble', () {
    test('double 原样', () {
      expect(lossyDouble(map({'k': 1.5}), 'k'), 1.5);
    });
    test('int → double（Dart 特有坑：jsonDecode 整数为 int）', () {
      expect(lossyDouble(map({'k': 120}), 'k'), 120.0);
    });
    test('字符串 trim 后解析', () {
      expect(lossyDouble(map({'k': ' 12.5 '}), 'k'), 12.5);
    });
    test('坏字符串 / 缺失 → null', () {
      expect(lossyDouble(map({'k': 'abc'}), 'k'), isNull);
      expect(lossyDouble(map({}), 'k'), isNull);
    });
    test('flexibleDouble 与 lossyDouble 等价', () {
      expect(flexibleDouble(map({'k': 3}), 'k'), 3.0);
      expect(flexibleDouble(map({'k': '7.25'}), 'k'), 7.25);
      expect(flexibleDouble(map({'k': false}), 'k'), isNull);
    });
  });

  group('lossyInt（含 int64 溢出检查）', () {
    test('int 原样', () {
      expect(lossyInt(map({'k': 42}), 'k'), 42);
    });
    test('double 有限 + 截断向零', () {
      expect(lossyInt(map({'k': 42.9}), 'k'), 42);
      expect(lossyInt(map({'k': -42.9}), 'k'), -42);
    });
    test('double 非有限 → null', () {
      expect(lossyInt(map({'k': double.infinity}), 'k'), isNull);
      expect(lossyInt(map({'k': double.nan}), 'k'), isNull);
    });
    test('double 超出 int64 → null 而非 crash', () {
      expect(lossyInt(map({'k': 1e300}), 'k'), isNull);
      expect(lossyInt(map({'k': -1e300}), 'k'), isNull);
    });
    test('字符串：int.parse 优先', () {
      expect(lossyInt(map({'k': ' 99 '}), 'k'), 99);
    });
    test('字符串：double.parse 再截断 + 溢出检查', () {
      expect(lossyInt(map({'k': '42.7'}), 'k'), 42);
      expect(lossyInt(map({'k': '1e300'}), 'k'), isNull);
      expect(lossyInt(map({'k': 'abc'}), 'k'), isNull);
    });
    test('缺失 / null / bool / 数组 → null', () {
      expect(lossyInt(map({}), 'k'), isNull);
      expect(lossyInt(map({'k': null}), 'k'), isNull);
      expect(lossyInt(map({'k': true}), 'k'), isNull);
    });
  });

  group('lossyBool', () {
    test('bool 原样', () {
      expect(lossyBool(map({'k': true}), 'k'), true);
    });
    test('int：0→false / 1→true / 其他→null', () {
      expect(lossyBool(map({'k': 0}), 'k'), false);
      expect(lossyBool(map({'k': 1}), 'k'), true);
      expect(lossyBool(map({'k': 2}), 'k'), isNull);
    });
    test('字符串 trim+lowercase', () {
      expect(lossyBool(map({'k': 'TRUE'}), 'k'), true);
      expect(lossyBool(map({'k': ' 1 '}), 'k'), true);
      expect(lossyBool(map({'k': 'yes'}), 'k'), true);
      expect(lossyBool(map({'k': 'No'}), 'k'), false);
      expect(lossyBool(map({'k': '0'}), 'k'), false);
      expect(lossyBool(map({'k': 'maybe'}), 'k'), isNull);
    });
    test('缺失 / double / 数组 → null', () {
      expect(lossyBool(map({}), 'k'), isNull);
      expect(lossyBool(map({'k': 1.0}), 'k'), isNull);
    });
  });

  group('firstKey 多键顺序尝试', () {
    test('按顺序取第一个非 null', () {
      expect(
        firstKey(map({'a': 'x'}), ['a', 'b'], lossyString),
        'x',
      );
      expect(
        firstKey(map({'b': 'y'}), ['a', 'b'], lossyString),
        'y',
      );
      expect(
        firstKey(map({'a': null, 'b': 1}), ['a', 'b'], lossyInt),
        1,
      );
      expect(
        firstKey(map({}), ['a', 'b'], lossyString),
        isNull,
      );
    });
  });

  group('lossyStringArray', () {
    test('List<String> 原样', () {
      expect(
        lossyStringArray(map({'k': ['a', 'b']}), ['k']),
        ['a', 'b'],
      );
    });
    test('混合数组逐项 lossyString 过滤 null（含 JsonValue 形态）', () {
      final raw = map({'k': [const JsonString('a'), const JsonNumber(1.0), const JsonNull()]});
      expect(lossyStringArray(raw, ['k']), ['a', '1.0']);
    });
    test('单个字符串包装成单元素数组', () {
      expect(lossyStringArray(map({'k': 'only'}), ['k']), ['only']);
    });
    test('键顺序尝试 / 全部失败 → null', () {
      expect(
        lossyStringArray(map({'b': ['y']}), ['a', 'b']),
        ['y'],
      );
      expect(lossyStringArray(map({'k': 42}), ['k']), isNull);
      expect(lossyStringArray(map({}), ['k']), isNull);
    });
  });

  group('opt* 普通读取', () {
    test('optString / optInt / optDouble / optBool', () {
      expect(optString(map({'k': 'v'}), 'k'), 'v');
      expect(optString(map({'k': 1}), 'k'), isNull);
      expect(optInt(map({'k': 5}), 'k'), 5);
      expect(optInt(map({'k': 5.0}), 'k'), isNull);
      expect(optDouble(map({'k': 1.5}), 'k'), 1.5);
      expect(optDouble(map({'k': 2}), 'k'), 2.0);
      expect(optBool(map({'k': true}), 'k'), true);
      expect(optBool(map({'k': 1}), 'k'), isNull);
      expect(optString(map({}), 'k'), isNull);
    });
  });

  group('optModel / optModelList', () {
    test('optModel：对象解码，非 Map → null', () {
      final model = optModel(map({'k': {'a': 1}}), 'k', (m) => m['a'] as int?);
      expect(model, 1);
      expect(optModel(map({'k': 'str'}), 'k', (m) => 0), isNull);
      expect(optModel(map({}), 'k', (m) => 0), isNull);
    });

    test('optModelList：任一元素非对象 → 整数组 null', () {
      final ok = optModelList(
        map({'k': [{'a': 1}, {'a': 2}]}),
        'k',
        (m) => m['a'] as int?,
      );
      expect(ok, [1, 2]);
      expect(
        optModelList(map({'k': [{'a': 1}, 'bad']}), 'k', (m) => 0),
        isNull,
      );
      expect(optModelList(map({'k': 'str'}), 'k', (m) => 0), isNull);
    });
  });

  group('optJsonValueList / optStringList', () {
    test('optJsonValueList：任意元素类型均可', () {
      final values = optJsonValueList(map({'k': ['a', 1, null]}), 'k');
      expect(values, isNotNull);
      expect(values![0], const JsonString('a'));
      expect(values[1], const JsonNumber(1));
      expect(values[2], isA<JsonNull>());
      expect(optJsonValueList(map({}), 'k'), isNull);
    });

    test('optStringList：任一元素非 String → null', () {
      expect(optStringList(map({'k': ['a', 'b']}), 'k'), ['a', 'b']);
      expect(optStringList(map({'k': ['a', 1]}), 'k'), isNull);
      expect(optStringList(map({'k': 'a'}), 'k'), isNull);
    });
  });
}
