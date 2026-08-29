import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 性能监控面板持久化键。
const String kShowPerfMonitorKey = 'settings.showPerfMonitor';

/// 性能监控面板开关 Provider（持久化到 shared_preferences，默认开启）。
///
/// 仅当 composerTwoPaneProvider 为 true 时面板可见；
/// 两段式关闭时该 Provider 自动置 false（由 _ChatSection.onChanged 触发）。
final perfMonitorProvider = NotifierProvider<PerfMonitorController, bool>(
  PerfMonitorController.new,
);

/// 性能监控面板开关控制器。
class PerfMonitorController extends Notifier<bool> {
  /// 持久化 Key。
  static const String keyShowPerfMonitor = kShowPerfMonitorKey;

  bool _hasCustomState = false;

  @override
  bool build() {
    _hasCustomState = false;
    unawaited(_load());
    return true; // 默认开启
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // ?? true：无历史值（新装）默认开。
      final value = prefs.getBool(keyShowPerfMonitor) ?? true;
      if (!_hasCustomState) {
        state = value;
      }
    } catch (_) {
      // Ignored in unit test environments.
    }
  }

  /// 外部手动触发加载（用于测试）。
  Future<void> load() => _load();

  /// 更新性能监控开关并持久化到 [SharedPreferences]。
  Future<void> setShowPerfMonitor(bool value) async {
    _hasCustomState = true;
    state = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(keyShowPerfMonitor, value);
    } catch (_) {
      // Ignored in unit test environments.
    }
  }
}
