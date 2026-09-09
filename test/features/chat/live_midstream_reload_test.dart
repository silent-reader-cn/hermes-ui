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

import '../../helpers/fake_chat_api.dart';
import '../../helpers/in_memory_secure_storage.dart';

void main() {
  group('live 中段 transcript 重载不得吞工具卡', () {
    test('loadMessages 带 tool_calls 时活跃流保留 liveToolCalls 与时间线工具行', () {
      fakeAsync((async) {
        final api = FakeChatApi();
        api.statusResponse = const ChatStreamStatusResponse(
          active: false,
          replayAvailable: true,
        );
        final clock = _FakeClock();
        final container = _buildContainer(api, clock);
        final controller = container.read(
          chatControllerProvider('').notifier,
        );

        unawaited(controller.send('hi'));
        async.flushMicrotasks();
        expect(api.startStreamCalls, 1);

        // live：先 think，再工具调用（复现主人截图：连续 think + 工具混排）。
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

        var state = container.read(chatControllerProvider(''));
        expect(state.liveReasoningText, 'Thinking...');
        expect(state.liveToolCalls, hasLength(1));
        expect(
          state.liveTimelinePoints.any((p) => p.kind.name == 'tools'),
          isTrue,
          reason: '工具断点应在重载前存在',
        );
        final streamingId = state.stream.streamingAssistantMessageId;
        expect(streamingId, isNotNull);
        expect(state.stream.activeStreamId, isNotNull);

        // 看门狗/恢复路径的中段重载：服务端已落库一个工具（与 live 的不是同一个），
        // 触发 _applySessionDetail 的 hasServerTools 分支。
        api.sessionResult = {
          'session': {
            'session_id': state.sessionId.isEmpty ? 'sess-new' : state.sessionId,
            'messages': [
              {'role': 'user', 'content': 'hi', 'message_id': 'u1'},
            ],
            'message_count': 1,
            'tool_calls': [
              {'name': 'server-tool', 'tid': 'srv-1'},
            ],
          },
        };
        unawaited(controller.loadMessages());
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 100));

        state = container.read(chatControllerProvider(''));
        // 流仍活跃：streaming 锚点必须还在（否则时间线直接回退 legacy）。
        expect(
          state.stream.streamingAssistantMessageId,
          streamingId,
          reason: '中段重载不得重锚/丢弃流式消息',
        );
        // 核心断言：live 工具调用不得被清空，否则时间线 tools 段切片
        // clamp 到空数组 → 聚合卡只剩 think 行（主人报的 bug）。
        expect(
          state.liveToolCalls.any((t) => t.id == 't-1'),
          isTrue,
          reason: '活跃流期间 liveToolCalls 必须保留，中段重载不得清空',
        );

        final timeline = container.read(liveTimelineProvider(''));
        expect(timeline, isNotNull);
        final toolEntries = timeline!.where((e) => e.toolGroup != null);
        expect(toolEntries, isNotEmpty, reason: '时间线应仍有工具卡条目');
        final hasLiveTool = toolEntries.any(
          (e) => e.toolGroup!.toolCalls.any((c) => c.id == 't-1'),
        );
        expect(
          hasLiveTool,
          isTrue,
          reason: '时间线工具卡应仍含 live 的 search_web 行（不只剩 think）',
        );
      });
    });
  });
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

ProviderContainer _buildContainer(FakeChatApi api, _FakeClock clock) {
  TestWidgetsFlutterBinding.ensureInitialized();
  final db = AppDatabase.memory();
  final cache = _NoopCacheService(db);
  final container = ProviderContainer(
    overrides: [
      chatApiProvider.overrideWithValue(api),
      chatClockProvider.overrideWithValue(clock.call),
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
