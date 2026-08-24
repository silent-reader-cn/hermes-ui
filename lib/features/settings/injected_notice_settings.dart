import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 注入通知折叠偏好（agent-injected-message-cards-spec §4）。
///
/// 单一开关控制全部 agent 代发通知（后台进程 / 技能 / 定时任务 / MCP）
/// 是否以紧凑卡片折叠展示。持久化到 [SharedPreferences]，键
/// `collapse_injected_notices`，兼容旧键 `collapse_process_notices`，
/// 未存时默认 `true`。
class InjectedNoticeSettings {
  const InjectedNoticeSettings({
    this.collapseInjectedNotices = true,
  });

  /// 是否折叠注入通知。
  final bool collapseInjectedNotices;

  InjectedNoticeSettings copyWith({
    bool? collapseInjectedNotices,
  }) {
    return InjectedNoticeSettings(
      collapseInjectedNotices:
          collapseInjectedNotices ?? this.collapseInjectedNotices,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InjectedNoticeSettings &&
          runtimeType == other.runtimeType &&
          collapseInjectedNotices == other.collapseInjectedNotices;

  @override
  int get hashCode => collapseInjectedNotices.hashCode;

  @override
  String toString() =>
      'InjectedNoticeSettings(collapseInjectedNotices: $collapseInjectedNotices)';
}

/// 注入通知折叠偏好 Provider（持久化到 shared_preferences）。
final injectedNoticeSettingsProvider =
    NotifierProvider<InjectedNoticeSettingsController, InjectedNoticeSettings>(
  InjectedNoticeSettingsController.new,
);

/// 注入通知折叠偏好 Controller。
class InjectedNoticeSettingsController
    extends Notifier<InjectedNoticeSettings> {
  /// 新键（spec §4）。
  static const String keyCollapseInjected = 'collapse_injected_notices';

  /// 旧键（hermes-webui 遗留，读时回落）。
  static const String legacyKeyCollapseProcess = 'collapse_process_notices';

  /// 读取折叠开关的静态辅助（供非 Riverpod 调用方，如需要同步读取时）。
  ///
  /// 优先 [keyCollapseInjected]，回落 [legacyKeyCollapseProcess]，
  /// 均缺省时返回 `true`。支持注入 [customPrefs] 以便测试使用
  /// `SharedPreferences.setMockInitialValues` 或 fake。
  static Future<bool> loadCollapsePref({
    SharedPreferences? customPrefs,
  }) async {
    final prefs = customPrefs ?? await SharedPreferences.getInstance();
    final value = prefs.getBool(keyCollapseInjected);
    if (value != null) return value;
    final legacy = prefs.getBool(legacyKeyCollapseProcess);
    if (legacy != null) return legacy;
    return true;
  }

  @override
  InjectedNoticeSettings build() {
    unawaited(_load());
    return const InjectedNoticeSettings();
  }

  Future<void> _load() async {
    state = InjectedNoticeSettings(
      collapseInjectedNotices: await loadCollapsePref(),
    );
  }

  /// 更新折叠开关并立即持久化到 [keyCollapseInjected]。
  ///
  /// 通过 Provider 通知聊天列表重建（watch 此 provider 即可）。
  Future<void> setCollapse(bool value) async {
    state = state.copyWith(collapseInjectedNotices: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(keyCollapseInjected, value);
  }
}
