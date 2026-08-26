import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/api/api_exception.dart';
import 'package:hermes_ui/core/api/sse_client.dart';
import 'package:hermes_ui/core/cache/app_database.dart';
import 'package:hermes_ui/core/cache/cache_providers.dart';
import 'package:hermes_ui/core/cache/cache_service.dart';
import 'package:hermes_ui/features/chat/chat_page.dart';
import 'package:hermes_ui/features/chat/chat_providers.dart';
import '../../helpers/fake_chat_api.dart';

void main() {
  group('ChatController 写缓存触点', () {
    test('初始加载 transcript 成功 → 触发 cacheService.writeMessages 覆盖写', () {
      fakeAsync((async) {
        final db = AppDatabase.memory();
        final cacheService = CacheService(db);
        final api = _FakeChatApi();
        api.sessionResult = {
          'session': {
            'session_id': 'sess-100',
            'title': '测试写缓存会话',
            'messages': [
              {'role': 'user', 'content': '问题1', 'message_id': 'm1'},
              {'role': 'assistant', 'content': '回答1', 'message_id': 'm2'},
            ],
          },
        };

        final container =
            _buildContainer(api, cacheService: cacheService, db: db);
        final controller = container.read(
          chatControllerProvider('sess-100').notifier,
        );

        unawaited(controller.loadMessages());
        async.flushMicrotasks();

        final state = container.read(chatControllerProvider('sess-100'));
        expect(state.messages, hasLength(2));
        expect(state.isShowingOfflineCache, isFalse);
        expect(state.isViewingCachedData, isFalse);

        // 异步等待缓存写入
        async.flushMicrotasks();

        // 验证 SQLite 中已写入消息
        late List<Map<String, Object?>> cached;
        unawaited(cacheService.readMessages('sess-100').then((v) => cached = v));
        async.flushMicrotasks();

        expect(cached, hasLength(2));
        expect(cached.any((m) => m['content'] == '问题1'), isTrue);
        expect(cached.any((m) => m['content'] == '回答1'), isTrue);
      });
    });

    test('流式 turn 结束（DoneStreamEvent）→ 触发写缓存（包含最新的 assistant 回复）', () {
      fakeAsync((async) {
        final db = AppDatabase.memory();
        final cacheService = CacheService(db);
        final api = _FakeChatApi();
        api.sessionResult = {
          'session': {'session_id': 'sess-stream', 'messages': const []},
        };

        final container =
            _buildContainer(api, cacheService: cacheService, db: db);
        final controller = container.read(
          chatControllerProvider('sess-stream').notifier,
        );

        unawaited(controller.send('流式发送消息'));
        async.flushMicrotasks();

        api.emit(const TokenSseEvent('流式回复片段'));
        async.elapse(const Duration(milliseconds: 64));

        api.emit(
          const DoneSseEvent(
            DoneStreamEvent(
              session: {
                'session_id': 'sess-stream',
                'messages': [
                  {'role': 'user', 'content': '流式发送消息', 'message_id': 'u1'},
                  {'role': 'assistant', 'content': '完整流式回复', 'message_id': 'a1'},
                ],
              },
            ),
          ),
        );
        async.flushMicrotasks();

        late List<Map<String, Object?>> cached;
        unawaited(cacheService.readMessages('sess-stream').then((v) => cached = v));
        async.flushMicrotasks();

        expect(cached, hasLength(2));
        expect(cached.any((m) => m['content'] == '完整流式回复'), isTrue);
      });
    });
  });

  group('ChatController 离线回放状态机', () {
    test('网络错误 + 有缓存 → 状态包含回放消息 + isShowingOfflineCache = true', () {
      fakeAsync((async) {
        final db = AppDatabase.memory();
        final cacheService = CacheService(db);

        // 先预置离线缓存数据
        unawaited(
          cacheService.writeMessages(
            sessionId: 'sess-offline',
            messages: [
              {'id': 'msg-1', 'role': 'user', 'content': '离线问题', '_ts': 1000.0},
              {'id': 'msg-2', 'role': 'assistant', 'content': '离线回答', '_ts': 1001.0},
            ],
          ),
        );
        async.flushMicrotasks();

        final api = _FakeChatApi();
        // 模拟网络连不上错误（NetworkExceptionKind.cannotConnect）
        api.sessionError = NetworkException(NetworkExceptionKind.cannotConnect);

        final container =
            _buildContainer(api, cacheService: cacheService, db: db);
        final controller = container.read(
          chatControllerProvider('sess-offline').notifier,
        );

        unawaited(controller.loadMessages());
        async.flushMicrotasks();

        final state = container.read(chatControllerProvider('sess-offline'));
        expect(state.isShowingOfflineCache, isTrue);
        expect(state.isViewingCachedData, isTrue);
        expect(state.messages, hasLength(2));
        expect(state.messages[0].content, '离线问题');
        expect(state.messages[1].content, '离线回答');
        expect(state.errorMessage, isNull);
      });
    });

    test('网络错误 + 无缓存 → 保持错误态（不回放）', () {
      fakeAsync((async) {
        final db = AppDatabase.memory();
        final cacheService = CacheService(db);
        final api = _FakeChatApi();
        api.sessionError = NetworkException(NetworkExceptionKind.timedOut);

        final container =
            _buildContainer(api, cacheService: cacheService, db: db);
        final controller = container.read(
          chatControllerProvider('sess-no-cache').notifier,
        );

        unawaited(controller.loadMessages());
        async.flushMicrotasks();

        final state = container.read(chatControllerProvider('sess-no-cache'));
        expect(state.isShowingOfflineCache, isFalse);
        expect(state.isViewingCachedData, isFalse);
        expect(state.messages, isEmpty);
        expect(state.errorMessage, isNotNull);
      });
    });

    test('非网络类错误（401 / 业务错误）+ 即使有缓存 → 保持现状错误态，不回放', () {
      fakeAsync((async) {
        final db = AppDatabase.memory();
        final cacheService = CacheService(db);

        // 预置缓存
        unawaited(
          cacheService.writeMessages(
            sessionId: 'sess-auth-error',
            messages: [
              {'id': 'msg-1', 'role': 'user', 'content': '秘密消息'},
            ],
          ),
        );
        async.flushMicrotasks();

        final api = _FakeChatApi();
        // 模拟 401 Unauthorized 未授权错误
        api.sessionError = const UnauthorizedException();

        final container =
            _buildContainer(api, cacheService: cacheService, db: db);
        final controller = container.read(
          chatControllerProvider('sess-auth-error').notifier,
        );

        unawaited(controller.loadMessages());
        async.flushMicrotasks();

        final state = container.read(chatControllerProvider('sess-auth-error'));
        expect(state.isShowingOfflineCache, isFalse);
        expect(state.isViewingCachedData, isFalse);
        expect(state.messages, isEmpty);
        expect(state.errorMessage, contains('密码被拒绝'));
      });
    });

    test('重新在线加载成功后 → isShowingOfflineCache = false 并覆盖写缓存', () {
      fakeAsync((async) {
        final db = AppDatabase.memory();
        final cacheService = CacheService(db);

        unawaited(
          cacheService.writeMessages(
            sessionId: 'sess-recover',
            messages: [
              {'id': 'msg-old', 'role': 'user', 'content': '旧离线消息'},
            ],
          ),
        );
        async.flushMicrotasks();

        final api = _FakeChatApi();
        api.sessionError = NetworkException(NetworkExceptionKind.cannotFindHost);

        final container =
            _buildContainer(api, cacheService: cacheService, db: db);
        final controller = container.read(
          chatControllerProvider('sess-recover').notifier,
        );

        // 第一次失败 → 进入离线回放态
        unawaited(controller.loadMessages());
        async.flushMicrotasks();

        var state = container.read(chatControllerProvider('sess-recover'));
        expect(state.isShowingOfflineCache, isTrue);
        expect(state.messages, hasLength(1));
        expect(state.messages.first.content, '旧离线消息');

        // 第二次在线恢复成功
        api.sessionError = null;
        api.sessionResult = {
          'session': {
            'session_id': 'sess-recover',
            'title': '在线新会话',
            'messages': [
              {'role': 'user', 'content': '在线最新消息1', 'message_id': 'new-1'},
              {'role': 'assistant', 'content': '在线最新消息2', 'message_id': 'new-2'},
            ],
          },
        };

        unawaited(controller.loadMessages());
        async.flushMicrotasks();

        state = container.read(chatControllerProvider('sess-recover'));
        expect(state.isShowingOfflineCache, isFalse);
        expect(state.isViewingCachedData, isFalse);
        expect(state.messages, hasLength(2));
        expect(state.messages[0].content, '在线最新消息1');

        // 验证缓存已被最新数据覆盖
        late List<Map<String, Object?>> updatedCache;
        unawaited(cacheService.readMessages('sess-recover').then((v) => updatedCache = v));
        async.flushMicrotasks();

        expect(updatedCache.any((m) => m['content'] == '在线最新消息1'), isTrue);
      });
    });

    test('dismissOfflineCache() 关闭横幅', () {
      fakeAsync((async) {
        final db = AppDatabase.memory();
        final cacheService = CacheService(db);
        unawaited(
          cacheService.writeMessages(
            sessionId: 'sess-dismiss',
            messages: [
              {'id': 'msg-1', 'role': 'user', 'content': '消息'},
            ],
          ),
        );
        async.flushMicrotasks();

        final api = _FakeChatApi();
        api.sessionError = NetworkException(NetworkExceptionKind.offline);

        final container =
            _buildContainer(api, cacheService: cacheService, db: db);
        final controller = container.read(
          chatControllerProvider('sess-dismiss').notifier,
        );

        unawaited(controller.loadMessages());
        async.flushMicrotasks();

        var state = container.read(chatControllerProvider('sess-dismiss'));
        expect(state.isShowingOfflineCache, isTrue);

        controller.dismissOfflineCache();
        state = container.read(chatControllerProvider('sess-dismiss'));
        expect(state.isShowingOfflineCache, isFalse);
      });
    });
  });

  group('ChatPage 离线横幅 UI', () {
    testWidgets('离线模式下展示 _OfflineCacheBanner，点击重试恢复，点击关闭消失', (tester) async {
      final db = AppDatabase.memory();
      final cacheService = CacheService(db);
      await cacheService.writeMessages(
        sessionId: 's-ui',
        messages: [
          {'id': 'm1', 'role': 'user', 'content': '离线消息文本'},
        ],
      );

      final api = _FakeChatApi();
      api.sessionError = NetworkException(NetworkExceptionKind.cannotConnect);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            chatApiProvider.overrideWithValue(api),
            cacheServiceProvider.overrideWithValue(cacheService),
            appDatabaseProvider.overrideWithValue(db),
          ],
          child: const CupertinoApp(home: ChatPage(sessionId: 's-ui')),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // 验证离线横幅展示
      expect(find.byKey(const ValueKey('chat-offline-cache-banner')), findsOneWidget);
      expect(find.textContaining('离线缓存模式'), findsOneWidget);
      expect(find.text('离线消息文本'), findsOneWidget);

      // 点击重试按钮（API 恢复正常）
      api.sessionError = null;
      api.sessionResult = {
        'session': {
          'session_id': 's-ui',
          'title': '在线恢复标题',
          'messages': [
            {'role': 'user', 'content': '在线消息', 'message_id': 'online-1'},
          ],
        },
      };

      await tester.tap(find.byKey(const ValueKey('chat-offline-cache-reload')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // 在线加载成功后，横幅自动消失
      expect(find.byKey(const ValueKey('chat-offline-cache-banner')), findsNothing);
      expect(find.text('在线消息'), findsOneWidget);

      await _unmount(tester);
      await db.close();
    });

    testWidgets('点击离线横幅关闭按钮，横幅消失', (tester) async {
      final db = AppDatabase.memory();
      final cacheService = CacheService(db);
      await cacheService.writeMessages(
        sessionId: 's-ui-close',
        messages: [
          {'id': 'm1', 'role': 'user', 'content': '离线消息'},
        ],
      );

      final api = _FakeChatApi();
      api.sessionError = NetworkException(NetworkExceptionKind.offline);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            chatApiProvider.overrideWithValue(api),
            cacheServiceProvider.overrideWithValue(cacheService),
            appDatabaseProvider.overrideWithValue(db),
          ],
          child: const CupertinoApp(home: ChatPage(sessionId: 's-ui-close')),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byKey(const ValueKey('chat-offline-cache-banner')), findsOneWidget);

      // 点击关闭按钮
      await tester.tap(find.byKey(const ValueKey('chat-offline-cache-dismiss')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byKey(const ValueKey('chat-offline-cache-banner')), findsNothing);

      await _unmount(tester);
      await db.close();
    });
  });
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

ProviderContainer _buildContainer(
  _FakeChatApi api, {
  CacheService? cacheService,
  AppDatabase? db,
}) {
  final container = ProviderContainer(
    overrides: [
      chatApiProvider.overrideWithValue(api),
      if (cacheService != null)
        cacheServiceProvider.overrideWithValue(cacheService),
      if (db != null) appDatabaseProvider.overrideWithValue(db),
    ],
  );
  addTearDown(() async {
    container.dispose();
    await db?.close();
  });
  return container;
}

typedef _FakeChatApi = FakeChatApi;
