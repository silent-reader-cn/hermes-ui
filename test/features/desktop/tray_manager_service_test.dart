import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermex_flutter/features/desktop/tray_manager_service.dart';
import 'package:tray_manager/tray_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TrayManagerService 系统托盘逻辑测试', () {
    test('非桌面平台 initialize / updateContextMenu / dispose 安全 no-op', () async {
      final service = TrayManagerService(
        isDesktop: false,
      );

      await service.initialize();
      expect(service.isInitialized, isFalse);

      await service.updateContextMenu();
      await service.dispose();
    });

    test('handleShowWindow 触发自定义回调', () async {
      bool showCalled = false;
      final service = TrayManagerService(
        isDesktop: false,
        onShowWindow: () {
          showCalled = true;
        },
      );

      await service.handleShowWindow();
      expect(showCalled, isTrue);
    });

    test('handleNewSession 触发自定义回调', () async {
      bool newSessionCalled = false;
      final service = TrayManagerService(
        isDesktop: false,
        onNewSession: () {
          newSessionCalled = true;
        },
      );

      await service.handleNewSession();
      expect(newSessionCalled, isTrue);
    });

    test('handleQuit 触发自定义回调', () async {
      bool quitCalled = false;
      final service = TrayManagerService(
        isDesktop: false,
        onQuit: () {
          quitCalled = true;
        },
      );

      await service.handleQuit();
      expect(quitCalled, isTrue);
    });

    test('onTrayIconMouseDown 触发 handleShowWindow', () async {
      bool showCalled = false;
      final service = TrayManagerService(
        isDesktop: false,
        onShowWindow: () {
          showCalled = true;
        },
      );

      service.onTrayIconMouseDown();
      await pumpEventQueue();
      expect(showCalled, isTrue);
    });

    test('onTrayMenuItemClick 菜单项分发', () async {
      bool showCalled = false;
      bool newSessionCalled = false;
      bool quitCalled = false;

      final service = TrayManagerService(
        isDesktop: false,
        onShowWindow: () => showCalled = true,
        onNewSession: () => newSessionCalled = true,
        onQuit: () => quitCalled = true,
      );

      service.onTrayMenuItemClick(
        MenuItem(key: TrayManagerService.menuItemShowWindow, label: '显示主窗口'),
      );
      await pumpEventQueue();
      expect(showCalled, isTrue);

      service.onTrayMenuItemClick(
        MenuItem(key: TrayManagerService.menuItemNewSession, label: '新建会话'),
      );
      await pumpEventQueue();
      expect(newSessionCalled, isTrue);

      service.onTrayMenuItemClick(
        MenuItem(key: TrayManagerService.menuItemQuitApp, label: '退出应用'),
      );
      await pumpEventQueue();
      expect(quitCalled, isTrue);
    });

    test('Provider 注入与释放测试', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final service = container.read(trayManagerServiceProvider);
      expect(service, isNotNull);
    });
  });
}
