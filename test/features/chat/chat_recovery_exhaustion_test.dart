import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/api/api_exception.dart';
import 'package:hermes_ui/core/cache/app_database.dart';
import 'package:hermes_ui/core/cache/cache_providers.dart';
import 'package:hermes_ui/core/cache/cache_service.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/connections/connection_store.dart';
import 'package:hermes_ui/core/models/server_catalog.dart';
import 'package:hermes_ui/core/models/session.dart';
import 'package:hermes_ui/features/chat/chat_providers.dart';
import 'package:hermes_ui/features/chat/chat_state.dart';
import 'package:hermes_ui/features/diagnostics/diagnostics_models.dart';
import 'package:hermes_ui/features/diagnostics/diagnostics_service.dart';
import 'package:hermes_ui/features/notifications/notification_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_chat_api.dart';
import '../../helpers/in_memory_secure_storage.dart';

class _FakeClock {
  DateTime now = DateTime(2026, 9, 8, 12, 0, 0);

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
  ChatWatchdogConfig watchdogConfig = const ChatWatchdogConfig(
    reconnectJitterMax: Duration.zero,
  ),
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

/// 反复传输错误 + 探活失败，直至烧尽 6 次重连预算（退避 1+2+4+8+16+30s）。
void _exhaustReconnectBudget(
  FakeAsync async,
  _FakeClock clock,
  FakeChatApi api,
) {
  for (var round = 0; round < 14; round++) {
    api.fail('network lost');
    async.flushMicrotasks();
    clock.advance(const Duration(seconds: 2));
    async.elapse(const Duration(seconds: 2));
    async.flushMicrotasks();
  }
}

int _exhaustedWarnCount() => DiagnosticsService.instance.logs
    .where(
      (e) =>
          e.level == DiagnosticsLogLevel.warn &&
          e.message.contains('Recovery exhausted'),
    )
    .length;

void main() {
  setUpAll(() async {
    // 启用诊断日志采集（F3 的 WARN 观测性断言依赖 DiagnosticsService.buffer）。
    SharedPreferences.setMockInitialValues({kDiagnosticsEnabledKey: true});
    await DiagnosticsService.instance.init();
    await DiagnosticsService.instance.clear();
  });

  setUp(() {
    unawaited(DiagnosticsService.instance.clear());
  });

  group('#100 F1: resumed 重置恢复状态（拆预算/闩锁死锁）', () {
    test('预算烧尽 + recovery 闩锁 → resumed 复位后解锁探活触发并重连流', () {
      fakeAsync((async) {
        final api = FakeChatApi();
        final clock = _FakeClock();
        final container = _buildContainer(api, clock);
        final controller = container.read(chatControllerProvider('').notifier);

        unawaited(controller.send('hi'));
        async.flushMicrotasks();
        expect(api.startStreamCalls, 1);

        // 传输错误 + 探活持续失败：退避重连链烧尽 6 次预算。
        api.statusError = NetworkException(NetworkExceptionKind.timedOut);
        _exhaustReconnectBudget(async, clock, api);

        // 死锁形态：recovery 闩在 checking；再 fail 不再触发重连（预算耗尽）。
        expect(
          container.read(chatControllerProvider('')).stream.recovery,
          ActiveStreamRecoveryState.checking,
          reason: 'onTransportError 置 checking，预算烧尽后无人复位',
        );
        final startsAfterExhaust = api.startStreamCalls;
        api.fail('still dead');
        async.flushMicrotasks();
        expect(
          api.startStreamCalls,
          startsAfterExhaust,
          reason: '预算耗尽后强制重连被抑制',
        );

        // 锁屏（真实场景：熄屏后再解锁），制造 paused→resumed 过渡。
        _setLifecycle(container, AppLifecycleState.paused);

        // 解锁回前台：F1 重置预算 + 复位闩锁 → #29 解锁探活不再被封死。
        // 先推进 3s 空窗（最后 fail 刚刷新过活动时间戳，gap<2s 会被探活阈值挡住）。
        clock.advance(const Duration(seconds: 3));
        async.elapse(const Duration(seconds: 3));
        api
          ..statusError = null
          ..statusResponse = const ChatStreamStatusResponse(active: true);
        final statusBeforeResume = api.statusCalls;
        _setLifecycle(container, AppLifecycleState.resumed);
        async.flushMicrotasks();

        expect(
          api.statusCalls,
          greaterThan(statusBeforeResume),
          reason: '解锁探活触发（recovery 闩锁已被 F1 复位）',
        );
        expect(
          container.read(chatControllerProvider('')).stream.recovery,
          ActiveStreamRecoveryState.idle,
        );
        expect(
          api.startStreamCalls,
          greaterThan(startsAfterExhaust),
          reason: 'status active=true → 重连 SSE 流',
        );
      });
    });

    test('recovery=idle 时短暂切走切回不额外改状态（幂等）', () {
      fakeAsync((async) {
        final api = FakeChatApi()
          ..statusResponse = const ChatStreamStatusResponse(active: true);
        final clock = _FakeClock();
        final container = _buildContainer(api, clock);
        final controller = container.read(chatControllerProvider('').notifier);

        unawaited(controller.send('hi'));
        async.flushMicrotasks();

        // 未断流（recovery=idle）短暂切走再切回：gap<2s 无探活、状态不变。
        _setLifecycle(container, AppLifecycleState.paused);
        clock.advance(const Duration(milliseconds: 500));
        async.elapse(const Duration(milliseconds: 500));
        _setLifecycle(container, AppLifecycleState.resumed);
        async.flushMicrotasks();

        final state = container.read(chatControllerProvider(''));
        expect(state.stream.recovery, ActiveStreamRecoveryState.idle);
        expect(api.statusCalls, 0);
        expect(api.startStreamCalls, 1);
      });
    });
  });

  group('#100 F2: resume 探活失败重试（等 WiFi/frp 就绪）', () {
    test('探活失败 → 2s 后重试 → 成功恢复（不转 forceReconnect）', () {
      fakeAsync((async) {
        final api = FakeChatApi();
        final clock = _FakeClock();
        final container = _buildContainer(api, clock);
        final controller = container.read(chatControllerProvider('').notifier);

        unawaited(controller.send('hi'));
        async.flushMicrotasks();
        expect(api.startStreamCalls, 1);

        // 后台空窗 3s → 解锁触发主动探活（此时网络未就绪，status 失败）。
        _setLifecycle(container, AppLifecycleState.paused);
        clock.advance(const Duration(seconds: 3));
        async.elapse(const Duration(seconds: 3));
        api.statusError = NetworkException(NetworkExceptionKind.timedOut);
        _setLifecycle(container, AppLifecycleState.resumed);
        async.flushMicrotasks();
        expect(api.statusCalls, 1);

        // 网络就绪前不重复请求。
        clock.advance(const Duration(seconds: 1));
        async.elapse(const Duration(seconds: 1));
        expect(api.statusCalls, 1);

        // 2s 重试到期：网络已就绪 → 探活成功 → 拉取消息并重连流。
        api
          ..statusError = null
          ..statusResponse = const ChatStreamStatusResponse(active: true);
        clock.advance(const Duration(seconds: 1));
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();
        expect(api.statusCalls, 2, reason: '重试到期后恢复探活');
        expect(api.startStreamCalls, 2, reason: 'active=true → 重连 SSE 流');
      });
    });

    test('重试耗尽后才转 forceReconnect（回归既有回退行为）', () {
      fakeAsync((async) {
        final api = FakeChatApi();
        final clock = _FakeClock();
        final container = _buildContainer(
          api,
          clock,
          watchdogConfig: const ChatWatchdogConfig(
            reconnectJitterMax: Duration.zero,
            resumeProbeRetries: 1,
            resumeProbeRetryDelay: Duration(seconds: 2),
          ),
        );
        final controller = container.read(chatControllerProvider('').notifier);

        unawaited(controller.send('hi'));
        async.flushMicrotasks();
        expect(api.startStreamCalls, 1);

        _setLifecycle(container, AppLifecycleState.paused);
        clock.advance(const Duration(seconds: 3));
        async.elapse(const Duration(seconds: 3));
        api.statusError = NetworkException(NetworkExceptionKind.timedOut);
        _setLifecycle(container, AppLifecycleState.resumed);
        async.flushMicrotasks();
        expect(api.statusCalls, 1);

        // 重试 1 次（仍失败）。
        clock.advance(const Duration(seconds: 2));
        async.elapse(const Duration(seconds: 2));
        async.flushMicrotasks();
        expect(api.statusCalls, 2);

        // 重试耗尽 → 转强连。
        clock.advance(const Duration(seconds: 1));
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();
        expect(api.startStreamCalls, 2, reason: '重试耗尽回退 forceReconnect');
      });
    });
  });

  group('#100 F3: 预算耗尽哨兵（观测性 + 前台自愈）', () {
    test('耗尽后每 60s WARN + 探活；探活成功即解除耗尽并自毁', () {
      fakeAsync((async) {
        final api = FakeChatApi();
        final clock = _FakeClock();
        final container = _buildContainer(api, clock);
        final controller = container.read(chatControllerProvider('').notifier);

        unawaited(controller.send('hi'));
        async.flushMicrotasks();
        expect(api.startStreamCalls, 1);

        // 前台烧尽预算（传输错误 + 探活全部失败）。
        api.statusError = NetworkException(NetworkExceptionKind.timedOut);
        _exhaustReconnectBudget(async, clock, api);
        expect(_exhaustedWarnCount(), 0, reason: '耗尽前无哨兵日志');

        // 耗尽后 60s：哨兵首次 tick → WARN + 探活（仍失败）。
        clock.advance(const Duration(seconds: 60));
        async.elapse(const Duration(seconds: 60));
        async.flushMicrotasks();
        expect(
          _exhaustedWarnCount(),
          1,
          reason: '耗尽后有 WARN 观测性日志（不再是纯静默）',
        );

        // 再 60s：哨兵第二次 tick → WARN + 探活（网络已就绪 → 成功）。
        api
          ..statusError = null
          ..statusResponse = const ChatStreamStatusResponse(active: true);
        final statusBeforeRecover = api.statusCalls;
        clock.advance(const Duration(seconds: 60));
        async.elapse(const Duration(seconds: 60));
        async.flushMicrotasks();
        expect(_exhaustedWarnCount(), 2);
        expect(
          api.statusCalls,
          greaterThan(statusBeforeRecover),
          reason: '哨兵探活成功',
        );

        // 探活成功 → 预算重置 + 哨兵自毁：之后 120s 不再有 exhausted WARN
        //（watchdog 正常探活仍在，但不属于哨兵行为）。
        clock.advance(const Duration(seconds: 120));
        async.elapse(const Duration(seconds: 120));
        async.flushMicrotasks();
        expect(
          _exhaustedWarnCount(),
          2,
          reason: '预算恢复后哨兵自毁，不再周期探活',
        );
      });
    });
  });

  group('#100 F4: onClosed 复位 recovery 闩锁', () {
    test('checking 态下传输关闭 → recovery 复位 idle（resume 探活入口不再被封）', () {
      fakeAsync((async) {
        final api = FakeChatApi();
        final clock = _FakeClock();
        final container = _buildContainer(api, clock);
        final controller = container.read(chatControllerProvider('').notifier);

        unawaited(controller.send('hi'));
        async.flushMicrotasks();
        expect(api.startStreamCalls, 1);

        // 触发 transport error（recovery → checking）。
        api.fail('network lost');
        async.flushMicrotasks();
        expect(
          container.read(chatControllerProvider('')).stream.recovery,
          ActiveStreamRecoveryState.checking,
        );

        // 模拟传输层关闭（无 onTransportError 的静默断开族）→ F4 复位。
        api.closeStream();
        async.flushMicrotasks();
        expect(
          container.read(chatControllerProvider('')).stream.recovery,
          ActiveStreamRecoveryState.idle,
          reason: 'onClosed 复位闩锁',
        );
      });
    });
  });
}
