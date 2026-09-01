import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hermes_ui/app/widgets/adaptive_sliver_navigation_bar.dart';
import 'package:hermes_ui/app/widgets/narrow_navigation_dropdown.dart';
import 'package:hermes_ui/core/utils/accessibility.dart';
import 'package:hermes_ui/features/session_list/session_entry_visibility.dart';
import 'package:hermes_ui/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _DefaultVisibilityNotifier extends SessionEntryVisibilityController {
  @override
  SessionEntryVisibility build() {
    return const SessionEntryVisibility();
  }
}

class _FilteredVisibilityNotifier extends SessionEntryVisibilityController {
  @override
  SessionEntryVisibility build() {
    return const SessionEntryVisibility(
      tasks: false,
      kanban: true,
      skills: true,
      insights: false,
      workspaces: true,
      memory: true,
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
      workspaces: true,
      memory: true,
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
      workspaces: false,
      memory: false,
      downloads: false,
    );
  }
}

class _PageStub extends StatelessWidget {
  const _PageStub({required this.title});
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

  group('NarrowNavigationDropdownButton 独立组件测试', () {
    Future<GoRouter> pumpDropdownButton(
      WidgetTester tester, {
      Override? visibilityOverride,
    }) async {
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const CupertinoPageScaffold(
              child: Center(child: NarrowNavigationDropdownButton()),
            ),
          ),
          GoRoute(
            path: '/tasks',
            builder: (_, _) => const _PageStub(title: 'TasksDestination'),
          ),
          GoRoute(
            path: '/kanban',
            builder: (_, _) => const _PageStub(title: 'KanbanDestination'),
          ),
          GoRoute(
            path: '/workspaces',
            builder: (_, _) => const _PageStub(title: 'WorkspacesDestination'),
          ),
          GoRoute(
            path: '/skills',
            builder: (_, _) => const _PageStub(title: 'SkillsDestination'),
          ),
          GoRoute(
            path: '/insights',
            builder: (_, _) => const _PageStub(title: 'InsightsDestination'),
          ),
          GoRoute(
            path: '/memory',
            builder: (_, _) => const _PageStub(title: 'MemoryDestination'),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            if (visibilityOverride != null)
              visibilityOverride
            else
              sessionEntryVisibilityProvider.overrideWith(
                _DefaultVisibilityNotifier.new,
              ),
          ],
          child: CupertinoApp.router(
            locale: const Locale('zh'),
            supportedLocales: const [Locale('zh'), Locale('en')],
            localizationsDelegates: testDelegates,
            routerConfig: router,
          ),
        ),
      );

