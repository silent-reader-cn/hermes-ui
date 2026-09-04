import 'dart:ui';

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

  group('LocaleResolver resolve 三态', () {
    test('mode 为 zh 时解析为 zh，isEnglish 为 false', () {
      LocaleResolver.updateMode(AppLocaleMode.zh);

      expect(LocaleResolver.resolve(), const Locale('zh'));
      expect(LocaleResolver.isEnglish, isFalse);
    });

    test('mode 为 en 时解析为 en，isEnglish 为 true', () {
      LocaleResolver.updateMode(AppLocaleMode.en);

      expect(LocaleResolver.resolve(), const Locale('en'));
      expect(LocaleResolver.isEnglish, isTrue);
    });

    test('mode 为 system 时，根据系统语言解析（系统 zh*→中文，其余→英文）', () {
      LocaleResolver.updateMode(AppLocaleMode.system);

      // 系统语言为中文简体 zh_CN
      LocaleResolver.mockPlatformLocale = const Locale('zh', 'CN');
      expect(LocaleResolver.resolve(), const Locale('zh'));
      expect(LocaleResolver.isEnglish, isFalse);

      // 系统语言为中文繁体 zh_TW
      LocaleResolver.mockPlatformLocale = const Locale('zh', 'TW');
      expect(LocaleResolver.resolve(), const Locale('zh'));
      expect(LocaleResolver.isEnglish, isFalse);

      // 系统语言为英文 en_US
      LocaleResolver.mockPlatformLocale = const Locale('en', 'US');
      expect(LocaleResolver.resolve(), const Locale('en'));
      expect(LocaleResolver.isEnglish, isTrue);

      // 系统语言为其他（如德文 de、日文 ja、法文 fr 等，按规格“其余→英文”）
      LocaleResolver.mockPlatformLocale = const Locale('ja', 'JP');
      expect(LocaleResolver.resolve(), const Locale('en'));
      expect(LocaleResolver.isEnglish, isTrue);

      LocaleResolver.mockPlatformLocale = const Locale('fr', 'FR');
      expect(LocaleResolver.resolve(), const Locale('en'));
      expect(LocaleResolver.isEnglish, isTrue);
    });
  });

  group('LocaleResolver onChange 触发时序与 provider 联动', () {
    test('updateMode 仅在模式变更时触发 onChange', () {
      var callCount = 0;
      LocaleResolver.addListener(() => callCount++);

      // 初始为 system，切换到 zh
      LocaleResolver.updateMode(AppLocaleMode.zh);
      expect(callCount, 1);
      expect(LocaleResolver.currentMode, AppLocaleMode.zh);

      // 再次 updateMode 为相同的 zh，不重复触发
      LocaleResolver.updateMode(AppLocaleMode.zh);
      expect(callCount, 1);

      // 切换到 en
      LocaleResolver.updateMode(AppLocaleMode.en);
      expect(callCount, 2);
      expect(LocaleResolver.currentMode, AppLocaleMode.en);
    });

    test('localeModeProvider 变更时联动更新 LocaleResolver 并触发 onChange', () async {
      var callCount = 0;
      LocaleResolver.addListener(() => callCount++);

      final container = ProviderContainer();
      addTearDown(container.dispose);

      final controller = container.read(localeModeProvider.notifier);

      await controller.setMode(AppLocaleMode.zh);
      expect(callCount, 1);
      expect(LocaleResolver.currentMode, AppLocaleMode.zh);
      expect(LocaleResolver.resolve(), const Locale('zh'));

      await controller.setMode(AppLocaleMode.en);
      expect(callCount, 2);
      expect(LocaleResolver.currentMode, AppLocaleMode.en);
      expect(LocaleResolver.resolve(), const Locale('en'));

      await controller.setMode(AppLocaleMode.system);
      expect(callCount, 3);
      expect(LocaleResolver.currentMode, AppLocaleMode.system);
    });
  });
}
