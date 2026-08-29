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
import 'package:hermes_ui/features/notifications/notification_providers.dart';

import '../../helpers/fake_chat_api.dart';
import '../../helpers/in_memory_secure_storage.dart';

void main() {
  group('ChatWatchdogConfig 默认阈值配置（单一真相源）', () {
    test('默认配置收紧为 1s/3s/3s/8s/8s/3s', () {
      const config = ChatWatchdogConfig();
      expect(config.watchdogInterval, const Duration(seconds: 1));
      expect(config.progressStaleThreshold, const Duration(seconds: 3));
      expect(config.transportStaleThreshold, const Duration(seconds: 3));
      expect(config.forceReconnectThreshold, const Duration(seconds: 8));
      expect(
        config.forceReconnectWithRunningToolsThreshold,
        const Duration(seconds: 8),
      );
      expect(config.statusPollCooldown, const Duration(seconds: 3));
    });
  });

  group('前台看门狗探活与强制重连（3s 探活 / 8s 强连）', () {
    test('传输停滞 3s 立即触发 status 探活（checking 态）', () {
      fakeAsync((async) {
        final api = FakeChatApi();
        final clock = _FakeClock();
        final container = _buildContainer(api, clock);
        final controller = container.read(chatControllerProvider('').notifier);

        unawaited(controller.send('hi'));
        async.flushMicrotasks();
        expect(api.startStreamCalls, 1);
        expect(api.statusCalls, 0);

        // 2s：未达 3s 阈值，不探活
        clock.advance(const Duration(seconds: 2));
        async.elapse(const Duration(seconds: 2));
        expect(api.statusCalls, 0);

        // 达到 3s：触发 status 检查
        clock.advance(const Duration(seconds: 1));
        async.elapse(const Duration(seconds: 1));
        expect(api.statusCalls, 1);
      });
    });

    test('双门槛机制：仅无 progress 但有 transport（如心跳）时不触发 status 探活', () {
      fakeAsync((async) {
        final api = FakeChatApi();
        final clock = _FakeClock();
        final container = _buildContainer(api, clock);
        final controller = container.read(chatControllerProvider('').notifier);

        unawaited(controller.send('hi'));
        async.flushMicrotasks();

        // 模拟每 2 秒收到一次心跳，维持 transport 存活
        for (var i = 0; i < 4; i++) {
          clock.advance(const Duration(seconds: 2));
          async.elapse(const Duration(seconds: 2));
          api.emit(const HeartbeatSseEvent());
        }

        // 虽累计 8s 无 token progress，但 transport 持续活跃，不误判断线
        expect(api.statusCalls, 0);
        expect(api.startStreamCalls, 1);
      });
    });

    test('探活冷却：status 检查触发后 3s 冷却期内不重复轮询', () {
      fakeAsync((async) {
        final api = FakeChatApi();
        api.statusResponse = const ChatStreamStatusResponse(active: true);
        final clock = _FakeClock();
        final container = _buildContainer(api, clock);
        final controller = container.read(chatControllerProvider('').notifier);

        unawaited(controller.send('hi'));
        async.flushMicrotasks();

        // 3s 触发首次探活
        clock.advance(const Duration(seconds: 3));
        async.elapse(const Duration(seconds: 3));
        async.flushMicrotasks();
        expect(api.statusCalls, 1);

        // 4s 与 5s（冷却 3s 期间）：不重复发送 status 请求
        clock.advance(const Duration(seconds: 1));
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();
        expect(api.statusCalls, 1);

        clock.advance(const Duration(seconds: 1));
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();
        expect(api.statusCalls, 1);

        // 6s（now == cooldown = 6s，尚未 isAfter）：仍受冷却保护
        clock.advance(const Duration(seconds: 1));
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();
        expect(api.statusCalls, 1);

        // 7s（now > cooldown = 6s，冷却已过且停滞 ≥ 3s）：再次触发 status 检查
        clock.advance(const Duration(seconds: 1));
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();
        expect(api.statusCalls, 2);
      });
    });

    test('传输停滞 8s 触发强制重连（无运行中工具）', () {
      fakeAsync((async) {
        final api = FakeChatApi();
        api.statusResponse = const ChatStreamStatusResponse(active: true);
        final clock = _FakeClock();
        final container = _buildContainer(api, clock);
        final controller = container.read(chatControllerProvider('').notifier);

        unawaited(controller.send('hi'));
        async.flushMicrotasks();
        expect(api.startStreamCalls, 1);

        // 停滞 8s
        clock.advance(const Duration(seconds: 8));
        async.elapse(const Duration(seconds: 8));
        async.flushMicrotasks();

        // 触发重连 → startStream 重新调用
        expect(api.startStreamCalls, greaterThanOrEqualTo(2));
      });
    });

    test('传输停滞 8s 触发强制重连（有运行中工具，统一 8s）', () {
      fakeAsync((async) {
        final api = FakeChatApi();
        api.statusResponse = const ChatStreamStatusResponse(active: true);
        final clock = _FakeClock();
        final container = _buildContainer(api, clock);
        final controller = container.read(chatControllerProvider('').notifier);

        unawaited(controller.send('hi'));
        async.flushMicrotasks();

        // 发射未完成工具事件
        api.emit(
          const ToolStartedSseEvent(
            ToolStreamEvent(stableId: 'tool-1', name: 'search'),
          ),
        );
        async.flushMicrotasks();

        // 停滞 7s：未达 8s，且在 3s/6s 会经历 status 探活重连
        clock.advance(const Duration(seconds: 7));
        async.elapse(const Duration(seconds: 7));
        async.flushMicrotasks();

        // 达到 8s：触发强制重连
        clock.advance(const Duration(seconds: 1));
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();

        expect(api.startStreamCalls, greaterThanOrEqualTo(2));
      });
    });

    test('后台/锁屏期间停滞不触发看门狗，切回前台立即按 3s 阈值补查', () {
      fakeAsync((async) {
        final api = FakeChatApi();
        final clock = _FakeClock();
        final container = _buildContainer(api, clock);
        final controller = container.read(chatControllerProvider('').notifier);

        unawaited(controller.send('hi'));
        async.flushMicrotasks();
        expect(api.startStreamCalls, 1);

        // 锁屏进入后台
        _setLifecycle(container, AppLifecycleState.paused);

        // 后台静默 10s：远超 3s/8s 阈值，但后台豁免 → 零探活零重连
        clock.advance(const Duration(seconds: 10));
        async.elapse(const Duration(seconds: 10));
        expect(api.statusCalls, 0);
        expect(api.startStreamCalls, 1);

        // 切回前台：空窗 10s ≥ 3s → 立即主动查 status
        api.statusResponse = const ChatStreamStatusResponse(active: true);
        _setLifecycle(container, AppLifecycleState.resumed);
        async.flushMicrotasks();

        expect(api.statusCalls, 1);
      });
    });
  });
}

// ---------------------------------------------------------------------------
// 测试辅助
// ---------------------------------------------------------------------------

class _FakeClock {
  DateTime now = DateTime(2026, 1, 1);

  DateTime call() => now;

  void advance(Duration duration) => now = now.add(duration);
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

void _setLifecycle(ProviderContainer container, AppLifecycleState state) {
  container.read(appLifecycleStateProvider.notifier).setState(state);
}
