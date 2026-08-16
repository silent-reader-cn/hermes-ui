import 'package:flutter_test/flutter_test.dart';
import 'package:hermex_flutter/core/models/skills.dart';
import 'package:hermex_flutter/core/models/slash_skill_formatter.dart';

void main() {
  group('SlashSkillFormatter.slug', () {
    test('小写、空白与下划线转 -、只留 [a-z0-9-]、去重连字符、trim -', () {
      expect(SlashSkillFormatter.slug('HerMes Agent'), 'hermes-agent');
      expect(SlashSkillFormatter.slug('my_skill'), 'my-skill');
      expect(SlashSkillFormatter.slug('  spaced  out  '), 'spaced-out');
      expect(SlashSkillFormatter.slug('a--b---c'), 'a-b-c');
      expect(SlashSkillFormatter.slug('-leading-trailing-'), 'leading-trailing');
      expect(SlashSkillFormatter.slug('中文技能'), '');
      expect(SlashSkillFormatter.slug('Code Review!'), 'code-review');
    });
  });

  group('SkillSlashSuggestion / suggestions', () {
    test('suggestions：过滤空名、去重、按 slashName 排序', () {
      final suggestions = SlashSkillFormatter.suggestions([
        SkillSummary.fromJson({'name': 'Zeta Skill'}),
        SkillSummary.fromJson({'name': '  '}),
        SkillSummary.fromJson({'name': 'Alpha Skill', 'category': 'tools', 'description': 'd'}),
        SkillSummary.fromJson({'name': 'zeta skill'}), // 与第一个同 slashName
      ]);
      expect(suggestions, hasLength(2));
      expect(suggestions[0].slashName, 'alpha-skill');
      expect(suggestions[0].category, 'tools');
      expect(suggestions[1].slashName, 'zeta-skill');
      expect(suggestions[1].id, 'zeta-skill');
    });

    test('skillQuery / invocation / skillNamed / messageText', () {
      final suggestions = SlashSkillFormatter.suggestions([
        SkillSummary.fromJson({'name': 'Deploy App'}),
      ]);
      expect(SlashSkillFormatter.skillQuery('deploy-app 详细说明'), 'deploy-app');
      expect(SlashSkillFormatter.skillQuery(''), '');

      final invocation = SlashSkillFormatter.invocation(
        'deploy-app 部署到生产',
        suggestions,
      );
      expect(invocation, isNotNull);
      expect(invocation!.skill.slashName, 'deploy-app');
      expect(invocation.message, '部署到生产');
      expect(SlashSkillFormatter.messageText(invocation), '/deploy-app 部署到生产');

      expect(
        SlashSkillFormatter.invocation('only-one-token', suggestions),
        isNull,
      );
      expect(
        SlashSkillFormatter.invocation('unknown-skill msg', suggestions),
        isNull,
      );
      expect(
        SlashSkillFormatter.invocation('deploy-app   ', suggestions),
        isNull,
      );
    });

    test('skillNamed 大小写不敏感', () {
      final suggestions = SlashSkillFormatter.suggestions([
        SkillSummary.fromJson({'name': 'Deploy App'}),
      ]);
      expect(SlashSkillFormatter.skillNamed('DEPLOY-APP', suggestions), isNotNull);
      expect(SlashSkillFormatter.skillNamed('Deploy App', suggestions), isNotNull);
      expect(SlashSkillFormatter.skillNamed('nope', suggestions), isNull);
    });

    test('detailMessage 包含 markdown 头', () {
      final suggestion = SlashSkillFormatter.suggestions([
        SkillSummary.fromJson(
          {'name': 'Deploy App', 'category': 'ops', 'description': '发布'},
        ),
      ]).single;
      final detail = SlashSkillFormatter.detailMessage(suggestion);
      expect(detail, contains('### `/deploy-app`'));
      expect(detail, contains('**Deploy App**'));
      expect(detail, contains('Category: ops'));
      expect(detail, contains('发布'));
    });

    test('matching：空查询返回全部，否则过滤', () {
      final suggestions = SlashSkillFormatter.suggestions([
        SkillSummary.fromJson({'name': 'Alpha', 'category': 'tools'}),
        SkillSummary.fromJson({'name': 'Beta', 'description': 'blue pill'}),
      ]);
      expect(SlashSkillFormatter.matching('', suggestions), hasLength(2));
      expect(SlashSkillFormatter.matching('alp', suggestions), hasLength(1));
      expect(SlashSkillFormatter.matching('TOOLS', suggestions), hasLength(1));
      expect(SlashSkillFormatter.matching('blue', suggestions), hasLength(1));
      expect(SlashSkillFormatter.matching('zzz', suggestions), isEmpty);
    });

    test('message：空列表 / 无匹配 / 分组展示', () {
      expect(
        SlashSkillFormatter.message(const [], ''),
        'No skills are configured on the server.',
      );
      final suggestions = SlashSkillFormatter.suggestions([
        SkillSummary.fromJson({'name': 'Alpha'}),
      ]);
      expect(
        SlashSkillFormatter.message(suggestions, 'zzz'),
        'No skills match `zzz`.',
      );
      final text = SlashSkillFormatter.message(suggestions, '');
      expect(text, contains('Available skills:'));
      expect(text, contains('- `/alpha` - **Alpha**'));
      final filtered = SlashSkillFormatter.message(suggestions, 'alp');
      expect(filtered, contains('Skills matching `alp`:'));
    });
  });
}
