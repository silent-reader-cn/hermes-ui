import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'locale_provider.dart';

/// 全局语言解析器：widget 树外（托盘/通知/转译表）取有效语言。
class LocaleResolver {
  LocaleResolver._();

  static AppLocaleMode _currentMode = AppLocaleMode.system;

  /// 多播监听器（token → callback）：托盘重建、通知刷新等 L2 服务层各自注册，
  /// 互不覆盖。token 用作 removeListener 的句柄。
  static final Map<Object, void Function()> _listeners = {};

  /// 供测试环境注入的平台语言。
  @visibleForTesting
  static Locale? mockPlatformLocale;

  /// 当前有效语言是否为英文。
  static bool get isEnglish => resolve().languageCode == 'en';

  /// 当前缓存的语言模式。
  static AppLocaleMode get currentMode => _currentMode;

  /// 注册模式变化监听（L2 接线用：托盘重建/通知刷新），返回注销用 token。
  static Object addListener(void Function() callback) {
    final token = Object();
    _listeners[token] = callback;
    return token;
  }

  /// 注销模式变化监听。
  static void removeListener(Object token) {
    _listeners.remove(token);
  }

  /// 当前已注册监听器数量（测试断言用）。
  static int get listenerCount => _listeners.length;

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

  /// 供 [localeModeProvider] 联动更新内部模式缓存并广播给全部监听器。
  static void updateMode(AppLocaleMode mode) {
    if (_currentMode == mode) return;
    _currentMode = mode;
    for (final callback in List<void Function()>.of(_listeners.values)) {
      callback();
    }
  }

  /// 重置为初始状态（主要用于测试清理）。
  @visibleForTesting
  static void reset({AppLocaleMode mode = AppLocaleMode.system}) {
    _currentMode = mode;
    _listeners.clear();
    mockPlatformLocale = null;
  }
}
