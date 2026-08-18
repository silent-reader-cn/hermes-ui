import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hermex_flutter/core/api/api_client.dart';
import 'package:hermex_flutter/core/connections/connection_providers.dart';
import 'package:hermex_flutter/core/models/session.dart';
import 'package:hermex_flutter/features/projects/project_providers.dart';
import 'package:hermex_flutter/features/session_list/session_list_page.dart';
import 'package:hermex_flutter/features/session_list/session_list_providers.dart';

import '../../helpers/fake_session_list_api.dart';

/// Phase2 会话列表 UI：筛选（归档/来源）、多选批量、项目移动、行 badge。
void main() {
  Future<void> pumpList(
    WidgetTester tester,
    FakeSessionListApi api, {
    _FakeProjectApi? projectApi,
  }) async {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (_, _) => const SessionListPage()),
        GoRoute(path: '/chat', builder: (_, _) => const _ChatStub(sessionId: '')),
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
          if (projectApi != null)
            projectApiFactoryProvider.overrideWithValue((_) => projectApi),
        ],
        child: CupertinoApp.router(routerConfig: router),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  SessionSummary session(
    String id,
    String title, {
    bool archived = false,
    String? sourceLabel,
    String? parentSessionId,
    bool readOnly = false,
    double? cost,
  }) {
    return SessionSummary(
      sessionId: id,
      title: title,
      archived: archived,
      sourceLabel: sourceLabel,
      parentSessionId: parentSessionId,
      readOnly: readOnly,
      isReadOnly: readOnly,
      estimatedCost: cost,
      createdAt: (DateTime.now().millisecondsSinceEpoch / 1000) - 3600,
    );
  }

  group('筛选栏', () {
    testWidgets('渲染：全部/已归档 segmented + 来源 chips', (tester) async {
      final api = FakeSessionListApi(
        sessions: [
          session('s1', '会话一', sourceLabel: 'telegram'),
          session('s2', '会话二', sourceLabel: 'qq'),
        ],
      );
      await pumpList(tester, api);

      expect(
        find.byKey(const ValueKey('session-list-filter-mode')),
        findsOneWidget,
      );
      expect(find.text('全部'), findsOneWidget);
      expect(find.text('已归档'), findsOneWidget);
      expect(find.byKey(const ValueKey('filter-chip-telegram')), findsOneWidget);
      expect(find.byKey(const ValueKey('filter-chip-qq')), findsOneWidget);
    });

    testWidgets('来源 chip 点击 → 只显示匹配会话 + 清除筛选 chip 出现', (tester) async {
      final api = FakeSessionListApi(
        sessions: [
          session('s1', '会话一', sourceLabel: 'telegram'),
          session('s2', '会话二', sourceLabel: 'qq'),
        ],
      );
      await pumpList(tester, api);

      await tester.tap(find.byKey(const ValueKey('filter-chip-telegram')));
      await tester.pump();

      expect(find.text('会话一'), findsOneWidget);
      expect(find.text('会话二'), findsNothing);
      expect(find.byKey(const ValueKey('filter-chip-clear')), findsOneWidget);

      // 清除筛选恢复
      await tester.tap(find.byKey(const ValueKey('filter-chip-clear')));
      await tester.pump();
      expect(find.text('会话二'), findsOneWidget);
    });

    testWidgets('归档模式：segmented 切换 → 拉取归档并展示归档会话 + 恢复归档菜单', (tester) async {
      final api = FakeSessionListApi(
        sessions: [
          session('s1', '普通会话'),
          session('a1', '归档会话A', archived: true),
          session('a2', '归档会话B', archived: true),
        ],
      );
      await pumpList(tester, api);

      await tester.tap(find.text('已归档'));
      await tester.pump();
      await tester.pump();

      expect(api.lastFetchedArchived, isTrue);
      expect(find.text('归档会话A'), findsOneWidget);
      expect(find.text('归档会话B'), findsOneWidget);
      expect(find.text('普通会话'), findsNothing);

      // 归档行菜单含「恢复归档」
      await tester.tap(find.byKey(const ValueKey('session-actions-a1')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.byKey(const ValueKey('session-action-unarchive')),
        findsOneWidget,
      );

      // 关闭菜单
      await tester.tap(find.text('取消'));
      await tester.pump(const Duration(milliseconds: 300));
    });
  });

  group('多选批量', () {
    testWidgets('长按行 → 多选模式：勾选圈 + 批量栏；确认批量归档', (tester) async {
      final api = FakeSessionListApi(
        sessions: [session('s1', '会话一'), session('s2', '会话二')],
      );
      await pumpList(tester, api);

      // 长按第一行进入多选
      await tester.longPress(find.byKey(const ValueKey('session-row-s1')));
      await tester.pump();

      expect(find.byIcon(CupertinoIcons.circle), findsOneWidget);
      expect(find.byKey(const ValueKey('batch-archive')), findsOneWidget);
      expect(find.byKey(const ValueKey('batch-delete')), findsOneWidget);
      expect(find.byKey(const ValueKey('batch-move')), findsOneWidget);

      // 再点第二行勾选
      await tester.tap(find.byKey(const ValueKey('session-row-s2')));
      await tester.pump();
      expect(find.text('已选 2 个'), findsOneWidget);

      // 批量归档确认
      await tester.tap(find.byKey(const ValueKey('batch-archive')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.byKey(const ValueKey('batch-archive-dialog')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('batch-archive-confirm')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        api.archiveCalls.where((c) => c.endsWith(':true')),
        hasLength(2),
      );
      // 多选模式退出（清空勾选）
      expect(find.text('已选 0 个'), findsNothing);
      expect(find.byKey(const ValueKey('batch-archive')), findsNothing);
    });

    testWidgets('批量删除：确认框显示数量 → 确认后调用删除', (tester) async {
      final api = FakeSessionListApi(
        sessions: [session('s1', '会话一'), session('s2', '会话二')],
      );
      await pumpList(tester, api);

      await tester.longPress(find.byKey(const ValueKey('session-row-s1')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('session-row-s2')));
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('batch-delete')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('2 个会话'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('batch-delete-confirm')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(api.deleteCalls, hasLength(2));
      expect(api.deleteCalls.toSet(), {'s1', 's2'});
    });

    testWidgets('取消按键退出多选', (tester) async {
      final api = FakeSessionListApi(
        sessions: [session('s1', '会话一')],
      );
      await pumpList(tester, api);

      await tester.longPress(find.byKey(const ValueKey('session-row-s1')));
      await tester.pump();
      expect(find.byKey(const ValueKey('session-list-selection-done')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('session-list-selection-done')));
      await tester.pump();
      expect(find.byKey(const ValueKey('batch-archive')), findsNothing);
      expect(find.byKey(const ValueKey('session-list-settings')), findsOneWidget);
    });
  });

  group('项目移动', () {
    testWidgets('行菜单 → 移动到项目 → picker 选择 → moveSession 调用', (tester) async {
      final api = FakeSessionListApi(sessions: [session('s1', '会话一')]);
      final projectApi = _FakeProjectApi(
        projects: [const ProjectSummary(projectId: 'p1', name: '游戏')],
      );
      await pumpList(tester, api, projectApi: projectApi);

      await tester.tap(find.byKey(const ValueKey('session-actions-s1')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(
        find.byKey(const ValueKey('session-action-move-project')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('游戏'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('project-picker-p1')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(api.moveCalls, ['s1:p1']);
    });

    testWidgets('批量移动项目：取消最后一个勾选 → 退出多选；勾选后调 batchMove', (tester) async {
      final api = FakeSessionListApi(sessions: [session('s1', '会话一')]);
      final projectApi = _FakeProjectApi(
        projects: [const ProjectSummary(projectId: 'p1', name: '游戏')],
      );
      await pumpList(tester, api, projectApi: projectApi);

      // 长按进入多选并勾选 → 再点一次取消 → 最后一个取消退出多选
      await tester.longPress(find.byKey(const ValueKey('session-row-s1')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('session-row-s1')));
      await tester.pump();
      expect(find.byKey(const ValueKey('batch-move')), findsNothing);

      // 重新进入多选 → 勾选 → 移动项目
      await tester.longPress(find.byKey(const ValueKey('session-row-s1')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('batch-move')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const ValueKey('project-picker-p1')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(api.moveCalls, ['s1:p1']);
    });
  });

  group('行 badge', () {
    testWidgets('分支/只读/待输入/成本 badge 渲染', (tester) async {
      final api = FakeSessionListApi(
        sessions: [
          session(
            's1',
            '分支会话',
            parentSessionId: 'p0',
            readOnly: true,
            cost: 1.25,
          ),
          session('s2', '待输入会话', sourceLabel: 'qq'),
        ],
      );
      await pumpList(tester, api);

      expect(find.byIcon(CupertinoIcons.arrow_2_squarepath), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.lock_fill), findsOneWidget);
      expect(find.textContaining('· \$1.25'), findsOneWidget);
      expect(find.textContaining('· qq'), findsOneWidget);
    });
  });
}

class _ChatStub extends StatelessWidget {
  const _ChatStub({required this.sessionId});

  final String sessionId;

  @override
  Widget build(BuildContext context) =>
      const CupertinoPageScaffold(child: SizedBox());
}

class _FakeProjectApi implements ProjectApi {
  _FakeProjectApi({this.projects = const []});

  List<ProjectSummary> projects;

  @override
  Future<ProjectsResponse> fetchProjects() async {
    return ProjectsResponse(projects: projects);
  }

  @override
  Future<ProjectMutationResponse> createProject({
    required String name,
    String? color,
  }) async {
    return const ProjectMutationResponse(
      ok: true,
      project: null,
    );
  }

  @override
  Future<ProjectMutationResponse> renameProject({
    required String projectId,
    required String name,
    String? color,
  }) async {
    return const ProjectMutationResponse();
  }

  @override
  Future<ProjectMutationResponse> deleteProject(String projectId) async {
    return const ProjectMutationResponse();
  }
}