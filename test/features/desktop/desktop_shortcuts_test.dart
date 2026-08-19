import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermex_flutter/features/desktop/desktop_shortcuts.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DesktopShortcutsService 快捷键定义与逻辑', () {
    test('Ctrl+Shift+H 与 Ctrl+Shift+N 键位定义正确', () {
      final showWindow = DesktopShortcutsService.showWindowHotKey;
      expect(showWindow.key, equals(PhysicalKeyboardKey.keyH));
      expect(
        showWindow.modifiers,
        containsAll([HotKeyModifier.control, HotKeyModifier.shift]),
      );
      expect(showWindow.scope, equals(HotKeyScope.system));

      final newSession = DesktopShortcutsService.newSessionHotKey;
      expect(newSession.key, equals(PhysicalKeyboardKey.keyN));
      expect(
        newSession.modifiers,
        containsAll([HotKeyModifier.control, HotKeyModifier.shift]),
      );
      expect(newSession.scope, equals(HotKeyScope.system));
    });

    test('非桌面平台 registerShortcuts / unregisterShortcuts 安全 no-op', () async {
      final service = DesktopShortcutsService(
        isDesktop: false,
      );

      await service.registerShortcuts();
      expect(service.registeredKeys, isEmpty);

      await service.unregisterShortcuts();
      expect(service.registeredKeys, isEmpty);
    });

    test('handleShowWindow 触发自定义 onShowWindow 回调', () async {
      bool showCalled = false;
      final service = DesktopShortcutsService(
        isDesktop: false,
        onShowWindow: () {
          showCalled = true;
        },
      );

      await service.handleShowWindow();
      expect(showCalled, isTrue);
    });

    test('handleNewSession 触发自定义 onNewSession 回调', () async {
      bool newSessionCalled = false;
      final service = DesktopShortcutsService(
        isDesktop: false,
        onNewSession: () {
          newSessionCalled = true;
        },
      );

      await service.handleNewSession();
      expect(newSessionCalled, isTrue);
    });

    test('Provider 注入与释放测试', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final service = container.read(desktopShortcutsServiceProvider);
      expect(service, isNotNull);
    });
  });
}
