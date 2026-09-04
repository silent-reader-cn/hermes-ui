import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/app/locale/locale_provider.dart';
import 'package:hermes_ui/app/locale/locale_resolver.dart';
import 'package:hermes_ui/features/desktop/tray_manager_service.dart';
import 'package:hermes_ui/features/notifications/background_keepalive_service.dart';
import 'package:hermes_ui/features/webui_sidecar/webui_sidecar_models.dart';
import 'package:tray_manager/tray_manager.dart';

/// L2 收口测试：服务层经 LocaleResolver 取语言（托盘英文态 / 通知英文态 /
/// LocaleResolver 多播监听器），钉死中文与英文双态断言。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    LocaleResolver.reset();
  });

  group('LocaleResolver 多播监听器', () {
    test('多个监听器共存并按注册序广播，removeListener 生效', () {
      final calls = <String>[];
      final t1 = LocaleResolver.addListener(() => calls.add('a'));
      final t2 = LocaleResolver.addListener(() => calls.add('b'));

      LocaleResolver.updateMode(AppLocaleMode.en);
      expect(calls, ['a', 'b']);

      LocaleResolver.removeListener(t1);
      calls.clear();
      LocaleResolver.updateMode(AppLocaleMode.zh);
      expect(calls, ['b']);

      LocaleResolver.removeListener(t2);
      calls.clear();
      LocaleResolver.updateMode(AppLocaleMode.system);
      expect(calls, isEmpty);
      expect(LocaleResolver.listenerCount, 0);
    });
  });

  group('托盘菜单英文态', () {
    test('mode=en 时核心菜单项与 WebUI 状态行输出英文 label', () {
      LocaleResolver.reset(mode: AppLocaleMode.en);

      final items = TrayManagerService.buildMenuItems(
        sidecarStatus: SidecarStatus.running,
        sidecarEnabled: true,
      );
      MenuItem byKey(String key) =>
          items.firstWhere((i) => i.key == key);

      expect(byKey(TrayManagerService.menuItemShowWindow).label,
          'Show Main Window');
      expect(
          byKey(TrayManagerService.menuItemNewSession).label, 'New Session');
      expect(
          byKey(TrayManagerService.menuItemOpenWebui).label, 'Open WebUI');
      expect(
          byKey(TrayManagerService.menuItemWebuiStatus).label,
          'WebUI: Running');
      expect(byKey(TrayManagerService.menuItemQuitApp).label, 'Quit App');
    });

    test('mode=zh 时中文 label 保持（回归钉）', () {
      LocaleResolver.reset(mode: AppLocaleMode.zh);
      final items = TrayManagerService.buildMenuItems(
        sidecarStatus: SidecarStatus.stopped,
      );
      MenuItem byKey(String key) =>
          items.firstWhere((i) => i.key == key);
      expect(byKey(TrayManagerService.menuItemShowWindow).label, '显示主窗口');
      expect(byKey(TrayManagerService.menuItemWebuiStatus).label,
          'WebUI 服务：已停止');
    });

    test('formatSessionStatus 双语态', () {
      LocaleResolver.reset(mode: AppLocaleMode.en);
      expect(formatWebuiStatusLabel(SidecarStatus.failed), 'WebUI: Failed');
      LocaleResolver.reset(mode: AppLocaleMode.zh);
      expect(formatWebuiStatusLabel(SidecarStatus.failed), 'WebUI 服务：失败');
    });
  });

  group('常驻通知文案语言接线', () {
    test('formatNotificationText isEnglish 双语（既有能力回归）', () {
      expect(
          ProductionBackgroundKeepaliveService.formatNotificationText(2,
              isEnglish: true),
          '2 sessions generating');
      expect(
          ProductionBackgroundKeepaliveService.formatNotificationText(0,
              isEnglish: true),
          'No active sessions');
      expect(
          ProductionBackgroundKeepaliveService.formatNotificationText(1),
          '1 个会话正在生成');
    });
  });
}
