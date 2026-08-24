import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 工具调用按回合聚合持久化键。
const String kToolGroupCoalesceKey = 'settings.groupToolsByTurn';

/// 工具调用按回合聚合偏好设置 Provider（持久化到 shared_preferences）。
final toolGroupCoalesceProvider =
    NotifierProvider<ToolGroupCoalesceController, bool>(
  ToolGroupCoalesceController.new,
);

/// 工具调用按回合聚合控制器。
///
/// 控制工具调用是按回合聚合成单个卡片展示（默认 true），
/// 还是按 anchorMessageID 穿插在对应 assistant 消息旁展示（false）。
class ToolGroupCoalesceController extends Notifier<bool> {
  /// 持久化 Key。
  static const String keyCoalesceTools = kToolGroupCoalesceKey;

  /// 读取聚合偏好设置的静态辅助。
  static Future<bool> loadCoalescePref({
    SharedPreferences? customPrefs,
  }) async {
    try {
      final prefs = customPrefs ?? await SharedPreferences.getInstance();
      return prefs.getBool(keyCoalesceTools) ?? true;
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
      final value = await loadCoalescePref();
      if (!_hasCustomState) {
        state = value;
      }
    } catch (_) {
      // Ignored in unit test environments.
    }
  }

  /// 外部手动触发加载。
  Future<void> load() => _load();

  /// 更新聚合开关并持久化到 [SharedPreferences]。
  Future<void> setCoalesce(bool value) async {
    _hasCustomState = true;
    state = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(keyCoalesceTools, value);
    } catch (_) {
      // Ignored in unit test environments.
    }
  }
}
