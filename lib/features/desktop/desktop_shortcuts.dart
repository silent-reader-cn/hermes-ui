import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../../app/router.dart';
import 'desktop_settings.dart';

/// 全局快捷键服务。
///
/// 默认注册两组系统快捷键：
/// - Ctrl+Shift+H：唤起主窗口（显示并聚焦）；
/// - Ctrl+Shift+N：深链跳转新建会话页（`/chat`）。
///
/// 支持注册失败静默降级与日志记录；非桌面平台安全 no-op。
class DesktopShortcutsService {
  /// 唤起主窗口快捷键（Ctrl + Shift + H）。
  static final HotKey showWindowHotKey = HotKey(
    key: PhysicalKeyboardKey.keyH,
    modifiers: [HotKeyModifier.control, HotKeyModifier.shift],
    scope: HotKeyScope.system,
  );

  /// 新建会话快捷键（Ctrl + Shift + N）。
  static final HotKey newSessionHotKey = HotKey(
    key: PhysicalKeyboardKey.keyN,
    modifiers: [HotKeyModifier.control, HotKeyModifier.shift],
    scope: HotKeyScope.system,
  );

  /// 唤起主窗口回调（可自定义用于测试）。
  final FutureOr<void> Function()? onShowWindow;

  /// 新建会话回调（可自定义用于测试）。
  final FutureOr<void> Function()? onNewSession;

  /// 是否为桌面平台。
  final bool isDesktop;

  /// 已成功注册的快捷键列表。
  final List<HotKey> _registeredKeys = [];

  /// 构造全局快捷键服务。
  DesktopShortcutsService({
    this.onShowWindow,
    this.onNewSession,
    bool? isDesktop,
  }) : isDesktop = isDesktop ?? isDesktopPlatform();

  /// 获取当前已注册的快捷键列表副本。
  List<HotKey> get registeredKeys => List.unmodifiable(_registeredKeys);

  /// 注册默认全局快捷键。
  Future<void> registerShortcuts() async {
    if (!isDesktop) return;

    await unregisterShortcuts();

    // 1. 注册 Ctrl+Shift+H (唤起主窗口)
    try {
      await hotKeyManager.register(
        showWindowHotKey,
        keyDownHandler: (_) => unawaited(handleShowWindow()),
      );
      _registeredKeys.add(showWindowHotKey);
    } catch (e, st) {
      developer.log(
        'Failed to register Ctrl+Shift+H hotkey (may be occupied)',
        name: 'DesktopShortcutsService',
        error: e,
        stackTrace: st,
      );
    }

    // 2. 注册 Ctrl+Shift+N (新建会话)
    try {
      await hotKeyManager.register(
        newSessionHotKey,
        keyDownHandler: (_) => unawaited(handleNewSession()),
      );
      _registeredKeys.add(newSessionHotKey);
    } catch (e, st) {
      developer.log(
        'Failed to register Ctrl+Shift+N hotkey (may be occupied)',
        name: 'DesktopShortcutsService',
        error: e,
        stackTrace: st,
      );
    }
  }

  /// 注销所有已注册快捷键。
  Future<void> unregisterShortcuts() async {
    if (!isDesktop) return;

    for (final hotKey in _registeredKeys) {
      try {
        await hotKeyManager.unregister(hotKey);
      } catch (e, st) {
        developer.log(
          'Failed to unregister hotkey: ${hotKey.debugName}',
          name: 'DesktopShortcutsService',
          error: e,
          stackTrace: st,
        );
      }
    }
    _registeredKeys.clear();
  }

  /// 处理「唤起主窗口」事件。
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
        'Failed to show and focus window',
        name: 'DesktopShortcutsService',
        error: e,
        stackTrace: st,
      );
    }
  }

  /// 处理「新建会话」事件。
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
        'Failed to show window for new session',
        name: 'DesktopShortcutsService',
        error: e,
        stackTrace: st,
      );
    }
  }

  /// 销毁服务并清理已注册快捷键。
  Future<void> dispose() async {
    await unregisterShortcuts();
  }
}

/// 全局快捷键服务 Provider。
final desktopShortcutsServiceProvider =
    Provider<DesktopShortcutsService>((ref) {
  final service = DesktopShortcutsService(
    onShowWindow: () async {
      try {
        await windowManager.show();
        await windowManager.focus();
      } catch (e) {
        developer.log(
          'Failed to show window on hotkey',
          name: 'DesktopShortcutsService',
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
          'Failed to create new session on hotkey',
          name: 'DesktopShortcutsService',
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
