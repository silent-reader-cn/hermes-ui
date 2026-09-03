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
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/connections/connection_store.dart';
import 'package:hermes_ui/core/models/server_catalog.dart';
import 'package:hermes_ui/core/models/session.dart';
import 'package:hermes_ui/features/chat/chat_page.dart';
import 'package:hermes_ui/features/chat/chat_providers.dart';
import 'package:hermes_ui/features/chat/chat_state.dart';

import '../../helpers/fake_chat_api.dart';
import '../../helpers/in_memory_secure_storage.dart';

class _FailingReconnectChatApi extends FakeChatApi {
  _FailingReconnectChatApi({
    this.failSubsequentStreams = false,
  });

  bool failSubsequentStreams;

  @override
  Future<void> startStream(
    String streamId, {
    int? replayAfterSeq,
    required void Function(SseEvent event) onEvent,
    void Function(String eventId)? onEventId,
    required void Function(String message) onTransportError,
    required void Function() onClosed,
  }) async {
    await super.startStream(
      streamId,
      replayAfterSeq: replayAfterSeq,
      onEvent: onEvent,
      onEventId: onEventId,
      onTransportError: onTransportError,
      onClosed: onClosed,
    );
    if (failSubsequentStreams && startStreamCalls > 1) {
      // 重连流启动即报连接断开（模拟持续离线）
      scheduleMicrotask(() {
        onTransportError('Connection refused');
      });
    }
  }
}

