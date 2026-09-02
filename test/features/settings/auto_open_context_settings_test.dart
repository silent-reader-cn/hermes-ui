import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/connections/connection_store.dart';
import 'package:hermes_ui/core/connections/server_connection.dart';
import 'package:hermes_ui/features/settings/settings_page.dart';
import 'package:hermes_ui/features/settings/settings_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_settings_api.dart';
import '../../helpers/in_memory_secure_storage.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('AutoOpenContextOnNewSessionController 状态与持久化', () {
    test('默认值为 true（新建会话默认自动打开上下文弹窗）', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final state = container.read(autoOpenContextOnNewSessionProvider);
      expect(state, isTrue);
    });

    test('初始状态从 SharedPreferences 读取（false）', () async {
      SharedPreferences.setMockInitialValues({
        kAutoOpenContextOnNewSessionKey: false,
      });

      final container = ProviderContainer();
      addTearDown(container.dispose);

      final controller = container.read(
        autoOpenContextOnNewSessionProvider.notifier,
      );
      await controller.load();

      expect(container.read(autoOpenContextOnNewSessionProvider), isFalse);
    });

    test('初始状态从 SharedPreferences 读取（true）', () async {
      SharedPreferences.setMockInitialValues({
        kAutoOpenContextOnNewSessionKey: true,
      });

      final container = ProviderContainer();
      addTearDown(container.dispose);

      final controller = container.read(
        autoOpenContextOnNewSessionProvider.notifier,
      );
      await controller.load();

      expect(container.read(autoOpenContextOnNewSessionProvider), isTrue);
    });

    test('setEnabled 修改配置并写入 SharedPreferences', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final controller = container.read(
        autoOpenContextOnNewSessionProvider.notifier,
      );
      await controller.setEnabled(false);

      expect(container.read(autoOpenContextOnNewSessionProvider), isFalse);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(kAutoOpenContextOnNewSessionKey), isFalse);

      await controller.setEnabled(true);
      expect(container.read(autoOpenContextOnNewSessionProvider), isTrue);
      expect(prefs.getBool(kAutoOpenContextOnNewSessionKey), isTrue);
    });
  });

  group('RecentlyCreatedSessionIdController 临时会话跟踪', () {
    test('默认值为 null', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(recentlyCreatedSessionIdProvider), isNull);
    });

    test('markCreated 设置会话 ID，clear 清空', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final controller = container.read(
        recentlyCreatedSessionIdProvider.notifier,
      );

      controller.markCreated('session-123');
      expect(
        container.read(recentlyCreatedSessionIdProvider),
        'session-123',
      );

      controller.clear();
      expect(container.read(recentlyCreatedSessionIdProvider), isNull);
    });
  });

  group('SettingsPage 对话分组新增开关', () {
    testWidgets('渲染「新建会话自动打开上下文」开关并支持切换', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final fakeApi = FakeSettingsApi();
      final connection = ServerConnection(
        id: 'conn-1',
        name: 'Test Server',
        baseUrl: 'http://test.local:30002',
        createdAt: DateTime.utc(2026, 1, 1),
      );
      final store = ConnectionStore(storage: InMemorySecureStorage());
      await store.save(connection);
      await store.setActive(connection.id);

      final client = ApiClient(baseUrl: connection.baseUrl);

      final container = ProviderContainer(
        overrides: [
          connectionStoreProvider.overrideWithValue(store),
          apiClientProvider.overrideWithValue(client),
          settingsApiFactoryProvider.overrideWithValue((_) => fakeApi),
        ],
      );
      addTearDown(container.dispose);

      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const CupertinoApp(
            home: CupertinoPageScaffold(child: SettingsPage()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final switchTileFinder = find.byKey(
        const ValueKey('settings-auto-open-context'),
      );
      expect(switchTileFinder, findsOneWidget);

      final switchFinder = find.byKey(
        const ValueKey('settings-switch-auto-open-context'),
      );
      expect(switchFinder, findsOneWidget);

      // 默认开启
      final switchWidget = tester.widget<CupertinoSwitch>(switchFinder);
      expect(switchWidget.value, isTrue);

      // 点击切换为关闭
      await tester.tap(switchFinder);
      await tester.pumpAndSettle();

      final switchWidgetAfter = tester.widget<CupertinoSwitch>(switchFinder);
      expect(switchWidgetAfter.value, isFalse);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(kAutoOpenContextOnNewSessionKey), isFalse);
    });
  });
}
