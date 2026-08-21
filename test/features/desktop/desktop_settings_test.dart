import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermex_flutter/core/api/api_client.dart';
import 'package:hermex_flutter/core/connections/connection_providers.dart';
import 'package:hermex_flutter/core/connections/connection_store.dart';
import 'package:hermex_flutter/features/desktop/desktop_settings.dart';
import 'package:hermex_flutter/features/onboarding/onboarding_providers.dart';
import 'package:hermex_flutter/features/settings/settings_page.dart';
import 'package:hermex_flutter/features/settings/settings_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_onboarding_login_api.dart';
import '../../helpers/fake_settings_api.dart';
import '../../helpers/in_memory_secure_storage.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('DesktopSettings 模型测试', () {
    test('默认值全为 true', () {
      const settings = DesktopSettings();
      expect(settings.minimizeToTray, isTrue);
      expect(settings.globalShortcutsEnabled, isTrue);
      expect(settings.rememberWindowPosition, isTrue);
    });

    test('copyWith 字段替换与保留', () {
      const original = DesktopSettings();
      final updated = original.copyWith(
        minimizeToTray: false,
        globalShortcutsEnabled: false,
      );
      expect(updated.minimizeToTray, isFalse);
      expect(updated.globalShortcutsEnabled, isFalse);
      expect(updated.rememberWindowPosition, isTrue);
    });

    test('== 与 hashCode 相等性', () {
      const a = DesktopSettings(
        minimizeToTray: true,
        globalShortcutsEnabled: false,
        rememberWindowPosition: true,
      );
      const b = DesktopSettings(
        minimizeToTray: true,
        globalShortcutsEnabled: false,
        rememberWindowPosition: true,
      );
      const c = DesktopSettings(
        minimizeToTray: false,
        globalShortcutsEnabled: false,
        rememberWindowPosition: true,
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
      expect(a.toString(), contains('DesktopSettings'));
    });
  });

  group('isDesktopPlatform 平台守卫判定', () {
    test('Windows / macOS / Linux 在非 Web 下返回 true', () {
      expect(
        isDesktopPlatform(platform: TargetPlatform.windows, isWeb: false),
        isTrue,
      );
      expect(
        isDesktopPlatform(platform: TargetPlatform.macOS, isWeb: false),
        isTrue,
      );
      expect(
        isDesktopPlatform(platform: TargetPlatform.linux, isWeb: false),
        isTrue,
      );
    });

    test('Android / iOS / Fuchsia 返回 false', () {
      expect(
        isDesktopPlatform(platform: TargetPlatform.android, isWeb: false),
        isFalse,
      );
      expect(
        isDesktopPlatform(platform: TargetPlatform.iOS, isWeb: false),
        isFalse,
      );
      expect(
        isDesktopPlatform(platform: TargetPlatform.fuchsia, isWeb: false),
        isFalse,
      );
    });

    test('Web 环境统一返回 false', () {
      expect(
        isDesktopPlatform(platform: TargetPlatform.windows, isWeb: true),
        isFalse,
      );
      expect(
        isDesktopPlatform(platform: TargetPlatform.macOS, isWeb: true),
        isFalse,
      );
    });
  });

  group('DesktopSettingsController 状态与持久化', () {
    test('初始状态从 SharedPreferences 读取', () async {
      SharedPreferences.setMockInitialValues({
        DesktopSettingsController.keyMinimizeToTray: false,
        DesktopSettingsController.keyGlobalShortcutsEnabled: false,
        DesktopSettingsController.keyRememberWindowPosition: false,
      });

      final container = ProviderContainer();
      addTearDown(container.dispose);

      final controller = container.read(desktopSettingsProvider.notifier);
      await pumpEventQueue();

      final state = container.read(desktopSettingsProvider);
      expect(state.minimizeToTray, isFalse);
      expect(state.globalShortcutsEnabled, isFalse);
      expect(state.rememberWindowPosition, isFalse);

      // 修改配置并验证持久化
      await controller.setMinimizeToTray(true);
      await controller.setGlobalShortcutsEnabled(true);
      await controller.setRememberWindowPosition(true);

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getBool(DesktopSettingsController.keyMinimizeToTray),
        isTrue,
      );
      expect(
        prefs.getBool(DesktopSettingsController.keyGlobalShortcutsEnabled),
        isTrue,
      );
      expect(
        prefs.getBool(DesktopSettingsController.keyRememberWindowPosition),
        isTrue,
      );
    });
  });

  group('SettingsPage 桌面分组 Widget 测试', () {
    testWidgets('渲染三个 CupertinoSwitch 并响应点击切换', (tester) async {
      final container = ProviderContainer(
        overrides: [
          connectionStoreProvider.overrideWithValue(
            ConnectionStore(storage: InMemorySecureStorage()),
          ),
          apiClientProvider.overrideWithValue(
            ApiClient(baseUrl: 'http://test.local:30002'),
          ),
          settingsApiFactoryProvider.overrideWithValue(
            (_) => FakeSettingsApi(),
          ),
          onboardingApiFactoryProvider.overrideWithValue(
            (_, _) => FakeOnboardingLoginApi(),
          ),
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

      // 桌面分组已移入二级页：先滚到「桌面」入口并进入
      final desktopEntry = find.byKey(const ValueKey('settings-entry-desktop'));
      await tester.scrollUntilVisible(desktopEntry, 50);
      await tester.pumpAndSettle();
      await tester.tap(desktopEntry);
      await tester.pumpAndSettle();

      final minTrayFinder = find.byKey(
        const ValueKey('settings-desktop-minimize-to-tray'),
      );
      final shortcutsFinder = find.byKey(
        const ValueKey('settings-desktop-global-shortcuts'),
      );
      final rememberFinder = find.byKey(
        const ValueKey('settings-desktop-remember-window'),
      );

      await tester.scrollUntilVisible(minTrayFinder, 50);
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView), const Offset(0, 100));
      await tester.pumpAndSettle();

      // 验证桌面分组标题与开关（导航栏标题 + 分组 header 均有「桌面」）
            expect(find.text('桌面'), findsNWidgets(2));
      expect(find.text('最小化到托盘'), findsOneWidget);
      expect(find.text('全局快捷键'), findsOneWidget);
      expect(find.text('记住窗口位置'), findsOneWidget);

      expect(minTrayFinder, findsOneWidget);
      expect(shortcutsFinder, findsOneWidget);
      expect(rememberFinder, findsOneWidget);

      // 默认状态为 true
      expect(tester.widget<CupertinoSwitch>(minTrayFinder).value, isTrue);
      expect(tester.widget<CupertinoSwitch>(shortcutsFinder).value, isTrue);
      expect(tester.widget<CupertinoSwitch>(rememberFinder).value, isTrue);

      // 点击切换
      await tester.tap(minTrayFinder);
      await tester.pumpAndSettle();
      expect(container.read(desktopSettingsProvider).minimizeToTray, isFalse);

      await tester.tap(shortcutsFinder);
      await tester.pumpAndSettle();
      expect(
        container.read(desktopSettingsProvider).globalShortcutsEnabled,
        isFalse,
      );

      await tester.tap(rememberFinder);
      await tester.pumpAndSettle();
      expect(
        container.read(desktopSettingsProvider).rememberWindowPosition,
        isFalse,
      );
    });
  });
}
