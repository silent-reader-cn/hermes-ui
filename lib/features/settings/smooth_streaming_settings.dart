import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 平滑输出持久化键。
const String kSmoothStreamingKey = 'settings.smoothStreaming';

/// 平滑打字机输出偏好设置 Provider（持久化到 shared_preferences，默认开启）。
final smoothStreamingProvider =
    NotifierProvider<SmoothStreamingController, bool>(
      SmoothStreamingController.new,
    );

/// 平滑打字机输出控制器。
class SmoothStreamingController extends Notifier<bool> {
  /// 持久化 Key。
  static const String keySmoothStreaming = kSmoothStreamingKey;

  /// 读取平滑输出偏好设置的静态辅助（默认 true）。
  static Future<bool> loadSmoothStreamingPref({
    SharedPreferences? customPrefs,
  }) async {
    try {
      final prefs = customPrefs ?? await SharedPreferences.getInstance();
      return prefs.getBool(keySmoothStreaming) ?? true;
    } catch (_) {
      return true;
    }
  }

  bool _hasCustomState = false;

  @override
  bool build() {
    _hasCustomState = false;
    unawaited(_load());
    return true;
  }

  Future<void> _load() async {
    try {
      final value = await loadSmoothStreamingPref();
      if (!_hasCustomState) {
        state = value;
      }
    } catch (_) {
      // Ignored in unit test environments.
    }
  }

  /// 外部手动触发加载。
  Future<void> load() => _load();

  /// 更新平滑输出开关并持久化到 [SharedPreferences]。
  Future<void> setSmoothStreaming(bool value) async {
    _hasCustomState = true;
    state = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(keySmoothStreaming, value);
    } catch (_) {
      // Ignored in unit test environments.
    }
  }
}
