import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'locale_provider.dart';

/// 全局语言解析器：widget 树外（托盘/通知/转译表）取有效语言。
class LocaleResolver {
  LocaleResolver._();

  static AppLocaleMode _currentMode = AppLocaleMode.system;

  static void Function()? _onChange;

  /// 供测试环境注入的平台语言。
  @visibleForTesting
  static Locale? mockPlatformLocale;

  /// 当前有效语言是否为英文。
  static bool get isEnglish => resolve().languageCode == 'en';

  /// 当前缓存的语言模式。
  static AppLocaleMode get currentMode => _currentMode;

  /// L2 接线用：获取当前注册的模式变化回调。
  static void Function()? get onChange => _onChange;

  /// 设置模式变化回调（L2 接线用：托盘重建等）。
  static void setOnChange(void Function()? callback) {
    _onChange = callback;
  }

  /// 解析当前有效 [Locale]：
  /// - mode != system：直接返回固定值（zh -> Locale('zh'), en -> Locale('en')）
  /// - mode == system：根据系统平台语言解析：
  ///   系统 zh*（如 zh, zh_CN, zh_TW 等）-> Locale('zh')，其余 -> Locale('en')。
  static Locale resolve() {
    switch (_currentMode) {
      case AppLocaleMode.zh:
        return const Locale('zh');
      case AppLocaleMode.en:
        return const Locale('en');
      case AppLocaleMode.system:
        final platformLocale =
            mockPlatformLocale ?? PlatformDispatcher.instance.locale;
        if (platformLocale.languageCode.toLowerCase() == 'zh') {
          return const Locale('zh');
        }
        return const Locale('en');
    }
  }

  /// 供 [localeModeProvider] 联动更新内部模式缓存并触发 [_onChange]。
  static void updateMode(AppLocaleMode mode) {
    if (_currentMode == mode) return;
    _currentMode = mode;
    _onChange?.call();
  }

  /// 重置为初始状态（主要用于测试清理）。
  @visibleForTesting
  static void reset({AppLocaleMode mode = AppLocaleMode.system}) {
    _currentMode = mode;
    _onChange = null;
    mockPlatformLocale = null;
  }
}
