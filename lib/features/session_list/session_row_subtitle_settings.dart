import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 会话行副标题显示项配置（对齐蓝本 `SessionRowDisplaySettings`，
/// 蓝本仅控制消息数 / 工作区，本项目扩展为完整开关组）。
///
/// 控制会话列表每行副标题（元数据行）显示哪些信息：
/// - [messageCount]：消息数量（如「5 条消息」），默认开；
/// - [projectName]：所属项目名称，默认开；
/// - [workspace]：工作区路径末段，默认开；
/// - [channel]：来源渠道（sourceLabel，如 webui / qq），默认关；
/// - [estimatedCost]：预估价钱（estimated_cost），默认关。
class SessionRowSubtitleSettings {
  const SessionRowSubtitleSettings({
    this.messageCount = true,
    this.projectName = true,
    this.workspace = true,
    this.channel = false,
    this.estimatedCost = false,
  });

  /// 默认配置（渠道与预估价钱默认关闭）。
  static const SessionRowSubtitleSettings defaults =
      SessionRowSubtitleSettings();

  /// 是否显示消息数量。
  final bool messageCount;

  /// 是否显示所属项目名称。
  final bool projectName;

  /// 是否显示工作区路径末段。
  final bool workspace;

  /// 是否显示来源渠道。
  final bool channel;

  /// 是否显示预估价钱。
  final bool estimatedCost;

  /// 创建副本并覆写指定字段。
  SessionRowSubtitleSettings copyWith({
    bool? messageCount,
    bool? projectName,
    bool? workspace,
    bool? channel,
    bool? estimatedCost,
  }) {
    return SessionRowSubtitleSettings(
      messageCount: messageCount ?? this.messageCount,
      projectName: projectName ?? this.projectName,
      workspace: workspace ?? this.workspace,
      channel: channel ?? this.channel,
      estimatedCost: estimatedCost ?? this.estimatedCost,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SessionRowSubtitleSettings &&
          runtimeType == other.runtimeType &&
          messageCount == other.messageCount &&
          projectName == other.projectName &&
          workspace == other.workspace &&
          channel == other.channel &&
          estimatedCost == other.estimatedCost;

  @override
  int get hashCode =>
      Object.hash(messageCount, projectName, workspace, channel, estimatedCost);

  @override
  String toString() =>
      'SessionRowSubtitleSettings(messageCount: $messageCount, '
      'projectName: $projectName, workspace: $workspace, '
      'channel: $channel, estimatedCost: $estimatedCost)';
}

/// 会话行副标题显示项状态 Provider（持久化到 shared_preferences）。
final sessionRowSubtitleSettingsProvider =
    NotifierProvider<
      SessionRowSubtitleSettingsController,
      SessionRowSubtitleSettings
    >(SessionRowSubtitleSettingsController.new);

/// 控制会话行副标题显示项及本地持久化的 Notifier。
class SessionRowSubtitleSettingsController
    extends Notifier<SessionRowSubtitleSettings> {
  /// SharedPreferences key 前缀。
  static const String prefix = 'session_row_subtitle_';

  /// 消息数量开关 key。
  static const String keyMessageCount = '${prefix}show_message_count';

  /// 项目名称开关 key。
  static const String keyProjectName = '${prefix}show_project_name';

  /// 工作区开关 key。
  static const String keyWorkspace = '${prefix}show_workspace';

  /// 渠道开关 key。
  static const String keyChannel = '${prefix}show_channel';

  /// 预估价钱开关 key。
  static const String keyEstimatedCost = '${prefix}show_estimated_cost';

  @override
  SessionRowSubtitleSettings build() {
    unawaited(_load());
    return const SessionRowSubtitleSettings();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = SessionRowSubtitleSettings(
      messageCount: prefs.getBool(keyMessageCount) ?? true,
      projectName: prefs.getBool(keyProjectName) ?? true,
      workspace: prefs.getBool(keyWorkspace) ?? true,
      channel: prefs.getBool(keyChannel) ?? false,
      estimatedCost: prefs.getBool(keyEstimatedCost) ?? false,
    );
  }

  /// 设置消息数量开关并持久化。
  Future<void> setMessageCount(bool value) {
    return _set(state.copyWith(messageCount: value), keyMessageCount, value);
  }

  /// 设置项目名称开关并持久化。
  Future<void> setProjectName(bool value) {
    return _set(state.copyWith(projectName: value), keyProjectName, value);
  }

  /// 设置工作区开关并持久化。
  Future<void> setWorkspace(bool value) {
    return _set(state.copyWith(workspace: value), keyWorkspace, value);
  }

  /// 设置渠道开关并持久化。
  Future<void> setChannel(bool value) {
    return _set(state.copyWith(channel: value), keyChannel, value);
  }

  /// 设置预估价钱开关并持久化。
  Future<void> setEstimatedCost(bool value) {
    return _set(state.copyWith(estimatedCost: value), keyEstimatedCost, value);
  }

  Future<void> _set(
    SessionRowSubtitleSettings next,
    String key,
    bool value,
  ) async {
    state = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }
}
