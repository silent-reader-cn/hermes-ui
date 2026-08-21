import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hermex_flutter/core/api/api_client.dart';
import 'package:hermex_flutter/core/connections/connection_providers.dart';
import 'package:hermex_flutter/core/models/session.dart';
import 'package:hermex_flutter/features/projects/project_providers.dart';
import 'package:hermex_flutter/features/session_list/session_entry_visibility.dart';
import 'package:hermex_flutter/features/session_list/session_list_page.dart';
import 'package:hermex_flutter/features/session_list/session_list_providers.dart';
import 'package:hermex_flutter/features/session_list/session_list_utility_rows.dart';

import '../../helpers/fake_session_list_api.dart';

class _FilteredVisibilityNotifier extends SessionEntryVisibilityController {
  @override
  SessionEntryVisibility build() {
    return const SessionEntryVisibility(
      tasks: false,
      kanban: true,
      skills: true,
      insights: false,
    );
  }
}

class _AllVisibleVisibilityNotifier extends SessionEntryVisibilityController {
  @override
  SessionEntryVisibility build() {
    return const SessionEntryVisibility(
      tasks: true,
      kanban: true,
      skills: true,
      insights: true,
    );
  }
}

class _AllHiddenVisibilityNotifier extends SessionEntryVisibilityController {
  @override
  SessionEntryVisibility build() {
    return const SessionEntryVisibility(
      tasks: false,
      kanban: false,
      skills: false,
      insights: false,
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

class _DestinationStub extends StatelessWidget {
  const _DestinationStub({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(middle: Text('nav-$title')),
      child: Center(child: Text('body-$title')),
    );
  }
}

void main() {
  group('SessionListUtilityRows 独立组件测试', () {
    testWidgets('默认渲染 3 个入口（看板与记忆默认隐藏）', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: CupertinoApp(
            home: CupertinoPageScaffold(child: SessionListUtilityRows()),
          ),
        ),
      );

      // 默认 3 个入口文本（看板与记忆默认关闭）
      expect(find.text('任务'), findsOneWidget);
      expect(find.text('看板'), findsNothing);
      expect(find.text('技能'), findsOneWidget);
      expect(find.text('记忆'), findsNothing);
      expect(find.text('统计'), findsOneWidget);

      // 入口 Key
      expect(
        find.byKey(const ValueKey('session-list-utility-tasks')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('session-list-utility-kanban')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('session-list-utility-skills')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('session-list-utility-memory')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('session-list-utility-insights')),
        findsOneWidget,
      );
    });

    testWidgets('显式全开时渲染 4 个入口（含看板）', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionEntryVisibilityProvider.overrideWith(
              _AllVisibleVisibilityNotifier.new,
            ),
          ],
          child: const CupertinoApp(
            home: CupertinoPageScaffold(child: SessionListUtilityRows()),
          ),
        ),
      );

