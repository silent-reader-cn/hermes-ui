import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermex_flutter/app/shell/session_sidebar.dart';
import 'package:hermex_flutter/app/shell/sidebar_utility_toolbar.dart';
import 'package:hermex_flutter/core/api/api_client.dart';
import 'package:hermex_flutter/core/connections/connection_providers.dart';
import 'package:hermex_flutter/core/models/session.dart';
import 'package:hermex_flutter/features/projects/project_providers.dart';
import 'package:hermex_flutter/features/session_list/session_entry_visibility.dart';
import 'package:hermex_flutter/features/session_list/session_list_providers.dart';
import 'package:hermex_flutter/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_session_list_api.dart';

class _FilteredVisibilityNotifier extends SessionEntryVisibilityController {
  @override
  SessionEntryVisibility build() {
    return const SessionEntryVisibility(
      tasks: false,
      kanban: true,
      skills: true,
      memory: false,
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
      memory: false,
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

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  const List<LocalizationsDelegate<dynamic>> testDelegates = [
    AppLocalizationsDelegate(),
    DefaultCupertinoLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  group('SidebarUtilityToolbar 显隐与过滤测试', () {
    testWidgets('默认全开时展示全部 6 个入口（含设置）', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: CupertinoApp(
            locale: Locale('zh'),
            supportedLocales: [Locale('zh'), Locale('en')],
            localizationsDelegates: testDelegates,
            home: CupertinoPageScaffold(
              child: SidebarUtilityToolbar(currentLocation: '/tasks'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('sidebar-utility-tasks')), findsOneWidget);
      expect(find.byKey(const ValueKey('sidebar-utility-kanban')), findsOneWidget);
      expect(find.byKey(const ValueKey('sidebar-utility-skills')), findsOneWidget);
      expect(find.byKey(const ValueKey('sidebar-utility-memory')), findsOneWidget);
      expect(find.byKey(const ValueKey('sidebar-utility-insights')), findsOneWidget);
      expect(find.byKey(const ValueKey('sidebar-utility-settings')), findsOneWidget);
    });

    testWidgets('部分关闭时仅过滤关闭的功能入口，设置入口固定保留', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionEntryVisibilityProvider.overrideWith(
              _FilteredVisibilityNotifier.new,
            ),
          ],
          child: const CupertinoApp(
            locale: Locale('zh'),
            supportedLocales: [Locale('zh'), Locale('en')],
            localizationsDelegates: testDelegates,
            home: CupertinoPageScaffold(
              child: SidebarUtilityToolbar(currentLocation: '/kanban'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('sidebar-utility-tasks')), findsNothing);
      expect(find.byKey(const ValueKey('sidebar-utility-kanban')), findsOneWidget);
      expect(find.byKey(const ValueKey('sidebar-utility-skills')), findsOneWidget);
      expect(find.byKey(const ValueKey('sidebar-utility-memory')), findsNothing);
      expect(find.byKey(const ValueKey('sidebar-utility-insights')), findsOneWidget);
      expect(find.byKey(const ValueKey('sidebar-utility-settings')), findsOneWidget);
    });

    testWidgets('5 个功能入口全关时整条工具条返回 SizedBox.shrink()', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionEntryVisibilityProvider.overrideWith(
              _AllHiddenVisibilityNotifier.new,
            ),
          ],
          child: const CupertinoApp(
            locale: Locale('zh'),
            supportedLocales: [Locale('zh'), Locale('en')],
            localizationsDelegates: testDelegates,
            home: CupertinoPageScaffold(
              child: SidebarUtilityToolbar(currentLocation: '/settings'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('sidebar-utility-tasks')), findsNothing);
      expect(find.byKey(const ValueKey('sidebar-utility-kanban')), findsNothing);
      expect(find.byKey(const ValueKey('sidebar-utility-skills')), findsNothing);
      expect(find.byKey(const ValueKey('sidebar-utility-memory')), findsNothing);
      expect(find.byKey(const ValueKey('sidebar-utility-insights')), findsNothing);
      expect(find.byKey(const ValueKey('sidebar-utility-settings')), findsNothing);
    });

    testWidgets('SessionSidebar 集成：全关功能入口时侧栏仍具备设置能力', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(
              ApiClient(baseUrl: 'http://test.local:30002'),
            ),
            sessionListApiFactoryProvider.overrideWithValue((_) => FakeSessionListApi()),
            projectApiFactoryProvider.overrideWithValue((_) => _StubProjectApi()),
            sessionEntryVisibilityProvider.overrideWith(
              _AllHiddenVisibilityNotifier.new,
            ),
          ],
          child: const CupertinoApp(
            locale: Locale('zh'),
            supportedLocales: [Locale('zh'), Locale('en')],
            localizationsDelegates: testDelegates,
            home: CupertinoPageScaffold(
              child: SizedBox(
                width: 320,
                child: SessionSidebar(currentLocation: '/'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 工具条内的入口不渲染
      expect(find.byKey(const ValueKey('sidebar-utility-tasks')), findsNothing);
      expect(find.byKey(const ValueKey('sidebar-utility-settings')), findsNothing);

      // 但 SessionListPage 顶部导航条仍有设置齿轮图标
      expect(find.byIcon(CupertinoIcons.gear_alt), findsOneWidget);
    });
  });
}
