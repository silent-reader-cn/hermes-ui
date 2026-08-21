import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermex_flutter/core/api/api_client.dart';
import 'package:hermex_flutter/core/connections/connection_providers.dart';
import 'package:hermex_flutter/core/connections/connection_store.dart';
import 'package:hermex_flutter/features/session_list/session_entry_visibility.dart';
import 'package:hermex_flutter/features/settings/settings_page.dart';
import 'package:hermex_flutter/features/settings/settings_providers.dart';
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
    tester.view.physicalSize = const Size(800, 1200);
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

  group('设置页会话列表入口显隐开关测试', () {
    testWidgets('渲染「会话列表入口」区块及 4 个功能入口开关与记忆入口', (tester) async {
      await pumpSettingsPage(tester);

      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('settings-visibility-insights')),
        50,
      );

      expect(find.text('会话列表入口'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('settings-visibility-tasks')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('settings-visibility-kanban')),
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
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('settings-memory-entry')),
        50,
      );
      expect(
        find.byKey(const ValueKey('settings-memory-entry')),
        findsOneWidget,
      );

      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('settings-visibility-tasks')),
        -50,
      );
      final tasksSwitch = tester.widget<CupertinoSwitch>(
        find.byKey(const ValueKey('settings-visibility-tasks')),
      );
      final kanbanSwitch = tester.widget<CupertinoSwitch>(
        find.byKey(const ValueKey('settings-visibility-kanban')),
      );
      final skillsSwitch = tester.widget<CupertinoSwitch>(
        find.byKey(const ValueKey('settings-visibility-skills')),
      );
      final insightsSwitch = tester.widget<CupertinoSwitch>(
        find.byKey(const ValueKey('settings-visibility-insights')),
      );

      expect(tasksSwitch.value, isTrue);
      expect(kanbanSwitch.value, isTrue);
      expect(skillsSwitch.value, isTrue);
      expect(insightsSwitch.value, isTrue);
    });

    testWidgets('切换开关后 Provider 状态实时更新且持久化', (tester) async {
      final container = await pumpSettingsPage(tester);

      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('settings-visibility-insights')),
        50,
      );

      // 点击任务开关关闭
      await tester.tap(find.byKey(const ValueKey('settings-visibility-tasks')));
      await tester.pumpAndSettle();

      var state = container.read(sessionEntryVisibilityProvider);
      expect(state.tasks, isFalse);
      expect(state.kanban, isTrue);

      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('settings-visibility-tasks')),
        -50,
      );
      final tasksSwitch = tester.widget<CupertinoSwitch>(
        find.byKey(const ValueKey('settings-visibility-tasks')),
      );
      expect(tasksSwitch.value, isFalse);

      // 点击看板和统计开关关闭
      await tester.tap(
        find.byKey(const ValueKey('settings-visibility-kanban')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('settings-visibility-insights')),
      );
      await tester.pumpAndSettle();

      state = container.read(sessionEntryVisibilityProvider);
      expect(state.tasks, isFalse);
      expect(state.kanban, isFalse);
      expect(state.skills, isTrue);
      expect(state.insights, isFalse);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('session_entry_visibility_tasks'), isFalse);
      expect(prefs.getBool('session_entry_visibility_kanban'), isFalse);
      expect(prefs.getBool('session_entry_visibility_insights'), isFalse);
    });

    testWidgets('读取 SharedPreferences 初始开关状态', (tester) async {
      await pumpSettingsPage(
        tester,
        initialPrefs: {
          'session_entry_visibility_tasks': false,
          'session_entry_visibility_skills': false,
        },
      );

      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('settings-visibility-insights')),
        50,
      );

      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('settings-visibility-tasks')),
        -50,
      );
      final tasksSwitch = tester.widget<CupertinoSwitch>(
        find.byKey(const ValueKey('settings-visibility-tasks')),
      );
      final kanbanSwitch = tester.widget<CupertinoSwitch>(
        find.byKey(const ValueKey('settings-visibility-kanban')),
      );
      final skillsSwitch = tester.widget<CupertinoSwitch>(
        find.byKey(const ValueKey('settings-visibility-skills')),
      );

      expect(tasksSwitch.value, isFalse);
      expect(kanbanSwitch.value, isTrue);
      expect(skillsSwitch.value, isFalse);
    });
  });
}