      await tester.pumpAndSettle();
      return router;
    }

    testWidgets('默认渲染下拉按钮并具备快捷导航 Accessibility 属性', (tester) async {
      await pumpDropdownButton(tester);

      expect(
        find.byKey(const ValueKey('narrow-nav-dropdown')),
        findsOneWidget,
      );

      final button = tester.widget<AccessibleButton>(
        find.byKey(const ValueKey('narrow-nav-dropdown')),
      );
      expect(button.label, '快捷导航');
    });

    testWidgets('点击展开菜单展示默认项并可跳转 /tasks', (tester) async {
      await pumpDropdownButton(tester);

      await tester.tap(find.byKey(const ValueKey('narrow-nav-dropdown')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('narrow-nav-tasks')), findsOneWidget);
      expect(find.byKey(const ValueKey('narrow-nav-workspaces')), findsOneWidget);
      expect(find.byKey(const ValueKey('narrow-nav-skills')), findsOneWidget);
      expect(find.byKey(const ValueKey('narrow-nav-insights')), findsOneWidget);
      expect(find.byKey(const ValueKey('narrow-nav-memory')), findsOneWidget);
      expect(find.byKey(const ValueKey('narrow-nav-kanban')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('narrow-nav-tasks')));
      await tester.pumpAndSettle();

      expect(find.text('body-TasksDestination'), findsOneWidget);
    });

    testWidgets('全开配置下展示全部 6 项并可跳转 /kanban 与 /workspaces', (tester) async {
      await pumpDropdownButton(
        tester,
        visibilityOverride: sessionEntryVisibilityProvider.overrideWith(
          _AllVisibleVisibilityNotifier.new,
        ),
      );

      await tester.tap(find.byKey(const ValueKey('narrow-nav-dropdown')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('narrow-nav-kanban')), findsOneWidget);
      expect(find.byKey(const ValueKey('narrow-nav-memory')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('narrow-nav-kanban')));
      await tester.pumpAndSettle();

      expect(find.text('body-KanbanDestination'), findsOneWidget);
    });

    testWidgets('过滤显隐配置下仅展示开启项', (tester) async {
      await pumpDropdownButton(
        tester,
        visibilityOverride: sessionEntryVisibilityProvider.overrideWith(
          _FilteredVisibilityNotifier.new,
        ),
      );

      await tester.tap(find.byKey(const ValueKey('narrow-nav-dropdown')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('narrow-nav-tasks')), findsNothing);
      expect(find.byKey(const ValueKey('narrow-nav-kanban')), findsOneWidget);
      expect(find.byKey(const ValueKey('narrow-nav-workspaces')), findsOneWidget);
      expect(find.byKey(const ValueKey('narrow-nav-skills')), findsOneWidget);
      expect(find.byKey(const ValueKey('narrow-nav-memory')), findsOneWidget);
      expect(find.byKey(const ValueKey('narrow-nav-insights')), findsNothing);
    });

    testWidgets('全关配置下按钮返回 SizedBox.shrink()', (tester) async {
      await pumpDropdownButton(
        tester,
        visibilityOverride: sessionEntryVisibilityProvider.overrideWith(
          _AllHiddenVisibilityNotifier.new,
        ),
      );

      expect(
        find.byKey(const ValueKey('narrow-nav-dropdown')),
        findsNothing,
      );
    });
  });

  group('AdaptiveSliverNavigationBar 窄屏与宽屏下拉集成测试', () {
    Widget buildScaffold({
      required bool showDropdown,
      Widget? trailing,
    }) {
      return ProviderScope(
        child: CupertinoApp(
          localizationsDelegates: testDelegates,
          home: CupertinoPageScaffold(
            child: CustomScrollView(
              slivers: [
                AdaptiveSliverNavigationBar(
                  title: '任务',
                  showNarrowNavigationDropdown: showDropdown,
                  trailing: trailing,
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 500)),
              ],
            ),
          ),
        ),
      );
    }

    testWidgets('窄屏（<900）：大标题右侧渲染窄屏下拉按钮，与原 trailing 组合', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      var originalTrailingCalled = false;
      await tester.pumpWidget(
        buildScaffold(
          showDropdown: true,
          trailing: CupertinoButton(
            key: const ValueKey('original-create-button'),
            onPressed: () => originalTrailingCalled = true,
            child: const Icon(CupertinoIcons.add),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 窄屏下大标题右侧同时存在下拉按钮与原 trailing
      expect(
        find.byKey(const ValueKey('narrow-nav-dropdown')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('original-create-button')),
        findsOneWidget,
      );

      // 原 trailing 点击功能正常
      await tester.tap(find.byKey(const ValueKey('original-create-button')));
      await tester.pump();
      expect(originalTrailingCalled, isTrue);
    });

    testWidgets('窄屏（<900）：showNarrowNavigationDropdown=false 时不渲染下拉按钮', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        buildScaffold(
          showDropdown: false,
          trailing: const CupertinoButton(
            key: ValueKey('original-create-button'),
            onPressed: null,
            child: Icon(CupertinoIcons.add),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('narrow-nav-dropdown')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('original-create-button')),
        findsOneWidget,
      );
    });

    testWidgets('宽屏（>=900）：不渲染窄屏下拉按钮，保持紧凑导航条', (tester) async {
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        buildScaffold(
          showDropdown: true,
          trailing: const CupertinoButton(
            key: ValueKey('original-create-button'),
            onPressed: null,
            child: Icon(CupertinoIcons.add),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('narrow-nav-dropdown')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('original-create-button')),
        findsOneWidget,
      );
    });
  });
}
