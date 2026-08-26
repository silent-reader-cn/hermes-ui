import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/models/auxiliary_model.dart';

void main() {
  group('AuxiliaryTaskRow', () {
    test('11 个 canonical tasks 正常解析与全量字段验证', () {
      const canonicalTasks = [
        'vision',
        'web_extract',
        'compression',
        'approval',
        'mcp',
        'title_generation',
        'skills_hub',
        'curator',
        'kanban_decomposer',
        'profile_describer',
        'triage_specifier',
      ];

      for (final t in canonicalTasks) {
        final row = AuxiliaryTaskRow.fromJson({
          'task': t,
          'provider': 'openai',
          'model': 'gpt-4o-mini',
          'base_url': 'https://api.openai.com/v1',
          'timeout': 60,
          'download_timeout': 120,
          'max_concurrency': 4,
          'extra_body': {'temperature': 0.2},
          'api_key_set': true,
          'label': '$t task',
          'description': 'Description for $t',
        });
        expect(row.task, t);
        expect(row.provider, 'openai');
        expect(row.model, 'gpt-4o-mini');
        expect(row.baseUrl, 'https://api.openai.com/v1');
        // lossyString 转换：数字转字符串
        expect(row.timeout, '60');
        expect(row.downloadTimeout, '120');
        expect(row.maxConcurrency, '4');
        expect(row.extraBody, {'temperature': 0.2});
        expect(row.apiKeySet, isTrue);
        expect(row.label, '$t task');
        expect(row.description, 'Description for $t');

        final json = row.toJson();
        expect(json['task'], t);
        expect(json['provider'], 'openai');
        expect(json['timeout'], '60');
        expect(json['extra_body'], {'temperature': 0.2});
      }
    });

    test('provider 缺失时默认 auto', () {
      final row = AuxiliaryTaskRow.fromJson({'task': 'vision'});
      expect(row.provider, 'auto');
      expect(row.model, '');
      expect(row.apiKeySet, isFalse);
      expect(row.extraBody, isEmpty);
    });

    test('支持 camelCase 变体与 lossy 转换', () {
      final row = AuxiliaryTaskRow.fromJson({
        'task': 'web_extract',
        'baseUrl': 'http://custom.local',
        'downloadTimeout': '300',
        'maxConcurrency': '8',
        'extraBody': {'top_p': 0.9},
        'apiKeySet': '1',
      });
      expect(row.baseUrl, 'http://custom.local');
      expect(row.downloadTimeout, '300');
      expect(row.maxConcurrency, '8');
      expect(row.extraBody, {'top_p': 0.9});
      expect(row.apiKeySet, isTrue);
    });

    test('畸形输入与空值容错', () {
      const def = AuxiliaryTaskRow();
      expect(def.task, '');
      expect(def.provider, 'auto');
      expect(def.model, '');
      expect(def.apiKeySet, isFalse);

      final bad = AuxiliaryTaskRow.fromJson({
        'task': null,
        'provider': null,
        'timeout': null,
        'download_timeout': true,
        'extra_body': 'bad_map',
        'api_key_set': 'invalid_bool',
      });
      expect(bad.task, '');
      expect(bad.provider, 'auto');
      expect(bad.timeout, '');
      expect(bad.downloadTimeout, 'true');
      expect(bad.extraBody, isEmpty);
      expect(bad.apiKeySet, isFalse);
    });

    test('== / hashCode / toString', () {
      const a = AuxiliaryTaskRow(task: 'vision', model: 'v1');
      const b = AuxiliaryTaskRow(task: 'vision', model: 'v1');
      const c = AuxiliaryTaskRow(task: 'vision', model: 'v2');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
      expect(a.toString(), contains('AuxiliaryTaskRow'));
    });
  });

  group('AuxMainModel', () {
    test('正常解析与 camelCase 变体', () {
      final main = AuxMainModel.fromJson({
        'provider': 'anthropic',
        'model': 'claude-3-5-sonnet',
        'supports_fast_tier': true,
        'service_tier': 'priority',
        'advanced': {'thinking_tokens': 4096},
      });
      expect(main.provider, 'anthropic');
      expect(main.model, 'claude-3-5-sonnet');
      expect(main.supportsFastTier, isTrue);
      expect(main.serviceTier, 'priority');
      expect(main.advanced, {'thinking_tokens': 4096});

      final mainCamel = AuxMainModel.fromJson({
        'supportsFastTier': 'true',
        'serviceTier': 'standard',
      });
      expect(mainCamel.supportsFastTier, isTrue);
      expect(mainCamel.serviceTier, 'standard');
    });

    test('缺失与畸形输入', () {
      const def = AuxMainModel();
      expect(def.provider, '');
      expect(def.model, '');
      expect(def.supportsFastTier, isFalse);
      expect(def.serviceTier, '');
      expect(def.advanced, isEmpty);

      final bad = AuxMainModel.fromJson({
        'provider': 123,
        'advanced': 'invalid',
      });
      expect(bad.provider, '123');
      expect(bad.advanced, isEmpty);
    });

    test('== / hashCode / toString', () {
      const a = AuxMainModel(provider: 'p', model: 'm');
      const b = AuxMainModel(provider: 'p', model: 'm');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a.toString(), contains('AuxMainModel'));
    });
  });

  group('AuxiliaryModelsResponse', () {
    test('正常解析 tasks 列表与 main 对象', () {
      final res = AuxiliaryModelsResponse.fromJson({
        'tasks': [
          {'task': 'vision', 'provider': 'openai', 'model': 'gpt-4o'},
        ],
        'main': {
          'provider': 'anthropic',
          'model': 'claude-3-5-sonnet',
        },
      });
      expect(res.tasks.length, 1);
      expect(res.tasks.first.task, 'vision');
      expect(res.main.provider, 'anthropic');
      expect(res.main.model, 'claude-3-5-sonnet');

      final json = res.toJson();
      expect(json['tasks'], isA<List>());
      expect(json['main'], isA<Map>());
    });

    test('缺失与脏数据容错', () {
      final bad = AuxiliaryModelsResponse.fromJson({
        'tasks': 'not-a-list',
        'main': null,
      });
      expect(bad.tasks, isEmpty);
      expect(bad.main.provider, '');
      expect(bad.main.model, '');
    });

    test('== / hashCode / toString', () {
      const a = AuxiliaryModelsResponse(tasks: [AuxiliaryTaskRow(task: 't1')]);
      const b = AuxiliaryModelsResponse(tasks: [AuxiliaryTaskRow(task: 't1')]);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a.toString(), contains('AuxiliaryModelsResponse'));
    });
  });

  group('ModelSetResponse', () {
    test('正常解析与 lossy 兼容', () {
      final res = ModelSetResponse.fromJson({
        'ok': true,
        'task': 'vision',
        'provider': 'openai',
        'model': 'gpt-4o',
      });
      expect(res.ok, isTrue);
      expect(res.task, 'vision');
      expect(res.provider, 'openai');
      expect(res.model, 'gpt-4o');

      final lossy = ModelSetResponse.fromJson({
        'ok': 'yes',
        'task': 123,
        'provider': 456,
        'model': 789,
      });
      expect(lossy.ok, isTrue);
      expect(lossy.task, '123');
      expect(lossy.provider, '456');
      expect(lossy.model, '789');

      final json = res.toJson();
      expect(json['ok'], isTrue);
      expect(json['task'], 'vision');
    });

    test('== / hashCode / toString', () {
      const a = ModelSetResponse(ok: true, task: 't', provider: 'p', model: 'm');
      const b = ModelSetResponse(ok: true, task: 't', provider: 'p', model: 'm');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a.toString(), contains('ModelSetResponse'));
    });
  });
}
