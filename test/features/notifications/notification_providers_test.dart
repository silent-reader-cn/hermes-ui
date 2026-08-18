import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermex_flutter/core/api/sse_client.dart';
import 'package:hermex_flutter/features/chat/chat_providers.dart';
import 'package:hermex_flutter/features/chat/chat_server_api.dart';
import 'package:hermex_flutter/features/chat/chat_state.dart';
import 'package:hermex_flutter/features/notifications/notification_lifecycle_observer.dart';
import 'package:hermex_flutter/features/notifications/notification_providers.dart';
import 'package:hermex_flutter/features/notifications/turn_notification_service.dart';

void main() {
  group('turnNotificationHookProvider（后台发 / 前台不发）', () {
    late _FakeTurnNotificationService service;
    late ProviderContainer container;

    setUp(() {
      service = _FakeTurnNotificationService();
      container = ProviderContainer(
        overrides: [
          turnNotificationServiceProvider.overrideWithValue(service),
        ],
      );
      addTearDown(container.dispose);
    });

    test('后台（paused）→ 发通知，参数原样传递', () {
      container
          .read(appLifecycleStateProvider.notifier)
          .setState(AppLifecycleState.paused);
      final hook = container.read(turnNotificationHookProvider);

      hook('sess-1', '我的会话', '你好！');

      expect(service.notifyCalls, [('sess-1', '我的会话', '你好！')]);
      expect(service.clearAllCalls, 0);
    });

    test('后台（inactive）→ 也发通知', () {
      container
          .read(appLifecycleStateProvider.notifier)
          .setState(AppLifecycleState.inactive);
      final hook = container.read(turnNotificationHookProvider);

      hook('s1', 't', 'p');

      expect(service.notifyCalls, [('s1', 't', 'p')]);
    });

    test('前台（resumed，默认）→ 不发通知，清残留', () {
      final hook = container.read(turnNotificationHookProvider);

      hook('sess-1', '我的会话', '你好！');

      expect(service.notifyCalls, isEmpty);
      expect(service.clearAllCalls, 1);
    });

    test('后台 → 前台切换后：先发后清', () {
      final notifier = container.read(appLifecycleStateProvider.notifier);
      final hook = container.read(turnNotificationHookProvider);

      notifier.setState(AppLifecycleState.paused);
      hook('s1', 't', 'p');
      expect(service.notifyCalls, hasLength(1));

      notifier.setState(AppLifecycleState.resumed);
      hook('s1', 't', 'p');
      expect(service.notifyCalls, hasLength(1));
      expect(service.clearAllCalls, 1);
    });
  });

  group('appLifecycleStateProvider', () {
    test('默认前台 resumed', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(appLifecycleStateProvider), AppLifecycleState.resumed);
    });

    test('setState 相同值不重复通知（listener 只收到一次变化）', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      var changes = 0;
      container.listen(appLifecycleStateProvider, (_, _) => changes++);

      container
          .read(appLifecycleStateProvider.notifier)
          .setState(AppLifecycleState.paused);
      container
          .read(appLifecycleStateProvider.notifier)
          .setState(AppLifecycleState.paused);
      container
          .read(appLifecycleStateProvider.notifier)
          .setState(AppLifecycleState.resumed);

      expect(changes, 2);
    });
  });

  group('chat 收尾 hook 端到端（真实 ChatController + SSE 事件）', () {
    late _FakeChatApi api;
    late _FakeClock clock;
    late _FakeTurnNotificationService service;

    ProviderContainer buildContainer({required AppLifecycleState lifecycle}) {
      final container = ProviderContainer(
        overrides: [
          chatApiProvider.overrideWithValue(api),
          chatClockProvider.overrideWithValue(clock.call),
          turnNotificationServiceProvider.overrideWithValue(service),
          chatTurnCompletedCallbackProvider.overrideWith(
            (ref) => ref.watch(turnNotificationHookProvider),
          ),
        ],
      );
      addTearDown(container.dispose);
      container
          .read(appLifecycleStateProvider.notifier)
          .setState(lifecycle);
      return container;
    }

    setUp(() {
      api = _FakeChatApi();
      clock = _FakeClock();
      service = _FakeTurnNotificationService();
    });

    Map<String, Object?> doneSession() => {
          'session_id': 'sess-new',
          'title': '我的会话',
          'messages': [
            {
              'role': 'user',
              'content': '你好',
              'message_id': 'u1',
              'timestamp': 0,
            },
            {
              'role': 'assistant',
              'content': '你好！有什么可以帮你？',
              'message_id': 'a1',
              'timestamp': 1,
            },
          ],
        };

    test('后台 + done → 发通知（sessionId/标题/预览取自收尾状态）', () {
      fakeAsync((async) {
        final container =
            buildContainer(lifecycle: AppLifecycleState.paused);
        final controller =
            container.read(chatControllerProvider('').notifier);

        unawaited(controller.send('你好'));
        async.flushMicrotasks();
        expect(
          container.read(chatControllerProvider('')).phase,
          ChatPhase.streaming,
        );

        api.emit(DoneSseEvent(DoneStreamEvent(session: doneSession())));
        async.flushMicrotasks();

        expect(service.notifyCalls, [
          ('sess-new', '我的会话', '你好！有什么可以帮你？'),
        ]);
        expect(service.clearAllCalls, 0);
        expect(
          container.read(chatControllerProvider('')).phase,
          ChatPhase.idle,
        );
      });
    });

    test('前台 + done → 不发通知，清残留', () {
      fakeAsync((async) {
        final container =
            buildContainer(lifecycle: AppLifecycleState.resumed);
        final controller =
            container.read(chatControllerProvider('').notifier);

        unawaited(controller.send('你好'));
        async.flushMicrotasks();
        api.emit(DoneSseEvent(DoneStreamEvent(session: doneSession())));
        async.flushMicrotasks();

        expect(service.notifyCalls, isEmpty);
        expect(service.clearAllCalls, 1);
      });
    });

    test('后台 + stream_end（无 done）→ 发通知一次', () {
      fakeAsync((async) {
        final container =
            buildContainer(lifecycle: AppLifecycleState.paused);
        final controller =
            container.read(chatControllerProvider('').notifier);

        unawaited(controller.send('你好'));
        async.flushMicrotasks();
        api.emit(const TokenSseEvent('好的，'));
        api.emit(const TokenSseEvent('马上处理'));
        // 16ms 合并 + 48ms 词级 reveal，让内容进入 messages
        async.elapse(const Duration(milliseconds: 80));

        api.emit(const StreamEndSseEvent());
        async.flushMicrotasks();

        expect(service.notifyCalls, hasLength(1));
        final (sessionId, title, preview) = service.notifyCalls.single;
        expect(sessionId, 'sess-new');
        expect(preview, contains('好的，马上处理'));
        expect(container.read(chatControllerProvider('')).phase, ChatPhase.idle);
      });
    });

    test('done 后 stream_end → 不重复通知', () {
      fakeAsync((async) {
        final container =
            buildContainer(lifecycle: AppLifecycleState.paused);
        final controller =
            container.read(chatControllerProvider('').notifier);

        unawaited(controller.send('你好'));
        async.flushMicrotasks();
        api.emit(DoneSseEvent(DoneStreamEvent(session: doneSession())));
        async.flushMicrotasks();
        expect(service.notifyCalls, hasLength(1));

        api.emit(const StreamEndSseEvent());
        async.flushMicrotasks();
        expect(service.notifyCalls, hasLength(1));
      });
    });

    test('取消（cancel）→ 不发通知', () {
      fakeAsync((async) {
        final container =
            buildContainer(lifecycle: AppLifecycleState.paused);
        final controller =
            container.read(chatControllerProvider('').notifier);

        unawaited(controller.send('你好'));
        async.flushMicrotasks();
        api.emit(const CancelledSseEvent());
        async.flushMicrotasks();

        expect(service.notifyCalls, isEmpty);
      });
    });

    test('错误事件 → 不发通知', () {
      fakeAsync((async) {
        final container =
            buildContainer(lifecycle: AppLifecycleState.paused);
        final controller =
            container.read(chatControllerProvider('').notifier);

        unawaited(controller.send('你好'));
        async.flushMicrotasks();
        api.emit(const ErrorSseEvent('服务器内部错误'));
        async.flushMicrotasks();

        expect(service.notifyCalls, isEmpty);
      });
    });

    test('无 hook override（默认 no-op）→ 不触碰通知服务', () {
      fakeAsync((async) {
        final container = ProviderContainer(
          overrides: [
            chatApiProvider.overrideWithValue(api),
            chatClockProvider.overrideWithValue(clock.call),
          ],
        );
        addTearDown(container.dispose);
        final controller =
            container.read(chatControllerProvider('').notifier);

        unawaited(controller.send('你好'));
        async.flushMicrotasks();
        api.emit(DoneSseEvent(DoneStreamEvent(session: doneSession())));
        async.flushMicrotasks();

        expect(container.read(chatControllerProvider('')).phase, ChatPhase.idle);
      });
    });
  });

  group('NotificationLifecycleObserver（前后台驱动 + 回前台清除）', () {
    testWidgets('paused → resumed：更新生命周期并在回前台时 clearAll',
        (tester) async {
      final service = _FakeTurnNotificationService();
      final container = ProviderContainer(
        overrides: [
          turnNotificationServiceProvider.overrideWithValue(service),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(() {
        tester.binding
            .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      });

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const NotificationLifecycleObserver(
            child: SizedBox(),
          ),
        ),
      );
      await tester.pump();

      expect(
        container.read(appLifecycleStateProvider),
        AppLifecycleState.resumed,
      );

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(
        container.read(appLifecycleStateProvider),
        AppLifecycleState.paused,
      );
      expect(service.clearAllCalls, 0);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(
        container.read(appLifecycleStateProvider),
        AppLifecycleState.resumed,
      );
      expect(service.clearAllCalls, 1);
    });
  });
}

