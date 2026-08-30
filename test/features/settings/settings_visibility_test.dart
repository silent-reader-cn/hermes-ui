import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/connections/connection_store.dart';
import 'package:hermes_ui/features/session_list/session_entry_visibility.dart';
import 'package:hermes_ui/features/settings/cron_visibility_settings.dart';
import 'package:hermes_ui/features/settings/settings_page.dart';
import 'package:hermes_ui/features/settings/settings_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_settings_api.dart';
import '../../helpers/in_memory_secure_storage.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<ProviderContainer> pumpSettingsPage(
    WidgetTester tester, {
    Map<String, Object> initialPrefs = const {},
  }) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    SharedPreferences.setMockInitialValues(initialPrefs);

    final storage = InMemorySecureStorage();
    final store = ConnectionStore(storage: storage);
    final api = FakeSettingsApi();

    final container = ProviderContainer(
      overrides: [
        connectionStoreProvider.overrideWithValue(store),
        apiClientProvider.overrideWithValue(
          ApiClient(baseUrl: 'http://test.local:30002'),
        ),
        settingsApiFactoryProvider.overrideWithValue((_) => api),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const CupertinoApp(home: SettingsPage()),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  group('设置页定时会话开关与会话列表入口显隐测试', () {
    testWidgets('首页渲染「显示定时会话」开关（默认关闭）', (tester) async {
      final container = await pumpSettingsPage(tester);

      final cronFinder = find.byKey(const ValueKey('settings-show-cron-sessions'));
      await tester.scrollUntilVisible(cronFinder, 50);
      expect(cronFinder, findsOneWidget);

      final cronSwitch = tester.widget<CupertinoSwitch>(
        find.byKey(const ValueKey('settings-switch-show-cron')),
      );
      expect(cronSwitch.value, isFalse);

      // 切换定时会话开关
      await tester.tap(find.byKey(const ValueKey('settings-switch-show-cron')));
      await tester.pumpAndSettle();

      expect(container.read(cronVisibilityProvider).showCron, isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('cron_show_cron_sessions'), isTrue);
    });

    testWidgets('渲染「会话列表入口」区块及 6 个功能入口开关', (tester) async {
      await pumpSettingsPage(tester);

      final entryFinder =
          find.byKey(const ValueKey('settings-entry-session-list-entries'));
      await tester.scrollUntilVisible(entryFinder, 100);
      await tester.drag(find.byKey(const ValueKey('settings-scroll')), const Offset(0, -150));
      await tester.pumpAndSettle();
      expect(entryFinder, findsOneWidget);

      // 进入二级页
      await tester.tap(entryFinder);
      await tester.pumpAndSettle();

      expect(find.text('会话列表入口'), findsWidgets);
      expect(
        find.byKey(const ValueKey('settings-visibility-tasks')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('settings-visibility-kanban')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('settings-visibility-workspaces')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('settings-visibility-skills')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('settings-visibility-insights')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('settings-visibility-memory')),
        findsOneWidget,
      );

      final tasksSwitch = tester.widget<CupertinoSwitch>(
        find.byKey(const ValueKey('settings-visibility-tasks')),
      );
      final kanbanSwitch = tester.widget<CupertinoSwitch>(
        find.byKey(const ValueKey('settings-visibility-kanban')),
      );
      final workspacesSwitch = tester.widget<CupertinoSwitch>(
        find.byKey(const ValueKey('settings-visibility-workspaces')),
      );
      final skillsSwitch = tester.widget<CupertinoSwitch>(
        find.byKey(const ValueKey('settings-visibility-skills')),
      );
      final insightsSwitch = tester.widget<CupertinoSwitch>(
        find.byKey(const ValueKey('settings-visibility-insights')),
      );
      final memorySwitch = tester.widget<CupertinoSwitch>(
        find.byKey(const ValueKey('settings-visibility-memory')),
      );

      expect(tasksSwitch.value, isTrue);
      expect(kanbanSwitch.value, isTrue);
      expect(workspacesSwitch.value, isTrue);
      expect(skillsSwitch.value, isTrue);
      expect(insightsSwitch.value, isTrue);
      expect(memorySwitch.value, isTrue);
    });

    testWidgets('切换二级页开关后 Provider 状态实时更新且持久化', (tester) async {
      final container = await pumpSettingsPage(tester);

      // 进入二级页
      final entryFinder =
          find.byKey(const ValueKey('settings-entry-session-list-entries'));
      await tester.scrollUntilVisible(entryFinder, 100);
      await tester.drag(find.byKey(const ValueKey('settings-scroll')), const Offset(0, -150));
      await tester.pumpAndSettle();
      await tester.tap(entryFinder);
      await tester.pumpAndSettle();

      // 点击任务开关关闭
      await tester.tap(find.byKey(const ValueKey('settings-visibility-tasks')));
      await tester.pumpAndSettle();

      var state = container.read(sessionEntryVisibilityProvider);
      expect(state.tasks, isFalse);
      expect(state.kanban, isTrue);

      final tasksSwitch = tester.widget<CupertinoSwitch>(
        find.byKey(const ValueKey('settings-visibility-tasks')),
      );
      expect(tasksSwitch.value, isFalse);

      // 点击看板、统计与记忆开关关闭
      await tester.tap(
        find.byKey(const ValueKey('settings-visibility-kanban')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('settings-visibility-insights')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('settings-visibility-memory')),
      );
      await tester.pumpAndSettle();

      state = container.read(sessionEntryVisibilityProvider);
      expect(state.tasks, isFalse);
      expect(state.kanban, isFalse);
      expect(state.skills, isTrue);
      expect(state.insights, isFalse);
      expect(state.memory, isFalse);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('session_entry_visibility_tasks'), isFalse);
      expect(prefs.getBool('session_entry_visibility_kanban'), isFalse);
      expect(prefs.getBool('session_entry_visibility_insights'), isFalse);
      expect(prefs.getBool('session_entry_visibility_memory'), isFalse);
    });

    testWidgets('读取 SharedPreferences 初始开关状态', (tester) async {
      await pumpSettingsPage(
        tester,
        initialPrefs: {
          'session_entry_visibility_tasks': false,
          'session_entry_visibility_skills': false,
          'session_entry_visibility_memory': false,
          'cron_show_cron_sessions': true,
        },
      );

      final cronSwitch = tester.widget<CupertinoSwitch>(
        find.byKey(const ValueKey('settings-switch-show-cron')),
      );
      expect(cronSwitch.value, isTrue);

      // 进入二级页
      final entryFinder =
          find.byKey(const ValueKey('settings-entry-session-list-entries'));
      await tester.scrollUntilVisible(entryFinder, 100);
      await tester.drag(find.byKey(const ValueKey('settings-scroll')), const Offset(0, -150));
      await tester.pumpAndSettle();
      await tester.tap(entryFinder);
      await tester.pumpAndSettle();

      final tasksSwitch = tester.widget<CupertinoSwitch>(
        find.byKey(const ValueKey('settings-visibility-tasks')),
      );
      final kanbanSwitch = tester.widget<CupertinoSwitch>(
        find.byKey(const ValueKey('settings-visibility-kanban')),
      );
      final skillsSwitch = tester.widget<CupertinoSwitch>(
        find.byKey(const ValueKey('settings-visibility-skills')),
      );
      final memorySwitch = tester.widget<CupertinoSwitch>(
        find.byKey(const ValueKey('settings-visibility-memory')),
      );

      expect(tasksSwitch.value, isFalse);
      expect(kanbanSwitch.value, isTrue);
      expect(skillsSwitch.value, isFalse);
      expect(memorySwitch.value, isFalse);
    });
  });
}
