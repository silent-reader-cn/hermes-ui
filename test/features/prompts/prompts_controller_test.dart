import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/api/api_exception.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/models/saved_prompt.dart';
import 'package:hermes_ui/features/prompts/prompts_providers.dart';

import '../../helpers/fake_prompts_api.dart';

ProviderContainer makeContainer(FakePromptsApi api) {
  final container = ProviderContainer(
    overrides: [
      apiClientProvider.overrideWithValue(
        ApiClient(baseUrl: 'http://test.local:30002'),
      ),
      promptsApiFactoryProvider.overrideWithValue((_) => api),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

SavedPrompt prompt(String id, String text, {String? label}) => SavedPrompt(
  id: id,
  label: label ?? text,
  text: text,
  createdAt: 1710000000,
);

void main() {
  group('SavedPromptsController build/fetch', () {
    test('empty list: server returns [] -> state []', () async {
      final api = FakePromptsApi(initialPrompts: const []);
      final c = makeContainer(api);
      await c.read(savedPromptsControllerProvider.future);
      final value = c.read(savedPromptsControllerProvider).valueOrNull!;
      expect(value, isEmpty);
      expect(c.read(savedPromptsCountProvider), 0);
      expect(c.read(savedPromptsIsEmptyProvider), isTrue);
    });

    test('normal list: server returns 2 -> state passthrough', () async {
      final api = FakePromptsApi(
        initialPrompts: [
          prompt('a1', 'hello'),
          prompt('a2', 'world', label: 'World label'),
        ],
      );
      final c = makeContainer(api);
      await c.read(savedPromptsControllerProvider.future);
      final value = c.read(savedPromptsControllerProvider).valueOrNull!;
      expect(value, hasLength(2));
      expect(value.first.id, 'a1');
      expect(value.last.label, 'World label');
      expect(c.read(savedPromptsCountProvider), 2);
      expect(c.read(savedPromptsIsEmptyProvider), isFalse);
    });

    test('fetch failure -> AsyncError, refresh retries success', () async {
      final api = FakePromptsApi(initialPrompts: [prompt('x', 'hi')]);
      api.fetchError = NetworkException(NetworkExceptionKind.cannotConnect);
      final c = makeContainer(api);

      await expectLater(
        c.read(savedPromptsControllerProvider.future),
        throwsA(isA<ApiException>()),
      );
      expect(c.read(savedPromptsControllerProvider).hasError, isTrue);

      api.fetchError = null;
      await c.read(savedPromptsControllerProvider.notifier).refresh();
      final value = c.read(savedPromptsControllerProvider).valueOrNull!;
      expect(value, hasLength(1));
      expect(value.first.id, 'x');
    });

    test('prompts null -> treated as empty', () async {
      final api = _NullPromptsApi();
      final c = makeContainer(api);
      await c.read(savedPromptsControllerProvider.future);
      expect(c.read(savedPromptsControllerProvider).valueOrNull, isEmpty);
    });
  });

  group('SavedPromptsController create', () {
    test('create success: local insert + re-fetch consistent', () async {
      final api = FakePromptsApi(initialPrompts: [prompt('a1', 'hello')]);
      final c = makeContainer(api);
      await c.read(savedPromptsControllerProvider.future);
      expect(c.read(savedPromptsControllerProvider).valueOrNull, hasLength(1));

      final created = await c
          .read(savedPromptsControllerProvider.notifier)
          .create(text: 'new prompt', label: 'My label');
      expect(created, isNotNull);
      expect(created!.text, 'new prompt');
      expect(api.lastCreateText, 'new prompt');
      expect(api.lastCreateLabel, 'My label');
      expect(c.read(savedPromptsControllerProvider).valueOrNull, hasLength(2));
      expect(c.read(savedPromptsCountProvider), 2);
    });

    test('create without label: label param null passthrough', () async {
      final api = FakePromptsApi(initialPrompts: const []);
      final c = makeContainer(api);
      await c.read(savedPromptsControllerProvider.future);

      await c.read(savedPromptsControllerProvider.notifier).create(text: 't');
      expect(api.lastCreateLabel, isNull);
      expect(c.read(savedPromptsControllerProvider).valueOrNull, hasLength(1));
    });

    test('200 limit error (HttpException): rethrow, state unchanged', () async {
      final api = FakePromptsApi(initialPrompts: [prompt('a1', 'hello')]);
      api.createError = HttpException.fromBody(
        400,
        '{"error":"saved prompts limit reached (max 200)"}',
      );
      final c = makeContainer(api);
      await c.read(savedPromptsControllerProvider.future);
      final before = c.read(savedPromptsControllerProvider).valueOrNull!;

      await expectLater(
        c.read(savedPromptsControllerProvider.notifier).create(text: 'x'),
        throwsA(isA<HttpException>()),
      );
      expect(
        c.read(savedPromptsControllerProvider).valueOrNull,
        hasLength(before.length),
      );
      expect(c.read(savedPromptsCountProvider), 1);
    });

    test('text required 400 rethrow', () async {
      final api = FakePromptsApi(initialPrompts: const []);
      api.createError = HttpException.fromBody(
        400,
        '{"error":"text is required"}',
      );
      final c = makeContainer(api);
      await c.read(savedPromptsControllerProvider.future);

      await expectLater(
        c.read(savedPromptsControllerProvider.notifier).create(text: ''),
        throwsA(isA<HttpException>()),
      );
      expect(c.read(savedPromptsControllerProvider).valueOrNull, isEmpty);
    });

    test('text too long 400 rethrow', () async {
      final api = FakePromptsApi(initialPrompts: const []);
      api.createError = HttpException.fromBody(
        400,
        '{"error":"text too long (max 8000 chars)"}',
      );
      final c = makeContainer(api);
      await c.read(savedPromptsControllerProvider.future);

      final long = List.filled(8001, 'a').join();
      await expectLater(
        c.read(savedPromptsControllerProvider.notifier).create(text: long),
        throwsA(isA<HttpException>()),
      );
    });
  });

  group('SavedPromptsController remove', () {
    test(
      'remove success: optimistic remove + re-fetch still removed',
      () async {
        final api = FakePromptsApi(
          initialPrompts: [prompt('a1', 'hello'), prompt('a2', 'world')],
        );
        final c = makeContainer(api);
        await c.read(savedPromptsControllerProvider.future);
        expect(
          c.read(savedPromptsControllerProvider).valueOrNull,
          hasLength(2),
        );

        await c.read(savedPromptsControllerProvider.notifier).remove('a1');
        expect(api.lastDeleteId, 'a1');
        expect(
          c.read(savedPromptsControllerProvider).valueOrNull,
          hasLength(1),
        );
        expect(
          c.read(savedPromptsControllerProvider).valueOrNull!.first.id,
          'a2',
        );
      },
    );

    test('remove idempotent: delete non-existent also success', () async {
      final api = FakePromptsApi(initialPrompts: [prompt('a1', 'hello')]);
      final c = makeContainer(api);
      await c.read(savedPromptsControllerProvider.future);

      await c.read(savedPromptsControllerProvider.notifier).remove('not-exist');
      expect(c.read(savedPromptsControllerProvider).valueOrNull, hasLength(1));
    });

    test('remove network failure: rollback and rethrow', () async {
      final api = FakePromptsApi(
        initialPrompts: [prompt('a1', 'hello'), prompt('a2', 'world')],
      );
      api.deleteError = NetworkException(NetworkExceptionKind.timedOut);
      final c = makeContainer(api);
      await c.read(savedPromptsControllerProvider.future);

      await expectLater(
        c.read(savedPromptsControllerProvider.notifier).remove('a1'),
        throwsA(isA<NetworkException>()),
      );
      expect(c.read(savedPromptsControllerProvider).valueOrNull, hasLength(2));
    });

    test('remove ok==false rollback', () async {
      final api = FakePromptsApi(
        initialPrompts: [prompt('a1', 'hello'), prompt('a2', 'world')],
      );
      api.deleteOk = false;
      final c = makeContainer(api);
      await c.read(savedPromptsControllerProvider.future);

      await c.read(savedPromptsControllerProvider.notifier).remove('a1');
      expect(c.read(savedPromptsControllerProvider).valueOrNull, hasLength(2));
    });
  });

  group('savedPromptDisplayLabel', () {
    test('label prioritized', () {
      expect(
        savedPromptDisplayLabel(
          const SavedPrompt(label: ' My label ', text: 'fallback'),
        ),
        'My label',
      );
    });

    test('empty label fallback to text', () {
      expect(
        savedPromptDisplayLabel(
          const SavedPrompt(label: '  ', text: 'fallback'),
        ),
        'fallback',
      );
      expect(
        savedPromptDisplayLabel(const SavedPrompt(text: 'fallback')),
        'fallback',
      );
    });

    test('fallback text truncated at 60', () {
      final long = List.filled(100, 'a').join();
      expect(savedPromptDisplayLabel(SavedPrompt(text: long)).length, 60);
    });

    test('empty text -> empty string', () {
      expect(savedPromptDisplayLabel(const SavedPrompt()), '');
    });
  });
}

class _NullPromptsApi extends FakePromptsApi {
  @override
  Future<SavedPromptsResponse> fetchPrompts() async {
    return const SavedPromptsResponse(prompts: null);
  }
}