// ---------------------------------------------------------------------------
// 测试基础设施
// ---------------------------------------------------------------------------

class _FakeTurnNotificationService implements TurnNotificationService {
  final List<(String, String, String)> notifyCalls = [];
  int clearAllCalls = 0;
  int permissionRequests = 0;
  String? launchSessionId;

  @override
  Future<void> notifyTurnCompleted(
    String sessionId,
    String title,
    String preview,
  ) async {
    notifyCalls.add((sessionId, title, preview));
  }

  @override
  Future<void> clearAll() async {
    clearAllCalls++;
  }

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return true;
  }

  @override
  Future<String?> getLaunchSessionId() async => launchSessionId;
}

class _FakeClock {
  DateTime now = DateTime(2026, 1, 1);

  DateTime call() => now;

  void advance(Duration duration) => now = now.add(duration);
}

class _FakeChatApi implements ChatServerApi {
  @override
  Future<Object?> startChat({
    required String sessionId,
    required String message,
    String? workspace,
    String? model,
    String? modelProvider,
    String? profile,
    bool explicitModelPick = false,
    List<Map<String, Object?>>? attachments,
  }) async {
    return {
      'stream_id': 'stream-1',
      'session_id': sessionId.isEmpty ? 'sess-new' : sessionId,
    };
  }

