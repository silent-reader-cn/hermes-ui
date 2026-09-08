import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/api/api_exception.dart';
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
    test('默认配置为 1s/5s/12s/18s/25s/4s 及退避序列与上限', () {
      const config = ChatWatchdogConfig();
      expect(config.watchdogInterval, const Duration(seconds: 1));
      expect(config.progressStaleThreshold, const Duration(seconds: 5));
      expect(config.transportStaleThreshold, const Duration(seconds: 12));
      expect(config.forceReconnectThreshold, const Duration(seconds: 18));
      expect(
        config.forceReconnectWithRunningToolsThreshold,
        const Duration(seconds: 25),
      );
      expect(config.statusPollCooldown, const Duration(seconds: 4));
      expect(config.heartbeatInterval, const Duration(seconds: 5));
      expect(config.transportFreshThreshold, const Duration(seconds: 10));
      expect(config.maxReconnectAttempts, 6);
      expect(config.reconnectBackoffDelays, const [
        Duration(seconds: 1),
        Duration(seconds: 2),
        Duration(seconds: 4),
        Duration(seconds: 8),
        Duration(seconds: 16),
        Duration(seconds: 30),
      ]);
      expect(config.backoffDelayForAttempt(0), const Duration(seconds: 1));
      expect(config.backoffDelayForAttempt(1), const Duration(seconds: 2));
      expect(config.backoffDelayForAttempt(5), const Duration(seconds: 30));
      expect(config.backoffDelayForAttempt(10), const Duration(seconds: 30));
      expect(config.reconnectJitterMax, const Duration(milliseconds: 1500));
      expect(config.fullReconnectCooldown, const Duration(seconds: 60));
    });
  });

  group('前台看门狗探活与强制重连（5s 进度 + 12s 传输探活 / 18s 强连 / 25s 工具强连）', () {
    test('传输停滞 12s 立即触发 status 探活（checking 态）', () {
      fakeAsync((async) {
        final api = FakeChatApi();
        final clock = _FakeClock();
        final container = _buildContainer(api, clock);
        final controller = container.read(chatControllerProvider('').notifier);

        unawaited(controller.send('hi'));
        async.flushMicrotasks();
        expect(api.startStreamCalls, 1);
        expect(api.statusCalls, 0);

        // 11s：未达 12s 阈值，不探活
        clock.advance(const Duration(seconds: 11));
        async.elapse(const Duration(seconds: 11));
        expect(api.statusCalls, 0);

        // 达到 12s：触发 status 检查
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
        for (var i = 0; i < 7; i++) {
          clock.advance(const Duration(seconds: 2));
          async.elapse(const Duration(seconds: 2));
          api.emit(const HeartbeatSseEvent());
        }

        // 虽累计 14s 无 token progress，但 transport 持续活跃，不误判断线
        expect(api.statusCalls, 0);
        expect(api.startStreamCalls, 1);
      });
    });

    test('探活冷却：status 检查触发后 4s 冷却期内不重复轮询', () {
      fakeAsync((async) {
        final api = FakeChatApi();
        api.statusResponse = const ChatStreamStatusResponse(active: true);
        final clock = _FakeClock();
        final container = _buildContainer(api, clock);
        final controller = container.read(chatControllerProvider('').notifier);

        unawaited(controller.send('hi'));
        async.flushMicrotasks();

        // 12s 触发首次探活
        clock.advance(const Duration(seconds: 12));
        async.elapse(const Duration(seconds: 12));
        async.flushMicrotasks();
        expect(api.statusCalls, 1);

        // 13s..15s（冷却 4s 期间）：不重复发送 status 请求
        clock.advance(const Duration(seconds: 1));
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();
        expect(api.statusCalls, 1);

        clock.advance(const Duration(seconds: 1));
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();
        expect(api.statusCalls, 1);

        clock.advance(const Duration(seconds: 1));
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();
        expect(api.statusCalls, 1);

        // 16s（now == cooldown = 16s，尚未 isAfter）：仍受冷却保护
        clock.advance(const Duration(seconds: 1));
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();
        expect(api.statusCalls, 1);

        // 17s（now > cooldown = 16s，冷却已过且停滞 ≥ 12s）：再次触发 status 检查
        clock.advance(const Duration(seconds: 1));
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();
        expect(api.statusCalls, 2);
      });
    });

    test('传输停滞 18s 触发强制重连（无运行中工具）', () {
      fakeAsync((async) {
        final api = FakeChatApi();
        api.statusResponse = const ChatStreamStatusResponse(active: true);
        final clock = _FakeClock();
        final container = _buildContainer(api, clock);
        final controller = container.read(chatControllerProvider('').notifier);

        unawaited(controller.send('hi'));
        async.flushMicrotasks();
        expect(api.startStreamCalls, 1);

        // 停滞 18s
        clock.advance(const Duration(seconds: 18));
        async.elapse(const Duration(seconds: 18));
        async.flushMicrotasks();

        // 触发重连 → startStream 重新调用
        expect(api.startStreamCalls, greaterThanOrEqualTo(2));
      });
    });

    test('传输停滞 25s 触发强制重连（有运行中工具）', () {
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

        // 停滞 24s：未达 25s
        clock.advance(const Duration(seconds: 24));
        async.elapse(const Duration(seconds: 24));
        async.flushMicrotasks();

        // 达到 25s：触发强制重连
        clock.advance(const Duration(seconds: 1));
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();

        expect(api.startStreamCalls, greaterThanOrEqualTo(2));
      });
    });

    test('工具运行中 + progress 陈旧超阈值 + _lastTransportActivity 距今 < 10s：不触发 status 轮询/强重连', () {
      fakeAsync((async) {
        final api = FakeChatApi();
        final clock = _FakeClock();
        final container = _buildContainer(api, clock);
        final controller = container.read(chatControllerProvider('').notifier);

        unawaited(controller.send('hi'));
        async.flushMicrotasks();

        // 发射未完成工具事件（如读取大文件/执行长后台命令）
        api.emit(
          const ToolStartedSseEvent(
            ToolStreamEvent(stableId: 'tool-read', name: 'read_file'),
          ),
        );
        async.flushMicrotasks();

        // 持续发送心跳（每 2s 一次，距今 < 10s 门控有效）维持 30s
        for (var i = 0; i < 15; i++) {
          clock.advance(const Duration(seconds: 2));
          async.elapse(const Duration(seconds: 2));
          api.emit(const HeartbeatSseEvent());
        }
        async.flushMicrotasks();

        // 工具运行中且进度陈旧超 18s/25s 阈值，但心跳持续到达（transport fresh），
        // 门控生效：不触发 status 轮询，不触发 force 强制重连（工具跑得慢 ≠ 连接死了）
        expect(api.statusCalls, 0);
        expect(api.startStreamCalls, 1);
      });
    });

    test(
      '工具运行中 + progress 陈旧超阈值 + transport 静默超阈值：仍触发 status 探活与强制重连（覆盖既有行为）',
      () {
        fakeAsync((async) {
          final api = FakeChatApi();
          api.statusError = NetworkException(NetworkExceptionKind.timedOut);
          final clock = _FakeClock();
          final container = _buildContainer(api, clock);
          final controller = container.read(
            chatControllerProvider('').notifier,
          );

          unawaited(controller.send('hi'));
          async.flushMicrotasks();
          expect(api.startStreamCalls, 1);

          // 发射未完成工具事件
          api.emit(
            const ToolStartedSseEvent(
              ToolStreamEvent(stableId: 'tool-read', name: 'read_file'),
            ),
          );
          async.flushMicrotasks();

          // 传输完全静默超 18s（心跳中断，距今 ≥ 10s 门控失效）
          clock.advance(const Duration(seconds: 18));
          async.elapse(const Duration(seconds: 18));
          async.flushMicrotasks();

          // 达到 18s 且 transport 不再 fresh：触发 status 探活；探活异常回退 force 强制重连
          expect(api.statusCalls, 1);
          expect(api.startStreamCalls, greaterThanOrEqualTo(2));
        });
      },
    );

    test('工具运行中 + transport 静默超阈值且探活挂起：25s 触发强制重连（覆盖既有行为）', () {
      fakeAsync((async) {
        final api = FakeChatApi();
        // status 探活请求一直挂起（模拟服务端僵死无响应）
        final pendingStatus = Completer<ChatStreamStatusResponse>();
        api.onChatStreamStatus = (_) => pendingStatus.future;

        final clock = _FakeClock();
        final container = _buildContainer(api, clock);
        final controller = container.read(chatControllerProvider('').notifier);

        unawaited(controller.send('hi'));
        async.flushMicrotasks();
        expect(api.startStreamCalls, 1);

        // 发射未完成工具事件
        api.emit(
          const ToolStartedSseEvent(
            ToolStreamEvent(stableId: 'tool-hang', name: 'read_file'),
          ),
        );
        async.flushMicrotasks();

        // 传输完全静默推进到 24s（18s 时已触发 status 但挂起中）
        clock.advance(const Duration(seconds: 24));
        async.elapse(const Duration(seconds: 24));
        async.flushMicrotasks();

        expect(api.statusCalls, greaterThanOrEqualTo(1));
        expect(api.startStreamCalls, 1);

        // 达到 25s（1s 后）
        clock.advance(const Duration(seconds: 1));
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();

        // 达到 25s 且传输静默：强制重连触发
        expect(api.startStreamCalls, greaterThanOrEqualTo(2));
      });
    });

    test('工具在 18s 内正常完成（ToolCompleted）：心跳持续存在时不误报探活', () {
      fakeAsync((async) {
        final api = FakeChatApi();
        final clock = _FakeClock();
        final container = _buildContainer(api, clock);
        final controller = container.read(chatControllerProvider('').notifier);

        unawaited(controller.send('hi'));
        async.flushMicrotasks();

        // 发射工具开始
        api.emit(
          const ToolStartedSseEvent(
            ToolStreamEvent(stableId: 'tool-fast', name: 'read_file'),
          ),
        );
        async.flushMicrotasks();

        // 6s 后工具完成
        clock.advance(const Duration(seconds: 6));
        async.elapse(const Duration(seconds: 6));
        api.emit(
          const ToolCompletedSseEvent(
            ToolStreamEvent(stableId: 'tool-fast', name: 'read_file'),
          ),
        );
        async.flushMicrotasks();

        // 之后持续心跳至 24s（自开始 30s）
        for (var i = 0; i < 12; i++) {
          clock.advance(const Duration(seconds: 2));
          async.elapse(const Duration(seconds: 2));
          api.emit(const HeartbeatSseEvent());
        }
        async.flushMicrotasks();

        // 工具已完成且心跳维持传输，不误报 status 探活
        expect(api.statusCalls, 0);
        expect(api.startStreamCalls, 1);
      });
    });

    test('后台/锁屏期间停滞不触发看门狗，切回前台立即按 12s 阈值补查', () {
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

        // 后台静默 15s：远超 5s/12s 阈值，但后台豁免 → 零探活零重连
        clock.advance(const Duration(seconds: 15));
        async.elapse(const Duration(seconds: 15));
        expect(api.statusCalls, 0);
        expect(api.startStreamCalls, 1);

        // 切回前台：空窗 15s ≥ 12s → 立即主动查 status
        api.statusResponse = const ChatStreamStatusResponse(active: true);
        _setLifecycle(container, AppLifecycleState.resumed);
        async.flushMicrotasks();

        expect(api.statusCalls, 1);
      });
    });
  });

  group('T1: 看门狗重连与探活错峰 jitter（防 N 会话同秒齐触发）', () {
    test('jitter=0 时：传输停滞 12s 立即触发 status 探活，18s 立即触发 forceReconnect', () {
      fakeAsync((async) {
        final api = FakeChatApi();
        api.statusResponse = const ChatStreamStatusResponse(active: true);
        final clock = _FakeClock();
        const config = ChatWatchdogConfig(
          reconnectJitterMax: Duration.zero,
        );
        final container = _buildContainer(api, clock, watchdogConfig: config);
        final controller = container.read(chatControllerProvider('').notifier);

        unawaited(controller.send('hi'));
        async.flushMicrotasks();
        expect(api.startStreamCalls, 1);

        // 逐步推进到 11s
        for (var i = 0; i < 11; i++) {
          clock.advance(const Duration(seconds: 1));
          async.elapse(const Duration(seconds: 1));
        }
        expect(api.statusCalls, 0);

        // 达到 12s：立即触发 statusCalls
        clock.advance(const Duration(seconds: 1));
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();
        expect(api.statusCalls, 1);

        // 推进到 17s
        for (var i = 0; i < 5; i++) {
          clock.advance(const Duration(seconds: 1));
          async.elapse(const Duration(seconds: 1));
        }

        // 达到 18s：立即触发 forceReconnect
        clock.advance(const Duration(seconds: 1));
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();
        expect(api.startStreamCalls, greaterThanOrEqualTo(2));
      });
    });

    test('jitter>0 时：延迟窗口内不触发 status 探活，延迟到期后触发', () {
      fakeAsync((async) {
        final api = FakeChatApi();
        api.statusResponse = const ChatStreamStatusResponse(active: true);
        final clock = _FakeClock();
        // 注入固定 800ms jitter
        final config = ChatWatchdogConfig(
          customJitter: ([_]) => const Duration(milliseconds: 800),
        );
        final container = _buildContainer(api, clock, watchdogConfig: config);
        final controller = container.read(chatControllerProvider('').notifier);

        unawaited(controller.send('hi'));
        async.flushMicrotasks();
        expect(api.statusCalls, 0);

        // 逐步推进到 11s：未超阈值
        for (var i = 0; i < 11; i++) {
          clock.advance(const Duration(seconds: 1));
          async.elapse(const Duration(seconds: 1));
        }
        async.flushMicrotasks();
        expect(api.statusCalls, 0);

        // 推进到 12s：看门狗 tick 检测到陈旧，调度 800ms jitter 定时器
        clock.advance(const Duration(seconds: 1));
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();
        // 延迟窗口内：尚未发起 status 请求
        expect(api.statusCalls, 0);

        // 推进 400ms（累计 400ms，在 800ms 窗口内）：依然未触发
        clock.advance(const Duration(milliseconds: 400));
        async.elapse(const Duration(milliseconds: 400));
        async.flushMicrotasks();
        expect(api.statusCalls, 0);

        // 再推进 400ms（累计 800ms，jitter 到期）：触发 status 请求
        clock.advance(const Duration(milliseconds: 400));
        async.elapse(const Duration(milliseconds: 400));
        async.flushMicrotasks();
        expect(api.statusCalls, 1);
      });
    });

    test('jitter>0 时：延迟窗口内不触发 forceReconnect，延迟到期后触发', () {
      fakeAsync((async) {
        final api = FakeChatApi();
        final pendingStatus = Completer<ChatStreamStatusResponse>();
        api.onChatStreamStatus = (_) => pendingStatus.future;
        final clock = _FakeClock();
        // 注入固定 600ms jitter
        final config = ChatWatchdogConfig(
          customJitter: ([_]) => const Duration(milliseconds: 600),
        );
        final container = _buildContainer(api, clock, watchdogConfig: config);
        final controller = container.read(chatControllerProvider('').notifier);

        unawaited(controller.send('hi'));
        async.flushMicrotasks();
        expect(api.startStreamCalls, 1);

        // 推进到 17s：未达 18s force 阈值
        for (var i = 0; i < 17; i++) {
          clock.advance(const Duration(seconds: 1));
          async.elapse(const Duration(seconds: 1));
        }
        async.flushMicrotasks();
        expect(api.startStreamCalls, 1);

        // 推进到 18s：看门狗 tick 检测到 silence，调度 600ms jitter 定时器
        clock.advance(const Duration(seconds: 1));
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();
        // 600ms 延迟窗口内：尚未发起 forceReconnect
        expect(api.startStreamCalls, 1);

        // 推进 300ms（在 600ms 窗口内）：仍未触发
        clock.advance(const Duration(milliseconds: 300));
        async.elapse(const Duration(milliseconds: 300));
        async.flushMicrotasks();
        expect(api.startStreamCalls, 1);

        // 再推进 300ms（累计 600ms，jitter 到期）：触发 forceReconnect
        clock.advance(const Duration(milliseconds: 300));
        async.elapse(const Duration(milliseconds: 300));
        async.flushMicrotasks();
        expect(api.startStreamCalls, 2);
      });
    });
  });

  group('T2: afterSeq=0 全量重放限频（拆风暴放大器）', () {
    test('连续两次 afterSeq=0 的 forceReconnect：第二次降级为 status 探活且不重建连接，冷却后恢复', () {
      fakeAsync((async) {
        final api = FakeChatApi();
        final pendingStatus = Completer<ChatStreamStatusResponse>();
        api.onChatStreamStatus = (_) => pendingStatus.future;
        final clock = _FakeClock();
        const config = ChatWatchdogConfig(
          reconnectJitterMax: Duration.zero,
          fullReconnectCooldown: Duration(seconds: 60),
        );
        final container = _buildContainer(api, clock, watchdogConfig: config);
        final controller = container.read(chatControllerProvider('').notifier);

        unawaited(controller.send('hi'));
        async.flushMicrotasks();
        expect(api.startStreamCalls, 1);
        final initialStopCalls = api.stopStreamCalls;

        // 停滞 18s 触发首次 forceReconnect（afterSeq=0）
        for (var i = 0; i < 18; i++) {
          clock.advance(const Duration(seconds: 1));
          async.elapse(const Duration(seconds: 1));
        }
        async.flushMicrotasks();

        // 首次全量重连：stopStream 与 startStream 均调用
        expect(api.startStreamCalls, 2);
        final stopCallsAfterFirst = api.stopStreamCalls;
        expect(stopCallsAfterFirst, greaterThan(initialStopCalls));

        // 60s 冷却内（18s 后）再次发生静默停滞超 18s
        for (var i = 0; i < 18; i++) {
          clock.advance(const Duration(seconds: 1));
          async.elapse(const Duration(seconds: 1));
        }
        async.flushMicrotasks();

        // 限频生效：第二次不断开重建连接（stopStream 与 startStream 调用次数均不增加）
        expect(api.stopStreamCalls, stopCallsAfterFirst);
        expect(api.startStreamCalls, 2);
        // 但降级为 status 探活
        expect(api.statusCalls, greaterThanOrEqualTo(1));

        // 冷却期过期（推进超过 60s）
        for (var i = 0; i < 60; i++) {
          clock.advance(const Duration(seconds: 1));
          async.elapse(const Duration(seconds: 1));
        }
        async.flushMicrotasks();

        // 再次停滞 18s 触发 forceReconnect
        for (var i = 0; i < 18; i++) {
          clock.advance(const Duration(seconds: 1));
          async.elapse(const Duration(seconds: 1));
        }
        async.flushMicrotasks();

        // 冷却已过：允许新的全量重连，stopStreamCalls 与 startStreamCalls 再次增加
        expect(api.stopStreamCalls, greaterThan(stopCallsAfterFirst));
        expect(api.startStreamCalls, 3);
      });
    });

    test('afterSeq>0 的 replay 路径不受 60s 冷却限制，连续触发正常重连', () {
      fakeAsync((async) {
        final api = FakeChatApi();
        final pendingStatus = Completer<ChatStreamStatusResponse>();
        api.onChatStreamStatus = (_) => pendingStatus.future;
        final clock = _FakeClock();
        const config = ChatWatchdogConfig(
          reconnectJitterMax: Duration.zero,
          fullReconnectCooldown: Duration(seconds: 60),
        );
        final container = _buildContainer(api, clock, watchdogConfig: config);
        final controller = container.read(chatControllerProvider('').notifier);

        unawaited(controller.send('hi'));
        async.flushMicrotasks();
        expect(api.startStreamCalls, 1);

        // 收到带 seq 序号的 eventId（afterSeq = 5）
        api.emitId('s1:5');
        api.emit(const TokenSseEvent('token1'));
        async.flushMicrotasks();

        // 首次 18s 停滞：触发带 replayAfterSeq 的重连
        for (var i = 0; i < 18; i++) {
          clock.advance(const Duration(seconds: 1));
          async.elapse(const Duration(seconds: 1));
        }
        async.flushMicrotasks();
        expect(api.startStreamCalls, 2);
        final stopCallsAfterFirst = api.stopStreamCalls;

        // 冷却期内（18s 后）再次停滞：因为 afterSeq=5 > 0，不受 fullReconnect 冷却限制
        for (var i = 0; i < 18; i++) {
          clock.advance(const Duration(seconds: 1));
          async.elapse(const Duration(seconds: 1));
        }
        async.flushMicrotasks();

        expect(api.startStreamCalls, 3);
        expect(api.stopStreamCalls, greaterThan(stopCallsAfterFirst));
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

void _setLifecycle(ProviderContainer container, AppLifecycleState state) {
  container.read(appLifecycleStateProvider.notifier).setState(state);
}
