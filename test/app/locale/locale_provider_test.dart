import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/app/locale/locale_provider.dart';
import 'package:hermes_ui/app/locale/locale_resolver.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    LocaleResolver.reset();
  });

  tearDown(() {
    LocaleResolver.reset();
  });

  group('AppLocaleMode', () {
    test('flutterLocale 映射正确', () {
      expect(AppLocaleMode.system.flutterLocale, isNull);
      expect(AppLocaleMode.zh.flutterLocale, const Locale('zh'));
      expect(AppLocaleMode.en.flutterLocale, const Locale('en'));
    });
  });

  group('localeModeProvider', () {
    test('默认值为 system', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final mode = container.read(localeModeProvider);
      expect(mode, AppLocaleMode.system);
    });

    test('从 SharedPreferences 恢复已保存的模式', () async {
      SharedPreferences.setMockInitialValues({
        LocaleModeController.prefsKey: 'en',
      });

      final container = ProviderContainer();
      addTearDown(container.dispose);

      final controller = container.read(localeModeProvider.notifier);
      await controller.load();

      expect(container.read(localeModeProvider), AppLocaleMode.en);
    });

    test('setMode 持久化 round-trip 并更新状态', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final controller = container.read(localeModeProvider.notifier);
      expect(container.read(localeModeProvider), AppLocaleMode.system);

      await controller.setMode(AppLocaleMode.zh);
      expect(container.read(localeModeProvider), AppLocaleMode.zh);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(LocaleModeController.prefsKey), 'zh');

      await controller.setMode(AppLocaleMode.en);
      expect(container.read(localeModeProvider), AppLocaleMode.en);
      expect(prefs.getString(LocaleModeController.prefsKey), 'en');
    });

    test('未知/非法值 fallback 到 system', () async {
      SharedPreferences.setMockInitialValues({
        LocaleModeController.prefsKey: 'unknown_mode',
      });

      final container = ProviderContainer();
      addTearDown(container.dispose);

      final controller = container.read(localeModeProvider.notifier);
      await controller.load();

      expect(container.read(localeModeProvider), AppLocaleMode.system);
    });
  });
}
