import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/api/sse_client.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/connections/server_connection.dart';
import 'package:hermes_ui/core/models/session.dart';
import 'package:hermes_ui/features/chat/chat_controller.dart';
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

/// 完成一整个回合：send → done → stream_end，并等事件链落定。
///
/// 直接传 controller 实例，避免按 provider id 重读产生新实例
/// （pending 集合是 controller 实例级状态，必须用同一实例）。
Future<void> _runTurn(
  FakeChatApi chatApi,
  ChatController controller,
  String sessionId,
) async {
  await controller.send('你好');
  chatApi.emit(
    DoneSseEvent(DoneStreamEvent(session: {'session_id': sessionId})),
  );
  chatApi.emit(const StreamEndSseEvent());
  await Future<void>.delayed(const Duration(milliseconds: 20));
}

void main() {
  group('#30 存量会话回合完成 → 会话列表刷新', () {
    test('存量会话 done 完成 → 立即一次强制刷新（窗口内不重复）', () async {
      final chatApi = FakeChatApi();
      chatApi.startChatResult = {'stream_id': 'stream-1', 'session_id': 's1'};
      final sessionApi = FakeSessionListApi(
        sessions: [
          const SessionSummary(sessionId: 's1', title: '存量', createdAt: 1000),
        ],
      );
      final container = _makeChatAndSessionContainer(chatApi, sessionApi);
      addTearDown(container.dispose);

      await container.read(sessionListControllerProvider.future);
      final before = sessionApi.fetchCount;
      final controller = container.read(chatControllerProvider('s1').notifier);

      // done 收尾 → 立即触发一次强制刷新（需求：存量会话也刷新）。
      await _runTurn(chatApi, controller, 's1');
      expect(sessionApi.fetchCount, before + 1);

      // 节流窗口内同会话再完成 → 合并，不再二次刷新。
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await _runTurn(chatApi, controller, 's1');
      expect(sessionApi.fetchCount, before + 1);

      // 窗口结束后无延迟触发残留（无 Timer 方案，防 FakeAsync 误报）。
      await Future<void>.delayed(const Duration(milliseconds: 1700));
      expect(sessionApi.fetchCount, before + 1);
    });

    test('节流窗口过期后再次完成 → 恢复触发刷新', () async {
      final chatApi = FakeChatApi();
      chatApi.startChatResult = {'stream_id': 'stream-1', 'session_id': 's1'};
      final sessionApi = FakeSessionListApi(
        sessions: [
          const SessionSummary(sessionId: 's1', title: '存量', createdAt: 1000),
        ],
      );
      final container = _makeChatAndSessionContainer(chatApi, sessionApi);
      addTearDown(container.dispose);

      await container.read(sessionListControllerProvider.future);
      final before = sessionApi.fetchCount;
      final controller = container.read(chatControllerProvider('s1').notifier);

      // 第一次完成 → 立即刷新。
      await _runTurn(chatApi, controller, 's1');
      // 300ms 后同会话再完成 → 仍在窗口内 → 合并跳过。
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await _runTurn(chatApi, controller, 's1');
      expect(sessionApi.fetchCount, before + 1);

      // 窗口过期后再次完成 → 恢复触发（累计两次刷新）。
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      await _runTurn(chatApi, controller, 's1');
      expect(sessionApi.fetchCount, before + 2);
    });

    test('并发多会话完成 → 窗口内合并为一次刷新', () async {
      final chatApi = FakeChatApi();
      chatApi.startChatResult = {'stream_id': 'stream-1', 'session_id': 's1'};
      final sessionApi = FakeSessionListApi(
        sessions: [
          const SessionSummary(sessionId: 's1', title: '存量', createdAt: 1000),
        ],
      );
      final container = _makeChatAndSessionContainer(chatApi, sessionApi);
      addTearDown(container.dispose);

      await container.read(sessionListControllerProvider.future);
      final before = sessionApi.fetchCount;
      final controller1 = container.read(chatControllerProvider('s1').notifier);

      // 会话 s1 完成 → 立即刷新。
      await _runTurn(chatApi, controller1, 's1');
      expect(sessionApi.fetchCount, before + 1);

      // 窗口内会话 s2（另一 Controller 实例）完成 → 合并进先到的刷新。
      final controller2 = container.read(chatControllerProvider('s2').notifier);
      chatApi.startChatResult = {'stream_id': 'stream-2', 'session_id': 's2'};
      await controller2.send('也来一条');
      chatApi.emit(
        const DoneSseEvent(DoneStreamEvent(session: {'session_id': 's2'})),
      );
      chatApi.emit(const StreamEndSseEvent());
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(sessionApi.fetchCount, before + 1);
    });

    test('新建会话（pending）done 收尾 → 立即刷新，不受节流窗口约束', () async {
      final chatApi = FakeChatApi();
      chatApi.startChatResult = {
        'stream_id': 'stream-new',
        'session_id': 'sess-new-42',
      };
      final sessionApi = FakeSessionListApi(sessions: const []);
      final container = _makeChatAndSessionContainer(chatApi, sessionApi);
      addTearDown(container.dispose);

      await container.read(sessionListControllerProvider.future);
      final controller = container.read(chatControllerProvider('').notifier);
      await controller.send('首条');

      // 等创建路径「立即 + 600ms 双次补拉」落定，再快照基线。
      await Future<void>.delayed(const Duration(milliseconds: 750));
      final before = sessionApi.fetchCount;

      // 首条流的 done 收尾 → pending 路径立即强制刷新（不受 1.5s 节流
      // 窗口约束）。必须用同一 '' 实例：pending 集合是 Controller 实例
      // 级状态。
      chatApi.emit(
        const DoneSseEvent(
          DoneStreamEvent(session: {'session_id': 'sess-new-42'}),
        ),
      );
      chatApi.emit(const StreamEndSseEvent());
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(
        sessionApi.fetchCount,
        greaterThanOrEqualTo(before + 1),
        reason: '新建会话双次补拉语义不能被节流破坏：收尾刷新必须立即发生',
      );
    });
  });
}
