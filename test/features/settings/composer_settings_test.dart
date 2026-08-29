import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/features/settings/composer_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('ComposerTwoPaneController 状态与持久化', () {
    test('默认值为 true（全新安装两段式默认开启）', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final state = container.read(composerTwoPaneProvider);
      // 任务规格：全新安装默认两段式开启（build() return true）
      expect(state, isTrue);
    });

    test('老用户显式 false 保持 false 不被覆盖', () async {
      SharedPreferences.setMockInitialValues({kComposerTwoPaneKey: false});

      final container = ProviderContainer();
      addTearDown(container.dispose);

      // ignore: unused_local_variable
      final controller = container.read(composerTwoPaneProvider.notifier);
      // 等待异步 _load 完成
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final state = container.read(composerTwoPaneProvider);
      // 已显式 false 的老用户尊重其选择
      expect(state, isFalse);
    });

    test('老用户显式 true 保持 true', () async {
      SharedPreferences.setMockInitialValues({kComposerTwoPaneKey: true});

      final container = ProviderContainer();
      addTearDown(container.dispose);

      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(container.read(composerTwoPaneProvider), isTrue);
    });

    test('setTwoPane 修改配置并写入 SharedPreferences', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // ignore: unused_local_variable
      final controller = container.read(composerTwoPaneProvider.notifier);
      await controller.setTwoPane(false);

      expect(container.read(composerTwoPaneProvider), isFalse);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(kComposerTwoPaneKey), isFalse);

      await controller.setTwoPane(true);
      expect(container.read(composerTwoPaneProvider), isTrue);
      expect(prefs.getBool(kComposerTwoPaneKey), isTrue);
    });

    test('无 SharedPreferences 值时使用默认值 true', () async {
      // 不设置任何初始值
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(container.read(composerTwoPaneProvider), isTrue);
    });
  });
}
