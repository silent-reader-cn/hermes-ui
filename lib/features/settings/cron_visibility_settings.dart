import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 定时会话列表显隐偏好设置模型（TASK W3）。
///
/// 控制是否在会话列表中展示定时任务（cron）会话。
/// 持久化到 [SharedPreferences]，键为 `cron_show_cron_sessions`，默认值为 `false`（默认隐藏）。
class CronVisibilitySettings {
  const CronVisibilitySettings({
    this.showCron = false,
  });

  /// 默认配置（默认隐藏定时会话）。
  static const CronVisibilitySettings defaults = CronVisibilitySettings();

  /// 是否在会话列表中显示定时会话。
  final bool showCron;

  CronVisibilitySettings copyWith({
    bool? showCron,
  }) {
    return CronVisibilitySettings(
      showCron: showCron ?? this.showCron,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CronVisibilitySettings &&
          runtimeType == other.runtimeType &&
          showCron == other.showCron;

  @override
  int get hashCode => showCron.hashCode;

  @override
  String toString() => 'CronVisibilitySettings(showCron: $showCron)';
}

/// 定时会话显隐状态 Provider（持久化到 shared_preferences）。
final cronVisibilityProvider =
    NotifierProvider<CronVisibilityController, CronVisibilitySettings>(
  CronVisibilityController.new,
);

/// 控制定时会话显隐及本地持久化的 Notifier。
class CronVisibilityController extends Notifier<CronVisibilitySettings> {
  /// SharedPreferences key。
  static const String keyShowCron = 'cron_show_cron_sessions';

  /// 读取定时会话显隐偏好的静态辅助。
  static Future<bool> loadShowCronPref({
    SharedPreferences? customPrefs,
  }) async {
    try {
      final prefs = customPrefs ?? await SharedPreferences.getInstance();
      return prefs.getBool(keyShowCron) ?? false;
    } catch (_) {
      return false;
    }
  }

  bool _hasCustomState = false;

  @override
  CronVisibilitySettings build() {
    _hasCustomState = false;
    unawaited(_load());
    return const CronVisibilitySettings();
  }

  Future<void> _load() async {
    try {
      final show = await loadShowCronPref();
      if (!_hasCustomState) {
        state = CronVisibilitySettings(showCron: show);
      }
    } catch (_) {
      // Ignored in unit test environments.
    }
  }

  /// 设置定时会话显隐并持久化到本地。
  Future<void> setShowCron(bool value) async {
    _hasCustomState = true;
    state = state.copyWith(showCron: value);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(keyShowCron, value);
    } catch (_) {
      // Ignored in unit test environments.
    }
  }
}
