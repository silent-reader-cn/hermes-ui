import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'startup_registrar.dart';

/// 桌面平台配置状态模型。
///
/// 包含五个平台能力开关：
/// 1. [minimizeToTray]：最小化到托盘（关闭窗口时隐藏到托盘而非退出）；
/// 2. [globalShortcutsEnabled]：全局快捷键（Ctrl+Shift+H / Ctrl+Shift+N）；
/// 3. [rememberWindowPosition]：记住窗口位置与大小；
/// 4. [startOnLogin]：开机启动（登录 Windows 时自动启动，写 HKCU Run 注册值）；
/// 5. [silentStart]：静默启动（启动时不显示主窗口，直接驻留系统托盘）。
class DesktopSettings {
  /// 是否开启最小化到托盘。
  final bool minimizeToTray;

  /// 是否开启全局快捷键。
  final bool globalShortcutsEnabled;

  /// 是否开启记住窗口位置。
  final bool rememberWindowPosition;

  /// 是否开启开机启动（登录 Windows 时自动启动）。
  final bool startOnLogin;

  /// 是否开启静默启动（启动时不显示主窗口，直接驻留托盘）。
  final bool silentStart;

  /// 构造桌面配置模型。
  const DesktopSettings({
    this.minimizeToTray = true,
    this.globalShortcutsEnabled = true,
    this.rememberWindowPosition = true,
    this.startOnLogin = false,
    this.silentStart = false,
  });

  /// 复制并更新部分字段。
  DesktopSettings copyWith({
    bool? minimizeToTray,
    bool? globalShortcutsEnabled,
    bool? rememberWindowPosition,
    bool? startOnLogin,
    bool? silentStart,
  }) {
    return DesktopSettings(
      minimizeToTray: minimizeToTray ?? this.minimizeToTray,
      globalShortcutsEnabled:
          globalShortcutsEnabled ?? this.globalShortcutsEnabled,
      rememberWindowPosition:
          rememberWindowPosition ?? this.rememberWindowPosition,
      startOnLogin: startOnLogin ?? this.startOnLogin,
      silentStart: silentStart ?? this.silentStart,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DesktopSettings &&
          runtimeType == other.runtimeType &&
          minimizeToTray == other.minimizeToTray &&
          globalShortcutsEnabled == other.globalShortcutsEnabled &&
          rememberWindowPosition == other.rememberWindowPosition &&
          startOnLogin == other.startOnLogin &&
          silentStart == other.silentStart;

  @override
  int get hashCode => Object.hash(
    minimizeToTray,
    globalShortcutsEnabled,
    rememberWindowPosition,
    startOnLogin,
    silentStart,
  );

  @override
  String toString() =>
      'DesktopSettings(minimizeToTray: $minimizeToTray, '
      'globalShortcutsEnabled: $globalShortcutsEnabled, '
      'rememberWindowPosition: $rememberWindowPosition, '
      'startOnLogin: $startOnLogin, silentStart: $silentStart)';
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

  /// 开机启动持久化 Key。
  static const String keyStartOnLogin = 'desktop_start_on_login';

  /// 静默启动持久化 Key。
  static const String keySilentStart = 'desktop_silent_start';

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
    final startOnLogin = prefs.getBool(keyStartOnLogin) ?? false;
    final silentStart = prefs.getBool(keySilentStart) ?? false;
    state = DesktopSettings(
      minimizeToTray: minimize,
      globalShortcutsEnabled: shortcuts,
      rememberWindowPosition: rememberWindow,
      startOnLogin: startOnLogin,
      silentStart: silentStart,
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

  /// 更新「开机启动」开关。
  ///
  /// 开启时按当前状态写入注册表值（命令含/不含 `--silent` 视 [DesktopSettings.silentStart]
  /// 而定），关闭时删除注册值；重复写入/删除幂等。
  Future<void> setStartOnLogin(bool value) async {
    state = state.copyWith(startOnLogin: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(keyStartOnLogin, value);
    await _syncStartupRegistration();
  }

  /// 更新「静默启动」开关。
  ///
  /// 静默启动本身不触碰注册表；仅当「开机启动」已开启时联动重写注册表值
  /// （即时更新命令中的 `--silent`），保证勾选顺序任意、结果一致。
  Future<void> setSilentStart(bool value) async {
    state = state.copyWith(silentStart: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(keySilentStart, value);
    if (state.startOnLogin) {
      await _syncStartupRegistration();
    }
  }

  /// 按当前状态同步开机启动注册值（仅 Windows 注册表实现生效，其余平台 no-op）。
  Future<void> _syncStartupRegistration() async {
    final registrar = ref.read(startupRegistrarProvider);
    if (state.startOnLogin) {
      final command = buildStartupCommand(
        executablePath: Platform.resolvedExecutable,
        silent: state.silentStart,
      );
      await registrar.setRegistered(true, command: command);
    } else {
      await registrar.setRegistered(false);
    }
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
