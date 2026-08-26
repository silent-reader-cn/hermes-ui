import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/api/api_client_prompts.dart';

void main() {
  const base = 'http://hermes.local:8787';

  (ApiClient, _JsonAdapter) buildClient(String responseBody) {
    final adapter = _JsonAdapter(responseBody);
    final dio = Dio(
      BaseOptions(validateStatus: (_) => true, followRedirects: false),
    );
    dio.httpClientAdapter = adapter;
    final publicDio = Dio(
      BaseOptions(validateStatus: (_) => true, followRedirects: false),
    );
    publicDio.httpClientAdapter = adapter;
    return (
      ApiClient(baseUrl: base, dio: dio, publicMediaDio: publicDio),
      adapter,
    );
  }

  group('ApiClientPrompts', () {
    test('fetchPrompts: GET /api/prompts 解析响应', () async {
      final (client, adapter) = buildClient(
        jsonEncode({
          'prompts': [
            {
              'id': 'abc123def456',
              'label': 'xxx',
              'text': 'full text',
              'created_at': 1710000000.0,
            },
          ],
        }),
      );

      final response = await client.fetchPrompts();

      expect(adapter.requests.single.uri.path, '/api/prompts');
      expect(adapter.requests.single.method, 'GET');
      expect(response.prompts, hasLength(1));
      expect(response.prompts!.first.id, 'abc123def456');
      expect(response.prompts!.first.label, 'xxx');
      expect(response.prompts!.first.text, 'full text');
      expect(response.prompts!.first.createdAt, 1710000000.0);
    });

    test('fetchPrompts: 空列表与畸形数组容错', () async {
      final (emptyClient, _) = buildClient(jsonEncode({'prompts': []}));
      final empty = await emptyClient.fetchPrompts();
      expect(empty.prompts, isEmpty);

      final (nullClient, _) = buildClient(jsonEncode({}));
      final nullResponse = await nullClient.fetchPrompts();
      expect(nullResponse.prompts, isNull);
    });

    test('createPrompt: POST /api/prompts body 含 text/label', () async {
      final (client, adapter) = buildClient(
        jsonEncode({
          'ok': true,
          'prompt': {
            'id': 'abc123def456',
            'label': 'xxx',
            'text': 'full text',
            'created_at': 1710000000.0,
          },
        }),
      );

      final response = await client.createPrompt(
        text: 'full text',
        label: 'xxx',
      );

      expect(adapter.requests.single.uri.path, '/api/prompts');
      expect(adapter.requests.single.method, 'POST');
      final body = jsonDecode(
        adapter.requests.single.data as String,
      ) as Map<String, dynamic>;
      expect(body['text'], 'full text');
      expect(body['label'], 'xxx');
      expect(response.ok, true);
      expect(response.prompt?.id, 'abc123def456');
      expect(response.error, isNull);
    });

    test('createPrompt: label 为空时不发送 label 字段', () async {
      final (client, adapter) = buildClient(
        jsonEncode({
          'ok': true,
          'prompt': {
            'id': 'abc123',
            'label': 'auto',
            'text': 'hello',
            'created_at': 1710000000.0,
          },
        }),
      );

      await client.createPrompt(text: 'hello');

      final body = jsonDecode(
        adapter.requests.single.data as String,
      ) as Map<String, dynamic>;
      expect(body['text'], 'hello');
      expect(body.containsKey('label'), isFalse);
    });

    test('createPrompt: 错误响应 {ok, error}', () async {
      final (client, _) = buildClient(
        jsonEncode({'ok': false, 'error': 'text is required'}),
      );

      final response = await client.createPrompt(text: '');

      expect(response.ok, isFalse);
      expect(response.error, 'text is required');
      expect(response.prompt, isNull);
    });

    test('deletePrompt: DELETE /api/prompts body 含 id', () async {
      final (client, adapter) = buildClient(jsonEncode({'ok': true}));

      final response = await client.deletePrompt('abc123def456');

      expect(adapter.requests.single.uri.path, '/api/prompts');
      expect(adapter.requests.single.method, 'DELETE');
      final body = jsonDecode(
        adapter.requests.single.data as String,
      ) as Map<String, dynamic>;
      expect(body['id'], 'abc123def456');
      expect(response.ok, true);
      expect(response.error, isNull);
    });

    test('deletePrompt: 幂等 200 解析 error 兼容', () async {
      final (client, _) = buildClient(jsonEncode({'ok': true}));

      final response = await client.deletePrompt('not-exist-id');

      expect(response.ok, true);
    });

    test('deletePrompt: 错误响应 {ok, error}', () async {
      final (client, _) = buildClient(
        jsonEncode({'ok': false, 'error': 'id is required'}),
      );

      final response = await client.deletePrompt('');

      expect(response.ok, isFalse);
      expect(response.error, 'id is required');
    });
  });
}

/// 记录请求并回放固定 JSON 的假 HttpClientAdapter。
class _JsonAdapter implements HttpClientAdapter {
  _JsonAdapter(this.body);

  final String body;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      body,
      200,
      headers: {
        'content-type': ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
