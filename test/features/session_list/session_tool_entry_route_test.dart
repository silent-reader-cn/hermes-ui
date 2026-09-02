import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hermes_ui/app/widgets/hermes_page_route.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/models/session.dart';
import 'package:hermes_ui/features/projects/project_providers.dart';
import 'package:hermes_ui/features/session_list/session_list_page.dart';
import 'package:hermes_ui/features/session_list/session_list_providers.dart';
import 'package:hermes_ui/features/shared/app_back_button.dart';
import 'package:hermes_ui/l10n/app_localizations.dart';

import '../../helpers/fake_session_list_api.dart';

/// 会话列表 → 顶层工具页（技能/设置/任务等）统一返回动画对齐（todo：#51）：
/// 窄屏（< kAdaptiveBreakpoint）进入工具页必须 `push` 真入栈 —— 返回时
/// `AppBackButton` 走 `pop()` 反向（工具页向右滑出、会话列表原地）而不是
/// `go()` 兜底把列表当新 route 正向盖上来。宽屏双栏保持 `go` 替换。
class _ToolStub extends StatelessWidget {
  const _ToolStub({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        leading: const AppBackButton(),
        middle: Text(label),
      ),
      child: Center(
        child: Text(
          'canPop=${context.canPop()}',
          key: const ValueKey('tool-canpop'),
        ),
      ),
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

GoRouter _buildRouter() {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => const SessionListPage(),
      ),
      GoRoute(
        path: '/skills',
        pageBuilder: (_, _) => HermesPage<void>(
          key: const ValueKey('tool-stub-skills'),
          builder: (_) => const _ToolStub(label: '技能'),
        ),
      ),
      GoRoute(
        path: '/settings',
        pageBuilder: (_, _) => HermesPage<void>(
          key: const ValueKey('tool-stub-settings'),
          builder: (_) => const _ToolStub(label: '设置'),
        ),
      ),
    ],
  );
}

Future<void> _pumpApp(
  WidgetTester tester, {
  required FakeSessionListApi api,
  required Size viewport,
}) async {
  tester.view.physicalSize = viewport;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final router = _buildRouter();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(
          ApiClient(baseUrl: 'http://test.local:30002'),
        ),
        sessionListApiFactoryProvider.overrideWithValue((_) => api),
        projectApiFactoryProvider.overrideWithValue((_) => _StubProjectApi()),
      ],
      child: CupertinoApp.router(
        routerConfig: router,
        locale: const Locale('zh'),
        supportedLocales: const [Locale('zh'), Locale('en')],
        localizationsDelegates: const [
          AppLocalizationsDelegate(),
          DefaultCupertinoLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  group('会话列表 → 工具页入口路由（todo：#51 返回动画对齐）', () {
    testWidgets('窄屏（390×844）头部下拉选技能 → push 入栈，返回走 pop（canPop=true）', (
      tester,
    ) async {
      final api = FakeSessionListApi();
      await _pumpApp(tester, api: api, viewport: const Size(390, 844));

      // 窄屏工具入口在头部右侧下拉（SessionListUtilityRows 仅宽屏渲染）
      await tester.tap(find.byKey(const ValueKey('session-list-narrow-nav')));
      await tester.pumpAndSettle();
      // 下拉菜单里选「技能」
      await tester.tap(find.byKey(const ValueKey('narrow-nav-skills')));
      await tester.pumpAndSettle();

      expect(find.text('技能'), findsOneWidget);
      // push 入栈 → 当前工具页可 pop
      expect(find.text('canPop=true'), findsOneWidget);

      // 返回 → pop 反向回会话列表
      await tester.tap(find.byType(AppBackButton));
      await tester.pumpAndSettle();
      expect(find.byType(SessionListPage), findsOneWidget);
      expect(find.text('技能'), findsNothing);
    });

    testWidgets('窄屏（390×844）点设置齿轮 → push 入栈，返回走 pop（canPop=true）', (
      tester,
    ) async {
      final api = FakeSessionListApi();
      await _pumpApp(tester, api: api, viewport: const Size(390, 844));

      await tester.tap(find.byKey(const ValueKey('session-list-settings')));
      await tester.pumpAndSettle();

      expect(find.text('设置'), findsOneWidget);
      expect(find.text('canPop=true'), findsOneWidget);

      await tester.tap(find.byType(AppBackButton));
      await tester.pumpAndSettle();
      expect(find.byType(SessionListPage), findsOneWidget);
    });
  });
}