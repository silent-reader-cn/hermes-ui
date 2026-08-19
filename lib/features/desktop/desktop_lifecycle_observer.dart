import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'desktop_settings.dart';
import 'desktop_shortcuts.dart';
import 'tray_manager_service.dart';
import 'window_memory.dart';

/// 桌面平台生命周期观察器（挂载在 App 壳根部）。
///
/// 职责：
/// 1. 桌面端启动初始化：托盘服务、窗口记忆与恢复、全局快捷键注册；
/// 2. 监听桌面设置变化并动态更新服务状态（开关快捷键、更新关闭拦截）；
/// 3. 非桌面平台安全 no-op。
class DesktopLifecycleObserver extends ConsumerStatefulWidget {
  const DesktopLifecycleObserver({super.key, required this.child});

  /// 被包裹的根 Widget。
  final Widget child;

  @override
  ConsumerState<DesktopLifecycleObserver> createState() =>
      _DesktopLifecycleObserverState();
}

class _DesktopLifecycleObserverState
    extends ConsumerState<DesktopLifecycleObserver> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_initDesktopServices());
    });
  }

  Future<void> _initDesktopServices() async {
    if (!isDesktopPlatform()) return;

    try {
      final trayService = ref.read(trayManagerServiceProvider);
      await trayService.initialize();

      final memoryService = ref.read(windowMemoryServiceProvider);
      await memoryService.initialize();
      await memoryService.restoreWindowBounds();

      final settings = ref.read(desktopSettingsProvider);
      if (settings.globalShortcutsEnabled) {
        final shortcutsService = ref.read(desktopShortcutsServiceProvider);
        await shortcutsService.registerShortcuts();
      }
    } catch (e, st) {
      developer.log(
        'Failed to initialize desktop services',
        name: 'DesktopLifecycleObserver',
        error: e,
        stackTrace: st,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<DesktopSettings>(desktopSettingsProvider, (previous, next) {
      if (!isDesktopPlatform()) return;

      if (previous?.globalShortcutsEnabled != next.globalShortcutsEnabled) {
        final shortcutsService = ref.read(desktopShortcutsServiceProvider);
        if (next.globalShortcutsEnabled) {
          unawaited(shortcutsService.registerShortcuts());
        } else {
          unawaited(shortcutsService.unregisterShortcuts());
        }
      }

      if (previous?.minimizeToTray != next.minimizeToTray) {
        try {
          unawaited(windowManager.setPreventClose(next.minimizeToTray));
        } catch (e) {
          developer.log(
            'Failed to update preventClose',
            name: 'DesktopLifecycleObserver',
            error: e,
          );
        }
      }
    });

    return widget.child;
  }
}
