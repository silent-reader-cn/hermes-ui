import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/features/desktop/window_memory.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('clampWindowBounds 屏幕边界约束算法测试', () {
    const primaryDisplay = Rect.fromLTWH(0, 0, 1920, 1080);
    const secondaryDisplay = Rect.fromLTWH(1920, 0, 1920, 1080);

    test('显示器列表为空时，保底最小尺寸与正向坐标', () {
      final target = const Rect.fromLTWH(-50, -50, 200, 150);
      final clamped = clampWindowBounds(
        target: target,
        displayBounds: const [],
        minSize: const Size(400, 300),
      );

      expect(clamped.left, equals(0.0));
      expect(clamped.top, equals(0.0));
      expect(clamped.width, equals(400.0));
      expect(clamped.height, equals(300.0));
    });

    test('窗口完全在主屏内部时保持原状', () {
      const target = Rect.fromLTWH(100, 100, 1000, 700);
      final clamped = clampWindowBounds(
        target: target,
        displayBounds: const [primaryDisplay],
      );

      expect(clamped, equals(target));
    });

    test('窗口超出主屏右侧 / 下侧时，坐标被 clamp 到可视区域内', () {
      const target = Rect.fromLTWH(1500, 800, 1000, 700);
      final clamped = clampWindowBounds(
        target: target,
        displayBounds: const [primaryDisplay],
      );

      expect(clamped.width, equals(1000.0));
      expect(clamped.height, equals(700.0));
      expect(clamped.left, equals(1920.0 - 1000.0)); // 920
      expect(clamped.top, equals(1080.0 - 700.0)); // 380
    });

    test('窗口超出主屏左侧 / 上侧时，坐标被 clamp 到屏幕左上角', () {
      const target = Rect.fromLTWH(-200, -100, 800, 600);
      final clamped = clampWindowBounds(
        target: target,
        displayBounds: const [primaryDisplay],
      );

      expect(clamped.left, equals(0.0));
      expect(clamped.top, equals(0.0));
      expect(clamped.width, equals(800.0));
      expect(clamped.height, equals(600.0));
    });

    test('窗口尺寸大于屏幕时，尺寸缩小为屏幕尺寸', () {
      const target = Rect.fromLTWH(0, 0, 2500, 1500);
      final clamped = clampWindowBounds(
        target: target,
        displayBounds: const [primaryDisplay],
      );

      expect(clamped.width, equals(1920.0));
      expect(clamped.height, equals(1080.0));
      expect(clamped.left, equals(0.0));
      expect(clamped.top, equals(0.0));
    });

    test('多显示器：窗口落在副屏时在副屏边界内约束', () {
      const target = Rect.fromLTWH(2000, 100, 1000, 700);
      final clamped = clampWindowBounds(
        target: target,
        displayBounds: const [primaryDisplay, secondaryDisplay],
      );

      expect(clamped.left, equals(2000.0));
      expect(clamped.top, equals(100.0));
      expect(clamped.width, equals(1000.0));
      expect(clamped.height, equals(700.0));
    });

    test('副屏拔出后窗口脱离所有屏幕，自动回退并约束在主屏', () {
      const target = Rect.fromLTWH(3000, 500, 1000, 700);
      final clamped = clampWindowBounds(
        target: target,
        displayBounds: const [primaryDisplay],
      );

      expect(clamped.left, equals(1920.0 - 1000.0));
      expect(clamped.top, equals(1080.0 - 700.0));
      expect(clamped.width, equals(1000.0));
      expect(clamped.height, equals(700.0));
    });
  });

  group('WindowMemoryService 服务生命周期与持久化', () {
    test('非桌面平台 initialize / restore / save / dispose 安全 no-op', () async {
      final service = WindowMemoryService(
        isDesktop: false,
      );

      await service.initialize();
      expect(service.isInitialized, isFalse);

      final restored = await service.restoreWindowBounds();
      expect(restored, isFalse);

      await service.saveCurrentBounds();
      await service.dispose();
    });

    test('restoreWindowBounds 在配置关闭时返回 false', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(WindowMemoryService.keyWindowX, 100);
      await prefs.setDouble(WindowMemoryService.keyWindowY, 100);
      await prefs.setDouble(WindowMemoryService.keyWindowWidth, 800);
      await prefs.setDouble(WindowMemoryService.keyWindowHeight, 600);

      final service = WindowMemoryService(
        isDesktop: true,
        getRememberSetting: () => false,
      );

      final restored = await service.restoreWindowBounds(
        customPrefs: prefs,
        customDisplayBounds: const [Rect.fromLTWH(0, 0, 1920, 1080)],
      );

      expect(restored, isFalse);
    });

    test('restoreWindowBounds 在无持久化数据时返回 false', () async {
      final prefs = await SharedPreferences.getInstance();
      final service = WindowMemoryService(
        isDesktop: true,
        getRememberSetting: () => true,
      );

      final restored = await service.restoreWindowBounds(
        customPrefs: prefs,
        customDisplayBounds: const [Rect.fromLTWH(0, 0, 1920, 1080)],
      );

      expect(restored, isFalse);
    });

    test('防抖保存逻辑测试', () {
      fakeAsync((async) {
        final service = WindowMemoryService(
          isDesktop: false,
          debounceDuration: const Duration(milliseconds: 300),
        );

        service.onWindowMove();
        service.onWindowResize();
        service.onWindowMoved();
        service.onWindowResized();

        async.elapse(const Duration(milliseconds: 400));
      });
    });

    test('Provider 注入与释放测试', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final service = container.read(windowMemoryServiceProvider);
      expect(service, isNotNull);
    });
  });
}
