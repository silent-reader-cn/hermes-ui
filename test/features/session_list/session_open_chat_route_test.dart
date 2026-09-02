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

/// 返回动画路由修复（todo：#43）的回归测试：
/// 窄屏（< kAdaptiveBreakpoint）进入聊天必须 `push` 真入栈 —— 返回时
/// `AppBackButton` 走 `pop()` 反向动画（聊天页向右滑出、会话列表原地）
/// 而不是 `go()` 兜底把会话列表当新 route 正向盖上来。
///
/// 宽屏（>= kAdaptiveBreakpoint）保持 `go` 替换（双栏侧栏不破坏）。
class _ChatStub extends StatelessWidget {
  const _ChatStub({required this.sessionId});

  final String sessionId;

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        // 与生产 ChatPage 一致：返回走 AppBackButton（canPop→pop / 否则 go）
        leading: const AppBackButton(),
        middle: Text('Chat $sessionId'),
      ),
      child: Center(
        child: Text(
          'canPop=${context.canPop()}',
          key: const ValueKey('chat-canpop'),
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
      GoRoute(path: '/', builder: (_, _) => const SessionListPage()),
      GoRoute(
        path: '/chat/:sessionId',
        pageBuilder: (_, state) => HermesPage<void>(
          key: ValueKey('chat-${state.pathParameters['sessionId']}'),
          builder: (_) =>
              _ChatStub(sessionId: state.pathParameters['sessionId'] ?? ''),
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
  // 首帧（AsyncLoading）+ 异步 build 完成（AsyncData）
  await tester.pump();
  await tester.pump();
}

void main() {
  group('会话列表进入聊天路由（todo：#43 返回动画修正）', () {
    testWidgets('窄屏（390×844）点击会话 → push 入栈，返回可走 pop（canPop=true）', (
      tester,
    ) async {
      final api = FakeSessionListApi(
        sessions: [
          SessionSummary(
            sessionId: 's1',
            title: '窄屏会话',
            lastMessageAt: DateTime.now().millisecondsSinceEpoch / 1000,
          ),
        ],
      );
      await _pumpApp(tester, api: api, viewport: const Size(390, 844));

      // 点击会话行进入聊天
      await tester.tap(find.byKey(const ValueKey('session-row-s1')));
      await tester.pumpAndSettle();

      // 已进入 chat 页
      expect(find.text('Chat s1'), findsOneWidget);

      // push 入栈 → 当前路由可 pop（返回走 pop 反向，而非 go 兜底）
      expect(find.text('canPop=true'), findsOneWidget);

      // 点左上角返回 → pop 反向回会话列表
      await tester.tap(find.byType(AppBackButton));
      await tester.pumpAndSettle();
      expect(find.text('窄屏会话'), findsOneWidget);
      expect(find.text('Chat s1'), findsNothing);
    });

    testWidgets('宽屏（1280×800）点击会话 → go 替换栈，返回走 go(fallback)', (tester) async {
      final api = FakeSessionListApi(
        sessions: [
          SessionSummary(
            sessionId: 's2',
            title: '宽屏会话',
            lastMessageAt: DateTime.now().millisecondsSinceEpoch / 1000,
          ),
        ],
      );
      await _pumpApp(tester, api: api, viewport: const Size(1280, 800));

      await tester.tap(find.byKey(const ValueKey('session-row-s2')));
      await tester.pumpAndSettle();

      // 已进入 chat 页
      expect(find.text('Chat s2'), findsOneWidget);

      // go 替换栈 → 当前路由不可 pop（返回走 go(fallback)）
      expect(find.text('canPop=false'), findsOneWidget);

      // 点左上角返回 → go('/') 兜底回会话列表
      await tester.tap(find.byType(AppBackButton));
      await tester.pumpAndSettle();
      expect(find.text('宽屏会话'), findsOneWidget);
      expect(find.text('Chat s2'), findsNothing);
    });
  });
}
