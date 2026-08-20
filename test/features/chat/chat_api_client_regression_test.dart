import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermex_flutter/core/api/api_client.dart';
import 'package:hermex_flutter/core/cache/cache_providers.dart';
import 'package:hermex_flutter/core/cache/cache_service.dart';
import 'package:hermex_flutter/features/chat/chat_providers.dart';
import 'package:hermex_flutter/features/chat/chat_server_api.dart';
import 'package:hermex_flutter/features/chat/chat_state.dart';

/// 聊天模块生产包装层（[ChatApiClient]）与 [ChatController] 全链路回归测试。
///
/// 背景（2026-08 实锤 bug）：
/// [ChatServerApi] 之前声明为 `Future<Object?>`，[ChatController] 内部对返回值做
/// `_asStringMap(raw)` 强转。而 [ApiClient] 扩展已将 JSON 解码为强类型模型对象
/// （如 [SessionResponse]），`_asStringMap` 无法转 Map 导致降级为空 map `{}`，
/// 从而导致会话标题丢失（全变成 "Untitled Session"）、消息列表全空、会话操作全失效。
///
/// 本测试使用真实 Dio + [_JsonAdapter] 走真实 HTTP 响应 → ApiClient 扩展解码 →
/// ChatApiClient 包装层 → ChatController 状态机的全链路，确保双层解析 Bug 永不复发。
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

  group('ChatApiClient（真实 HTTP 解码透传）', () {
    test('session() 正确保留 messages / messageCount / title / workspace 字段', () async {
      final (client, adapter) = buildClient(jsonEncode({
        'session': {
          'session_id': 's123',
          'title': 'AI 对话',
          'workspace': '/path/to/project',
          'model': 'claude-3-5-sonnet',
          'model_provider': 'anthropic',
          'profile': 'coder',
          'read_only': false,
          'message_count': 2,
          'messages_offset': 0,
          'messages': [
            {
              'message_id': 'm1',
              'role': 'user',
              'content': '你好，介绍一下项目',
              'timestamp': 1700000000,
            },
            {
              'message_id': 'm2',
              'role': 'assistant',
              'content': '这是一个 Flutter 移植项目。',
              'timestamp': 1700000005,
            },
          ],
        },
      }));

      final api = ChatApiClient(client);
      final response = await api.session(sessionId: 's123');

      expect(adapter.requests.single.uri.path, '/api/session');
      expect(adapter.requests.single.uri.queryParameters['session_id'], 's123');
      expect(response.session, isNotNull);
      final detail = response.session!;
      expect(detail.sessionId, 's123');
      expect(detail.title, 'AI 对话');
      expect(detail.workspace, '/path/to/project');
      expect(detail.model, 'claude-3-5-sonnet');
      expect(detail.modelProvider, 'anthropic');
      expect(detail.profile, 'coder');
      expect(detail.messageCount, 2);
      expect(detail.messages, hasLength(2));
      expect(detail.messages![0].role, 'user');
      expect(detail.messages![0].content, '你好，介绍一下项目');
      expect(detail.messages![1].role, 'assistant');
      expect(detail.messages![1].content, '这是一个 Flutter 移植项目。');
    });

    test('startChat() 正确透传 streamId 与 sessionId', () async {
      final (client, adapter) = buildClient(jsonEncode({
        'stream_id': 'stream-xyz',
        'session_id': 'sess-456',
      }));

      final api = ChatApiClient(client);
      final response = await api.startChat(
        sessionId: 'sess-456',
        message: 'Hello',
      );

      expect(adapter.requests.single.method, 'POST');
      expect(adapter.requests.single.uri.path, '/api/chat/start');
      expect(response.streamId, 'stream-xyz');
      expect(response.sessionId, 'sess-456');
    });

    test('steerChat() 正确透传 accepted', () async {
      final (client, adapter) = buildClient(jsonEncode({
        'accepted': true,
      }));

      final api = ChatApiClient(client);
      final response = await api.steerChat(sessionId: 's1', text: '转向指令');

      expect(adapter.requests.single.uri.path, '/api/chat/steer');
      expect(response.accepted, true);
    });

    test('cancelChat() 正确透传 ok', () async {
      final (client, adapter) = buildClient(jsonEncode({
        'ok': true,
        'cancelled': true,
      }));

      final api = ChatApiClient(client);
      final response = await api.cancelChat('stream-1');

      expect(adapter.requests.single.uri.path, '/api/chat/cancel');
      expect(response.ok, true);
    });

    test('chatStreamStatus() 正确透传 active 与 replay_available', () async {
      final (client, adapter) = buildClient(jsonEncode({
        'active': false,
        'replay_available': true,
      }));

      final api = ChatApiClient(client);
      final response = await api.chatStreamStatus('stream-1');

      expect(adapter.requests.single.uri.path, '/api/chat/stream/status');
      expect(response.active, false);
      expect(response.replayAvailable, true);
    });

    test('renameSession() 正确透传 SessionMutationResponse', () async {
      final (client, adapter) = buildClient(jsonEncode({
        'ok': true,
        'session': {'session_id': 's1', 'title': '新标题'},
      }));

      final api = ChatApiClient(client);
      final response = await api.renameSession(sessionId: 's1', title: '新标题');

      expect(adapter.requests.single.uri.path, '/api/session/rename');
      expect(response.ok, true);
      expect(response.session?.title, '新标题');
    });

    test('branchSession() 正确透传 SessionBranchResponse', () async {
      final (client, adapter) = buildClient(jsonEncode({
        'session_id': 's1-branch',
        'parent_session_id': 's1',
      }));

      final api = ChatApiClient(client);
      final response = await api.branchSession('s1', keepCount: 3);

      expect(adapter.requests.single.uri.path, '/api/session/branch');
      expect(response.sessionId, 's1-branch');
      expect(response.parentSessionId, 's1');
    });

    test('retrySession() 正确透传 SessionRetryResponse 及 last_user_text', () async {
      final (client, adapter) = buildClient(jsonEncode({
        'ok': true,
        'last_user_text': '请问天气如何？',
      }));

      final api = ChatApiClient(client);
      final response = await api.retrySession('s1');

      expect(adapter.requests.single.uri.path, '/api/session/retry');
      expect(response.ok, true);
      expect(response.lastUserText, '请问天气如何？');
    });

    test('getYolo() 与 setYolo() 正确透传 SessionYoloResponse', () async {
      final (getClient, _) = buildClient(jsonEncode({
        'ok': true,
        'yolo_enabled': true,
      }));
      final getResponse = await ChatApiClient(getClient).getYolo('s1');
      expect(getResponse.ok, true);
      expect(getResponse.yoloEnabled, true);

      final (setClient, _) = buildClient(jsonEncode({
        'ok': true,
        'yolo_enabled': false,
      }));
      final setResponse = await ChatApiClient(setClient).setYolo(
        sessionId: 's1',
        enabled: false,
      );
      expect(setResponse.ok, true);
      expect(setResponse.yoloEnabled, false);
    });
  });

  group('ChatController 全链路（真实 ChatApiClient 注入）', () {
    test('loadMessages() 成功拉取并正确填充 state.displayTitle 与 state.messages', () async {
      final (client, _) = buildClient(jsonEncode({
        'session': {
          'session_id': 's-full-test',
          'title': '深入解析系统架构',
          'workspace': '/work/proj',
          'model': 'gpt-4o',
          'model_provider': 'openai',
          'profile': 'general',
          'read_only': false,
          'message_count': 2,
          'messages': [
            {
              'message_id': 'msg-1',
              'role': 'user',
              'content': '什么是两层解析 Bug？',
              'timestamp': 1700000000,
            },
            {
              'message_id': 'msg-2',
              'role': 'assistant',
              'content': '两层解析 Bug 指外层包装类对内层已解码对象做二次反序列化导致数据丢失。',
              'timestamp': 1700000010,
            },
          ],
        },
      }));

      final chatApi = ChatApiClient(client);
      final container = ProviderContainer(
        overrides: [
          chatApiProvider.overrideWithValue(chatApi),
          cacheServiceProvider.overrideWithValue(_NoopCacheService()),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(chatControllerProvider('s-full-test').notifier);
      await controller.loadMessages();

      final state = container.read(chatControllerProvider('s-full-test'));

      // 验证标题不再是 "Untitled Session"，而是服务端真实标题
      expect(state.displayTitle, '深入解析系统架构');
      // 验证消息列表被正确填充
      expect(state.messages, hasLength(2));
      expect(state.messages[0].messageId, 'msg-1');
      expect(state.messages[0].role, 'user');
      expect(state.messages[0].content, '什么是两层解析 Bug？');
      expect(state.messages[1].messageId, 'msg-2');
      expect(state.messages[1].role, 'assistant');
      expect(
        state.messages[1].content,
        '两层解析 Bug 指外层包装类对内层已解码对象做二次反序列化导致数据丢失。',
      );
      // 验证会话元数据
      expect(state.workspace, '/work/proj');
      expect(state.model, 'gpt-4o');
      expect(state.modelProvider, 'openai');
      expect(state.isReadOnly, false);
      expect(state.phase, ChatPhase.idle);
    });

    test('renameSession() 经真实 ChatApiClient 正确更新 state.displayTitle', () async {
      final (client, _) = buildClient(jsonEncode({
        'ok': true,
        'session': {'session_id': 's1', 'title': '重命名后的新标题'},
      }));

      final chatApi = ChatApiClient(client);
      final container = ProviderContainer(
        overrides: [
          chatApiProvider.overrideWithValue(chatApi),
          cacheServiceProvider.overrideWithValue(_NoopCacheService()),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(chatControllerProvider('s1').notifier);
      final success = await controller.renameSession('重命名后的新标题');

      expect(success, true);
      final state = container.read(chatControllerProvider('s1'));
      expect(state.displayTitle, '重命名后的新标题');
    });

    test('retryLastTurn() 经真实 ChatApiClient 正确回填 composerPrefill', () async {
      final (client, _) = buildClient(jsonEncode({
        'ok': true,
        'last_user_text': '请重新回答上一问',
      }));

      final chatApi = ChatApiClient(client);
      final container = ProviderContainer(
        overrides: [
          chatApiProvider.overrideWithValue(chatApi),
          cacheServiceProvider.overrideWithValue(_NoopCacheService()),
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(chatControllerProvider('s1').notifier);
      final text = await controller.retryLastTurn();

      expect(text, '请重新回答上一问');
      final state = container.read(chatControllerProvider('s1'));
      expect(state.composerPrefill, '请重新回答上一问');
    });
  });
}

/// 假 HttpClientAdapter，记录请求并返回固定的 JSON 响应。
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

/// 测试用空缓存服务，不做任何持久化。
class _NoopCacheService implements CacheService {
  @override
  Future<void> writeMessages({
    required String sessionId,
    required List<Map<String, Object?>> messages,
  }) async {}

  @override
  Future<List<Map<String, Object?>>> readMessages(String sessionId) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
