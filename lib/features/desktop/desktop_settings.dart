import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 桌面平台配置状态模型。
///
/// 包含三个平台能力开关（默认均为开启）：
/// 1. [minimizeToTray]：最小化到托盘（关闭窗口时隐藏到托盘而非退出）；
/// 2. [globalShortcutsEnabled]：全局快捷键（Ctrl+Shift+H / Ctrl+Shift+N）；
/// 3. [rememberWindowPosition]：记住窗口位置与大小。
class DesktopSettings {
  /// 是否开启最小化到托盘。
  final bool minimizeToTray;

  /// 是否开启全局快捷键。
  final bool globalShortcutsEnabled;

  /// 是否开启记住窗口位置。
  final bool rememberWindowPosition;

  /// 构造桌面配置模型。
  const DesktopSettings({
    this.minimizeToTray = true,
    this.globalShortcutsEnabled = true,
    this.rememberWindowPosition = true,
  });

  /// 复制并更新部分字段。
  DesktopSettings copyWith({
    bool? minimizeToTray,
    bool? globalShortcutsEnabled,
    bool? rememberWindowPosition,
  }) {
    return DesktopSettings(
      minimizeToTray: minimizeToTray ?? this.minimizeToTray,
      globalShortcutsEnabled:
          globalShortcutsEnabled ?? this.globalShortcutsEnabled,
      rememberWindowPosition:
          rememberWindowPosition ?? this.rememberWindowPosition,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DesktopSettings &&
          runtimeType == other.runtimeType &&
          minimizeToTray == other.minimizeToTray &&
          globalShortcutsEnabled == other.globalShortcutsEnabled &&
          rememberWindowPosition == other.rememberWindowPosition;

  @override
  int get hashCode => Object.hash(
        minimizeToTray,
        globalShortcutsEnabled,
        rememberWindowPosition,
      );

  @override
  String toString() =>
      'DesktopSettings(minimizeToTray: $minimizeToTray, '
      'globalShortcutsEnabled: $globalShortcutsEnabled, '
      'rememberWindowPosition: $rememberWindowPosition)';
}

/// 桌面设置 Provider（持久化到 shared_preferences）。
final desktopSettingsProvider =
    NotifierProvider<DesktopSettingsController, DesktopSettings>(
  DesktopSettingsController.new,
);

/// 桌面设置 Controller。
class DesktopSettingsController extends Notifier<DesktopSettings> {
  /// 最小化到托盘持久化 Key。
  static const String keyMinimizeToTray = 'desktop_minimize_to_tray';

  /// 全局快捷键持久化 Key。
  static const String keyGlobalShortcutsEnabled =
      'desktop_global_shortcuts_enabled';

  /// 记住窗口位置持久化 Key。
  static const String keyRememberWindowPosition =
      'desktop_remember_window_position';

  @override
  DesktopSettings build() {
    unawaited(_load());
    return const DesktopSettings();
  }

  /// 从 [SharedPreferences] 异步加载配置。
  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final minimize = prefs.getBool(keyMinimizeToTray) ?? true;
    final shortcuts = prefs.getBool(keyGlobalShortcutsEnabled) ?? true;
    final rememberWindow = prefs.getBool(keyRememberWindowPosition) ?? true;
    state = DesktopSettings(
      minimizeToTray: minimize,
      globalShortcutsEnabled: shortcuts,
      rememberWindowPosition: rememberWindow,
    );
  }

  /// 更新「最小化到托盘」开关。
  Future<void> setMinimizeToTray(bool value) async {
    state = state.copyWith(minimizeToTray: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(keyMinimizeToTray, value);
  }

  /// 更新「全局快捷键」开关。
  Future<void> setGlobalShortcutsEnabled(bool value) async {
    state = state.copyWith(globalShortcutsEnabled: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(keyGlobalShortcutsEnabled, value);
  }

  /// 更新「记住窗口位置」开关。
  Future<void> setRememberWindowPosition(bool value) async {
    state = state.copyWith(rememberWindowPosition: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(keyRememberWindowPosition, value);
  }
}

/// 判断当前运行平台是否为桌面平台（Windows / macOS / Linux）。
bool isDesktopPlatform({TargetPlatform? platform, bool? isWeb}) {
  if (isWeb ?? kIsWeb) return false;
  final target = platform ?? defaultTargetPlatform;
  return target == TargetPlatform.windows ||
      target == TargetPlatform.macOS ||
      target == TargetPlatform.linux;
}
