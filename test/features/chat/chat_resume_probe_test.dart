import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/api/sse_client.dart';
import 'package:hermes_ui/core/cache/app_database.dart';
import 'package:hermes_ui/core/cache/cache_providers.dart';
import 'package:hermes_ui/core/cache/cache_service.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/connections/connection_store.dart';
import 'package:hermes_ui/core/models/server_catalog.dart';
import 'package:hermes_ui/core/models/session.dart';
import 'package:hermes_ui/features/chat/chat_providers.dart';
import 'package:hermes_ui/features/chat/chat_state.dart';
import 'package:hermes_ui/features/notifications/notification_providers.dart';

import '../../helpers/fake_chat_api.dart';
import '../../helpers/in_memory_secure_storage.dart';

class _FakeClock {
  DateTime now = DateTime(2026, 9, 1, 12, 0, 0);

  DateTime call() => now;

  void advance(Duration d) => now = now.add(d);
}

class _NoopCacheService extends CacheService {
  _NoopCacheService(super.db);
  @override
  Future<void> writeMessages({
    required String sessionId,
    required List<Map<String, Object?>> messages,
  }) async {}

  @override
  Future<List<Map<String, Object?>>> readMessages(String sessionId) async =>
      const [];

  @override
  Future<void> writeSessions(List<SessionSummary> sessions) async {}

  @override
  Future<List<SessionSummary>> readSessions() async => const [];
}

ProviderContainer _buildContainer(
  FakeChatApi api,
  _FakeClock clock, {
  ChatWatchdogConfig watchdogConfig = const ChatWatchdogConfig(),
}) {
  TestWidgetsFlutterBinding.ensureInitialized();
  final db = AppDatabase.memory();
  final cache = _NoopCacheService(db);
  final container = ProviderContainer(
    overrides: [
      chatApiProvider.overrideWithValue(api),
      chatClockProvider.overrideWithValue(clock.call),
      chatWatchdogConfigProvider.overrideWithValue(watchdogConfig),
      connectionStoreProvider.overrideWithValue(
        ConnectionStore(storage: InMemorySecureStorage()),
      ),
      appDatabaseProvider.overrideWithValue(db),
      cacheServiceProvider.overrideWithValue(cache),
    ],
  );
  addTearDown(() async {
    try {
      await db.close();
    } catch (_) {}
    container.dispose();
  });
  return container;
}

void _setLifecycle(ProviderContainer container, AppLifecycleState next) {
  container.read(appLifecycleStateProvider.notifier).setState(next);
}

void main() {
  group('Phase A: 恢复/弱网空窗即时探活测试', () {
    test('后台空窗 >= 2s 时，resumed 立即触发 status probe（不等 12s 看门狗阈值）', () {
      fakeAsync((async) {
        final api = FakeChatApi()
          ..statusResponse = const ChatStreamStatusResponse(active: true);
        final clock = _FakeClock();
        // 生产默认配置：transportStaleThreshold 默认为 12s
        final container = _buildContainer(
          api,
          clock,
          watchdogConfig: const ChatWatchdogConfig(
            watchdogInterval: Duration(seconds: 1),
            progressStaleThreshold: Duration(seconds: 5),
            transportStaleThreshold: Duration(seconds: 12),
            forceReconnectThreshold: Duration(seconds: 18),
            forceReconnectWithRunningToolsThreshold: Duration(seconds: 25),
            statusPollCooldown: Duration(seconds: 4),
          ),
        );

        final controller = container.read(chatControllerProvider('').notifier);
        unawaited(controller.send('hi'));
        async.flushMicrotasks();
        expect(api.startStreamCalls, 1);

        // 切后台 3 秒（空窗 3s 远小于 12s 阈值，但在 Phase A 即时探测 2s 阈值内）
        _setLifecycle(container, AppLifecycleState.paused);
        clock.advance(const Duration(seconds: 3));
        async.elapse(const Duration(seconds: 3));
        expect(api.statusCalls, 0); // 后台期间豁免

        // 恢复前台（resumed）：应立即发起 status 探活，不等 12s/18s 重新计时
        _setLifecycle(container, AppLifecycleState.resumed);
        async.flushMicrotasks();

        expect(
          api.statusCalls,
          1,
          reason: 'resumed 且 gap >= 2s 应立即触发 status probe',
        );
        expect(api.sessionCalls, 1); // 补拉最新 transcript
        expect(api.startStreamCalls, 2); // 重连 SSE 流
      });
    });

    test('后台空窗极短（< 2s）时，resumed 不立即探活，由看门狗后续正常接管', () {
      fakeAsync((async) {
        final api = FakeChatApi()
          ..statusResponse = const ChatStreamStatusResponse(active: true);
        final clock = _FakeClock();
        final container = _buildContainer(
          api,
          clock,
          watchdogConfig: const ChatWatchdogConfig(
            watchdogInterval: Duration(seconds: 1),
            progressStaleThreshold: Duration(seconds: 5),
            transportStaleThreshold: Duration(seconds: 12),
            forceReconnectThreshold: Duration(seconds: 18),
            forceReconnectWithRunningToolsThreshold: Duration(seconds: 25),
            statusPollCooldown: Duration(seconds: 4),
          ),
        );

        final controller = container.read(chatControllerProvider('').notifier);
        unawaited(controller.send('hi'));
        async.flushMicrotasks();
        expect(api.startStreamCalls, 1);

        // 切后台仅 500ms（极短切走切回）
        _setLifecycle(container, AppLifecycleState.paused);
        clock.advance(const Duration(milliseconds: 500));
        async.elapse(const Duration(milliseconds: 500));

        _setLifecycle(container, AppLifecycleState.resumed);
        async.flushMicrotasks();

        expect(api.statusCalls, 0, reason: '极短切屏不应触发 status probe 避免刷接口');
        expect(api.startStreamCalls, 1);
      });
    });

    test('resumed 后收到首个 token 时记录诊断耗时日志', () {
      fakeAsync((async) {
        final api = FakeChatApi()
          ..statusResponse = const ChatStreamStatusResponse(active: true);
        final clock = _FakeClock();
        final container = _buildContainer(api, clock);

        final controller = container.read(chatControllerProvider('').notifier);
        unawaited(controller.send('hi'));
        async.flushMicrotasks();

        // 模拟切后台 3s 后恢复
        _setLifecycle(container, AppLifecycleState.paused);
        clock.advance(const Duration(seconds: 3));
        async.elapse(const Duration(seconds: 3));

        _setLifecycle(container, AppLifecycleState.resumed);
        async.flushMicrotasks();

        // 模拟 200ms 后收到新 token
        clock.advance(const Duration(milliseconds: 200));
        api.emit(const TokenSseEvent('First token after resume'));
        async.elapse(const Duration(milliseconds: 16));
        async.elapse(const Duration(milliseconds: 48));

        // 验证状态正常进入流式追加
        final state = container.read(chatControllerProvider(''));
        expect(state.phase, ChatPhase.streaming);
      });
    });
  });
}
