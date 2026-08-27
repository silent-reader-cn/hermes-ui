import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/api/sse_client.dart';
import 'package:hermes_ui/features/chat/chat_providers.dart';
import 'package:hermes_ui/features/chat/chat_state.dart';
import 'package:hermes_ui/features/notifications/notification_lifecycle_observer.dart';
import 'package:hermes_ui/features/notifications/notification_providers.dart';
import 'package:hermes_ui/features/notifications/turn_notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../helpers/fake_chat_api.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

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
          chatClarificationNeededCallbackProvider.overrideWith(
            (ref) => ref.watch(clarificationNotificationHookProvider),
          ),
          chatSessionErrorCallbackProvider.overrideWith(
            (ref) => ref.watch(sessionErrorNotificationHookProvider),
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

    test('取消（cancel）→ 触发异常中断通知', () {
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
        expect(service.errorCalls, hasLength(1));
        expect(service.errorCalls.single.$2, '响应已取消');
      });
    });

    test('错误事件 → 触发异常中断通知', () {
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
        expect(service.errorCalls, hasLength(1));
        expect(service.errorCalls.single.$3, '服务器内部错误');
      });
    });

    test('澄清事件 → 触发澄清请求通知', () {
      fakeAsync((async) {
        final container =
            buildContainer(lifecycle: AppLifecycleState.paused);
        final controller =
            container.read(chatControllerProvider('').notifier);

        unawaited(controller.send('你好'));
        async.flushMicrotasks();
        api.emit(const ClarificationPendingSseEvent({
          'pending': {
            'clarify_id': 'c1',
            'question': '请选择模式',
            'choices_offered': ['A', 'B'],
          },
          'pending_count': 1,
        }));
        async.flushMicrotasks();

        expect(service.clarifyCalls, [('sess-new', '请选择模式')]);
        expect(
          container.read(chatControllerProvider('')).phase,
          ChatPhase.clarifyPending,
        );
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

  group('三类通知与设置联动测试', () {
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

    test('澄清通知：后台触发', () {
      container
          .read(appLifecycleStateProvider.notifier)
          .setState(AppLifecycleState.paused);
      final hook = container.read(clarificationNotificationHookProvider);

      hook('sess-1', '需要输入密码吗？');

      expect(service.clarifyCalls, [('sess-1', '需要输入密码吗？')]);
    });

    test('澄清通知：开关关闭时不触发', () async {
      container
          .read(appLifecycleStateProvider.notifier)
          .setState(AppLifecycleState.paused);
      await container
          .read(notificationSettingsProvider.notifier)
          .setNotifyClarifyEnabled(false);
      final hook = container.read(clarificationNotificationHookProvider);

      hook('sess-1', '需要输入密码吗？');

      expect(service.clarifyCalls, isEmpty);
    });

    test('错误通知：后台触发', () {
      container
          .read(appLifecycleStateProvider.notifier)
          .setState(AppLifecycleState.paused);
      final hook = container.read(sessionErrorNotificationHookProvider);

      hook('sess-1', '连接失败', '超时');

      expect(service.errorCalls, [('sess-1', '连接失败', '超时')]);
    });

    test('错误通知：开关关闭时不触发', () async {
      container
          .read(appLifecycleStateProvider.notifier)
          .setState(AppLifecycleState.paused);
      await container
          .read(notificationSettingsProvider.notifier)
          .setNotifyErrorsEnabled(false);
      final hook = container.read(sessionErrorNotificationHookProvider);

      hook('sess-1', '连接失败', '超时');

      expect(service.errorCalls, isEmpty);
    });

    test('回合完成通知：开关关闭时不触发', () async {
      container
          .read(appLifecycleStateProvider.notifier)
          .setState(AppLifecycleState.paused);
      await container
          .read(notificationSettingsProvider.notifier)
          .setNotifyTurnsEnabled(false);
      final hook = container.read(turnNotificationHookProvider);

      hook('sess-1', '标题', '预览');

      expect(service.notifyCalls, isEmpty);
    });

    test('前台不同会话触发 → 推送至 inAppNotificationProvider', () {
      container
          .read(appLifecycleStateProvider.notifier)
          .setState(AppLifecycleState.resumed);
      final hook = container.read(clarificationNotificationHookProvider);

      hook('sess-other', '请澄清');

      final inApp = container.read(inAppNotificationProvider);
      expect(inApp, isNotNull);
      expect(inApp!.sessionId, 'sess-other');
      expect(inApp.message, '请澄清');
      expect(inApp.type, InAppNotificationType.clarificationNeeded);
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
  final List<(String, String)> clarifyCalls = [];
  final List<(String, String, String)> errorCalls = [];
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
  Future<void> notifyClarificationNeeded(
    String sessionId,
    String question,
  ) async {
    clarifyCalls.add((sessionId, question));
  }

  @override
  Future<void> notifySessionError(
    String sessionId,
    String title,
    String preview,
  ) async {
    errorCalls.add((sessionId, title, preview));
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

typedef _FakeChatApi = FakeChatApi;
