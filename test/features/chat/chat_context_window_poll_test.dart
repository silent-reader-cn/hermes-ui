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
import 'package:hermes_ui/features/chat/chat_state.dart';
import 'package:hermes_ui/features/notifications/notification_providers.dart';

import '../../helpers/fake_chat_api.dart';
import '../../helpers/in_memory_secure_storage.dart';

void main() {
  group('#37 live 流式上下文指示器实时轮询', () {
    test('live 期间每 2s 轮询一次会话详情，snapshot 读数单调更新', () {
      fakeAsync((async) {
        final api = FakeChatApi();
        api.startChatResult = {'stream_id': 'stream-1', 'session_id': 'sess-1'};
        final clock = _FakeClock();
        final container = _buildContainer(api, clock);
        final controller =
            container.read(chatControllerProvider('sess-1').notifier);
        async.flushMicrotasks(); // 排空 build 期间的 loadMessages
        api.sessionCalls = 0;

        // 初始空闲状态：tokensUsed 为 null，sessionCalls 为 0
        expect(api.sessionCalls, 0);
        expect(controller.state.contextWindowSnapshot?.tokensUsed, isNull);

        // 发送消息，进入流式
        unawaited(controller.send('hello'));
        async.flushMicrotasks();
        expect(controller.state.phase, ChatPhase.streaming);
        expect(api.startStreamCalls, 1);
        expect(api.sessionCalls, 0);

        // 1s 过去：未到 2s 间隔，不轮询
        clock.advance(const Duration(seconds: 1));
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();
        expect(api.sessionCalls, 0);

        // 设置服务端第 1 次轮询响应数据
        api.sessionResponse = const SessionResponse(
          session: SessionDetail(
            sessionId: 'sess-1',
            contextLength: 200000,
            thresholdTokens: 160000,
            lastPromptTokens: 1200,
            inputTokens: 1200,
            outputTokens: 50,
            estimatedCost: 0.005,
          ),
        );

        // 达到 2s：触发第 1 次轮询
        clock.advance(const Duration(seconds: 1));
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();
        expect(api.sessionCalls, 1);

        final snap1 = controller.state.contextWindowSnapshot;
        expect(snap1, isNotNull);
        expect(snap1!.contextLength, 200000);
        expect(snap1.tokensUsed, 1200);
        expect(snap1.percentage, closeTo(1200 / 200000, 0.0001));

        // 设置服务端第 2 次轮询响应数据（token 增长）
        api.sessionResponse = const SessionResponse(
          session: SessionDetail(
            sessionId: 'sess-1',
            contextLength: 200000,
            thresholdTokens: 160000,
            lastPromptTokens: 2500,
            inputTokens: 2500,
            outputTokens: 180,
            estimatedCost: 0.012,
          ),
        );

        // 再过 2s（累计 4s）：触发第 2 次轮询，读数单调递增
        clock.advance(const Duration(seconds: 2));
        async.elapse(const Duration(seconds: 2));
        async.flushMicrotasks();
        expect(api.sessionCalls, 2);

        final snap2 = controller.state.contextWindowSnapshot;
        expect(snap2, isNotNull);
        expect(snap2!.tokensUsed, 2500);
        expect(snap2.percentage, closeTo(2500 / 200000, 0.0001));
        expect(snap2.tokensUsed!, greaterThan(snap1.tokensUsed!));
      });
    });

    test('非流式（空闲）状态零请求', () {
      fakeAsync((async) {
        final api = FakeChatApi();
        final clock = _FakeClock();
        final container = _buildContainer(api, clock);
        final controller =
            container.read(chatControllerProvider('sess-idle').notifier);
        async.flushMicrotasks();
        api.sessionCalls = 0;

        expect(controller.state.phase, ChatPhase.idle);
        expect(api.sessionCalls, 0);

        // 空闲状态流逝 30s，不应发出任何轮询请求
        clock.advance(const Duration(seconds: 30));
        async.elapse(const Duration(seconds: 30));
        async.flushMicrotasks();
        expect(api.sessionCalls, 0);
      });
    });

    test('done 结束后轮询立即停止，读数收敛且无残留请求', () {
      fakeAsync((async) {
        final api = FakeChatApi();
        api.startChatResult = {'stream_id': 'stream-1', 'session_id': 'sess-1'};
        final clock = _FakeClock();
        final container = _buildContainer(api, clock);
        final controller =
            container.read(chatControllerProvider('sess-1').notifier);
        async.flushMicrotasks();
        api.sessionCalls = 0;

        unawaited(controller.send('hello'));
        async.flushMicrotasks();

        api.sessionResponse = const SessionResponse(
          session: SessionDetail(
            sessionId: 'sess-1',
            contextLength: 100000,
            lastPromptTokens: 1500,
            inputTokens: 1500,
          ),
        );

        // 2s：触发轮询
        clock.advance(const Duration(seconds: 2));
        async.elapse(const Duration(seconds: 2));
        async.flushMicrotasks();
        expect(api.sessionCalls, 1);
        expect(controller.state.contextWindowSnapshot?.tokensUsed, 1500);

        // 收到 done 事件（带完整 session transcript，终值 3200 tokens）
        api.emit(
          const DoneSseEvent(
            DoneStreamEvent(
              session: {
                'session_id': 'sess-1',
                'context_length': 100000,
                'last_prompt_tokens': 3200,
                'input_tokens': 3200,
                'output_tokens': 400,
                'messages': [
                  {'role': 'user', 'content': 'hello'},
                  {'role': 'assistant', 'content': 'hi'},
                ],
              },
            ),
          ),
        );
        api.emit(const StreamEndSseEvent());
        async.flushMicrotasks();

        // 终值一致
        expect(controller.state.phase, ChatPhase.idle);
        expect(controller.state.contextWindowSnapshot?.tokensUsed, 3200);
        final callsAtDone = api.sessionCalls;

        // done 之后时间推进 20s，不再触发任何轮询
        clock.advance(const Duration(seconds: 20));
        async.elapse(const Duration(seconds: 20));
        async.flushMicrotasks();
        expect(api.sessionCalls, callsAtDone);
      });
    });

    test('慢响应安全：在途轮询在 done 之后到达被安全丢弃，不覆盖终值', () {
      fakeAsync((async) {
        final api = FakeChatApi();
        api.startChatResult = {'stream_id': 'stream-1', 'session_id': 'sess-1'};
        final clock = _FakeClock();
        final container = _buildContainer(api, clock);
        final controller =
            container.read(chatControllerProvider('sess-1').notifier);
        async.flushMicrotasks();
        api.sessionCalls = 0;

        unawaited(controller.send('hello'));
        async.flushMicrotasks();

        api.sessionResponse = const SessionResponse(
          session: SessionDetail(
            sessionId: 'sess-1',
            contextLength: 100000,
            lastPromptTokens: 1200,
            inputTokens: 1200,
          ),
        );

        // 触发第 1 次轮询
        clock.advance(const Duration(seconds: 2));
        async.elapse(const Duration(seconds: 2));
        async.flushMicrotasks();
        expect(controller.state.contextWindowSnapshot?.tokensUsed, 1200);

        // 收到 done 事件（终值 5000 tokens）
        api.emit(
          const DoneSseEvent(
            DoneStreamEvent(
              session: {
                'session_id': 'sess-1',
                'context_length': 100000,
                'last_prompt_tokens': 5000,
                'input_tokens': 5000,
                'messages': [
                  {'role': 'user', 'content': 'hello'},
                  {'role': 'assistant', 'content': 'hi'},
                ],
              },
            ),
          ),
        );
        api.emit(const StreamEndSseEvent());
        async.flushMicrotasks();

        expect(controller.state.contextWindowSnapshot?.tokensUsed, 5000);

        // 后续推进时间
        clock.advance(const Duration(seconds: 5));
        async.elapse(const Duration(seconds: 5));
        async.flushMicrotasks();

        // 终值 5000 未被覆盖
        expect(controller.state.contextWindowSnapshot?.tokensUsed, 5000);
      });
    });

    test('轮询网络异常静默容错，不打断流式且不弹错', () {
      fakeAsync((async) {
        final api = FakeChatApi();
        api.startChatResult = {'stream_id': 'stream-1', 'session_id': 'sess-1'};
        final clock = _FakeClock();
        final container = _buildContainer(api, clock);
        final controller =
            container.read(chatControllerProvider('sess-1').notifier);
        async.flushMicrotasks();
        api.sessionCalls = 0;

        api.sessionError = HttpException(500, null, message: 'Server error');

        unawaited(controller.send('hello'));
        async.flushMicrotasks();
        expect(controller.state.phase, ChatPhase.streaming);

        // 2s 轮询抛错
        clock.advance(const Duration(seconds: 2));
        async.elapse(const Duration(seconds: 2));
        async.flushMicrotasks();

        expect(api.sessionCalls, 1);
        // 流式状态继续，无全局错误
        expect(controller.state.phase, ChatPhase.streaming);
        expect(controller.state.errorMessage, isNull);
        expect(controller.state.sendErrorMessage, isNull);
      });
    });

    test('轮询更新 snapshot 时保留既有 liveTokensPerSecond (tps)', () {
      fakeAsync((async) {
        final api = FakeChatApi();
        api.startChatResult = {'stream_id': 'stream-1', 'session_id': 'sess-1'};
        final clock = _FakeClock();
        final container = _buildContainer(api, clock);
        final controller =
            container.read(chatControllerProvider('sess-1').notifier);
        async.flushMicrotasks();
        api.sessionCalls = 0;

        unawaited(controller.send('hello'));
        async.flushMicrotasks();

        // 收到 metering 事件，带 tps = 52.5
        api.emit(
          const MeteringSseEvent(
            tps: 52.5,
            tpsAvailable: true,
            estimated: false,
            sessionId: 'sess-1',
          ),
        );
        async.flushMicrotasks();
        expect(controller.state.stream.liveTokensPerSecond, 52.5);
        expect(
          controller.state.contextWindowSnapshot?.tokensPerSecond,
          52.5,
        );

        // 轮询返回新的 tokens 读数
        api.sessionResponse = const SessionResponse(
          session: SessionDetail(
            sessionId: 'sess-1',
            contextLength: 200000,
            lastPromptTokens: 2000,
            inputTokens: 2000,
          ),
        );

        clock.advance(const Duration(seconds: 2));
        async.elapse(const Duration(seconds: 2));
        async.flushMicrotasks();

        final snapshot = controller.state.contextWindowSnapshot;
        expect(snapshot, isNotNull);
        expect(snapshot!.tokensUsed, 2000);
        // tps 被完整保留
        expect(snapshot.tokensPerSecond, 52.5);
      });
    });

    test('App paused（后台/锁屏）期间暂停轮询，resumed 后恢复', () {
      fakeAsync((async) {
        final api = FakeChatApi();
        api.startChatResult = {'stream_id': 'stream-1', 'session_id': 'sess-1'};
        api.statusResponse = const ChatStreamStatusResponse(active: true);
        api.sessionResponse = const SessionResponse(
          session: SessionDetail(
            sessionId: 'sess-1',
            contextLength: 200000,
            inputTokens: 1000,
          ),
        );
        final clock = _FakeClock();
        final container = _buildContainer(api, clock);
        final controller =
            container.read(chatControllerProvider('sess-1').notifier);
        async.flushMicrotasks();
        api.sessionCalls = 0;

        unawaited(controller.send('hello'));
        async.flushMicrotasks();

        // 2s 正常轮询 1 次
        clock.advance(const Duration(seconds: 2));
        async.elapse(const Duration(seconds: 2));
        async.flushMicrotasks();
        expect(api.sessionCalls, 1);

        // 切到后台
        _setLifecycle(container, AppLifecycleState.paused);
        clock.advance(const Duration(seconds: 10));
        async.elapse(const Duration(seconds: 10));
        async.flushMicrotasks();
        // 后台期间无新增轮询
        expect(api.sessionCalls, 1);

        // 切回前台：resumed probe 补拉 transcript (calls = 2)
        _setLifecycle(container, AppLifecycleState.resumed);
        async.flushMicrotasks();
        expect(api.sessionCalls, 2);

        // 前台继续流式推进 2s：再次触发 live 轮询 (calls = 3)
        clock.advance(const Duration(seconds: 2));
        async.elapse(const Duration(seconds: 2));
        async.flushMicrotasks();
        expect(api.sessionCalls, 3);
      });
    });

    test('dispose 干净清理，FakeAsync 下无未决 Timer', () {
      fakeAsync((async) {
        final api = FakeChatApi();
        api.startChatResult = {'stream_id': 'stream-1', 'session_id': 'sess-1'};
        final clock = _FakeClock();
        final container = _buildContainer(api, clock);
        final controller =
            container.read(chatControllerProvider('sess-1').notifier);
        async.flushMicrotasks();
        api.sessionCalls = 0;

        unawaited(controller.send('hello'));
        async.flushMicrotasks();

        // 销毁 container
        container.dispose();
        async.flushMicrotasks();
        // fakeAsync 作用域自然结束，不抛 "A Timer is still pending"
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
