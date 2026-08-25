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
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_session_list_api.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });
  SessionSummary session(
    String id,
    String title, {
    String? sourceLabel,
    String? projectId,
    bool archived = false,
  }) {
    return SessionSummary(
      sessionId: id,
      title: title,
      sourceLabel: sourceLabel,
      projectId: projectId,
      archived: archived,
      createdAt: (DateTime.now().millisecondsSinceEpoch / 1000) - 3600,
    );
  }

  Future<void> pumpList(
    WidgetTester tester,
    FakeSessionListApi api, {
    ProjectApi? projectApi,
  }) async {
    final router = GoRouter(
      initialLocation: '/',
      routes: [GoRoute(path: '/', builder: (_, _) => const SessionListPage())],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(
            ApiClient(baseUrl: 'http://test.local:30002'),
          ),
          sessionListApiFactoryProvider.overrideWithValue((_) => api),
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

  group('筛选弹窗三段等宽与选中回调', () {
    testWidgets('三段等宽：会话/渠道/项目 section 同宽同边距', (tester) async {
      final api = FakeSessionListApi(
        sessions: [
          session('s1', '会话一', sourceLabel: 'telegram', projectId: 'p1'),
          session('s2', '会话二', sourceLabel: 'qq', projectId: 'p2'),
        ],
      );
      final projectApi = _FakeProjectApi(
        projects: const [
          ProjectSummary(projectId: 'p1', name: '项目一'),
          ProjectSummary(projectId: 'p2', name: '项目二'),
        ],
      );
      await pumpList(tester, api, projectApi: projectApi);
      await tester.tap(
        find.byKey(const ValueKey('session-list-filter-trigger')),
      );
      await tester.pumpAndSettle();

      final sessionsSection = tester.getRect(
        find.byKey(const ValueKey('filter-section-sessions')),
      );
      final channelsSection = tester.getRect(
        find.byKey(const ValueKey('filter-section-channels')),
      );
      final projectsSection = tester.getRect(
        find.byKey(const ValueKey('filter-section-projects')),
      );

      // 三段等宽（同一横向内边距 → width 相等）
      expect(sessionsSection.width, closeTo(channelsSection.width, 1.0));
      expect(sessionsSection.width, closeTo(projectsSection.width, 1.0));
      // 同左对齐（insetGrouped 统一 16 边距）
      expect(sessionsSection.left, closeTo(channelsSection.left, 1.0));
      expect(sessionsSection.left, closeTo(projectsSection.left, 1.0));
      // 三段可见
      expect(
        find.byKey(const ValueKey('filter-section-sessions')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('filter-section-channels')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('filter-section-projects')),
        findsOneWidget,
      );
    });

    testWidgets('渠道列表行：纵向单选，checkmark 选中态', (tester) async {
      final api = FakeSessionListApi(
        sessions: [
          session('s1', '会话一', sourceLabel: 'telegram'),
          session('s2', '会话二', sourceLabel: 'qq'),
        ],
      );
      await pumpList(tester, api);
      await tester.tap(
        find.byKey(const ValueKey('session-list-filter-trigger')),
      );
      await tester.pumpAndSettle();

      // 渠道以列表行呈现，点击来源后弹层关闭并过滤
      expect(
        find.byKey(const ValueKey('filter-chip-telegram')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('filter-chip-qq')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('filter-chip-telegram')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('session-filter-sheet')), findsNothing);
      expect(find.text('会话一'), findsOneWidget);
      expect(find.text('会话二'), findsNothing);
    });

    testWidgets('项目列表行：选中回调正确，项目筛选生效', (tester) async {
      final api = FakeSessionListApi(
        sessions: [
          session('s1', '会话一', projectId: 'p1'),
          session('s2', '会话二', projectId: 'p2'),
        ],
      );
      final projectApi = _FakeProjectApi(
        projects: const [
          ProjectSummary(projectId: 'p1', name: '项目一'),
          ProjectSummary(projectId: 'p2', name: '项目二'),
        ],
      );
      await pumpList(tester, api, projectApi: projectApi);
      await tester.tap(
        find.byKey(const ValueKey('session-list-filter-trigger')),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('project-chip-p1')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('project-chip-p1')));
      await tester.pumpAndSettle();
      expect(find.text('会话一'), findsOneWidget);
      expect(find.text('会话二'), findsNothing);
    });

    testWidgets('选中态：在对应筛选下进入弹层，选中行展示 checkmark', (tester) async {
      final api = FakeSessionListApi(
        sessions: [session('s1', '会话一', sourceLabel: 'telegram')],
      );
      await pumpList(tester, api);
      await tester.tap(
        find.byKey(const ValueKey('session-list-filter-trigger')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('filter-chip-telegram')));
      await tester.pumpAndSettle();

      // 再次打开应显示清除筛选项
      await tester.tap(
        find.byKey(const ValueKey('session-list-filter-trigger')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('sheet-filter-clear')), findsOneWidget);
      // telegram 选中行应带 checkmark
      expect(find.byIcon(CupertinoIcons.checkmark_alt), findsWidgets);
    });

    testWidgets('去白条：弹层背景为 grouped 无底部白条残留', (tester) async {
      final api = FakeSessionListApi(
        sessions: [session('s1', '会话一', sourceLabel: 'telegram')],
      );
      await pumpList(tester, api);
      await tester.tap(
        find.byKey(const ValueKey('session-list-filter-trigger')),
      );
      await tester.pumpAndSettle();

      // 弹层根容器存在且可滚动内容紧凑（SizedBox 8 而非 16）
      final sheet = find.byKey(const ValueKey('session-filter-sheet'));
      expect(sheet, findsOneWidget);
      final sheetBox = tester.getRect(sheet);
      // 不应占满全屏（紧凑高度）
      expect(sheetBox.height, lessThan(600));
    });

    testWidgets(
      '分割线边距：三段 filter section 均配置 hasLeading: false（无 leading 图标缩进）',
      (tester) async {
        final api = FakeSessionListApi(
          sessions: [
            session('s1', '会话一', sourceLabel: 'telegram', projectId: 'p1'),
            session('s2', '会话二', sourceLabel: 'qq', projectId: 'p2'),
          ],
        );
        final projectApi = _FakeProjectApi(
          projects: const [
            ProjectSummary(projectId: 'p1', name: '项目一'),
            ProjectSummary(projectId: 'p2', name: '项目二'),
          ],
        );
        await pumpList(tester, api, projectApi: projectApi);
        await tester.tap(
          find.byKey(const ValueKey('session-list-filter-trigger')),
        );
        await tester.pumpAndSettle();

        final sessionsSection = tester.widget<CupertinoListSection>(
          find.byKey(const ValueKey('filter-section-sessions')),
        );
        final channelsSection = tester.widget<CupertinoListSection>(
          find.byKey(const ValueKey('filter-section-channels')),
        );
        final projectsSection = tester.widget<CupertinoListSection>(
          find.byKey(const ValueKey('filter-section-projects')),
        );

        // hasLeading: false 时 additionalDividerMargin 应为 14.0（而非默认 hasLeading: true 的 42.0）
        expect(sessionsSection.additionalDividerMargin, equals(14.0));
        expect(channelsSection.additionalDividerMargin, equals(14.0));
        expect(projectsSection.additionalDividerMargin, equals(14.0));
      },
    );
  });

  group('subagent 显示开关（默认关闭）', () {
    SessionSummary subagentSession(String id, String title) {
      return SessionSummary(
        sessionId: id,
        title: title,
        sourceLabel: 'Subagent',
        sourceTag: 'subagent',
        rawSource: 'subagent',
        createdAt: (DateTime.now().millisecondsSinceEpoch / 1000) - 1800,
      );
    }

    testWidgets('默认关闭：开关为 off，Subagent 渠道不出现', (tester) async {
      final api = FakeSessionListApi(
        sessions: [
          session('s1', '普通会话', sourceLabel: 'telegram'),
          subagentSession('sub1', '子代理会话'),
        ],
      );
      await pumpList(tester, api);
      await tester.tap(
        find.byKey(const ValueKey('session-list-filter-trigger')),
      );
      await tester.pumpAndSettle();

      final sw = tester.widget<CupertinoSwitch>(
        find.byKey(const ValueKey('session-filter-subagent-switch')),
      );
      expect(sw.value, isFalse);
      // 隐藏时渠道列表剔除 Subagent，普通渠道保留
      expect(find.byKey(const ValueKey('filter-chip-Subagent')), findsNothing);
      expect(
        find.byKey(const ValueKey('filter-chip-telegram')),
        findsOneWidget,
      );
      // 列表默认不展示子代理会话
      expect(find.text('子代理会话'), findsNothing);
    });

    testWidgets('切换开关：弹层不关闭、即时生效、持久化到 SharedPreferences', (tester) async {
      final api = FakeSessionListApi(
        sessions: [
          session('s1', '普通会话', sourceLabel: 'telegram'),
          subagentSession('sub1', '子代理会话'),
        ],
      );
      await pumpList(tester, api);
      await tester.tap(
        find.byKey(const ValueKey('session-list-filter-trigger')),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('session-filter-subagent-switch')),
      );
      await tester.pumpAndSettle();

      // 弹层保持打开，开关即时翻转
      expect(
        find.byKey(const ValueKey('session-filter-sheet')),
        findsOneWidget,
      );
      final sw = tester.widget<CupertinoSwitch>(
        find.byKey(const ValueKey('session-filter-subagent-switch')),
      );
      expect(sw.value, isTrue);
      // Subagent 渠道恢复出现
      expect(
        find.byKey(const ValueKey('filter-chip-Subagent')),
        findsOneWidget,
      );
      // 持久化
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('session_list_show_subagent'), isTrue);

      // 关闭弹层后列表展示子代理会话
      await tester.tap(
        find.byKey(const ValueKey('session-filter-sheet-close')),
      );
      await tester.pumpAndSettle();
      expect(find.text('子代理会话'), findsOneWidget);
      expect(find.text('普通会话'), findsOneWidget);
    });

    testWidgets('预置 prefs=true：打开弹层开关即开，Subagent 渠道出现', (tester) async {
      SharedPreferences.setMockInitialValues({
        'session_list_show_subagent': true,
      });
      final api = FakeSessionListApi(
        sessions: [
          session('s1', '普通会话', sourceLabel: 'telegram'),
          subagentSession('sub1', '子代理会话'),
        ],
      );
      await pumpList(tester, api);
      await tester.tap(
        find.byKey(const ValueKey('session-list-filter-trigger')),
      );
      await tester.pumpAndSettle();

      final sw = tester.widget<CupertinoSwitch>(
        find.byKey(const ValueKey('session-filter-subagent-switch')),
      );
      expect(sw.value, isTrue);
      expect(
        find.byKey(const ValueKey('filter-chip-Subagent')),
        findsOneWidget,
      );
    });
  });
}

class _FakeProjectApi implements ProjectApi {
  _FakeProjectApi({this.projects = const []});

  List<ProjectSummary> projects;

  @override
  Future<ProjectsResponse> fetchProjects() async =>
      ProjectsResponse(projects: projects);

  @override
  Future<ProjectMutationResponse> createProject({
    required String name,
    String? color,
  }) async => const ProjectMutationResponse(ok: true, project: null);

  @override
  Future<ProjectMutationResponse> deleteProject(String projectId) async =>
      const ProjectMutationResponse();

  @override
  Future<ProjectMutationResponse> renameProject({
    required String projectId,
    required String name,
    String? color,
  }) async => const ProjectMutationResponse();
}
