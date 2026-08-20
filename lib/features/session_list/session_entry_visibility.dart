import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 会话列表功能入口显隐配置模型（TASK W5 / 蓝本 SidebarSectionVisibility）。
///
/// 包含 5 个功能入口的显隐状态，默认全部开启（true）。
class SessionEntryVisibility {
  /// 创建会话列表入口显隐状态，缺省全为 true。
  const SessionEntryVisibility({
    this.tasks = true,
    this.kanban = true,
    this.skills = true,
    this.memory = true,
    this.insights = true,
  });

  /// 默认全开配置。
  static const SessionEntryVisibility defaults = SessionEntryVisibility();

  /// 任务 (Tasks) 入口显隐。
  final bool tasks;

  /// 看板 (Kanban) 入口显隐。
  final bool kanban;

  /// 技能 (Skills) 入口显隐。
  final bool skills;

  /// 记忆 (Memory) 入口显隐。
  final bool memory;

  /// 统计 (Insights) 入口显隐。
  final bool insights;

  /// 是否有任何一个功能入口处于开启状态（对齐蓝本 `showsAnyUtilityLink` 语义）。
  bool get showsAny => tasks || kanban || skills || memory || insights;

  /// 检查指定标识的功能入口是否可见。
  ///
  /// 支持的标识：`tasks`, `kanban`, `skills`, `memory`, `insights`。未知标识默认返回 true。
  bool isVisible(String entry) {
    switch (entry) {
      case 'tasks':
        return tasks;
      case 'kanban':
        return kanban;
      case 'skills':
        return skills;
      case 'memory':
        return memory;
      case 'insights':
        return insights;
      default:
        return true;
    }
  }

  /// 创建副本并覆写指定字段。
  SessionEntryVisibility copyWith({
    bool? tasks,
    bool? kanban,
    bool? skills,
    bool? memory,
    bool? insights,
  }) {
    return SessionEntryVisibility(
      tasks: tasks ?? this.tasks,
      kanban: kanban ?? this.kanban,
      skills: skills ?? this.skills,
      memory: memory ?? this.memory,
      insights: insights ?? this.insights,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SessionEntryVisibility &&
          runtimeType == other.runtimeType &&
          tasks == other.tasks &&
          kanban == other.kanban &&
          skills == other.skills &&
          memory == other.memory &&
          insights == other.insights;

  @override
  int get hashCode => Object.hash(tasks, kanban, skills, memory, insights);

  @override
  String toString() =>
      'SessionEntryVisibility(tasks: $tasks, kanban: $kanban, skills: $skills, memory: $memory, insights: $insights)';
}

/// 会话列表功能入口显隐状态 Provider（持久化到 shared_preferences）。
final sessionEntryVisibilityProvider =
    NotifierProvider<SessionEntryVisibilityController, SessionEntryVisibility>(
  SessionEntryVisibilityController.new,
);

/// 控制会话列表功能入口显隐及本地持久化的 Notifier。
class SessionEntryVisibilityController extends Notifier<SessionEntryVisibility> {
  /// SharedPreferences key 前缀。
  static const String prefix = 'session_entry_visibility_';

  /// 任务入口持久化 key。
  static const String keyTasks = 'session_entry_visibility_tasks';

  /// 看板入口持久化 key。
  static const String keyKanban = 'session_entry_visibility_kanban';

  /// 技能入口持久化 key。
  static const String keySkills = 'session_entry_visibility_skills';

  /// 记忆入口持久化 key。
  static const String keyMemory = 'session_entry_visibility_memory';

  /// 统计入口持久化 key。
  static const String keyInsights = 'session_entry_visibility_insights';

  @override
  SessionEntryVisibility build() {
    unawaited(_load());
    return const SessionEntryVisibility();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final tasks = prefs.getBool(keyTasks) ?? true;
    final kanban = prefs.getBool(keyKanban) ?? true;
    final skills = prefs.getBool(keySkills) ?? true;
    final memory = prefs.getBool(keyMemory) ?? true;
    final insights = prefs.getBool(keyInsights) ?? true;

    state = SessionEntryVisibility(
      tasks: tasks,
      kanban: kanban,
      skills: skills,
      memory: memory,
      insights: insights,
    );
  }

  /// 设置指定功能入口的显隐并持久化到本地。
  Future<void> setVisible(String entry, bool value) async {
    switch (entry) {
      case 'tasks':
        state = state.copyWith(tasks: value);
        break;
      case 'kanban':
        state = state.copyWith(kanban: value);
        break;
      case 'skills':
        state = state.copyWith(skills: value);
        break;
      case 'memory':
        state = state.copyWith(memory: value);
        break;
      case 'insights':
        state = state.copyWith(insights: value);
        break;
      default:
        return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$prefix$entry', value);
  }
}
