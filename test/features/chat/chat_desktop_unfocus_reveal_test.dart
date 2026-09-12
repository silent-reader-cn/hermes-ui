import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart' show
    TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/api/sse_client.dart';
import 'package:hermes_ui/core/cache/app_database.dart';
import 'package:hermes_ui/core/cache/cache_providers.dart';
import 'package:hermes_ui/core/cache/cache_service.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/connections/connection_store.dart';
import 'package:hermes_ui/core/models/session.dart';
import 'package:hermes_ui/features/chat/chat_controller.dart';
import 'package:hermes_ui/features/chat/chat_providers.dart';
import 'package:hermes_ui/features/chat/chat_state.dart';
import 'package:hermes_ui/features/notifications/notification_providers.dart';

import '../../helpers/fake_chat_api.dart';
import '../../helpers/in_memory_secure_storage.dart';

/// 桌面端「失焦（inactive）不再冻结打字机」回归测试。
///
/// 背景：Windows/macOS/Linux 的 Flutter 引擎把「窗口失焦」上报为
/// `inactive`（仅最小化/隐藏才 `hidden`，见 windows_lifecycle_manager
/// UpdateState）。旧实现 `next != resumed` 即冻结 reveal 消费，导致桌面
/// unfocus 时 live 文本停摆、回焦整段爆铺（并诱发 resume 探活重放叠影）。
/// 修复后：桌面仅 hidden/detached 暂停，inactive 照常逐词流式；移动端语义
/// （非 resumed 即暂停）保持不变。
void main() {
  group('桌面端 unfocus（inactive）不冻结 reveal', () {
    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
    });

    test('Windows inactive 期间 token 持续逐词消费（无积压、不爆铺）', () {
      fakeAsync((async) {
        debugDefaultTargetPlatformOverride = TargetPlatform.windows;
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

        // 失焦（引擎上报 inactive，窗口仍完整可见）。
        _setLifecycle(container, AppLifecycleState.inactive);

        api.emit(const TokenSseEvent('Alpha Beta Gamma Delta '));
        async.elapse(ChatController.mergeDelay);
        async.elapse(const Duration(milliseconds: 300));

        var state = container.read(chatControllerProvider(''));
        // inactive 不冻结：内容持续增量消费，pending/reveal 队列无积压。
        expect(_streamingContent(state, streamId), isNotEmpty);
        expect(state.pendingAssistantTokenChunks, isEmpty);
        expect(state.isRevealQueueEmpty, isTrue);

        // 回焦后也不应有「整段爆铺」：继续逐词增量，内容单调增长。
        _setLifecycle(container, AppLifecycleState.resumed);
        api.emit(const TokenSseEvent('Epsilon Zeta '));
        async.elapse(ChatController.mergeDelay);
        async.elapse(const Duration(milliseconds: 300));
        state = container.read(chatControllerProvider(''));
        expect(
          _streamingContent(state, streamId),
          'Alpha Beta Gamma Delta Epsilon Zeta ',
        );
      });
    });

    test('Windows 最小化（hidden）仍冻结，恢复可见后铺全文', () {
      fakeAsync((async) {
        debugDefaultTargetPlatformOverride = TargetPlatform.windows;
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

        _setLifecycle(container, AppLifecycleState.hidden);
        api.emit(const TokenSseEvent('Hidden backlog text '));
        async.elapse(const Duration(seconds: 1));

        var state = container.read(chatControllerProvider(''));
        // 真不可见（最小化/隐藏到托盘）：冻结省电，积压保留。
        expect(_streamingContent(state, streamId), isEmpty);
        expect(state.pendingAssistantTokenChunks, isNotEmpty);

        // 任务栏点回 = 窗口重新可见（即使键盘焦点未回，引擎上报
        // inactive）：按方案 A 语义此刻即解除冻结铺全文，用户立刻看到
        // 最新内容，不必等焦点。
        _setLifecycle(container, AppLifecycleState.inactive);
        async.elapse(const Duration(milliseconds: 100));
        state = container.read(chatControllerProvider(''));
        expect(_streamingContent(state, streamId), 'Hidden backlog text ');

        // 继续失焦流式（inactive 态下新 token 逐词消费，不再冻结）。
        api.emit(const TokenSseEvent('More text '));
        async.elapse(ChatController.mergeDelay);
        async.elapse(const Duration(milliseconds: 300));
        state = container.read(chatControllerProvider(''));
        expect(
          _streamingContent(state, streamId),
          'Hidden backlog text More text ',
        );
      });
    });

    test('移动端 inactive 仍冻结（锁屏/通知栏语义不变）', () {
      fakeAsync((async) {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
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

        _setLifecycle(container, AppLifecycleState.inactive);
        api.emit(const TokenSseEvent('Mobile frozen text '));
        async.elapse(const Duration(seconds: 1));

        var state = container.read(chatControllerProvider(''));
        expect(_streamingContent(state, streamId), isEmpty);
        expect(state.pendingAssistantTokenChunks, isNotEmpty);

        _setLifecycle(container, AppLifecycleState.resumed);
        async.elapse(const Duration(milliseconds: 100));
        state = container.read(chatControllerProvider(''));
        expect(_streamingContent(state, streamId), 'Mobile frozen text ');
      });
    });
  });
}

// ---------------------------------------------------------------------------
// 测试基础设施（对齐 chat_lockscreen_reveal_test.dart）
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
