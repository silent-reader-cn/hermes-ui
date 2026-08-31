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

/// 思考（推理）按回合聚合偏好设置 Provider。
///
/// 语义同工具聚合：开 = 整轮会话全部思考段合成一张折叠卡；
/// 关 = 仅相邻（无 text/tool 打断）的思考段合并。
final thinkGroupCoalesceProvider =
    NotifierProvider<ThinkGroupCoalesceController, bool>(
      ThinkGroupCoalesceController.new,
    );

/// 隐藏思考（推理）偏好设置 Provider：开 = 思考卡不渲染。
final hideReasoningProvider = NotifierProvider<HideReasoningController, bool>(
  HideReasoningController.new,
);

/// 思考聚合持久化键。
const String kThinkGroupCoalesceKey = 'settings.groupThinkByTurn';

/// 隐藏思考持久化键。
const String kHideReasoningKey = 'settings.hideReasoning';

/// 思考按回合聚合控制器。
class ThinkGroupCoalesceController extends Notifier<bool> {
  static const String keyCoalesceThink = kThinkGroupCoalesceKey;

  static Future<bool> loadCoalescePref({SharedPreferences? customPrefs}) async {
    try {
      final prefs = customPrefs ?? await SharedPreferences.getInstance();
      return prefs.getBool(keyCoalesceThink) ?? true;
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

  Future<void> load() => _load();

  Future<void> setCoalesce(bool value) async {
    _hasCustomState = true;
    state = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(keyCoalesceThink, value);
    } catch (_) {
      // Ignored in unit test environments.
    }
  }
}

/// 隐藏思考控制器。
class HideReasoningController extends Notifier<bool> {
  static const String keyHideReasoning = kHideReasoningKey;

  static Future<bool> loadHidePref({SharedPreferences? customPrefs}) async {
    try {
      final prefs = customPrefs ?? await SharedPreferences.getInstance();
      return prefs.getBool(keyHideReasoning) ?? false;
    } catch (_) {
      return false;
    }
  }

  bool _hasCustomState = false;

  @override
  bool build() {
    _hasCustomState = false;
    unawaited(_load());
    return false;
  }

  Future<void> _load() async {
    try {
      final value = await loadHidePref();
      if (!_hasCustomState) {
        state = value;
      }
    } catch (_) {
      // Ignored in unit test environments.
    }
  }

  Future<void> load() => _load();

  Future<void> setHide(bool value) async {
    _hasCustomState = true;
    state = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(keyHideReasoning, value);
    } catch (_) {
      // Ignored in unit test environments.
    }
  }
}

/// 工具调用按回合聚合控制器。
///
/// 控制工具调用是按回合聚合成单个卡片展示（默认 true），
/// 还是按 anchorMessageID 穿插在对应 assistant 消息旁展示（false）。
class ToolGroupCoalesceController extends Notifier<bool> {
  /// 持久化 Key。
  static const String keyCoalesceTools = kToolGroupCoalesceKey;

  /// 读取聚合偏好设置的静态辅助。
  static Future<bool> loadCoalescePref({SharedPreferences? customPrefs}) async {
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
