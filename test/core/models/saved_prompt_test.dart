import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/models/saved_prompt.dart';

void main() {
  group('SavedPrompt', () {
    test('正常解析全部字段', () {
      final prompt = SavedPrompt.fromJson({
        'id': 'abc123def456',
        'label': 'My prompt',
        'text': 'full text content',
        'created_at': 1710000000.0,
      });
      expect(prompt.id, 'abc123def456');
      expect(prompt.label, 'My prompt');
      expect(prompt.text, 'full text content');
      expect(prompt.createdAt, 1710000000.0);
    });

    test('created_at 容错：int / double / String → double', () {
      expect(
        SavedPrompt.fromJson({'created_at': 1710000000}).createdAt,
        1710000000.0,
      );
      expect(
        SavedPrompt.fromJson({'created_at': 1710000000.5}).createdAt,
        1710000000.5,
      );
      expect(
        SavedPrompt.fromJson({'created_at': '1710000000.5'}).createdAt,
        1710000000.5,
      );
      expect(SavedPrompt.fromJson({'created_at': '  42  '}).createdAt, 42.0);
      expect(SavedPrompt.fromJson({'created_at': 'bad'}).createdAt, isNull);
      expect(SavedPrompt.fromJson({'created_at': true}).createdAt, isNull);
    });

    test('label/text lossyString 宽容转换', () {
      expect(SavedPrompt.fromJson({'label': 42}).label, '42');
      expect(SavedPrompt.fromJson({'label': 3.14}).label, '3.14');
      expect(SavedPrompt.fromJson({'label': true}).label, 'true');
      expect(SavedPrompt.fromJson({'label': false}).label, 'false');
      expect(SavedPrompt.fromJson({'text': 0}).text, '0');
      expect(SavedPrompt.fromJson({'text': true}).text, 'true');
      // 非 lossy 类型（如 List/Map）→ null
      expect(
        SavedPrompt.fromJson({
          'label': [1, 2],
        }).label,
        isNull,
      );
      expect(
        SavedPrompt.fromJson({
          'label': {'a': 1},
        }).label,
        isNull,
      );
    });

    test('缺字段 → null 容错', () {
      final empty = SavedPrompt.fromJson(const {});
      expect(empty.id, isNull);
      expect(empty.label, isNull);
      expect(empty.text, isNull);
      expect(empty.createdAt, isNull);
    });

    test('类型错 → null 容错 + 未知字段忽略', () {
      final prompt = SavedPrompt.fromJson({
        'id': 123, // optString 严格 → null
        'label': 'ok',
        'text': 999, // lossyString → '999'
        'created_at': true, // flexibleDouble → null
        'unknown_field': 'ignored',
        'extra': 42,
      });
      expect(prompt.id, isNull);
      expect(prompt.label, 'ok');
      expect(prompt.text, '999');
      expect(prompt.createdAt, isNull);
    });

    test('toJson 只输出非空字段 snake_case', () {
      const prompt = SavedPrompt(
        id: 'abc',
        label: 'L',
        text: 'T',
        createdAt: 1.0,
      );
      expect(prompt.toJson(), {
        'id': 'abc',
        'label': 'L',
        'text': 'T',
        'created_at': 1.0,
      });
      const partial = SavedPrompt(id: 'x');
      expect(partial.toJson(), {'id': 'x'});
      expect(SavedPrompt.fromJson(const {}).toJson(), isEmpty);
    });

    test('== / hashCode / toString', () {
      const a = SavedPrompt(id: '1', label: 'a', text: 't', createdAt: 1.0);
      const b = SavedPrompt(id: '1', label: 'a', text: 't', createdAt: 1.0);
      const c = SavedPrompt(id: '2', label: 'a', text: 't', createdAt: 1.0);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == c, isFalse);
      expect(a.toString(), contains('SavedPrompt'));
      expect(a.toString(), contains('1'));
    });

    test('copyWith', () {
      const original = SavedPrompt(id: '1', label: 'a', text: 't');
      final copied = original.copyWith(label: 'b');
      expect(copied.id, '1');
      expect(copied.label, 'b');
      expect(copied.text, 't');
    });
  });

  group('SavedPromptsResponse', () {
    test('正常解析 prompts 数组', () {
      final response = SavedPromptsResponse.fromJson({
        'prompts': [
          {'id': '1', 'label': 'a', 'text': 'hello', 'created_at': 1.0},
          {'id': '2', 'label': 'b', 'text': 'world', 'created_at': 2.0},
        ],
      });
      expect(response.prompts, hasLength(2));
      expect(response.prompts![0].id, '1');
      expect(response.prompts![1].id, '2');
    });

    test('null / 非 List → null', () {
      expect(SavedPromptsResponse.fromJson(const {}).prompts, isNull);
      expect(SavedPromptsResponse.fromJson({'prompts': null}).prompts, isNull);
      expect(SavedPromptsResponse.fromJson({'prompts': 'bad'}).prompts, isNull);
      expect(SavedPromptsResponse.fromJson({'prompts': 42}).prompts, isNull);
    });

    test('元素非 Map 跳过，空 List 返回空', () {
      final response = SavedPromptsResponse.fromJson({
        'prompts': [
          {'id': '1', 'text': 'ok'},
          'bad_string',
          42,
          null,
          {'id': '2', 'text': 'ok2'},
        ],
      });
      expect(response.prompts, hasLength(2));
      expect(response.prompts![0].id, '1');
      expect(response.prompts![1].id, '2');

      final empty = SavedPromptsResponse.fromJson({'prompts': []});
      expect(empty.prompts, isEmpty);
    });

    test('未知字段忽略 + 畸形元素容错', () {
      final response = SavedPromptsResponse.fromJson({
        'prompts': [
          {'id': '1', 'unknown': 'ignored'},
        ],
        'unknown_top': 'ignored',
      });
      expect(response.prompts, hasLength(1));
      expect(response.prompts![0].id, '1');
    });

    test('== / hashCode / toString', () {
      final a = SavedPromptsResponse.fromJson({
        'prompts': [
          {'id': '1'},
        ],
      });
      final b = SavedPromptsResponse.fromJson({
        'prompts': [
          {'id': '1'},
        ],
      });
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a.toString(), contains('SavedPromptsResponse'));
    });
  });

  group('SavePromptResponse', () {
    test('正常：{ok, prompt}', () {
      final response = SavePromptResponse.fromJson({
        'ok': true,
        'prompt': {
          'id': 'abc123def456',
          'label': 'xxx',
          'text': 'full text',
          'created_at': 1710000000.0,
        },
      });
      expect(response.ok, true);
      expect(response.prompt?.id, 'abc123def456');
      expect(response.prompt?.label, 'xxx');
      expect(response.error, isNull);
    });

    test('兼容：{ok, error}', () {
      final response = SavePromptResponse.fromJson({
        'ok': false,
        'error': 'text is required',
      });
      expect(response.ok, false);
      expect(response.prompt, isNull);
      expect(response.error, 'text is required');
    });

    test('ok 宽容 bool 解析（int/string）', () {
      expect(SavePromptResponse.fromJson({'ok': 1}).ok, true);
      expect(SavePromptResponse.fromJson({'ok': 0}).ok, false);
      expect(SavePromptResponse.fromJson({'ok': 'true'}).ok, true);
      expect(SavePromptResponse.fromJson({'ok': 'false'}).ok, false);
      // 非法值 → null
      expect(SavePromptResponse.fromJson({'ok': 'garbage'}).ok, isNull);
      expect(SavePromptResponse.fromJson({'ok': 2}).ok, isNull);
    });

    test('缺字段 / 未知字段 → null 容错', () {
      final empty = SavePromptResponse.fromJson(const {});
      expect(empty.ok, isNull);
      expect(empty.prompt, isNull);
      expect(empty.error, isNull);

      final withUnknown = SavePromptResponse.fromJson({
        'ok': true,
        'unknown': 'ignored',
      });
      expect(withUnknown.ok, true);
    });

    test('prompt 非 Map → null', () {
      final response = SavePromptResponse.fromJson({
        'ok': true,
        'prompt': 'bad',
      });
      expect(response.prompt, isNull);
    });

    test('== / hashCode / toString', () {
      final a = SavePromptResponse.fromJson({'ok': true});
      final b = SavePromptResponse.fromJson({'ok': true});
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a.toString(), contains('SavePromptResponse'));
    });
  });

  group('DeletePromptResponse', () {
    test('正常：{ok: true}', () {
      final response = DeletePromptResponse.fromJson({'ok': true});
      expect(response.ok, true);
      expect(response.error, isNull);
    });

    test('兼容：{ok: false, error}', () {
      final response = DeletePromptResponse.fromJson({
        'ok': false,
        'error': 'id is required',
      });
      expect(response.ok, false);
      expect(response.error, 'id is required');
    });

    test('宽容 ok 解析', () {
      expect(DeletePromptResponse.fromJson({'ok': 1}).ok, true);
      expect(DeletePromptResponse.fromJson({'ok': 'true'}).ok, true);
      expect(DeletePromptResponse.fromJson({'ok': 'garbage'}).ok, isNull);
    });

    test('缺字段 / 未知字段忽略', () {
      final empty = DeletePromptResponse.fromJson(const {});
      expect(empty.ok, isNull);
      final withUnknown = DeletePromptResponse.fromJson({
        'ok': true,
        'unknown': 'ignored',
      });
      expect(withUnknown.ok, true);
    });

    test('== / hashCode / toString', () {
      final a = DeletePromptResponse.fromJson({'ok': true});
      final b = DeletePromptResponse.fromJson({'ok': true});
      const c = DeletePromptResponse(ok: false);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == c, isFalse);
      expect(a.toString(), contains('DeletePromptResponse'));
    });
  });
}
