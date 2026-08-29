import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/api/api_exception.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/models/session.dart';
import 'package:hermes_ui/core/models/workspace.dart';
import 'package:hermes_ui/features/projects/project_providers.dart';
import 'package:hermes_ui/features/session_list/session_list_page.dart';
import 'package:hermes_ui/features/session_list/session_list_providers.dart';

import '../../helpers/fake_session_list_api.dart';

SessionSummary _buildSession(
  String id,
  String title, {
  String? workspace,
  DateTime? at,
}) {
  return SessionSummary(
    sessionId: id,
    title: title,
    workspace: workspace,
    lastMessageAt: at == null ? 0.0 : at.millisecondsSinceEpoch / 1000,
  );
}

class _ChatStub extends StatelessWidget {
  const _ChatStub({required this.sessionId});

  final String sessionId;

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(middle: Text('chat-$sessionId')),
      child: const Center(child: Text('聊天占位')),
    );
  }
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

void main() {
  group('rankWorkspaces 工作区使用频率排序与截断', () {
    test('按使用频率降序，频率相同按最近使用时间降序，未使用的保序，截取前 6 个', () {
      final now = DateTime(2026, 8, 29, 12);
      final registered = [
        const WorkspaceRoot(path: '/ws/zero1', name: 'Zero 1'),
        const WorkspaceRoot(path: '/ws/popular', name: 'Popular'),
        const WorkspaceRoot(path: '/ws/recent', name: 'Recent'),
        const WorkspaceRoot(path: '/ws/old', name: 'Old'),
        const WorkspaceRoot(path: '/ws/zero2', name: 'Zero 2'),
        const WorkspaceRoot(path: '/ws/zero3', name: 'Zero 3'),
        const WorkspaceRoot(path: '/ws/zero4', name: 'Zero 4 (overflow)'),
      ];

      final sessions = [
        // popular: 3 次
        _buildSession('s1', 'A', workspace: '/ws/popular', at: now.subtract(const Duration(days: 3))),
        _buildSession('s2', 'B', workspace: '/ws/popular', at: now.subtract(const Duration(days: 2))),
        _buildSession('s3', 'C', workspace: '/ws/popular', at: now.subtract(const Duration(days: 1))),
        // recent: 1 次，时间较新
        _buildSession('s4', 'D', workspace: '/ws/recent', at: now),
        // old: 1 次，时间较旧
        _buildSession('s5', 'E', workspace: '/ws/old', at: now.subtract(const Duration(days: 10))),
      ];

      final ranked = rankWorkspaces(
        registered: registered,
        sessions: sessions,
        maxItems: 6,
      );

      expect(ranked.map((w) => w.path).toList(), [
        '/ws/popular', // freq = 3
        '/ws/recent',  // freq = 1, newer
        '/ws/old',     // freq = 1, older
        '/ws/zero1',   // freq = 0, first in list
        '/ws/zero2',   // freq = 0, second in list
        '/ws/zero3',   // freq = 0, third in list
      ]);
      expect(ranked.length, 6);
    });

    test('空输入或空路径安全容错', () {
      expect(rankWorkspaces(registered: const [], sessions: const []), isEmpty);

      final withInvalid = [
        const WorkspaceRoot(path: null, name: 'Null Path'),
        const WorkspaceRoot(path: '   ', name: 'Empty Path'),
        const WorkspaceRoot(path: '/ws/valid', name: 'Valid'),
      ];
      final ranked = rankWorkspaces(registered: withInvalid, sessions: const []);
      expect(ranked.length, 1);
      expect(ranked.first.path, '/ws/valid');
    });
  });

  group('SessionListController createSession with workspace', () {
    test('创建带 workspace 的会话成功：插入列表顶部并记录 workspace', () async {
      final api = FakeSessionListApi(sessions: [_buildSession('s1', '老会话')]);
      api.createdSession = const SessionSummary(sessionId: 'new-ws-1', title: '新工作区会话');

      final container = ProviderContainer(
        overrides: [
          apiClientProvider.overrideWithValue(
            ApiClient(baseUrl: 'http://test.local:30002'),
          ),
          sessionListApiFactoryProvider.overrideWithValue((_) => api),
          projectApiFactoryProvider.overrideWithValue((_) => _StubProjectApi()),
        ],
      );
      addTearDown(container.dispose);

      await container.read(sessionListControllerProvider.future);
      final controller = container.read(sessionListControllerProvider.notifier);

      final id = await controller.createSession(workspace: '/custom/workspace');
      expect(id, 'new-ws-1');
      expect(api.createCount, 1);
      expect(api.lastCreatedWorkspace, '/custom/workspace');

      final sessions = container.read(sessionListControllerProvider).valueOrNull!.sessions;
      expect(sessions.first.sessionId, 'new-ws-1');
      expect(sessions.first.workspace, '/custom/workspace');
    });

    test('创建带 workspace 失败：抛出 ApiException 记录 actionError', () async {
      final api = FakeSessionListApi(sessions: [_buildSession('s1', '老会话')]);
      api.createError = HttpException(400, null, message: '工作区不存在');

      final container = ProviderContainer(
        overrides: [
          apiClientProvider.overrideWithValue(
            ApiClient(baseUrl: 'http://test.local:30002'),
          ),
          sessionListApiFactoryProvider.overrideWithValue((_) => api),
          projectApiFactoryProvider.overrideWithValue((_) => _StubProjectApi()),
        ],
      );
      addTearDown(container.dispose);

      await container.read(sessionListControllerProvider.future);
      final controller = container.read(sessionListControllerProvider.notifier);

      final id = await controller.createSession(workspace: '/bad/workspace');
      expect(id, isNull);
      final state = container.read(sessionListControllerProvider).valueOrNull!;
      expect(state.actionError, '工作区不存在');
    });
  });

  group('SessionListPage FAB 工作区长按滑选交互', () {
    Future<void> pumpSessionListPage(
      WidgetTester tester,
      FakeSessionListApi api,
    ) async {
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(path: '/', builder: (_, _) => const SessionListPage()),
          GoRoute(
            path: '/chat',
            builder: (_, _) => const _ChatStub(sessionId: ''),
          ),
          GoRoute(
            path: '/chat/:sessionId',
            builder: (_, state) =>
                _ChatStub(sessionId: state.pathParameters['sessionId'] ?? ''),
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(
              ApiClient(baseUrl: 'http://test.local:30002'),
            ),
            sessionListApiFactoryProvider.overrideWithValue((_) => api),
            projectApiFactoryProvider.overrideWithValue((_) => _StubProjectApi()),
          ],
          child: CupertinoApp.router(routerConfig: router),
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    testWidgets('短按 FAB (<350ms)：直接新建无 workspace 会话并跳转', (tester) async {
      final api = FakeSessionListApi(sessions: [_buildSession('s1', '会话 1')]);
      api.createdSession = const SessionSummary(sessionId: 'default-1', title: '默认会话');
      api.workspaces = [const WorkspaceRoot(path: '/ws/1', name: 'W1')];

      await pumpSessionListPage(tester, api);

      await tester.tap(find.byKey(const ValueKey('session-list-new')));
      await tester.pumpAndSettle();

      expect(api.createCount, 1);
      expect(api.lastCreatedWorkspace, isNull);
      expect(find.text('chat-default-1'), findsOneWidget);
      expect(find.byKey(const ValueKey('fab-workspace-menu')), findsNothing);
    });

    testWidgets('长按 FAB (≥350ms) 弹出弧形菜单，滑动选中某工作区松开即创建', (tester) async {
      final api = FakeSessionListApi(
        sessions: [
          _buildSession('s1', '会话 1', workspace: '/ws/code'),
        ],
      );
      api.createdSession = const SessionSummary(sessionId: 'ws-sess-1', title: '工作区会话');
      api.workspaces = [
        const WorkspaceRoot(path: '/ws/code', name: 'Code Repo'),
        const WorkspaceRoot(path: '/ws/docs', name: 'Docs Repo'),
      ];

      await pumpSessionListPage(tester, api);

      final fabFinder = find.byKey(const ValueKey('session-list-new'));
      expect(fabFinder, findsOneWidget);
      final fabCenter = tester.getCenter(fabFinder);

      // 按住 FAB
      final gesture = await tester.startGesture(fabCenter);
      // 等待超过 350ms 长按阈值
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      // 菜单弹出
      expect(find.byKey(const ValueKey('fab-workspace-menu')), findsOneWidget);
      final itemCode = find.byKey(const ValueKey('fab-workspace-item-/ws/code'));
      final itemDocs = find.byKey(const ValueKey('fab-workspace-item-/ws/docs'));
      expect(itemCode, findsOneWidget);
      expect(itemDocs, findsOneWidget);

      // 滑动到 /ws/code 处
      final itemCodeCenter = tester.getCenter(itemCode);
      await gesture.moveTo(itemCodeCenter);
      await tester.pump(const Duration(milliseconds: 150));

      // 松开
      await gesture.up();
      await tester.pumpAndSettle();

      // 菜单收起，以 /ws/code 新建会话并跳转
      expect(find.byKey(const ValueKey('fab-workspace-menu')), findsNothing);
      expect(api.createCount, 1);
      expect(api.lastCreatedWorkspace, '/ws/code');
      expect(find.text('chat-ws-sess-1'), findsOneWidget);
    });

    testWidgets('长按 FAB 弹出菜单后滑动到空白无效区松开：取消创建，不跳页', (tester) async {
      final api = FakeSessionListApi(sessions: [_buildSession('s1', '会话 1')]);
      api.workspaces = [
        const WorkspaceRoot(path: '/ws/code', name: 'Code Repo'),
      ];

      await pumpSessionListPage(tester, api);

      final fabFinder = find.byKey(const ValueKey('session-list-new'));
      final fabCenter = tester.getCenter(fabFinder);

      final gesture = await tester.startGesture(fabCenter);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      expect(find.byKey(const ValueKey('fab-workspace-menu')), findsOneWidget);

      // 拖拽到左上远端无效区（例如 (10, 10)）
      await gesture.moveTo(const Offset(10, 10));
      await tester.pump(const Duration(milliseconds: 100));

      await gesture.up();
      await tester.pumpAndSettle();

      // 菜单收起，未创建会话
      expect(find.byKey(const ValueKey('fab-workspace-menu')), findsNothing);
      expect(api.createCount, 0);
      expect(find.text('chat-'), findsNothing);
    });

    testWidgets('工作区为空或拉取失败时长按 FAB：不弹菜单，松开走普通新建会话', (tester) async {
      final api = FakeSessionListApi(sessions: [_buildSession('s1', '会话 1')]);
      api.createdSession = const SessionSummary(sessionId: 'fallback-1', title: '兜底会话');
      api.workspaces = const []; // 空工作区

      await pumpSessionListPage(tester, api);

      final fabFinder = find.byKey(const ValueKey('session-list-new'));
      final fabCenter = tester.getCenter(fabFinder);

      final gesture = await tester.startGesture(fabCenter);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      // 不弹菜单
      expect(find.byKey(const ValueKey('fab-workspace-menu')), findsNothing);

      await gesture.up();
      await tester.pumpAndSettle();

      // 松开正常建会话
      expect(api.createCount, 1);
      expect(api.lastCreatedWorkspace, isNull);
      expect(find.text('chat-fallback-1'), findsOneWidget);
    });

    testWidgets('长按滑选创建会话失败：显示错误弹窗，不跳页', (tester) async {
      final api = FakeSessionListApi(sessions: [_buildSession('s1', '会话 1')]);
      api.createError = HttpException(500, null, message: '工作区创建服务故障');
      api.workspaces = [
        const WorkspaceRoot(path: '/ws/err', name: 'Err Repo'),
      ];

      await pumpSessionListPage(tester, api);

      final fabFinder = find.byKey(const ValueKey('session-list-new'));
      final fabCenter = tester.getCenter(fabFinder);

      final gesture = await tester.startGesture(fabCenter);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      final itemFinder = find.byKey(const ValueKey('fab-workspace-item-/ws/err'));
      await gesture.moveTo(tester.getCenter(itemFinder));
      await tester.pump(const Duration(milliseconds: 100));

      await gesture.up();
      await tester.pump();
      await tester.pump();

      expect(find.text('操作失败'), findsOneWidget);
      expect(find.text('工作区创建服务故障'), findsOneWidget);
      expect(find.text('chat-'), findsNothing);

      // 关闭错误弹窗
      await tester.tap(find.text('好'));
      await tester.pumpAndSettle();
      expect(find.text('操作失败'), findsNothing);
    });

    testWidgets('多选模式下长按 FAB：不弹出工作区菜单', (tester) async {
      final api = FakeSessionListApi(sessions: [_buildSession('s1', '会话 1')]);
      api.workspaces = [const WorkspaceRoot(path: '/ws/1', name: 'W1')];

      await pumpSessionListPage(tester, api);

      // 长按会话行进入多选模式
      await tester.longPress(find.byKey(const ValueKey('session-row-s1')));
      await tester.pumpAndSettle();

      final fabFinder = find.byKey(const ValueKey('session-list-new'));
      final fabCenter = tester.getCenter(fabFinder);

      final gesture = await tester.startGesture(fabCenter);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      // 多选模式下长按不弹菜单
      expect(find.byKey(const ValueKey('fab-workspace-menu')), findsNothing);

      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('在多个工作区项间滑动：高亮跟随切换并以最终选定项创建', (tester) async {
      final api = FakeSessionListApi(
        sessions: [
          _buildSession('s1', 'A', workspace: '/ws/one'),
          _buildSession('s2', 'B', workspace: '/ws/two'),
        ],
      );
      api.createdSession = const SessionSummary(sessionId: 'ws-two-id', title: 'Two');
      api.workspaces = [
        const WorkspaceRoot(path: '/ws/one', name: 'One'),
        const WorkspaceRoot(path: '/ws/two', name: 'Two'),
      ];

      await pumpSessionListPage(tester, api);

      final fabFinder = find.byKey(const ValueKey('session-list-new'));
      final fabCenter = tester.getCenter(fabFinder);

      final gesture = await tester.startGesture(fabCenter);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      expect(find.byKey(const ValueKey('fab-workspace-menu')), findsOneWidget);

      final item1 = find.byKey(const ValueKey('fab-workspace-item-/ws/one'));
      final item2 = find.byKey(const ValueKey('fab-workspace-item-/ws/two'));

      // 先滑到 item1
      await gesture.moveTo(tester.getCenter(item1));
      await tester.pump(const Duration(milliseconds: 100));

      // 再滑到 item2
      await gesture.moveTo(tester.getCenter(item2));
      await tester.pump(const Duration(milliseconds: 100));

      // 在 item2 松开
      await gesture.up();
      await tester.pumpAndSettle();

      expect(api.createCount, 1);
      expect(api.lastCreatedWorkspace, '/ws/two');
      expect(find.text('chat-ws-two-id'), findsOneWidget);
    });
  });
}