      expect(find.text('看板'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('session-list-utility-kanban')),
        findsOneWidget,
      );
    });

    testWidgets('自定义回调可正常触发', (tester) async {
      var tasksCalled = false;
      var kanbanCalled = false;
      var skillsCalled = false;
      var insightsCalled = false;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionEntryVisibilityProvider.overrideWith(
              _AllVisibleVisibilityNotifier.new,
            ),
          ],
          child: CupertinoApp(
            home: CupertinoPageScaffold(
              child: SessionListUtilityRows(
                onTapTasks: () => tasksCalled = true,
                onTapKanban: () => kanbanCalled = true,
                onTapSkills: () => skillsCalled = true,
                onTapInsights: () => insightsCalled = true,
              ),
            ),
          ),
        ),
      );

      await tester.tap(
        find.byKey(const ValueKey('session-list-utility-tasks')),
      );
      await tester.pump();
      expect(tasksCalled, isTrue);

      await tester.tap(
        find.byKey(const ValueKey('session-list-utility-kanban')),
      );
      await tester.pump();
      expect(kanbanCalled, isTrue);

      await tester.tap(
        find.byKey(const ValueKey('session-list-utility-skills')),
      );
      await tester.pump();
      expect(skillsCalled, isTrue);

      await tester.tap(
        find.byKey(const ValueKey('session-list-utility-insights')),
      );
      await tester.pump();
      expect(insightsCalled, isTrue);
    });

    testWidgets('可访问性语义：每个按钮具备 Semantics 标签', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionEntryVisibilityProvider.overrideWith(
              _AllVisibleVisibilityNotifier.new,
            ),
          ],
          child: const CupertinoApp(
            home: CupertinoPageScaffold(child: SessionListUtilityRows()),
          ),
        ),
      );

      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Semantics &&
              w.properties.button == true &&
              w.properties.label == '任务',
        ),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Semantics &&
              w.properties.button == true &&
              w.properties.label == '看板',
        ),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Semantics &&
              w.properties.button == true &&
              w.properties.label == '技能',
        ),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Semantics &&
              w.properties.button == true &&
              w.properties.label == '统计',
        ),
        findsOneWidget,
      );
    });

    testWidgets('按显隐配置过滤入口：关闭任务与统计，仅渲染其余 2 个', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionEntryVisibilityProvider.overrideWith(
              _FilteredVisibilityNotifier.new,
            ),
          ],
          child: const CupertinoApp(
            home: CupertinoPageScaffold(child: SessionListUtilityRows()),
          ),
        ),
      );

      expect(
        find.byKey(const ValueKey('session-list-utility-rows')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('session-list-utility-tasks')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('session-list-utility-kanban')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('session-list-utility-skills')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('session-list-utility-memory')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('session-list-utility-insights')),
        findsNothing,
      );
    });

    testWidgets('4 个功能入口全关时组件返回 SizedBox.shrink()（不渲染容器）', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionEntryVisibilityProvider.overrideWith(
              _AllHiddenVisibilityNotifier.new,
            ),
          ],
          child: const CupertinoApp(
            home: CupertinoPageScaffold(child: SessionListUtilityRows()),
          ),
        ),
      );

      expect(
        find.byKey(const ValueKey('session-list-utility-rows')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('session-list-utility-tasks')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('session-list-utility-kanban')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('session-list-utility-skills')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('session-list-utility-memory')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('session-list-utility-insights')),
        findsNothing,
      );
    });
  });

  group('SessionListPage 工具行集成测试与路由跳转', () {
    Future<GoRouter> pumpSessionListPage(
      WidgetTester tester, {
      FakeSessionListApi? api,
      Override? visibilityOverride,
    }) async {
      final fakeApi =
          api ??
          FakeSessionListApi(
            sessions: [
              SessionSummary(
                sessionId: 's-test-1',
                title: '测试会话 1',
                lastMessageAt: DateTime.now().millisecondsSinceEpoch / 1000,
              ),
            ],
          );

      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(path: '/', builder: (_, _) => const SessionListPage()),
          GoRoute(
            path: '/tasks',
            builder: (_, _) =>
                const _DestinationStub(title: 'TasksDestination'),
          ),
          GoRoute(
            path: '/kanban',
            builder: (_, _) =>
                const _DestinationStub(title: 'KanbanDestination'),
          ),
          GoRoute(
            path: '/skills',
            builder: (_, _) =>
                const _DestinationStub(title: 'SkillsDestination'),
          ),
          GoRoute(
            path: '/memory',
            builder: (_, _) =>
                const _DestinationStub(title: 'MemoryDestination'),
          ),
          GoRoute(
            path: '/insights',
            builder: (_, _) =>
                const _DestinationStub(title: 'InsightsDestination'),
          ),
          GoRoute(
            path: '/settings',
            builder: (_, _) =>
                const _DestinationStub(title: 'SettingsDestination'),
          ),
          GoRoute(
            path: '/chat',
            builder: (_, _) => const _DestinationStub(title: 'ChatNew'),
          ),
          GoRoute(
            path: '/chat/:sessionId',
            builder: (_, state) => const _DestinationStub(title: 'Chat_'),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(
              ApiClient(baseUrl: 'http://test.local:30002'),
            ),
            sessionListApiFactoryProvider.overrideWithValue((_) => fakeApi),
            projectApiFactoryProvider.overrideWithValue(
              (_) => _StubProjectApi(),
            ),
            ?visibilityOverride,
          ],
          child: CupertinoApp.router(routerConfig: router),
        ),
      );

      // 加载完成
      await tester.pump();
      await tester.pump();
      return router;
    }

    testWidgets('会话列表页正常加载时，默认 3 个工具行入口可见（看板与记忆默认隐藏）', (tester) async {
      await pumpSessionListPage(tester);

      expect(
        find.byKey(const ValueKey('session-list-utility-rows')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('session-list-utility-tasks')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('session-list-utility-kanban')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('session-list-utility-skills')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('session-list-utility-memory')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('session-list-utility-insights')),
        findsOneWidget,
      );
    });

    testWidgets('点击任务入口 → 跳转 /tasks', (tester) async {
      await pumpSessionListPage(tester);

      await tester.tap(
        find.byKey(const ValueKey('session-list-utility-tasks')),
      );
      await tester.pumpAndSettle();

      expect(find.text('body-TasksDestination'), findsOneWidget);
    });

    testWidgets('点击看板入口 → 跳转 /kanban', (tester) async {
      await pumpSessionListPage(
        tester,
        visibilityOverride: sessionEntryVisibilityProvider.overrideWith(
          _AllVisibleVisibilityNotifier.new,
        ),
      );

      await tester.tap(
        find.byKey(const ValueKey('session-list-utility-kanban')),
      );
      await tester.pumpAndSettle();

      expect(find.text('body-KanbanDestination'), findsOneWidget);
    });

    testWidgets('点击技能入口 → 跳转 /skills', (tester) async {
      await pumpSessionListPage(tester);

      await tester.tap(
        find.byKey(const ValueKey('session-list-utility-skills')),
      );
      await tester.pumpAndSettle();

      expect(find.text('body-SkillsDestination'), findsOneWidget);
    });

    testWidgets('点击统计入口 → 跳转 /insights', (tester) async {
      await pumpSessionListPage(tester);

      await tester.tap(
        find.byKey(const ValueKey('session-list-utility-insights')),
      );
      await tester.pumpAndSettle();

      expect(find.text('body-InsightsDestination'), findsOneWidget);
    });

    testWidgets('搜索模式下工具行隐藏，清空搜索后重新显示', (tester) async {
      await pumpSessionListPage(tester);

      expect(
        find.byKey(const ValueKey('session-list-utility-rows')),
        findsOneWidget,
      );

      // 输入搜索内容进入搜索模式
      await tester.enterText(
        find.byKey(const ValueKey('session-list-search')),
        '测试',
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      // 搜索模式下工具行应该隐藏
      expect(
        find.byKey(const ValueKey('session-list-utility-rows')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('session-list-utility-tasks')),
        findsNothing,
      );

      // 清空搜索内容退出搜索模式
      await tester.enterText(
        find.byKey(const ValueKey('session-list-search')),
        '',
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      // 工具行恢复显示
      expect(
        find.byKey(const ValueKey('session-list-utility-rows')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('session-list-utility-tasks')),
        findsOneWidget,
      );
    });

    testWidgets('会话列表页根据显隐配置仅展示开启的入口', (tester) async {
      await pumpSessionListPage(
        tester,
        visibilityOverride: sessionEntryVisibilityProvider.overrideWith(
          _FilteredVisibilityNotifier.new,
        ),
      );

      expect(
        find.byKey(const ValueKey('session-list-utility-rows')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('session-list-utility-tasks')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('session-list-utility-kanban')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('session-list-utility-skills')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('session-list-utility-memory')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('session-list-utility-insights')),
        findsNothing,
      );
    });

    testWidgets('会话列表页在全关功能入口时整行不渲染', (tester) async {
      await pumpSessionListPage(
        tester,
        visibilityOverride: sessionEntryVisibilityProvider.overrideWith(
          _AllHiddenVisibilityNotifier.new,
        ),
      );

      expect(
        find.byKey(const ValueKey('session-list-utility-rows')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('session-list-utility-tasks')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('session-list-utility-kanban')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('session-list-utility-skills')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('session-list-utility-memory')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('session-list-utility-insights')),
        findsNothing,
      );
    });
  });
}
