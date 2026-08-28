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

/// todo #20 锁屏/后台恢复疯狂吐重复文本 + 卡死修复的受控复现测试。
///
/// 模拟方式：`appLifecycleStateProvider.notifier.setState(...)` 驱动生命周期
/// （生产链路即 NotificationLifecycleObserver 把
/// `WidgetsBinding.handleAppLifecycleStateChanged` 转发到该 provider），
/// 对应任务书要求的「handleAppLifecycleStateChanged 模拟 paused/resumed」。
void main() {
  group('① 后台/锁屏暂停 reveal 消费 + resumed 直接铺全文', () {
    test('paused 期间 token 零消费（pending 保留），resumed 一次性铺全文', () {
      fakeAsync((async) {
        final api = FakeChatApi();
        final clock = _FakeClock();
        final container = _buildContainer(api, clock);
        final controller = container.read(chatControllerProvider('').notifier);
        unawaited(controller.send('hi'));
        async.flushMicrotasks();
        final streamId = container
            .read(chatControllerProvider(''))
            .stream
            .streamingAssistantMessageId;

        // 锁屏（paused）：SSE 仍持续到达，但只入 pending 不消费。
        _setLifecycle(container, AppLifecycleState.paused);
        const first = 'Alpha Beta Gamma Delta Epsilon Zeta ';
        const backlog =
            'one two three four five six seven eight nine ten eleven twelve ';
        api.emit(const TokenSseEvent(first));
        api.emit(const TokenSseEvent(backlog));
        async.elapse(const Duration(seconds: 1));

        var state = container.read(chatControllerProvider(''));
        // pending 完整保留（未被 merge/消费）
        expect(state.pendingAssistantTokenChunks, [first, backlog]);
        expect(_streamingContent(state, streamId), '');
        // 没有 reveal 逐词吐出
        expect(api.stopStreamCalls, 0);

        // 解锁（resumed）：积压一次性铺全文，无逐词残留。
        _setLifecycle(container, AppLifecycleState.resumed);
        state = container.read(chatControllerProvider(''));
        expect(state.pendingAssistantTokenChunks, isEmpty);
        expect(_streamingContent(state, streamId), '$first$backlog');

        // 前台流式体验恢复：后续 token 继续 16ms 合并 + 48ms 逐词。
        api.emit(const TokenSseEvent('tail word '));
        async.elapse(const Duration(milliseconds: 16));
        expect(_streamingContent(state, streamId), '$first$backlog');
        async.elapse(const Duration(milliseconds: 48));
        state = container.read(chatControllerProvider(''));
        expect(
          _streamingContent(state, streamId),
          '$first$backlog${'tail word '}',
        );
      });
    });

    test('paused 前已 reveal 部分文本，resumed 补齐剩余积压（顺序不乱）', () {
      fakeAsync((async) {
        final api = FakeChatApi();
        final clock = _FakeClock();
        final container = _buildContainer(api, clock);
        final controller = container.read(chatControllerProvider('').notifier);
        unawaited(controller.send('hi'));
        async.flushMicrotasks();
        final streamId = container
            .read(chatControllerProvider(''))
            .stream
            .streamingAssistantMessageId;

        // 前台先露 5 词（48ms tick，'Zeta ' 留在队列）。
        const first = 'Alpha Beta Gamma Delta Epsilon Zeta ';
        api.emit(const TokenSseEvent(first));
        async.elapse(const Duration(milliseconds: 16));
        async.elapse(const Duration(milliseconds: 48));
        expect(
          _streamingContent(
            container.read(chatControllerProvider('')),
            streamId,
          ),
          'Alpha Beta Gamma Delta Epsilon ',
        );

        // 锁屏期间新 token 只进 pending。
        _setLifecycle(container, AppLifecycleState.paused);
        const backlog = 'one two three four five ';
        api.emit(const TokenSseEvent(backlog));
        async.elapse(const Duration(seconds: 1));
        expect(
          _streamingContent(
            container.read(chatControllerProvider('')),
            streamId,
          ),
          'Alpha Beta Gamma Delta Epsilon ',
        );

        // 解锁：queue（'Zeta '）在前、pending 在后，文本顺序与到达一致。
        _setLifecycle(container, AppLifecycleState.resumed);
        final state = container.read(chatControllerProvider(''));
        expect(_streamingContent(state, streamId), '$first$backlog');
      });
    });
  });

  group('② _revealQueue 上限保护（超限直接落全文）', () {
    test('超过 2000 词单元积压 → 一次铺全文，后续管线不破坏', () {
      fakeAsync((async) {
        final api = FakeChatApi();
        final clock = _FakeClock();
        final container = _buildContainer(api, clock);
        final controller = container.read(chatControllerProvider('').notifier);
        unawaited(controller.send('hi'));
        async.flushMicrotasks();
        final streamId = container
            .read(chatControllerProvider(''))
            .stream
            .streamingAssistantMessageId;

        // 2600 词单元（每个 'a ' 一个）> maxRevealQueueUnits(2000)。
        final big = 'a ' * 2600;
        api.emit(TokenSseEvent(big));
        async.elapse(const Duration(milliseconds: 16)); // merge 触发超限落全文
        var state = container.read(chatControllerProvider(''));
        expect(_streamingContent(state, streamId), big);

        // 空队列后不再重复 reveal。
        async.elapse(const Duration(milliseconds: 500));
        state = container.read(chatControllerProvider(''));
        expect(_streamingContent(state, streamId), big);
        expect(state.pendingAssistantTokenChunks, isEmpty);

        // 上限以下的正常增量继续逐词 reveal。
        // 注意：big 尾部自带空格，正常拼接为 `${big}b c `（b 前无额外空格，
        // 不要写成 '$big b c ' 模板字面空格，那会误判成双空格）。
        api.emit(const TokenSseEvent('b c '));
        async.elapse(const Duration(milliseconds: 16));
        async.elapse(const Duration(milliseconds: 48));
        state = container.read(chatControllerProvider(''));
        expect(_streamingContent(state, streamId), '${big}b c ');
      });
    });
  });

  group('③ watchdog 后台豁免（paused 冻结计时器不误判断线）', () {
    test('paused 期间超阈值零检测；resumed 后重新计时恢复检测', () {
      fakeAsync((async) {
        final api = FakeChatApi();
        final clock = _FakeClock();
        final container = _buildContainer(
          api,
          clock,
          watchdogConfig: const ChatWatchdogConfig(
            watchdogInterval: Duration(milliseconds: 100),
            progressStaleThreshold: Duration(milliseconds: 500),
            transportStaleThreshold: Duration(milliseconds: 500),
            forceReconnectThreshold: Duration(seconds: 2),
            forceReconnectWithRunningToolsThreshold: Duration(seconds: 2),
            statusPollCooldown: Duration(milliseconds: 200),
          ),
        );
        final controller = container.read(chatControllerProvider('').notifier);
        unawaited(controller.send('hi'));
        async.flushMicrotasks();
        expect(api.startStreamCalls, 1);

        // 锁屏 10s：冻结计时器远超全部阈值，但后台豁免 → 零检测零重连。
        _setLifecycle(container, AppLifecycleState.paused);
        clock.advance(const Duration(seconds: 10));
        async.elapse(const Duration(seconds: 10));
        expect(api.statusCalls, 0);
        expect(api.stopStreamCalls, 0);
        expect(api.startStreamCalls, 1);
        expect(api.sessionCalls, 0);
        expect(
          container.read(chatControllerProvider('')).phase,
          ChatPhase.streaming,
        );

        // 解锁：基线重新校准（从当前时刻重新计时）。
        api.statusResponse = const ChatStreamStatusResponse(active: true);
        _setLifecycle(container, AppLifecycleState.resumed);
        expect(api.statusCalls, 0); // 校准后立即不触发
        expect(api.startStreamCalls, 1);

        // 恢复前台检测：再次超过阈值后正常触发（status 检查 + 重连）。
        clock.advance(const Duration(seconds: 3));
        async.elapse(const Duration(seconds: 3));
        async.flushMicrotasks();
        expect(api.statusCalls, greaterThan(0));
        expect(api.startStreamCalls, greaterThan(1));
      });
    });
  });

  group('④ interim replay 去重游标修复（与 token 共用 matchedPrefixLength）', () {
    test('replay 游标推进后 interim 整段去重，不重复入文且游标回写', () {
      fakeAsync((async) {
        final api = FakeChatApi();
        final clock = _FakeClock();
        final container = _buildContainer(api, clock);
        final controller = container.read(chatControllerProvider('').notifier);
        unawaited(controller.send('hi'));
        async.flushMicrotasks();

        // 正常流产出内容 'AB根因C'（中文场景：单字重叠最易误判）。
        const full = 'AB根因C';
        api.emit(const TokenSseEvent(full));
        async.elapse(const Duration(milliseconds: 16));
        async.elapse(const Duration(milliseconds: 48));

        // 断线 → status active → transcript 重载 + fullReconnect（replay 态）。
        api.statusResponse = const ChatStreamStatusResponse(active: true);
        api.sessionResult = {
          'session': {
            'session_id': 'sess-new',
            'messages': [
              {'role': 'user', 'content': 'hi', 'message_id': 'u0'},
              {'role': 'assistant', 'content': full, 'message_id': 'a0'},
            ],
          },
        };
        api.fail('network down');
        async.flushMicrotasks();
        expect(api.startStreamCalls, 2); // fullReconnect
        var state = container.read(chatControllerProvider(''));
        expect(state.stream.isReplayConnection, isTrue);
        expect(state.stream.matchedPrefixLength, 0);
        final reAnchor = state.stream.streamingAssistantMessageId;
        expect(reAnchor, 'a0');
        expect(_streamingContent(state, reAnchor), full);

        // replay token 先推进游标到中间（'AB根因' 4 字已匹配）。
        api.emit(const TokenSseEvent('AB根因'));
        state = container.read(chatControllerProvider(''));
        expect(state.stream.matchedPrefixLength, 4);

        // interim 整段 = 游标处残余 'C' + 新内容 '续文'。
        // 修复前（恒 0 游标）：单字重叠被跳过 → 整段 'C续文' 重复入文
        // （content 变 'AB根因CC续文'）；修复后只追加 '续文'。
        api.emit(
          const InterimAssistantSseEvent(text: 'C续文', alreadyStreamed: false),
        );
        state = container.read(chatControllerProvider(''));
        expect(_streamingContent(state, reAnchor), 'AB根因C续文');
        // 游标回写：残余拼接后 newCursor=0，replay 状态保留。
        expect(state.stream.matchedPrefixLength, 0);
        expect(state.stream.isReplayConnection, isTrue);

        // 后续 token 继续正常增量（非重复）。
        api.emit(const TokenSseEvent(' 结尾'));
        async.elapse(const Duration(milliseconds: 16));
        async.elapse(const Duration(milliseconds: 48));
        state = container.read(chatControllerProvider(''));
        expect(_streamingContent(state, reAnchor), 'AB根因C续文 结尾');
      });
    });
  });
}

// ---------------------------------------------------------------------------
// 测试基础设施
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

/// 驱动 App 生命周期（等价 handleAppLifecycleStateChanged 的生产链路）。
void _setLifecycle(ProviderContainer container, AppLifecycleState state) {
  container.read(appLifecycleStateProvider.notifier).setState(state);
}

String _streamingContent(ChatState state, String? messageId) {
  if (messageId == null) return '';
  for (final message in state.messages) {
    if (message.messageId == messageId) {
      return message.content ?? '';
    }
  }
  return '';
}