void main() {
  group('重连退避与重试间隔递增（指数退避 1s, 2s, 4s, 8s, 16s, 30s）', () {
    test('首次断线后退避 1s 触发重连，1s 前不发重连请求', () {
      fakeAsync((async) {
        final api = FakeChatApi();
        api.statusResponse = const ChatStreamStatusResponse(active: true);
        final clock = _FakeClock();
        final container = _buildContainer(api, clock);
        final controller = container.read(chatControllerProvider('').notifier);

        unawaited(controller.send('hi'));
        async.flushMicrotasks();
        expect(api.startStreamCalls, 1);
        expect(api.statusCalls, 0);

        // 触发传输断开
        api.emit(const TransportErrorSseEvent('connection dropped'));
        async.flushMicrotasks();

        // 500ms：退避等待中，未达 1s，不发起任何重试请求
        async.elapse(const Duration(milliseconds: 500));
        async.flushMicrotasks();
        expect(api.statusCalls, 0);
        expect(api.startStreamCalls, 1);

        // 900ms：仍未达 1s
        async.elapse(const Duration(milliseconds: 400));
        async.flushMicrotasks();
        expect(api.statusCalls, 0);
        expect(api.startStreamCalls, 1);

        // 达到 1000ms（1s）：定时器触发，发起首轮 status 检查与重连
        async.elapse(const Duration(milliseconds: 100));
        async.flushMicrotasks();
        expect(api.statusCalls, 1);
        expect(api.startStreamCalls, 2);
      });
    });

    test('连续失败时重试间隔严格递增（1s → 2s → 4s → 8s → 16s → 30s）', () {
      fakeAsync((async) {
        final api = _FailingReconnectChatApi(failSubsequentStreams: true);
        // status 探活请求持续报错（模拟服务端离线）
        api.statusError = NetworkException(NetworkExceptionKind.cannotConnect);
        final clock = _FakeClock();
        final container = _buildContainer(api, clock);
        final controller = container.read(chatControllerProvider('').notifier);

        unawaited(controller.send('hi'));
        async.flushMicrotasks();
        expect(api.startStreamCalls, 1);

        // T=0: 触发首次断线
        api.emit(const TransportErrorSseEvent('drop'));
        async.flushMicrotasks();
        expect(api.statusCalls, 0);

        // Attempt 1: 延迟 1s
        async.elapse(const Duration(milliseconds: 999));
        async.flushMicrotasks();
        expect(api.statusCalls, 0);

        async.elapse(const Duration(milliseconds: 1));
        async.flushMicrotasks();
        // 1s 时触发第 1 次重连探活（status 失败回退 forceReconnect → startStream 也失败）
        expect(api.statusCalls, 1);
        expect(api.startStreamCalls, 2);

        // Attempt 2: 延迟 2s（从 T=1s 到 T=3s）
        async.elapse(const Duration(milliseconds: 1999));
        async.flushMicrotasks();
        expect(api.statusCalls, 1);

        async.elapse(const Duration(milliseconds: 1));
        async.flushMicrotasks();
        expect(api.statusCalls, 2);
        expect(api.startStreamCalls, 3);

        // Attempt 3: 延迟 4s（从 T=3s 到 T=7s）
        async.elapse(const Duration(milliseconds: 3999));
        async.flushMicrotasks();
        expect(api.statusCalls, 2);

        async.elapse(const Duration(milliseconds: 1));
        async.flushMicrotasks();
        expect(api.statusCalls, 3);
        expect(api.startStreamCalls, 4);

        // Attempt 4: 延迟 8s（从 T=7s 到 T=15s）
        async.elapse(const Duration(milliseconds: 7999));
        async.flushMicrotasks();
        expect(api.statusCalls, 3);

        async.elapse(const Duration(milliseconds: 1));
        async.flushMicrotasks();
        expect(api.statusCalls, 4);
        expect(api.startStreamCalls, 5);

        // Attempt 5: 延迟 16s（从 T=15s 到 T=31s）
        async.elapse(const Duration(milliseconds: 15999));
        async.flushMicrotasks();
        expect(api.statusCalls, 4);

        async.elapse(const Duration(milliseconds: 1));
        async.flushMicrotasks();
        expect(api.statusCalls, 5);
        expect(api.startStreamCalls, 6);

        // Attempt 6: 延迟 30s 封顶（从 T=31s 到 T=61s）
        async.elapse(const Duration(milliseconds: 29999));
        async.flushMicrotasks();
        expect(api.statusCalls, 5);

        async.elapse(const Duration(milliseconds: 1));
        async.flushMicrotasks();
        expect(api.statusCalls, 6);
      });
    });
  });

  group('重连上限与停止自动重连（封顶 maxReconnectAttempts）', () {
    test('达上限后彻底停止自动重连，API 调用封顶且保留 recovering 状态', () {
      fakeAsync((async) {
        final api = _FailingReconnectChatApi(failSubsequentStreams: true);
        api.statusError = NetworkException(NetworkExceptionKind.cannotConnect);
        final clock = _FakeClock();
        // 自定义配置：上限 3 次，退避 [1s, 2s, 4s]
        const config = ChatWatchdogConfig(
          maxReconnectAttempts: 3,
          reconnectBackoffDelays: [
            Duration(seconds: 1),
            Duration(seconds: 2),
            Duration(seconds: 4),
          ],
        );
        final container = _buildContainer(api, clock, watchdogConfig: config);
        final controller = container.read(chatControllerProvider('').notifier);

        unawaited(controller.send('hi'));
        async.flushMicrotasks();
        expect(api.startStreamCalls, 1);

        // 触发断开
        api.emit(const TransportErrorSseEvent('drop'));
        async.flushMicrotasks();

        // Attempt 1 (1s)
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();
        expect(api.statusCalls, 1);

        // Attempt 2 (2s)
        async.elapse(const Duration(seconds: 2));
        async.flushMicrotasks();
        expect(api.statusCalls, 2);

        // Attempt 3 (4s - 达到上限 3 次)
        async.elapse(const Duration(seconds: 4));
        async.flushMicrotasks();
        expect(api.statusCalls, 3);
        final statusCallsAtCap = api.statusCalls;
        final streamCallsAtCap = api.startStreamCalls;

        // 推进较长时间（如 60s、300s）：断言不再产生任何自动重试请求
        async.elapse(const Duration(seconds: 60));
        async.flushMicrotasks();
        expect(api.statusCalls, statusCallsAtCap);
        expect(api.startStreamCalls, streamCallsAtCap);

        async.elapse(const Duration(seconds: 300));
        async.flushMicrotasks();
        expect(api.statusCalls, statusCallsAtCap);
        expect(api.startStreamCalls, streamCallsAtCap);

        // 状态保留现有 recovering 语义
        final state = container.read(chatControllerProvider(''));
        expect(state.phase, ChatPhase.recovering);
        expect(state.stream.isSuspended, isTrue);
      });
    });

    test('达到上限后，用户手动重试不受退避限制并重置计数', () {
      fakeAsync((async) {
        final api = _FailingReconnectChatApi(failSubsequentStreams: true);
        api.statusError = NetworkException(NetworkExceptionKind.cannotConnect);
        final clock = _FakeClock();
        const config = ChatWatchdogConfig(
          maxReconnectAttempts: 2,
          reconnectBackoffDelays: [
            Duration(seconds: 1),
            Duration(seconds: 2),
          ],
        );
        final container = _buildContainer(api, clock, watchdogConfig: config);
        final controller = container.read(chatControllerProvider('').notifier);

        unawaited(controller.send('hi'));
        async.flushMicrotasks();

        // 触发断开并耗尽 2 次上限
        api.emit(const TransportErrorSseEvent('drop'));
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 2));
        async.flushMicrotasks();
        expect(api.statusCalls, 2);

        // 此时已停滞
        async.elapse(const Duration(seconds: 10));
        async.flushMicrotasks();
        expect(api.statusCalls, 2);

        // 服务端恢复
        api.statusError = null;
        api.failSubsequentStreams = false;
        api.statusResponse = const ChatStreamStatusResponse(active: true);

        // 用户手动发送新消息重试
        unawaited(controller.send('retry message'));
        async.flushMicrotasks();
        expect(container.read(chatControllerProvider('')).phase, ChatPhase.steered);

        // 收到服务端 token 响应后回到 streaming 态
        api.emit(const TokenSseEvent('welcome back'));
        async.flushMicrotasks();

        final state = container.read(chatControllerProvider(''));
        expect(state.phase, ChatPhase.streaming);
      });
    });
  });

  group('成功事件重置退避（attempt 归零）', () {
    test('status 正常响应重置退避计数，后续断线再次从 1s 开始退避', () {
      fakeAsync((async) {
        final api = _FailingReconnectChatApi(failSubsequentStreams: true);
        api.statusError = NetworkException(NetworkExceptionKind.cannotConnect);
        final clock = _FakeClock();
        final container = _buildContainer(api, clock);
        final controller = container.read(chatControllerProvider('').notifier);

        unawaited(controller.send('hi'));
        async.flushMicrotasks();

        // 触发第 1 次断线 → 失败 1 次
        api.emit(const TransportErrorSseEvent('drop 1'));
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();
        expect(api.statusCalls, 1);

        // 此时退避应进入 2s 档位；若此时服务端恢复且 status 成功响应
        api.statusError = null;
        api.failSubsequentStreams = false;
        api.statusResponse = const ChatStreamStatusResponse(
          active: false,
          replayAvailable: true,
        );

        // 等待第 2 次退避（2s）触发
        async.elapse(const Duration(seconds: 2));
        async.flushMicrotasks();
        expect(api.statusCalls, 2);

        // status 成功响应后，退避计数重置为 0
        // 再次模拟断线
        api.emit(const TransportErrorSseEvent('drop 2'));
        async.flushMicrotasks();

        // 证明重置：下一轮重试在 1s 触发，而不是按之前递增到 4s
        async.elapse(const Duration(milliseconds: 999));
        async.flushMicrotasks();
        expect(api.statusCalls, 2); // 999ms 尚未触发

        async.elapse(const Duration(milliseconds: 1));
        async.flushMicrotasks();
        expect(api.statusCalls, 3); // 1000ms（1s）立即触发，证明已重置为 1s
      });
    });

    test('收到任意 SSE event / eventId 重置退避计数', () {
      fakeAsync((async) {
        final api = _FailingReconnectChatApi(failSubsequentStreams: true);
        api.statusError = NetworkException(NetworkExceptionKind.cannotConnect);
        final clock = _FakeClock();
        final container = _buildContainer(api, clock);
        final controller = container.read(chatControllerProvider('').notifier);

        unawaited(controller.send('hi'));
        async.flushMicrotasks();

        // 经历 2 次失败（1s, 2s）
        api.emit(const TransportErrorSseEvent('drop'));
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 2));
        async.flushMicrotasks();
        expect(api.statusCalls, 2);

        // 服务端恢复，status 成功
        api.statusError = null;
        api.failSubsequentStreams = false;
        api.statusResponse = const ChatStreamStatusResponse(
          active: false,
          replayAvailable: true,
        );
        async.elapse(const Duration(seconds: 4));
        async.flushMicrotasks();
        expect(api.statusCalls, 3);

        // 收到新 token 事件
        api.emitId('s1:10');
        api.emit(const TokenSseEvent('chunk'));
        async.flushMicrotasks();

        // 再次断线
        api.emit(const TransportErrorSseEvent('drop again'));
        async.flushMicrotasks();

        // 验证从 1s 开始退避（非 8s）
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();
        expect(api.statusCalls, 4);
      });
    });
  });

  group('生命周期与定时器安全（防止 Timer 泄漏）', () {
    testWidgets('退避等待期间 Widget 卸载（dispose）取消挂起定时器，无 pending timer', (tester) async {
      final api = FakeChatApi()..statusResponse = const ChatStreamStatusResponse(active: true);
      api.sessionResult = {
        'session': {
          'session_id': 's-backoff-dispose',
          'active_stream_id': 'stream-1',
          'messages': [
            {'role': 'user', 'content': 'hi', 'message_id': 'u1'},
          ],
          'message_count': 1,
        },
      };

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            chatApiProvider.overrideWithValue(api),
          ],
          child: const CupertinoApp(
            home: ChatPage(sessionId: 's-backoff-dispose'),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // 触发断开错误 → 挂起 1s 退避定时器
      api.emit(const TransportErrorSseEvent('network error'));
      await tester.pump();

      // 在退避等待期间（未满 1s 时）卸载页面
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      // 验证页面安全卸载，无未决定时器导致测试框架抛出 pending timer 异常
      expect(tester.takeException(), isNull);
    });

    test('退避等待期间发送新消息立即取消挂起定时器', () {
      fakeAsync((async) {
        final api = FakeChatApi();
        api.statusResponse = const ChatStreamStatusResponse(active: true);
        final clock = _FakeClock();
        final container = _buildContainer(api, clock);
        final controller = container.read(chatControllerProvider('').notifier);

        unawaited(controller.send('hi'));
        async.flushMicrotasks();

        // 触发断开错误 → 挂起 1s 退避定时器
        api.emit(const TransportErrorSseEvent('dropped'));
        async.flushMicrotasks();

        // 500ms 时发送新消息（尚未触发 1s 定时器）
        async.elapse(const Duration(milliseconds: 500));
        unawaited(controller.send('new question'));
        async.flushMicrotasks();

        // 推进到 1500ms（原 1s 定时器时刻已过）
        async.elapse(const Duration(milliseconds: 1000));
        async.flushMicrotasks();

        // 原挂起重连的 statusCalls 不会被触发
        expect(api.statusCalls, 0);
      });
    });
  });

  group('调用点约束与看门狗交互', () {
    test('退避定时器挂起期间，看门狗探活与 forceReconnect 被抑制', () {
      fakeAsync((async) {
        final api = FakeChatApi();
        api.statusResponse = const ChatStreamStatusResponse(active: true);
        final clock = _FakeClock();
        // 设置看门狗 1s 检查、12s 探活、18s 强制重连
        final container = _buildContainer(api, clock);
        final controller = container.read(chatControllerProvider('').notifier);

        unawaited(controller.send('hi'));
        async.flushMicrotasks();
        expect(api.startStreamCalls, 1);

        // 触发断线
        api.emit(const TransportErrorSseEvent('dropped'));
        async.flushMicrotasks();

        // 退避等待中，前推时钟 20s 模拟传输严重停滞
        clock.advance(const Duration(seconds: 20));

        // 推进 500ms（仍在 1s 退避内）
        async.elapse(const Duration(milliseconds: 500));
        async.flushMicrotasks();

        // 期间看门狗探活被抑制，不产生并发重试风暴
        expect(api.statusCalls, 0);
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
