import 'dart:async';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 主题模式三态（app_shell_spec.md §4）：跟随系统 / 浅色 / 深色。
enum AppThemeMode {
  system,
  light,
  dark;

  /// 映射到 Flutter [ThemeMode]（CupertinoApp.themeMode 使用）。
  ThemeMode get flutterThemeMode {
    switch (this) {
      case AppThemeMode.system:
        return ThemeMode.system;
      case AppThemeMode.light:
        return ThemeMode.light;
      case AppThemeMode.dark:
        return ThemeMode.dark;
    }
  }
}

/// 主题模式 Provider（持久化到 shared_preferences）。
final themeModeProvider = NotifierProvider<ThemeModeController, AppThemeMode>(
  ThemeModeController.new,
);

class ThemeModeController extends Notifier<AppThemeMode> {
  static const String prefsKey = 'app_theme_mode';

  @override
  AppThemeMode build() {
    unawaited(_load());
    return AppThemeMode.system;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(prefsKey);
    if (raw == null) return;
    for (final mode in AppThemeMode.values) {
      if (mode.name == raw) {
        state = mode;
        return;
      }
    }
  }

  /// 切换主题模式并持久化。
  Future<void> setMode(AppThemeMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefsKey, mode.name);
  }
}
