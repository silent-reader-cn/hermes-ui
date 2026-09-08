import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/connections/server_connection.dart';
import 'package:hermes_ui/core/models/session.dart';
import 'package:hermes_ui/features/chat/chat_providers.dart';
import 'package:hermes_ui/features/onboarding/onboarding_providers.dart';
import 'package:hermes_ui/features/projects/project_providers.dart';
import 'package:hermes_ui/features/session_list/session_list_providers.dart';

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
  }) async => const ProjectMutationResponse(ok: true);

  @override
  Future<ProjectMutationResponse> renameProject({
    required String projectId,
    required String name,
    String? color,
  }) async => const ProjectMutationResponse(ok: true);

  @override
  Future<ProjectMutationResponse> deleteProject(String projectId) async =>
      const ProjectMutationResponse(ok: true);
}

ProviderContainer _makeContainer(
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

SessionListState _listState(ProviderContainer container) {
  return container.read(sessionListControllerProvider).valueOrNull!;
}

void main() {
  group('聊天页行操作 → 会话列表免网络本地同步', () {
    test('改名成功 → 列表同行标题即时更新，不触发全量拉取', () async {
      final chatApi = FakeChatApi();
      final sessionApi = FakeSessionListApi(
        sessions: [
          const SessionSummary(
            sessionId: 's1',
            title: '旧标题',
            createdAt: 1000,
          ),
        ],
      );
      final container = _makeContainer(chatApi, sessionApi);
      addTearDown(container.dispose);

      await container.read(sessionListControllerProvider.future);
      final before = sessionApi.fetchCount;
      final controller = container.read(chatControllerProvider('s1').notifier);

      expect(await controller.renameSession('新标题'), isTrue);
      expect(_listState(container).sessions.single.title, '新标题');
      expect(sessionApi.fetchCount, before);
    });

    test('改名失败 → 列表保持旧标题', () async {
      final chatApi = FakeChatApi()
        ..mutationOk = false
        ..mutationError = '标题已存在';
      final sessionApi = FakeSessionListApi(
        sessions: [
          const SessionSummary(
            sessionId: 's1',
            title: '旧标题',
            createdAt: 1000,
          ),
        ],
      );
      final container = _makeContainer(chatApi, sessionApi);
      addTearDown(container.dispose);

      await container.read(sessionListControllerProvider.future);
      final controller = container.read(chatControllerProvider('s1').notifier);

      expect(await controller.renameSession('新标题'), isFalse);
      expect(_listState(container).sessions.single.title, '旧标题');
    });

    test('置顶成功 → 同行 pinned 即时翻转，不触发全量拉取', () async {
      final chatApi = FakeChatApi();
      final sessionApi = FakeSessionListApi(
        sessions: [
          const SessionSummary(
            sessionId: 's1',
            title: '会话',
            pinned: false,
            createdAt: 1000,
          ),
        ],
      );
      final container = _makeContainer(chatApi, sessionApi);
      addTearDown(container.dispose);

      await container.read(sessionListControllerProvider.future);
      final before = sessionApi.fetchCount;
      final controller = container.read(chatControllerProvider('s1').notifier);

      expect(await controller.setPinned(true), isTrue);
      expect(_listState(container).sessions.single.pinned, isTrue);
      expect(sessionApi.fetchCount, before);
    });

    test('归档成功 → 该行从普通列表移除（返回列表即对上）', () async {
      final chatApi = FakeChatApi();
      final sessionApi = FakeSessionListApi(
        sessions: [
          const SessionSummary(
            sessionId: 's1',
            title: '要归档',
            createdAt: 1000,
          ),
          const SessionSummary(
            sessionId: 's2',
            title: '保留',
            createdAt: 900,
          ),
        ],
      );
      final container = _makeContainer(chatApi, sessionApi);
      addTearDown(container.dispose);

      await container.read(sessionListControllerProvider.future);
      final before = sessionApi.fetchCount;
      final controller = container.read(chatControllerProvider('s1').notifier);

      expect(await controller.setArchived(true), isTrue);
      final ids =
          _listState(container).sessions.map((s) => s.sessionId).toList();
      expect(ids, isNot(contains('s1')));
      expect(ids, contains('s2'));
      expect(sessionApi.fetchCount, before);
    });

    test('取消归档成功 → 该行 archived=false（不凭空造行）', () async {
      final chatApi = FakeChatApi();
      final sessionApi = FakeSessionListApi(
        sessions: [
          const SessionSummary(
            sessionId: 's1',
            title: '已归档',
            archived: true,
            createdAt: 1000,
          ),
        ],
      );
      final container = _makeContainer(chatApi, sessionApi);
      addTearDown(container.dispose);

      // FakeSessionListApi 普通模式过滤掉 archived 行：初始列表为空。
      await container.read(sessionListControllerProvider.future);
      expect(_listState(container).sessions, isEmpty);

      final controller = container.read(chatControllerProvider('s1').notifier);
      expect(await controller.setArchived(false), isTrue);
      // 普通列表无此行 → 不插入造行（等全量刷新补全）。
      expect(_listState(container).sessions, isEmpty);
    });

    test('删除成功 → 该行从列表移除', () async {
      final chatApi = FakeChatApi();
      final sessionApi = FakeSessionListApi(
        sessions: [
          const SessionSummary(
            sessionId: 's1',
            title: '要删除',
            createdAt: 1000,
          ),
          const SessionSummary(
            sessionId: 's2',
            title: '保留',
            createdAt: 900,
          ),
        ],
      );
      final container = _makeContainer(chatApi, sessionApi);
      addTearDown(container.dispose);

      await container.read(sessionListControllerProvider.future);
      final before = sessionApi.fetchCount;
      final controller = container.read(chatControllerProvider('s1').notifier);

      expect(await controller.deleteSession(), isTrue);
      final ids =
          _listState(container).sessions.map((s) => s.sessionId).toList();
      expect(ids, isNot(contains('s1')));
      expect(ids, contains('s2'));
      expect(sessionApi.fetchCount, before);
    });

    test('分支成功 → 新会话插到列表顶部（缺时间戳兜底现在）', () async {
      final chatApi = FakeChatApi();
      final sessionApi = FakeSessionListApi(
        sessions: [
          const SessionSummary(
            sessionId: 's1',
            title: '原会话',
            createdAt: 1000,
          ),
        ],
      );
      final container = _makeContainer(chatApi, sessionApi);
      addTearDown(container.dispose);

      await container.read(sessionListControllerProvider.future);
      final before = sessionApi.fetchCount;
      final controller = container.read(chatControllerProvider('s1').notifier);

      // FakeChatApi 默认 branchResponse：sessionId='branch-s1'，无标题。
      final newId = await controller.branchSession();
      expect(newId, 'branch-s1');
      final list = _listState(container).sessions;
      expect(list.first.sessionId, 'branch-s1');
      // 缺服务端标题 → 兜底 '<原标题> (fork)'。
      expect(list.first.title, isNotNull);
      expect(sessionApi.fetchCount, before);
    });

    test('列表尚未就绪（冷启动错误态）→ 聊天页操作不抛错', () async {
      final chatApi = FakeChatApi();
      final sessionApi = FakeSessionListApi(sessions: const []);
      final container = _makeContainer(chatApi, sessionApi);
      addTearDown(container.dispose);

      // 不等待 sessionListControllerProvider.future：state 为 loading/无值。
      final controller = container.read(chatControllerProvider('s1').notifier);
      expect(await controller.renameSession('新标题'), isTrue);
      expect(await controller.setPinned(true), isTrue);
      expect(await controller.deleteSession(), isTrue);
    });
  });
}