  @override
  Future<Object?> steerChat({
    required String sessionId,
    required String text,
  }) async {
    return {'accepted': true};
  }

  @override
  Future<Object?> cancelChat(String streamId) async {
    return {'ok': true};
  }

  @override
  Future<Object?> chatStreamStatus(String streamId) async {
    return {'active': false, 'replay_available': false};
  }

  @override
  Future<Object?> session({
    required String sessionId,
    bool includeMessages = true,
    int? messageLimit,
    int? messageBefore,
    bool expandRenderable = false,
  }) async {
    return {
      'session': {'session_id': sessionId, 'messages': const []},
    };
  }

  @override
  Future<Object?> respondApproval({
    required String sessionId,
    required String choice,
    String? approvalId,
  }) async {
    return {'ok': true};
  }

  @override
  Future<Object?> respondClarification({
    required String sessionId,
    required String response,
    String? clarifyId,
  }) async {
    return {'ok': true};
  }

  @override
  Future<Object?> renameSession({
    required String sessionId,
    required String title,
  }) async {
    return {'ok': true, 'session': {'session_id': sessionId, 'title': title}};
  }

  @override
  Future<Object?> pinSession({
    required String sessionId,
    required bool pinned,
  }) async {
    return {'ok': true};
  }

  @override
  Future<Object?> archiveSession({
    required String sessionId,
    required bool archived,
  }) async {
    return {'ok': true};
  }

  @override
  Future<Object?> deleteSession(String sessionId) async => {'ok': true};

  @override
  Future<Object?> branchSession(String sessionId) async => {
        'session_id': 'branch-$sessionId',
        'parent_session_id': sessionId,
      };

  @override
  Future<Object?> truncateSession({
    required String sessionId,
    required int keepCount,
  }) async {
    return {'ok': true};
  }

  @override
  Future<Object?> compressSession({
    required String sessionId,
    String? focusTopic,
  }) async {
    return {'ok': true};
  }

  @override
  Future<Object?> undoSession(String sessionId) async => {'ok': true};

  @override
  Future<Object?> retrySession(String sessionId) async => {
        'ok': true,
        'last_user_text': '你好',
      };

  @override
  Future<Object?> updateSession({
    required String sessionId,
    String? workspace,
    String? model,
    String? modelProvider,
  }) async {
    return {'ok': true};
  }

  @override
  Future<Object?> getYolo(String sessionId) async =>
      {'ok': true, 'yolo_enabled': false};

  @override
  Future<Object?> setYolo({
    required String sessionId,
    required bool enabled,
  }) async {
    return {'ok': true, 'yolo_enabled': enabled};
  }

  @override
  Future<void> startStream(
    String streamId, {
    int? replayAfterSeq,
    required void Function(SseEvent event) onEvent,
    void Function(String eventId)? onEventId,
    required void Function(String message) onTransportError,
    required void Function() onClosed,
  }) async {
    _onEvent = onEvent;
  }

  @override
  void stopStream() {}

  void emit(SseEvent event) => _onEvent?.call(event);

  void Function(SseEvent event)? _onEvent;
}
