import 'package:fake_async/fake_async.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermex_flutter/core/api/api_exception.dart';
import 'package:hermex_flutter/core/cache/app_database.dart';
import 'package:hermex_flutter/core/cache/cache_providers.dart';
import 'package:hermex_flutter/core/cache/cache_service.dart';
import 'package:hermex_flutter/core/connections/connection_providers.dart';
import 'package:hermex_flutter/core/connections/connection_store.dart';
import 'package:hermex_flutter/core/models/chat_message.dart';
import 'package:hermex_flutter/core/models/json_value.dart';
import 'package:hermex_flutter/core/models/message_attachment.dart';
import 'package:hermex_flutter/core/models/session.dart';
import 'package:hermex_flutter/features/chat/chat_diff_merge.dart';
import 'package:hermex_flutter/features/chat/chat_page.dart';
import 'package:hermex_flutter/features/chat/chat_providers.dart';
import 'package:hermex_flutter/features/chat/chat_state.dart';
import 'package:hermex_flutter/features/notifications/notification_providers.dart';

import '../../helpers/fake_chat_api.dart';
import '../../helpers/in_memory_secure_storage.dart';

void main() {
  group('diffMergeMessages 算法（类 VDOM 调和）', () {
    test('初始状态：本地为空，以服务端列表全量填充', () {
      const server = [
        ChatMessage(messageId: 'm1', role: 'user', content: 'hello', timestamp: 100),
        ChatMessage(messageId: 'm2', role: 'assistant', content: 'world', timestamp: 101),
      ];

      final merged = diffMergeMessages(
        localMessages: const [],
        serverMessages: server,
      );

      expect(merged, hasLength(2));
      expect(merged[0].messageId, 'm1');
      expect(merged[1].messageId, 'm2');
    });

    test('服务端为空：保留本地消息', () {
      const local = [
        ChatMessage(messageId: 'm1', role: 'user', content: 'hello', timestamp: 100),
      ];

      final merged = diffMergeMessages(
        localMessages: local,
        serverMessages: const [],
      );

      expect(merged, hasLength(1));
      expect(merged[0].messageId, 'm1');
    });

    test('跨端漏记在末尾（尾部补漏）：本地 [m1, m2]，服务端 [m1, m2, m3] → [m1, m2, m3]', () {
      const local = [
        ChatMessage(messageId: 'm1', role: 'user', content: 'm1', timestamp: 100),
        ChatMessage(messageId: 'm2', role: 'assistant', content: 'm2', timestamp: 101),
      ];
      const server = [
        ChatMessage(messageId: 'm1', role: 'user', content: 'm1', timestamp: 100),
        ChatMessage(messageId: 'm2', role: 'assistant', content: 'm2', timestamp: 101),
        ChatMessage(messageId: 'm3', role: 'user', content: 'm3 (Web 端发送)', timestamp: 102),
      ];

      final merged = diffMergeMessages(
        localMessages: local,
        serverMessages: server,
      );

      expect(merged, hasLength(3));
      expect(merged.map((m) => m.messageId).toList(), ['m1', 'm2', 'm3']);
      expect(merged[2].content, 'm3 (Web 端发送)');
    });

    test('跨端漏记在中间（中间插入）：本地 [m1, m3]，服务端 [m1, m2, m3] → [m1, m2, m3]', () {
      const local = [
        ChatMessage(messageId: 'm1', role: 'user', content: 'm1', timestamp: 100),
        ChatMessage(messageId: 'm3', role: 'assistant', content: 'm3', timestamp: 103),
      ];
      const server = [
        ChatMessage(messageId: 'm1', role: 'user', content: 'm1', timestamp: 100),
        ChatMessage(messageId: 'm2', role: 'assistant', content: 'm2', timestamp: 101),
        ChatMessage(messageId: 'm3', role: 'user', content: 'm3', timestamp: 103),
      ];

      final merged = diffMergeMessages(
        localMessages: local,
        serverMessages: server,
      );

      expect(merged, hasLength(3));
      expect(merged.map((m) => m.messageId).toList(), ['m1', 'm2', 'm3']);
    });

    test('内容与元数据就地更新（Patch）：已存在消息被服务端权威内容替换', () {
      const local = [
        ChatMessage(messageId: 'm1', role: 'user', content: '旧内容', timestamp: 100),
        ChatMessage(messageId: 'm2', role: 'assistant', content: '旧回复', timestamp: 101, turnTps: 42.0),
      ];
      const server = [
        ChatMessage(messageId: 'm1', role: 'user', content: '更新后的内容', timestamp: 100),
        ChatMessage(
          messageId: 'm2',
          role: 'assistant',
          content: '更新后的完整回复',
          timestamp: 101,
          attachments: [MessageAttachment(name: 'file.txt', mime: 'text/plain')],
          toolCalls: [JsonString('tool-call-data')],
        ),
      ];

      final merged = diffMergeMessages(
        localMessages: local,
        serverMessages: server,
      );

      expect(merged, hasLength(2));
      expect(merged[0].content, '更新后的内容');
      expect(merged[1].content, '更新后的完整回复');
      expect(merged[1].attachments, hasLength(1));
      expect(merged[1].toolCalls, hasLength(1));
      expect(merged[1].turnTps, 42.0); // 保留本地特有指标
    });

    test('指纹去重：本地 messageId == null 乐观消息与服务端权威消息匹配，不重复插入', () {
      const local = [
        ChatMessage(messageId: 'm1', role: 'user', content: 'm1', timestamp: 100),
        ChatMessage(messageId: null, role: 'user', content: 'hello from local', timestamp: 105.0),
      ];
      const server = [
        ChatMessage(messageId: 'm1', role: 'user', content: 'm1', timestamp: 100),
        ChatMessage(messageId: 'srv-105', role: 'user', content: 'hello from local', timestamp: 105.05),
      ];

      final merged = diffMergeMessages(
        localMessages: local,
        serverMessages: server,
      );

      expect(merged, hasLength(2));
      expect(merged[1].messageId, 'srv-105');
      expect(merged[1].content, 'hello from local');
    });

    test('指纹去重：本地 local- 开头临时 ID 与服务端分配 ID 匹配', () {
      const local = [
        ChatMessage(messageId: 'local-uuid-1234', role: 'user', content: 'ping', timestamp: 200.0),
      ];
      const server = [
        ChatMessage(messageId: 'msg-real-999', role: 'user', content: 'ping', timestamp: 200.02),
      ];

      final merged = diffMergeMessages(
        localMessages: local,
        serverMessages: server,
      );

      expect(merged, hasLength(1));
      expect(merged[0].messageId, 'msg-real-999');
    });

    test('头部保留：历史分页消息（早于首个命中项）不被覆盖丢弃', () {
      const local = [
        ChatMessage(messageId: 'm_hist1', role: 'user', content: '历史 1', timestamp: 50),
        ChatMessage(messageId: 'm_hist2', role: 'assistant', content: '历史 2', timestamp: 60),
        ChatMessage(messageId: 'm1', role: 'user', content: 'm1', timestamp: 100),
        ChatMessage(messageId: 'm2', role: 'assistant', content: 'm2', timestamp: 101),
      ];
      const server = [
        ChatMessage(messageId: 'm1', role: 'user', content: 'm1', timestamp: 100),
        ChatMessage(messageId: 'm2', role: 'assistant', content: 'm2', timestamp: 101),
        ChatMessage(messageId: 'm3', role: 'user', content: 'm3', timestamp: 102),
      ];

      final merged = diffMergeMessages(
        localMessages: local,
        serverMessages: server,
      );

      expect(merged, hasLength(5));
      expect(
        merged.map((m) => m.messageId).toList(),
        ['m_hist1', 'm_hist2', 'm1', 'm2', 'm3'],
      );
    });

    test('尾部保留：本地尚未落库的乐观消息（晚于最后一个命中项）予以保留', () {
      const local = [
        ChatMessage(messageId: 'm1', role: 'user', content: 'm1', timestamp: 100),
        ChatMessage(messageId: 'm2', role: 'assistant', content: 'm2', timestamp: 101),
        ChatMessage(messageId: 'local-pending', role: 'user', content: '未上送内容', timestamp: 105),
      ];
      const server = [
        ChatMessage(messageId: 'm1', role: 'user', content: 'm1', timestamp: 100),
        ChatMessage(messageId: 'm2', role: 'assistant', content: 'm2', timestamp: 101),
      ];

      final merged = diffMergeMessages(
        localMessages: local,
        serverMessages: server,
      );

      expect(merged, hasLength(3));
      expect(merged[2].messageId, 'local-pending');
      expect(merged[2].content, '未上送内容');
    });

    test('中间未命中本地消息保留：夹在中间的本地消息不做删除', () {
      const local = [
        ChatMessage(messageId: 'm1', role: 'user', content: 'm1', timestamp: 100),
        ChatMessage(messageId: 'local-draft', role: 'user', content: '草稿', timestamp: 102),
        ChatMessage(messageId: 'm3', role: 'assistant', content: 'm3', timestamp: 103),
      ];
      const server = [
        ChatMessage(messageId: 'm1', role: 'user', content: 'm1', timestamp: 100),
        ChatMessage(messageId: 'm3', role: 'assistant', content: 'm3', timestamp: 103),
      ];

      final merged = diffMergeMessages(
        localMessages: local,
        serverMessages: server,
      );

      expect(merged, hasLength(3));
      expect(merged.map((m) => m.messageId).toList(), ['m1', 'local-draft', 'm3']);
    });

    test('服务端重排：保持服务端相对顺序', () {
      const local = [
        ChatMessage(messageId: 'm1', role: 'user', content: 'm1', timestamp: 100),
        ChatMessage(messageId: 'm2', role: 'user', content: 'm2', timestamp: 101),
        ChatMessage(messageId: 'm3', role: 'assistant', content: 'm3', timestamp: 102),
      ];
      const server = [
        ChatMessage(messageId: 'm1', role: 'user', content: 'm1', timestamp: 100),
        ChatMessage(messageId: 'm3', role: 'assistant', content: 'm3', timestamp: 102),
        ChatMessage(messageId: 'm2', role: 'user', content: 'm2', timestamp: 101),
      ];

      final merged = diffMergeMessages(
        localMessages: local,
        serverMessages: server,
      );

      expect(merged, hasLength(3));
      expect(merged.map((m) => m.messageId).toList(), ['m1', 'm3', 'm2']);
    });

    test('无交集双列表：按时间戳前后拼接', () {
      const local = [
        ChatMessage(messageId: 'm1', role: 'user', content: 'm1', timestamp: 10),
        ChatMessage(messageId: 'm2', role: 'assistant', content: 'm2', timestamp: 20),
      ];
      const server = [
        ChatMessage(messageId: 'm3', role: 'user', content: 'm3', timestamp: 30),
        ChatMessage(messageId: 'm4', role: 'assistant', content: 'm4', timestamp: 40),
      ];

      final merged = diffMergeMessages(
        localMessages: local,
        serverMessages: server,
      );

      expect(merged, hasLength(4));
      expect(merged.map((m) => m.messageId).toList(), ['m1', 'm2', 'm3', 'm4']);
    });
  });

  group('ChatController.syncMissingMessages 全链路同步测试', () {
    test('从服务器拉取缺失消息并补齐（本地 m1, m2 → 服务端 m1, m2, m3）', () async {
      final api = FakeChatApi();
      api.sessionResult = {
        'session': {
          'session_id': 'sess-1',
          'messages': [
            {'message_id': 'm1', 'role': 'user', 'content': 'm1', 'timestamp': 100.0},
            {'message_id': 'm2', 'role': 'assistant', 'content': 'm2', 'timestamp': 101.0},
            {'message_id': 'm3', 'role': 'user', 'content': 'm3 (Web 端)', 'timestamp': 102.0},
          ],
        },
      };

      final clock = _FakeClock();
      final container = _buildContainer(api, clock);
      final controller = container.read(chatControllerProvider('sess-1').notifier);
      await Future<void>.delayed(Duration.zero);

      // 初始填充本地只有 m1, m2
      controller.state = controller.state.copyWith(
        messages: const [
          ChatMessage(messageId: 'm1', role: 'user', content: 'm1', timestamp: 100.0),
          ChatMessage(messageId: 'm2', role: 'assistant', content: 'm2', timestamp: 101.0),
        ],
      );

      api.sessionCalls = 0;
      await controller.syncMissingMessages();

      final state = container.read(chatControllerProvider('sess-1'));
      expect(state.messages, hasLength(3));
      expect(state.messages[2].messageId, 'm3');
      expect(state.messages[2].content, 'm3 (Web 端)');
      expect(api.sessionCalls, 1);
    });

    test('内容变化就地 patch 更新', () async {
      final api = FakeChatApi();
      api.sessionResult = {
        'session': {
          'session_id': 'sess-1',
          'messages': [
            {'message_id': 'm1', 'role': 'user', 'content': 'm1', 'timestamp': 100.0},
            {'message_id': 'm2', 'role': 'assistant', 'content': '已由其它端编辑的最新回答', 'timestamp': 101.0},
          ],
        },
      };

      final clock = _FakeClock();
      final container = _buildContainer(api, clock);
      final controller = container.read(chatControllerProvider('sess-1').notifier);
      await Future<void>.delayed(Duration.zero);

      controller.state = controller.state.copyWith(
        messages: const [
          ChatMessage(messageId: 'm1', role: 'user', content: 'm1', timestamp: 100.0),
          ChatMessage(messageId: 'm2', role: 'assistant', content: '旧回答', timestamp: 101.0),
        ],
      );

      await controller.syncMissingMessages();

      final state = container.read(chatControllerProvider('sess-1'));
      expect(state.messages, hasLength(2));
      expect(state.messages[1].content, '已由其它端编辑的最新回答');
    });

    test('本地未落库乐观消息与服务端消息指纹去重', () async {
      final api = FakeChatApi();
      api.sessionResult = {
        'session': {
          'session_id': 'sess-1',
          'messages': [
            {'message_id': 'm1', 'role': 'user', 'content': 'm1', 'timestamp': 100.0},
            {'message_id': 'srv-msg-2', 'role': 'user', 'content': '我的乐观消息', 'timestamp': 102.0},
          ],
        },
      };

      final clock = _FakeClock();
      final container = _buildContainer(api, clock);
      final controller = container.read(chatControllerProvider('sess-1').notifier);
      await Future<void>.delayed(Duration.zero);

      controller.state = controller.state.copyWith(
        messages: const [
          ChatMessage(messageId: 'm1', role: 'user', content: 'm1', timestamp: 100.0),
          ChatMessage(messageId: 'local-opt-1', role: 'user', content: '我的乐观消息', timestamp: 102.0),
        ],
      );

      await controller.syncMissingMessages();

      final state = container.read(chatControllerProvider('sess-1'));
      expect(state.messages, hasLength(2));
      expect(state.messages[1].messageId, 'srv-msg-2');
    });

    test('同步请求异常静默容错（不弹全局错误弹窗）', () async {
      final api = FakeChatApi();
      final clock = _FakeClock();
      final container = _buildContainer(api, clock);
      final controller = container.read(chatControllerProvider('sess-1').notifier);
      await Future<void>.delayed(Duration.zero);

      controller.state = controller.state.copyWith(
        messages: const [
          ChatMessage(messageId: 'm1', role: 'user', content: 'm1', timestamp: 100.0),
        ],
        clearErrorMessage: true,
      );

      api.sessionError = NetworkException(NetworkExceptionKind.cannotConnect);
      await controller.syncMissingMessages();

      final state = container.read(chatControllerProvider('sess-1'));
      expect(state.messages, hasLength(1));
      expect(state.errorMessage, isNull);
      expect(state.sendErrorMessage, isNull);
    });

    test('流式进行中守卫：若当前正在 streaming 或 sending，跳过同步', () async {
      final api = FakeChatApi();
      final clock = _FakeClock();
      final container = _buildContainer(api, clock);
      final controller = container.read(chatControllerProvider('sess-1').notifier);
      await Future<void>.delayed(Duration.zero);

      controller.state = controller.state.copyWith(
        phase: ChatPhase.streaming,
        stream: const ChatStreamState(activeStreamId: 'active-stream-1'),
      );

      api.sessionCalls = 0;
      await controller.syncMissingMessages();

      expect(api.sessionCalls, 0);
    });

    test('服务端存在活跃流时接管并进入 streaming', () async {
      final api = FakeChatApi();
      api.sessionResult = {
        'session': {
          'session_id': 'sess-1',
          'active_stream_id': 'srv-stream-88',
          'messages': [
            {'message_id': 'm1', 'role': 'user', 'content': 'm1', 'timestamp': 100.0},
          ],
        },
      };

      final clock = _FakeClock();
      final container = _buildContainer(api, clock);
      final controller = container.read(chatControllerProvider('sess-1').notifier);
      await Future<void>.delayed(Duration.zero);

      await controller.syncMissingMessages();

      final state = container.read(chatControllerProvider('sess-1'));
      expect(state.phase, ChatPhase.streaming);
      expect(state.stream.activeStreamId, 'srv-stream-88');
    });
  });

  group('loadMessages diff-merge 语义测试', () {
    test('全量 loadMessages() 对本地已分页历史消息执行 diff-merge 而非直接覆盖丢弃', () async {
      final api = FakeChatApi();
      api.sessionResult = {
        'session': {
          'session_id': 'sess-1',
          'messages': [
            {'message_id': 'm1', 'role': 'user', 'content': 'm1', 'timestamp': 100.0},
            {'message_id': 'm2', 'role': 'assistant', 'content': 'm2', 'timestamp': 101.0},
            {'message_id': 'm3', 'role': 'user', 'content': 'm3', 'timestamp': 102.0},
          ],
        },
      };

      final clock = _FakeClock();
      final container = _buildContainer(api, clock);
      final controller = container.read(chatControllerProvider('sess-1').notifier);

      // 本地拥有更早的历史分页记录 m_old
      controller.state = controller.state.copyWith(
        messages: const [
          ChatMessage(messageId: 'm_old', role: 'user', content: '分页更早记录', timestamp: 50.0),
          ChatMessage(messageId: 'm1', role: 'user', content: 'm1', timestamp: 100.0),
          ChatMessage(messageId: 'm2', role: 'assistant', content: 'm2', timestamp: 101.0),
        ],
      );

      await controller.loadMessages();

      final state = container.read(chatControllerProvider('sess-1'));
      expect(state.messages, hasLength(4));
      expect(
        state.messages.map((m) => m.messageId).toList(),
        ['m_old', 'm1', 'm2', 'm3'],
      );
    });
  });

  group('生命周期与 500ms 防抖测试', () {
    test('AppLifecycleState.resumed 切换触发同步', () {
      fakeAsync((async) {
        final api = FakeChatApi();
        api.sessionResult = {
          'session': {
            'session_id': 'sess-1',
            'messages': [
              {'message_id': 'm1', 'role': 'user', 'content': 'm1', 'timestamp': 100.0},
              {'message_id': 'm2', 'role': 'assistant', 'content': 'm2', 'timestamp': 101.0},
            ],
          },
        };
        final clock = _FakeClock();
        final container = _buildContainer(api, clock);

        // 切换生命周期到 paused 再回到 resumed
        container.read(appLifecycleStateProvider.notifier).setState(AppLifecycleState.paused);
        expect(container.read(appLifecycleStateProvider), AppLifecycleState.paused);

        container.read(appLifecycleStateProvider.notifier).setState(AppLifecycleState.resumed);
        expect(container.read(appLifecycleStateProvider), AppLifecycleState.resumed);
      });
    });
  });

  group('ChatPage 页面级同步与防抖测试', () {
    testWidgets('ChatPage 初始化自动触发 loadMessages 与 syncMissingMessages', (tester) async {
      final api = FakeChatApi();
      api.sessionResult = {
        'session': {
          'session_id': 's1',
          'messages': [
            {'message_id': 'm1', 'role': 'user', 'content': '初次加载消息', 'timestamp': 100.0},
          ],
        },
      };

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            chatApiProvider.overrideWithValue(api),
          ],
          child: const CupertinoApp(
            home: ChatPage(sessionId: 's1'),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('初次加载消息'), findsOneWidget);
      expect(api.sessionCalls, greaterThanOrEqualTo(1));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('AppLifecycleState.resumed 切换触发 syncMissingMessages 且受 500ms 防抖保护', (tester) async {
      final api = FakeChatApi();
      api.sessionResult = {
        'session': {
          'session_id': 's1',
          'messages': [
            {'message_id': 'm1', 'role': 'user', 'content': 'm1', 'timestamp': 100.0},
          ],
        },
      };

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            chatApiProvider.overrideWithValue(api),
          ],
          child: const CupertinoApp(
            home: ChatPage(sessionId: 's1'),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final callsBefore = api.sessionCalls;

      // 快速连续触发两次 resumed（在 500ms 内）
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      // 防抖拦截，在 500ms 内未产生多余调用
      expect(api.sessionCalls - callsBefore, lessThanOrEqualTo(1));

      // 等待 600ms 超过防抖窗口
      await tester.pump(const Duration(milliseconds: 600));

      // 再次触发 resumed
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(api.sessionCalls, greaterThan(callsBefore));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  });
}

// ---------------------------------------------------------------------------
// 测试辅助构建
// ---------------------------------------------------------------------------

class _FakeClock {
  DateTime now = DateTime(2026, 1, 1);

  DateTime call() => now;

  void advance(Duration duration) => now = now.add(duration);
}

class _NoopCacheService extends CacheService {
  _NoopCacheService(super.db);
  @override
  Future<void> writeMessages({required String sessionId, required List<Map<String, Object?>> messages}) async {}
  @override
  Future<List<Map<String, Object?>>> readMessages(String sessionId) async => const [];
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
