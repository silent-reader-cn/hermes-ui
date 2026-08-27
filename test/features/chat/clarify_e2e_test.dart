import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/api/sse_client.dart';
import 'package:hermes_ui/features/chat/chat_providers.dart';
import 'package:hermes_ui/features/chat/chat_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_chat_api.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  group('Clarify 端到端与状态机联动测试', () {
    late FakeChatApi api;
    late List<(String, String)> clarifyNotified;
    late List<(String, String, String)> errorNotified;

    setUp(() {
      api = FakeChatApi();
      clarifyNotified = [];
      errorNotified = [];
    });

    ProviderContainer buildContainer() {
      final container = ProviderContainer(
        overrides: [
          chatApiProvider.overrideWithValue(api),
          chatClarificationNeededCallbackProvider.overrideWithValue(
            (sessionId, question) {
              clarifyNotified.add((sessionId, question));
            },
          ),
          chatSessionErrorCallbackProvider.overrideWithValue(
            (sessionId, title, preview) {
              errorNotified.add((sessionId, title, preview));
            },
          ),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('收到 ClarificationPendingSseEvent → phase 切换为 clarifyPending 并触发通知', () {
      fakeAsync((async) {
        final container = buildContainer();
        final controller =
            container.read(chatControllerProvider('sess-1').notifier);

        async.flushMicrotasks();
        expect(
          container.read(chatControllerProvider('sess-1')).phase,
          ChatPhase.idle,
        );

        unawaited(controller.send('开始'));
        async.flushMicrotasks();

        api.emit(const ClarificationPendingSseEvent({
          'pending': {
            'clarify_id': 'c-1',
            'question': '请选择运行模式',
            'choices_offered': ['Debug', 'Release'],
            'expires_at': 1756300000,
          },
          'pending_count': 1,
        }));
        async.flushMicrotasks();

        final state = container.read(chatControllerProvider('sess-1'));
        expect(state.phase, ChatPhase.clarifyPending);
        expect(state.pendingAction.clarificationPrompt, isNotNull);
        expect(
          state.pendingAction.clarificationPrompt!['question'],
          '请选择运行模式',
        );
        expect(clarifyNotified, [('sess-1', '请选择运行模式')]);
      });
    });

    test('respondToClarification 提交成功 → 清除澄清卡片并恢复 phase', () {
      fakeAsync((async) {
        final container = buildContainer();
        final controller =
            container.read(chatControllerProvider('sess-1').notifier);

        async.flushMicrotasks();
        unawaited(controller.send('开始'));
        async.flushMicrotasks();

        api.emit(const ClarificationPendingSseEvent({
          'pending': {
            'clarify_id': 'c-1',
            'question': '需要确认',
            'choices_offered': ['OK'],
          },
          'pending_count': 1,
        }));
        async.flushMicrotasks();

        expect(
          container.read(chatControllerProvider('sess-1')).phase,
          ChatPhase.clarifyPending,
        );

        bool? result;
        unawaited(
          controller.respondToClarification('OK').then((v) => result = v),
        );
        async.flushMicrotasks();

        expect(result, isTrue);
        expect(api.respondClarificationCalls, 1);
        expect(api.lastClarificationSessionId, 'sess-1');
        expect(api.lastClarificationResponse, 'OK');

        final state = container.read(chatControllerProvider('sess-1'));
        expect(state.pendingAction.clarificationPrompt, isNull);
      });
    });

    test('handleClarificationTimeout → 清除澄清卡片并弹出「澄清已超时」提示', () {
      fakeAsync((async) {
        final container = buildContainer();
        final controller =
            container.read(chatControllerProvider('sess-1').notifier);

        async.flushMicrotasks();
        unawaited(controller.send('开始'));
        async.flushMicrotasks();

        api.emit(const ClarificationPendingSseEvent({
          'pending': {
            'clarify_id': 'c-1',
            'question': '限时回答',
            'timeout_seconds': 10,
          },
          'pending_count': 1,
        }));
        async.flushMicrotasks();

        expect(
          container.read(chatControllerProvider('sess-1')).phase,
          ChatPhase.clarifyPending,
        );

        controller.handleClarificationTimeout();
        async.flushMicrotasks();

        final state = container.read(chatControllerProvider('sess-1'));
        expect(state.pendingAction.clarificationPrompt, isNull);
        expect(state.noticeMessage, '澄清已超时');
      });
    });

    test('pending 为空（null）事件 → 自动清除澄清卡片', () {
      fakeAsync((async) {
        final container = buildContainer();
        final controller =
            container.read(chatControllerProvider('sess-1').notifier);

        async.flushMicrotasks();
        unawaited(controller.send('开始'));
        async.flushMicrotasks();

        api.emit(const ClarificationPendingSseEvent({
          'pending': {
            'clarify_id': 'c-1',
            'question': '需要确认',
          },
          'pending_count': 1,
        }));
        async.flushMicrotasks();
        expect(
          container.read(chatControllerProvider('sess-1')).phase,
          ChatPhase.clarifyPending,
        );

        // 后端下发 pending: null
        api.emit(const ClarificationPendingSseEvent({
          'pending': null,
          'pending_count': 0,
        }));
        async.flushMicrotasks();

        final state = container.read(chatControllerProvider('sess-1'));
        expect(state.pendingAction.clarificationPrompt, isNull);
      });
    });
  });
}
