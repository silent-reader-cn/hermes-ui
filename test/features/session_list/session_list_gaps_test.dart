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
          // 列表页 watch 项目（筛选 chips）：无 projectApi 时用空 stub，
          // 避免真实 ApiClient 发出 dio 请求残留超时 Timer。
          projectApiFactoryProvider.overrideWithValue(
            (_) => projectApi ?? _FakeProjectApi(),
          ),
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
    String? projectId,
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
      projectId: projectId,
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
      expect(
        find.byKey(const ValueKey('filter-chip-telegram')),
        findsOneWidget,
      );
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

      await tester.tap(find.textContaining('已归档'));
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

      expect(api.archiveCalls.where((c) => c.endsWith(':true')), hasLength(2));
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
      final api = FakeSessionListApi(sessions: [session('s1', '会话一')]);
      await pumpList(tester, api);

      await tester.longPress(find.byKey(const ValueKey('session-row-s1')));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('session-list-selection-done')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey('session-list-selection-done')),
      );
      await tester.pump();
      expect(find.byKey(const ValueKey('batch-archive')), findsNothing);
      expect(
        find.byKey(const ValueKey('session-list-settings')),
        findsOneWidget,
      );
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

      expect(find.byKey(const ValueKey('project-picker-p1')), findsOneWidget);
      expect(find.text('游戏'), findsWidgets);
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

  group('搜索高亮与深链', () {
    testWidgets('搜索命中标题关键词高亮（TextSpan）+ 点击带 q 深链跳转', (tester) async {
      final api = FakeSessionListApi();
      api.searchResults['flutter'] = [session('s1', '今天修了 Flutter 样式问题')];
      await pumpList(tester, api);

      // 输入关键词触发搜索（FakeSessionListApi 同步返回命中）
      await tester.enterText(
        find.byKey(const ValueKey('session-list-search')),
        'flutter',
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));

      // 标题命中片段被拆成 RichText（含高亮 TextSpan，大小写不敏感）
      final rich = tester
          .widgetList<Text>(find.byType(Text))
          .where(
            (t) =>
                t.textSpan != null &&
                t.textSpan!.toPlainText().toLowerCase().contains('flutter'),
          );
      expect(rich, isNotEmpty);

      // 点击命中行 → 跳 /chat/s1?q=flutter&match=title
      await tester.tap(find.byKey(const ValueKey('session-row-s1')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('chat-s1'), findsWidgets);
    });

    testWidgets('content 命中行点击 → 深链带 match=content', (tester) async {
      final api = FakeSessionListApi();
      api.searchResults['flutter'] = [
        SessionSummary(
          sessionId: 's2',
          title: '标题不含关键词',
          matchType: 'content',
          matchPreview: '正文命中 flutter 片段',
          createdAt: (DateTime.now().millisecondsSinceEpoch / 1000) - 3600,
        ),
      ];
      await pumpList(tester, api);

      await tester.enterText(
        find.byKey(const ValueKey('session-list-search')),
        'flutter',
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));

      // 摘录展示在元数据行
      expect(find.textContaining('正文命中'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('session-row-s2')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('chat-s2'), findsWidgets);
    });
  });

  group('项目筛选与 CRUD', () {
    testWidgets('有项目时显示项目 chips，点击 → 项目筛选', (tester) async {
      final api = FakeSessionListApi(
        sessions: [session('s1', '会话一', projectId: 'p1')],
      );
      final projectApi = _FakeProjectApi(
        projects: [const ProjectSummary(projectId: 'p1', name: '游戏')],
      );
      await pumpList(tester, api, projectApi: projectApi);

      expect(find.byKey(const ValueKey('project-chip-p1')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('project-chip-p1')));
      await tester.pump();
      expect(find.byKey(const ValueKey('session-row-s1')), findsOneWidget);
    });

    testWidgets('picker 长按项目行 → 重命名（调用 rename）', (tester) async {
      final api = FakeSessionListApi(sessions: [session('s1', '会话一')]);
      final projectApi = _FakeProjectApi(
        projects: [const ProjectSummary(projectId: 'p1', name: '旧名')],
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

      // 长按项目行 → 管理菜单 → 重命名 → 输入新名 → 保存
      await tester.longPress(find.byKey(const ValueKey('project-picker-p1')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.byKey(const ValueKey('project-action-rename')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('project-action-rename')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.enterText(
        find.byKey(const ValueKey('project-create-name')),
        '新名',
      );
      await tester.tap(find.byKey(const ValueKey('project-create-confirm')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(projectApi.renamedName, '新名');
    });

    testWidgets('picker 长按项目行 → 删除（确认后调用 delete）', (tester) async {
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

      await tester.longPress(find.byKey(const ValueKey('project-picker-p1')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const ValueKey('project-action-delete')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.byKey(const ValueKey('project-delete-confirm')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('project-delete-confirm')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(projectApi.deletedIds, ['p1']);
    });
  });

  group('已归档 count', () {
    testWidgets('segmented 显示已归档数量角标', (tester) async {
      final api = FakeSessionListApi(
        sessions: [
          session('a1', '归档A', archived: true),
          session('a2', '归档B', archived: true),
          session('s1', '普通'),
        ],
      );
      await pumpList(tester, api);
      expect(find.textContaining('已归档 (2)'), findsOneWidget);
    });
  });
}

class _ChatStub extends StatelessWidget {
  const _ChatStub({required this.sessionId});

  final String sessionId;

  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    navigationBar: CupertinoNavigationBar(middle: Text('chat-$sessionId')),
    child: const SizedBox(),
  );
}

class _FakeProjectApi implements ProjectApi {
  _FakeProjectApi({this.projects = const []});

  List<ProjectSummary> projects;

  /// 最近一次重命名的目标名称（断言用）。
  String? renamedName;

  /// 已删除的项目 id（断言用）。
  final List<String> deletedIds = [];

  @override
  Future<ProjectsResponse> fetchProjects() async {
    return ProjectsResponse(projects: projects);
  }

  @override
  Future<ProjectMutationResponse> createProject({
    required String name,
    String? color,
  }) async {
    return const ProjectMutationResponse(ok: true, project: null);
  }

  @override
  Future<ProjectMutationResponse> renameProject({
    required String projectId,
    required String name,
    String? color,
  }) async {
    renamedName = name;
    return const ProjectMutationResponse();
  }

  @override
  Future<ProjectMutationResponse> deleteProject(String projectId) async {
    deletedIds.add(projectId);
    return const ProjectMutationResponse();
  }
}
