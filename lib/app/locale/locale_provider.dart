import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'locale_resolver.dart';

/// 语言模式三态（active.md 多语言切换设置）：跟随系统 / 中文 / English。
enum AppLocaleMode {
  system,
  zh,
  en;

  /// 映射到 Flutter [Locale]，null 表示跟随系统自动解析。
  Locale? get flutterLocale {
    switch (this) {
      case AppLocaleMode.system:
        return null;
      case AppLocaleMode.zh:
        return const Locale('zh');
      case AppLocaleMode.en:
        return const Locale('en');
    }
  }
}

/// 语言模式 Provider（持久化到 shared_preferences，完全仿 [themeModeProvider]）。
final localeModeProvider =
    NotifierProvider<LocaleModeController, AppLocaleMode>(
  LocaleModeController.new,
);

class LocaleModeController extends Notifier<AppLocaleMode> {
  static const String prefsKey = 'app_locale_mode';

  @override
  AppLocaleMode build() {
    // 初值跟随 LocaleResolver 现态（生产默认 system；测试基线由
    // test/flutter_test_config.dart 预钉 zh——provider 首建不得翻转它），
    // prefs 异步加载后 setMode/updateMode 纠正为持久值。
    unawaited(_load());
    return LocaleResolver.currentMode;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(prefsKey);
    if (raw == null) return;
    for (final mode in AppLocaleMode.values) {
      if (mode.name == raw) {
        state = mode;
        LocaleResolver.updateMode(mode);
        return;
      }
    }
  }

  /// 显式等待持久化加载完成（供测试或前置启动调用）。
  Future<void> load() => _load();

  /// 切换语言模式并持久化。
  Future<void> setMode(AppLocaleMode mode) async {
    state = mode;
    LocaleResolver.updateMode(mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefsKey, mode.name);
  }
}
