import 'dart:async';

import 'package:fake_async/fake_async.dart';
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

import '../../helpers/fake_chat_api.dart';
import '../../helpers/in_memory_secure_storage.dart';

void main() {
  group('重连回放防重复加固（replayAfterSeq & 内容级去重）', () {
    test('live 中已收到 token A,B (seq 1,2) → 断线重连 → 回放含 seq 1,2,3 (A,B,C) → 仅 C 生效', () {
      fakeAsync((async) {
        final api = FakeChatApi();
        api.statusResponse = const ChatStreamStatusResponse(
          active: false,
          replayAvailable: true,
        );
        final clock = _FakeClock();
        final container = _buildContainer(api, clock);
        final controller = container.read(chatControllerProvider('').notifier);

        unawaited(controller.send('hi'));
        async.flushMicrotasks();
        expect(api.startStreamCalls, 1);

        // 收到 token A (seq 1) 与 B (seq 2)
        api.emitId('s1:1');
        api.emit(const TokenSseEvent('A'));
        async.elapse(const Duration(milliseconds: 64));

        api.emitId('s1:2');
        api.emit(const TokenSseEvent('B'));
        async.elapse(const Duration(milliseconds: 64));

        var state = container.read(chatControllerProvider(''));
        final streamingId = state.stream.streamingAssistantMessageId;
        expect(_messageContent(state, streamingId), 'AB');

        // 触发传输断开 → 进入恢复重连
        api.emit(const TransportErrorSseEvent('SSE connection lost'));
        async.flushMicrotasks();

        expect(api.startStreamCalls, 2);
        state = container.read(chatControllerProvider(''));
        expect(state.stream.isReplayConnection, isTrue);
        expect(state.stream.replayAfterSeq, 2);

        // 服务端重放：回放 seq 1 (A), seq 2 (B), seq 3 (C)
        api.emitId('s1:1');
        api.emit(const TokenSseEvent('A'));
        async.elapse(const Duration(milliseconds: 64));

        api.emitId('s1:2');
        api.emit(const TokenSseEvent('B'));
        async.elapse(const Duration(milliseconds: 64));

        // 此时 A, B 被 seq 门槛或 token 去重拦截，内容依然为 AB，未发生重复推流或抖动
        state = container.read(chatControllerProvider(''));
        expect(_messageContent(state, streamingId), 'AB');

        // 发射新增 seq 3 (C)
        api.emitId('s1:3');
        api.emit(const TokenSseEvent('C'));
        async.elapse(const Duration(milliseconds: 64));

        state = container.read(chatControllerProvider(''));
        expect(_messageContent(state, streamingId), 'ABC');
      });
    });

    test('重连回放：reasoning 与 tool 事件不重复生成和冗余入段', () {
      fakeAsync((async) {
        final api = FakeChatApi();
        api.statusResponse = const ChatStreamStatusResponse(
          active: false,
          replayAvailable: true,
        );
        final clock = _FakeClock();
        final container = _buildContainer(api, clock);
        final controller = container.read(chatControllerProvider('').notifier);

        unawaited(controller.send('hi'));
        async.flushMicrotasks();

        // live 期间接收 reasoning 与工具调用
        api.emitId('s1:1');
        api.emit(const ReasoningSseEvent('Thinking...'));
        async.elapse(const Duration(milliseconds: 64));

        api.emitId('s1:2');
        api.emit(
          const ToolStartedSseEvent(
            ToolStreamEvent(stableId: 't-1', name: 'search_web'),
          ),
        );
        async.flushMicrotasks();

        api.emitId('s1:3');
        api.emit(
          const ToolCompletedSseEvent(
            ToolStreamEvent(stableId: 't-1', name: 'search_web'),
          ),
        );
        async.flushMicrotasks();

        var state = container.read(chatControllerProvider(''));
        expect(state.liveReasoningText, 'Thinking...');
        expect(state.liveToolCalls, hasLength(1));
        expect(state.liveToolCalls.first.isCompleted, isTrue);

        // 触发断开
        api.emit(const TransportErrorSseEvent('net cut'));
        async.flushMicrotasks();

        // 回放已有事件 1, 2, 3
        api.emitId('s1:1');
        api.emit(const ReasoningSseEvent('Thinking...'));
        async.elapse(const Duration(milliseconds: 64));

        api.emitId('s1:2');
        api.emit(
          const ToolStartedSseEvent(
            ToolStreamEvent(stableId: 't-1', name: 'search_web'),
          ),
        );
        async.flushMicrotasks();

        api.emitId('s1:3');
        api.emit(
          const ToolCompletedSseEvent(
            ToolStreamEvent(stableId: 't-1', name: 'search_web'),
          ),
        );
        async.flushMicrotasks();

        // 验证 tool 与 reasoning 未重复翻倍
        state = container.read(chatControllerProvider(''));
        expect(state.liveReasoningText, 'Thinking...');
        expect(state.liveToolCalls, hasLength(1));

        // 新增 seq 4 最终文本
        api.emitId('s1:4');
        api.emit(const TokenSseEvent('Found the answer.'));
        async.elapse(const Duration(milliseconds: 64));

        final streamingId = state.stream.streamingAssistantMessageId;
        state = container.read(chatControllerProvider(''));
        expect(_messageContent(state, streamingId), 'Found the answer.');
      });
    });

    test('无 seq ID 重连（纯内容级去重）：已有 token 序列平滑吃掉，仅接续新增', () {
      fakeAsync((async) {
        final api = FakeChatApi();
        api.statusResponse = const ChatStreamStatusResponse(
          active: false,
          replayAvailable: true,
        );
        final clock = _FakeClock();
        final container = _buildContainer(api, clock);
        final controller = container.read(chatControllerProvider('').notifier);

        unawaited(controller.send('hi'));
        async.flushMicrotasks();

        // 无 seq ID 的首批 token
        api.emit(const TokenSseEvent('Hello '));
        async.elapse(const Duration(milliseconds: 64));
        api.emit(const TokenSseEvent('world'));
        async.elapse(const Duration(milliseconds: 64));

        var state = container.read(chatControllerProvider(''));
        final streamingId = state.stream.streamingAssistantMessageId;
        expect(_messageContent(state, streamingId), 'Hello world');

        // 断开重连
        api.emit(const TransportErrorSseEvent('cut'));
        async.flushMicrotasks();

        // 无 seq ID 回放（触发 token 粒度去重）
        api.emit(const TokenSseEvent('Hello '));
        async.elapse(const Duration(milliseconds: 64));
        api.emit(const TokenSseEvent('world'));
        async.elapse(const Duration(milliseconds: 64));

        state = container.read(chatControllerProvider(''));
        expect(_messageContent(state, streamingId), 'Hello world');

        // 追加新增
        api.emit(const TokenSseEvent('! Today is sunny.'));
        async.elapse(const Duration(milliseconds: 64));

        state = container.read(chatControllerProvider(''));
        expect(_messageContent(state, streamingId), 'Hello world! Today is sunny.');
      });
    });

    test('工具运行期间重连：已见 ToolStarted(stableId) 不重复入 liveToolCalls，新 Started/Completed 正常接续并完成', () {
      fakeAsync((async) {
        final api = FakeChatApi();
        api.statusResponse = const ChatStreamStatusResponse(
          active: false,
          replayAvailable: true,
        );
        final clock = _FakeClock();
        final container = _buildContainer(api, clock);
        final controller = container.read(chatControllerProvider('').notifier);

        unawaited(controller.send('hi'));
        async.flushMicrotasks();

        // live 期间工具 1 开始
        api.emitId('s1:1');
        api.emit(
          const ToolStartedSseEvent(
            ToolStreamEvent(stableId: 't-1', name: 'read_file'),
          ),
        );
        async.flushMicrotasks();

        var state = container.read(chatControllerProvider(''));
        expect(state.liveToolCalls, hasLength(1));
        expect(state.liveToolCalls.first.id, 't-1');
        expect(state.liveToolCalls.first.isCompleted, isFalse);

        // 模拟断开
        api.emit(const TransportErrorSseEvent('net drop'));
        async.flushMicrotasks();

        expect(api.startStreamCalls, 2);

        // 重连回放：再次发送已见到的 ToolStarted t-1
        api.emitId('s1:1');
        api.emit(
          const ToolStartedSseEvent(
            ToolStreamEvent(stableId: 't-1', name: 'read_file'),
          ),
        );
        async.flushMicrotasks();

        // 幂等去重：liveToolCalls 依然只有 1 项，没有重复添加
        state = container.read(chatControllerProvider(''));
        expect(state.liveToolCalls, hasLength(1));
        expect(state.liveToolCalls.first.id, 't-1');

        // 发送工具 1 完成
        api.emitId('s1:2');
        api.emit(
          const ToolCompletedSseEvent(
            ToolStreamEvent(stableId: 't-1', name: 'read_file'),
          ),
        );
        async.flushMicrotasks();

        state = container.read(chatControllerProvider(''));
        expect(state.liveToolCalls, hasLength(1));
        expect(state.liveToolCalls.first.isCompleted, isTrue);

        // 发送新工具 2 开始与完成
        api.emitId('s1:3');
        api.emit(
          const ToolStartedSseEvent(
            ToolStreamEvent(stableId: 't-2', name: 'terminal'),
          ),
        );
        async.flushMicrotasks();

        api.emitId('s1:4');
        api.emit(
          const ToolCompletedSseEvent(
            ToolStreamEvent(stableId: 't-2', name: 'terminal'),
          ),
        );
        async.flushMicrotasks();

        state = container.read(chatControllerProvider(''));
        expect(state.liveToolCalls, hasLength(2));
        expect(state.liveToolCalls[0].id, 't-1');
        expect(state.liveToolCalls[0].isCompleted, isTrue);
        expect(state.liveToolCalls[1].id, 't-2');
        expect(state.liveToolCalls[1].isCompleted, isTrue);
      });
    });
  });
}

// ---------------------------------------------------------------------------
// 测试辅助
// ---------------------------------------------------------------------------

String _messageContent(ChatState state, String? messageId) {
  if (messageId == null) return '';
  for (final m in state.messages) {
    if (m.messageId == messageId) {
      return m.content ?? '';
    }
  }
  return '';
}

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
