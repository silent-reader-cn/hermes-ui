import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/models/memory.dart';

void main() {
  group('MemorySection', () {
    test('解析与未知值', () {
      expect(memorySectionFromJson('memory'), MemorySection.memory);
      expect(memorySectionFromJson('user'), MemorySection.user);
      expect(memorySectionFromJson('soul'), MemorySection.soul);
      expect(memorySectionFromJson('unknown'), isNull);
      expect(memorySectionFromJson(1), isNull);
    });
  });

  group('MemoryResponse', () {
    test('规格示例正常解析', () {
      final response = MemoryResponse.fromJson({
        'memory': '用户偏好…',
        'user': '…',
        'soul': '…',
        'memory_path': '/home/u/.hermes/memory.md',
        'memory_mtime': 1723700000.0,
        'project_context': '…',
        'project_context_name': 'hermex',
        'project_context_path': '/home/u/proj',
        'project_context_workspace': 'default',
        'project_context_shadowed': true,
        'external_notes_enabled': false,
      });
      expect(response.memory, '用户偏好…');
      expect(response.memoryPath, '/home/u/.hermes/memory.md');
      expect(response.memoryMtime, 1723700000.0);
      expect(response.projectContextName, 'hermex');
      expect(response.projectContextShadowed, true);
      expect(response.externalNotesEnabled, false);
    });

    test('mtime flexible 解析（int / 字符串）', () {
      expect(MemoryResponse.fromJson({'memory_mtime': 5}).memoryMtime, 5.0);
      expect(
        MemoryResponse.fromJson({'memory_mtime': '6.5'}).memoryMtime,
        6.5,
      );
      expect(MemoryResponse.fromJson(const {}).memoryMtime, isNull);
    });

    test('projectContextShadowed 特殊：bool / List / 其他 → null', () {
      expect(
        MemoryResponse.fromJson({'project_context_shadowed': true})
            .projectContextShadowed,
        true,
      );
      expect(
        MemoryResponse.fromJson({'project_context_shadowed': [{'f': 1}]})
            .projectContextShadowed,
        true,
      );
      expect(
        MemoryResponse.fromJson({'project_context_shadowed': []})
            .projectContextShadowed,
        false,
      );
      expect(
        MemoryResponse.fromJson({'project_context_shadowed': 'yes'})
            .projectContextShadowed,
        isNull,
      );
    });

    test('畸形输入：缺失/错型 → null 容错（17 字段全可空）', () {
      final response = MemoryResponse.fromJson({
        'memory': 1,
        'user': false,
        'memory_path': {'x': 1},
        'external_notes_enabled': 'nope',
      });
      expect(response.memory, isNull);
      expect(response.user, isNull);
      expect(response.memoryPath, isNull);
      expect(response.externalNotesEnabled, isNull);
      final empty = MemoryResponse.fromJson(const {});
      expect(empty.soul, isNull);
      expect(empty.projectContext, isNull);
    });
  });

  group('MemoryWriteResponse', () {
    test('正常 + 畸形', () {
      final response = MemoryWriteResponse.fromJson({
        'ok': true,
        'section': 'memory',
        'path': '/home/u/.hermes/memory.md',
        'error': null,
      });
      expect(response.ok, true);
      expect(response.section, MemorySection.memory);
      expect(response.path, '/home/u/.hermes/memory.md');

      final broken = MemoryWriteResponse.fromJson({
        'ok': 'yes',
        'section': 'bogus',
        'path': 3,
      });
      // optBool 严格：'yes' 非 bool → null（对齐 Swift decodeIfPresent(Bool)）
      expect(broken.ok, isNull);
      expect(broken.section, isNull);
      expect(broken.path, isNull);
      expect(MemoryWriteResponse.fromJson(const {}).section, isNull);
    });
  });

  test('== / hashCode', () {
    final a = MemoryResponse.fromJson({'memory': 'x'});
    final b = MemoryResponse.fromJson({'memory': 'x'});
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });
}
