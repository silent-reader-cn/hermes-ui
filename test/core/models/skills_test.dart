import 'package:flutter_test/flutter_test.dart';
import 'package:hermex_flutter/core/models/skills.dart';

void main() {
  group('SkillsResponse / SkillSummary', () {
    test('规格示例正常解析', () {
      final response = SkillsResponse.fromJson({
        'skills': [
          {
            'name': 'hermes-agent',
            'category': 'autonomous-ai-agents',
            'description': '…',
            'path': '/skills/hermes-agent',
            'disabled': false,
            'tags': ['hermes'],
            'related_skills': ['codex'],
          },
        ],
      });
      final skill = response.skills!.single;
      expect(skill.name, 'hermes-agent');
      expect(skill.category, 'autonomous-ai-agents');
      expect(skill.disabled, false);
      expect(skill.tags, ['hermes']);
      expect(skill.relatedSkills, ['codex']);
      expect(skill.id, 'hermes-agent');
    });

    test('畸形输入：缺失/错型 → null 容错', () {
      final skill = SkillSummary.fromJson({
        'name': 1,
        'disabled': 'no',
        'tags': ['a', 2],
        'related_skills': 'bad',
      });
      expect(skill.name, isNull);
      // optBool 严格：'no' 非 bool → null
      expect(skill.disabled, isNull);
      expect(skill.tags, isNull);
      expect(skill.relatedSkills, isNull);
      expect(skill.id, isNotEmpty);
      expect(SkillsResponse.fromJson({'skills': 'bad'}).skills, isNull);
    });
  });

  group('ToggleSkillRequest / ToggleSkillResponse', () {
    test('请求 toJson 输出 snake_case', () {
      const request = ToggleSkillRequest(name: 'hermes-agent', enabled: true);
      expect(request.toJson(), {'name': 'hermes-agent', 'enabled': true});
    });

    test('响应正常 + 畸形', () {
      final response = ToggleSkillResponse.fromJson(
        {'ok': true, 'name': 'hermes-agent', 'enabled': true},
      );
      expect(response.ok, true);
      expect(response.name, 'hermes-agent');
      expect(response.enabled, true);
      final broken = ToggleSkillResponse.fromJson({
        'ok': 'yes',
        'name': 5,
        'enabled': 'garbage',
      });
      expect(broken.ok, true);
      expect(broken.name, '5');
      expect(broken.enabled, isNull);
    });
  });

  group('SkillDetailResponse.linkedFiles 多形态', () {
    test('Map<String,String> → keys 排序', () {
      final response = SkillDetailResponse.fromJson({
        'name': 'hermes-agent',
        'content': 'SKILL.md 内容…',
        'linked_files': {
          'references/api.md': '…',
          'templates/x.md': '…',
        },
      });
      expect(response.name, 'hermes-agent');
      expect(response.content, 'SKILL.md 内容…');
      expect(response.linkedFiles, ['references/api.md', 'templates/x.md']);
    });

    test('JsonValue 形态：string/array/object 递归收集去重排序', () {
      // object 形态：值是 string → 取 key 本身
      final objectForm = SkillDetailResponse.fromJson({
        'linked_files': {
          'refs': {'a.md': 'content', 'nested': ['b.md', 'c.md']},
        },
      });
      expect(objectForm.linkedFiles, ['a.md', 'b.md', 'c.md']);
      // 数组形态
      final arrayForm = SkillDetailResponse.fromJson({
        'linked_files': ['a.md', ['b.md', 'a.md']],
      });
      expect(arrayForm.linkedFiles, ['a.md', 'b.md']);
      // 字符串形态
      final stringForm = SkillDetailResponse.fromJson({'linked_files': 'a.md'});
      expect(stringForm.linkedFiles, ['a.md']);
    });

    test('畸形输入：非 Map/非 JsonValue → null', () {
      expect(
        SkillDetailResponse.fromJson({'linked_files': 42}).linkedFiles,
        isNull,
      );
      expect(
        SkillDetailResponse.fromJson(const {}).linkedFiles,
        isNull,
      );
    });
  });

  group('SkillLinkedFileResponse', () {
    test('正常 + 畸形', () {
      final response = SkillLinkedFileResponse.fromJson(
        {'content': '…', 'path': 'references/api.md'},
      );
      expect(response.content, '…');
      expect(response.path, 'references/api.md');
      final broken = SkillLinkedFileResponse.fromJson({'content': 1});
      expect(broken.content, isNull);
      expect(broken.path, isNull);
    });
  });

  test('== / hashCode', () {
    final a = SkillSummary.fromJson({'name': 'x'});
    final b = SkillSummary.fromJson({'name': 'x'});
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    const request = ToggleSkillRequest(name: 'x', enabled: true);
    const same = ToggleSkillRequest(name: 'x', enabled: true);
    expect(request, same);
  });
}
