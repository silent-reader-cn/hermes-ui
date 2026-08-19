import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../../app/router.dart';
import 'desktop_settings.dart';

/// 系统托盘服务。
///
/// 职责：
/// 1. 创建并维护系统托盘图标；
/// 2. 设置右键上下文菜单（显示主窗口 / 新建会话 / 退出应用）；
/// 3. 处理托盘点击恢复窗口；
/// 4. 非桌面平台安全降级 no-op。
class TrayManagerService with TrayListener {
  /// 菜单项 Key 常量
  static const String menuItemShowWindow = 'show_window';
  static const String menuItemNewSession = 'new_session';
  static const String menuItemQuitApp = 'quit_app';

  /// 唤起主窗口回调（可自定义用于测试）。
  final FutureOr<void> Function()? onShowWindow;

  /// 新建会话回调（可自定义用于测试）。
  final FutureOr<void> Function()? onNewSession;

  /// 退出应用回调（可自定义用于测试）。
  final FutureOr<void> Function()? onQuit;

  /// 是否为桌面平台。
  final bool isDesktop;

  bool _initialized = false;

  /// 构造系统托盘服务。
  TrayManagerService({
    this.onShowWindow,
    this.onNewSession,
    this.onQuit,
    bool? isDesktop,
  }) : isDesktop = isDesktop ?? isDesktopPlatform();

  /// 服务是否已初始化。
  bool get isInitialized => _initialized;

  /// 初始化托盘图标与上下文菜单。
  Future<void> initialize() async {
    if (!isDesktop || _initialized) return;

    try {
      trayManager.addListener(this);
      await _setupTrayIcon();
      await updateContextMenu();
      _initialized = true;
    } catch (e, st) {
      developer.log(
        'Failed to initialize TrayManagerService',
        name: 'TrayManagerService',
        error: e,
        stackTrace: st,
      );
    }
  }

  /// 设置托盘图标与悬浮提示。
  Future<void> _setupTrayIcon() async {
    try {
      String iconPath = 'windows/runner/resources/app_icon.ico';
      if (defaultTargetPlatform == TargetPlatform.macOS) {
        iconPath =
            'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_32.png';
      }
      await trayManager.setIcon(iconPath);
      await trayManager.setToolTip('Hermex');
    } catch (e, st) {
      developer.log(
        'Failed to set tray icon / tooltip',
        name: 'TrayManagerService',
        error: e,
        stackTrace: st,
      );
    }
  }

  /// 构建并设置托盘上下文菜单。
  Future<void> updateContextMenu() async {
    if (!isDesktop) return;

    try {
      final menu = Menu(
        items: [
          MenuItem(
            key: menuItemShowWindow,
            label: '显示主窗口',
            onClick: (_) => unawaited(handleShowWindow()),
          ),
          MenuItem(
            key: menuItemNewSession,
            label: '新建会话',
            onClick: (_) => unawaited(handleNewSession()),
          ),
          MenuItem.separator(),
          MenuItem(
            key: menuItemQuitApp,
            label: '退出应用',
            onClick: (_) => unawaited(handleQuit()),
          ),
        ],
      );
      await trayManager.setContextMenu(menu);
    } catch (e, st) {
      developer.log(
        'Failed to set tray context menu',
        name: 'TrayManagerService',
        error: e,
        stackTrace: st,
      );
    }
  }

  /// 处理「显示主窗口」操作。
  Future<void> handleShowWindow() async {
    if (onShowWindow != null) {
      await onShowWindow!();
      return;
    }
    try {
      await windowManager.show();
      await windowManager.focus();
    } catch (e, st) {
      developer.log(
        'Failed to show window',
        name: 'TrayManagerService',
        error: e,
        stackTrace: st,
      );
    }
  }

  /// 处理「新建会话」操作。
  Future<void> handleNewSession() async {
    if (onNewSession != null) {
      await onNewSession!();
      return;
    }
    try {
      await windowManager.show();
      await windowManager.focus();
    } catch (e, st) {
      developer.log(
        'Failed to handle new session',
        name: 'TrayManagerService',
        error: e,
        stackTrace: st,
      );
    }
  }

  /// 处理「退出应用」操作。
  Future<void> handleQuit() async {
    if (onQuit != null) {
      await onQuit!();
      return;
    }
    try {
      await windowManager.destroy();
    } catch (e, st) {
      developer.log(
        'Failed to destroy window on quit',
        name: 'TrayManagerService',
        error: e,
        stackTrace: st,
      );
    }
  }

  @override
  void onTrayIconMouseDown() {
    unawaited(handleShowWindow());
  }

  @override
  void onTrayIconRightMouseDown() {
    try {
      unawaited(trayManager.popUpContextMenu());
    } catch (e, st) {
      developer.log(
        'Failed to pop up tray context menu',
        name: 'TrayManagerService',
        error: e,
        stackTrace: st,
      );
    }
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case menuItemShowWindow:
        unawaited(handleShowWindow());
        break;
      case menuItemNewSession:
        unawaited(handleNewSession());
        break;
      case menuItemQuitApp:
        unawaited(handleQuit());
        break;
    }
  }

  /// 销毁托盘服务。
  Future<void> dispose() async {
    if (!isDesktop) return;

    try {
      trayManager.removeListener(this);
      await trayManager.destroy();
    } catch (e, st) {
      developer.log(
        'Failed to dispose tray manager',
        name: 'TrayManagerService',
        error: e,
        stackTrace: st,
      );
    }
    _initialized = false;
  }
}

/// 系统托盘服务 Provider。
final trayManagerServiceProvider = Provider<TrayManagerService>((ref) {
  final service = TrayManagerService(
    onShowWindow: () async {
      try {
        await windowManager.show();
        await windowManager.focus();
      } catch (e) {
        developer.log(
          'Failed to show window',
          name: 'TrayManagerService',
          error: e,
        );
      }
    },
    onNewSession: () async {
      try {
        await windowManager.show();
        await windowManager.focus();
        ref.read(routerProvider).go('/chat');
      } catch (e) {
        developer.log(
          'Failed to show window and navigate to /chat',
          name: 'TrayManagerService',
          error: e,
        );
      }
    },
    onQuit: () async {
      try {
        await windowManager.destroy();
      } catch (e) {
        developer.log(
          'Failed to destroy window',
          name: 'TrayManagerService',
          error: e,
        );
      }
    },
  );
  ref.onDispose(() {
    unawaited(service.dispose());
  });
  return service;
});
