import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hermex_flutter/core/api/api_client.dart';
import 'package:hermex_flutter/core/connections/connection_providers.dart';
import 'package:hermex_flutter/core/connections/server_connection.dart';
import 'package:hermex_flutter/core/models/session.dart';
import 'package:hermex_flutter/features/chat/chat_page.dart';
import 'package:hermex_flutter/features/chat/chat_providers.dart';
import 'package:hermex_flutter/features/onboarding/onboarding_providers.dart';
import 'package:hermex_flutter/features/projects/project_providers.dart';
import 'package:hermex_flutter/features/session_list/session_list_providers.dart';

import '../../helpers/fake_chat_api.dart';
import '../../helpers/fake_onboarding_login_api.dart';
import '../../helpers/fake_session_list_api.dart';

ServerConnection _conn() {
  return ServerConnection(
    id: 'c1',
    name: 'Test',
    baseUrl: 'http://test.local:30002',
    createdAt: DateTime.utc(2026, 1, 1),
  );
}

class _StubActiveConnection extends ActiveConnectionController {
  _StubActiveConnection(this._connection);
  final ServerConnection _connection;
  @override
  ServerConnection? build() => _connection;
}

class _StubProjectApi implements ProjectApi {
  @override
  Future<ProjectsResponse> fetchProjects() async =>
      const ProjectsResponse(projects: []);

  @override
  Future<ProjectMutationResponse> createProject({
    required String name,
    String? color,
  }) async =>
      const ProjectMutationResponse(ok: true);

  @override
  Future<ProjectMutationResponse> renameProject({
    required String projectId,
    required String name,
    String? color,
  }) async =>
      const ProjectMutationResponse(ok: true);

  @override
  Future<ProjectMutationResponse> deleteProject(String projectId) async =>
      const ProjectMutationResponse(ok: true);
}

ProviderContainer _makeChatAndSessionContainer(
  FakeChatApi chatApi,
  FakeSessionListApi sessionApi,
) {
  return ProviderContainer(
    overrides: [
      apiClientProvider.overrideWithValue(
        ApiClient(baseUrl: 'http://test.local:30002'),
      ),
      chatApiProvider.overrideWithValue(chatApi),
      sessionListApiFactoryProvider.overrideWithValue((_) => sessionApi),
      projectApiFactoryProvider.overrideWithValue((_) => _StubProjectApi()),
      activeConnectionProvider.overrideWith(
        () => _StubActiveConnection(_conn()),
      ),
      onboardingApiFactoryProvider.overrideWithValue(
        (baseUrl, headers) => FakeOnboardingLoginApi(),
      ),
    ],
  );
}

void main() {
  group('P4 新会话首条消息后列表即时显示', () {
    test('handleNewChatSession 立即触发强制刷新 + 600ms 二次补拉', () async {
      final sessionApi = FakeSessionListApi(
        sessions: [
          const SessionSummary(sessionId: 's1', title: '旧会话', createdAt: 1000),
        ],
      );
      final container = ProviderContainer(
        overrides: [
          apiClientProvider.overrideWithValue(
            ApiClient(baseUrl: 'http://test.local:30002'),
          ),
          sessionListApiFactoryProvider.overrideWithValue((_) => sessionApi),
          projectApiFactoryProvider.overrideWithValue((_) => _StubProjectApi()),
          activeConnectionProvider.overrideWith(
            () => _StubActiveConnection(_conn()),
          ),
          onboardingApiFactoryProvider.overrideWithValue(
            (baseUrl, headers) => FakeOnboardingLoginApi(),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(sessionListControllerProvider.future);
      expect(sessionApi.fetchCount, 1);

      await container
          .read(sessionListControllerProvider.notifier)
          .handleNewChatSession('new-123', titleHint: 'hello world');

      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(sessionApi.fetchCount, greaterThanOrEqualTo(2));

      await Future<void>.delayed(const Duration(milliseconds: 700));
      expect(sessionApi.fetchCount, greaterThanOrEqualTo(3));
    });

    test('ChatController 新会话 send 成功 → 触发 sessionList 刷新', () async {
      final chatApi = FakeChatApi();
      chatApi.startChatResult = {
        'stream_id': 'stream-xyz',
        'session_id': 'sess-new-42',
      };
      final sessionApi = FakeSessionListApi(
        sessions: [
          const SessionSummary(sessionId: 's1', title: '旧'),
        ],
      );
      final container = _makeChatAndSessionContainer(chatApi, sessionApi);

      await container.read(sessionListControllerProvider.future);
      final before = sessionApi.fetchCount;

      final controller = container.read(chatControllerProvider('').notifier);
      final sent = await controller.send('你好，这是首条消息');
      expect(sent, isTrue);
      expect(container.read(chatControllerProvider('')).sessionId, 'sess-new-42');

      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(sessionApi.fetchCount, greaterThan(before));

      await Future<void>.delayed(const Duration(milliseconds: 700));
      expect(sessionApi.fetchCount, greaterThan(before + 1));
    });

    testWidgets('新会话 ChatPage 发送后导航到 /chat/<newId>', (tester) async {
      final chatApi = FakeChatApi();
      chatApi.startChatResult = {
        'stream_id': 'stream-nav',
        'session_id': 'sess-nav-1',
      };
      final container = ProviderContainer(
        overrides: [
          apiClientProvider.overrideWithValue(
            ApiClient(baseUrl: 'http://test.local:30002'),
          ),
          chatApiProvider.overrideWithValue(chatApi),
          sessionListApiFactoryProvider.overrideWithValue(
            (_) => FakeSessionListApi(sessions: const []),
          ),
          projectApiFactoryProvider.overrideWithValue((_) => _StubProjectApi()),
          activeConnectionProvider.overrideWith(
            () => _StubActiveConnection(_conn()),
          ),
          onboardingApiFactoryProvider.overrideWithValue(
            (baseUrl, headers) => FakeOnboardingLoginApi(),
          ),
        ],
      );
      addTearDown(container.dispose);

      final router = GoRouter(
        initialLocation: '/chat',
        routes: [
          GoRoute(
            path: '/chat',
            builder: (context, state) => const ChatPage(sessionId: ''),
          ),
          GoRoute(
            path: '/chat/:sessionId',
            builder: (context, state) => ChatPage(
              sessionId: state.pathParameters['sessionId'] ?? '',
            ),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: CupertinoApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      expect(router.routerDelegate.currentConfiguration.uri.toString(), '/chat');

      final controller = container.read(chatControllerProvider('').notifier);
      await controller.send('首条');
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        router.routerDelegate.currentConfiguration.uri.toString(),
        '/chat/sess-nav-1',
      );
    });
  });
}
