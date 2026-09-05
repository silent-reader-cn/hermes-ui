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
import 'package:hermes_ui/core/models/session.dart';
import 'package:hermes_ui/features/chat/chat_providers.dart';

import '../../helpers/fake_chat_api.dart';
import '../../helpers/in_memory_secure_storage.dart';

void main() {
  group('interim 快照去重防叠影', () {
    test('1. 喂 token 后喂包含该前缀的 interim 快照 → 渲染 content 无重叠，等于较长快照本身', () {
      fakeAsync((async) {
        final api = FakeChatApi();
        final clock = _FakeClock();
        final container = _buildContainer(api, clock);
        final controller = container.read(chatControllerProvider('').notifier);

        unawaited(controller.send('hi'));
        async.flushMicrotasks();

        // 喂 token「先验证锁屏检测命令可用」
        api.emit(const TokenSseEvent('先验证锁屏检测命令可用'));

        // 喂 interim 快照「先验证锁屏检测命令可用，再把看门狗脚本升级」
        api.emit(
          const InterimAssistantSseEvent(
            text: '先验证锁屏检测命令可用，再把看门狗脚本升级',
            alreadyStreamed: false,
          ),
        );

        expect(
          _streamingContent(container),
          '先验证锁屏检测命令可用，再把看门狗脚本升级',
        );
      });
    });

    test('2. 喂两个递增 interim 快照（无 token 先行）→ 最终 content == 最后一个快照，无分段叠影', () {
      fakeAsync((async) {
        final api = FakeChatApi();
        final clock = _FakeClock();
        final container = _buildContainer(api, clock);
        final controller = container.read(chatControllerProvider('').notifier);

        unawaited(controller.send('hi'));
        async.flushMicrotasks();

        // 快照 1
        api.emit(
          const InterimAssistantSseEvent(
            text: '先验证锁屏检测',
            alreadyStreamed: false,
          ),
        );

        // 快照 2（包含快照 1 的前缀递增快照）
        api.emit(
          const InterimAssistantSseEvent(
            text: '先验证锁屏检测命令可用',
            alreadyStreamed: false,
          ),
        );

        expect(
          _streamingContent(container),
          '先验证锁屏检测命令可用',
        );
      });
    });

    test('2b. 重复快照包含判定 → 吞掉重复内容，无「先」「先」式分段', () {
      fakeAsync((async) {
        final api = FakeChatApi();
        final clock = _FakeClock();
        final container = _buildContainer(api, clock);
        final controller = container.read(chatControllerProvider('').notifier);

        unawaited(controller.send('hi'));
        async.flushMicrotasks();

        // 首次快照
        api.emit(
          const InterimAssistantSseEvent(
            text: '先',
            alreadyStreamed: false,
          ),
        );

        // 重复快照
        api.emit(
          const InterimAssistantSseEvent(
            text: '先',
            alreadyStreamed: false,
          ),
        );

        expect(
          _streamingContent(container),
          '先',
        );
      });
    });

    test('3. 真·新段落回归：token 段结束后喂内容完全不相干的 interim → 仍以 \\n\\n 分段共存', () {
      fakeAsync((async) {
        final api = FakeChatApi();
        final clock = _FakeClock();
        final container = _buildContainer(api, clock);
        final controller = container.read(chatControllerProvider('').notifier);

        unawaited(controller.send('hi'));
        async.flushMicrotasks();

        api.emit(const TokenSseEvent('第一段内容'));
        api.emit(
          const InterimAssistantSseEvent(
            text: '第二段完全不相干的独立段落',
            alreadyStreamed: false,
          ),
        );

        expect(
          _streamingContent(container),
          '第一段内容\n\n第二段完全不相干的独立段落',
        );
      });
    });

    test('快照后缀空白短片段防误判 → 吞掉空白残余', () {
      fakeAsync((async) {
        final api = FakeChatApi();
        final clock = _FakeClock();
        final container = _buildContainer(api, clock);
        final controller = container.read(chatControllerProvider('').notifier);

        unawaited(controller.send('hi'));
        async.flushMicrotasks();

        api.emit(const TokenSseEvent('先验证锁屏检测'));
        // 与既有内容重叠后残余为空白
        api.emit(
          const InterimAssistantSseEvent(
            text: '先验证锁屏检测   ',
            alreadyStreamed: false,
          ),
        );

        expect(
          _streamingContent(container),
          '先验证锁屏检测',
        );
      });
    });
  });
}

// ---------------------------------------------------------------------------
// 测试辅助
// ---------------------------------------------------------------------------

String _streamingContent(ProviderContainer container) {
  final state = container.read(chatControllerProvider(''));
  final streaming = state.messages
      .where((m) => m.messageId == state.stream.streamingAssistantMessageId)
      .firstOrNull;
  return streaming?.content ?? '';
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
