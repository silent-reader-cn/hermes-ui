import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 会话列表功能入口显隐配置模型（TASK W5 / 蓝本 SidebarSectionVisibility）。
///
/// 包含 7 个功能入口的显隐状态：任务、看板、工作区、技能、统计、记忆、下载。
class SessionEntryVisibility {
  /// 创建会话列表入口显隐状态，缺省 tasks/skills/insights/workspaces/memory/downloads 开、kanban 关。
  const SessionEntryVisibility({
    this.tasks = true,
    this.kanban = false,
    this.skills = true,
    this.insights = true,
    this.workspaces = true,
    this.memory = true,
    this.downloads = true,
  });

  /// 默认全开配置（看板默认隐藏）。
  static const SessionEntryVisibility defaults = SessionEntryVisibility();

  /// 任务 (Tasks) 入口显隐。
  final bool tasks;

  /// 看板 (Kanban) 入口显隐。
  final bool kanban;

  /// 技能 (Skills) 入口显隐。
  final bool skills;

  /// 统计 (Insights) 入口显隐。
  final bool insights;

  /// 工作区 (Workspaces) 入口显隐。
  final bool workspaces;

  /// 记忆 (Memory) 入口显隐。
  final bool memory;

  /// 下载 (Downloads) 入口显隐。
  final bool downloads;

  /// 是否有任何一个功能入口处于开启状态（对齐蓝本 `showsAnyUtilityLink` 语义）。
  bool get showsAny =>
      tasks ||
      kanban ||
      skills ||
      insights ||
      workspaces ||
      memory ||
      downloads;

  /// 检查指定标识的功能入口是否可见。
  ///
  /// 支持的标识：`tasks`, `kanban`, `skills`, `insights`, `workspaces`, `memory`, `downloads`。未知标识默认返回 true。
  bool isVisible(String entry) {
    switch (entry) {
      case 'tasks':
        return tasks;
      case 'kanban':
        return kanban;
      case 'skills':
        return skills;
      case 'insights':
        return insights;
      case 'workspaces':
        return workspaces;
      case 'memory':
        return memory;
      case 'downloads':
        return downloads;
      default:
        return true;
    }
  }

  /// 创建副本并覆写指定字段。
  SessionEntryVisibility copyWith({
    bool? tasks,
    bool? kanban,
    bool? skills,
    bool? insights,
    bool? workspaces,
    bool? memory,
    bool? downloads,
  }) {
    return SessionEntryVisibility(
      tasks: tasks ?? this.tasks,
      kanban: kanban ?? this.kanban,
      skills: skills ?? this.skills,
      insights: insights ?? this.insights,
      workspaces: workspaces ?? this.workspaces,
      memory: memory ?? this.memory,
      downloads: downloads ?? this.downloads,
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
          insights == other.insights &&
          workspaces == other.workspaces &&
          memory == other.memory &&
          downloads == other.downloads;

  @override
  int get hashCode => Object.hash(
    tasks,
    kanban,
    skills,
    insights,
    workspaces,
    memory,
    downloads,
  );

  @override
  String toString() =>
      'SessionEntryVisibility(tasks: $tasks, kanban: $kanban, skills: $skills, insights: $insights, workspaces: $workspaces, memory: $memory, downloads: $downloads)';
}

/// 会话列表功能入口显隐状态 Provider（持久化到 shared_preferences）。
final sessionEntryVisibilityProvider =
    NotifierProvider<SessionEntryVisibilityController, SessionEntryVisibility>(
      SessionEntryVisibilityController.new,
    );

/// 控制会话列表功能入口显隐及本地持久化的 Notifier。
class SessionEntryVisibilityController
    extends Notifier<SessionEntryVisibility> {
  /// SharedPreferences key 前缀。
  static const String prefix = 'session_entry_visibility_';

  /// 任务入口持久化 key。
  static const String keyTasks = 'session_entry_visibility_tasks';

  /// 看板入口持久化 key。
  static const String keyKanban = 'session_entry_visibility_kanban';

  /// 技能入口持久化 key。
  static const String keySkills = 'session_entry_visibility_skills';

  /// 统计入口持久化 key。
  static const String keyInsights = 'session_entry_visibility_insights';

  /// 工作区入口持久化 key。
  static const String keyWorkspaces = 'session_entry_visibility_workspaces';

  /// 记忆入口持久化 key。
  static const String keyMemory = 'session_entry_visibility_memory';

  /// 下载入口持久化 key。
  static const String keyDownloads = 'session_entry_visibility_downloads';

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
    final insights = prefs.getBool(keyInsights) ?? true;
    final workspaces = prefs.getBool(keyWorkspaces) ?? true;
    final memory = prefs.getBool(keyMemory) ?? true;
    final downloads = prefs.getBool(keyDownloads) ?? true;

    state = SessionEntryVisibility(
      tasks: tasks,
      kanban: kanban,
      skills: skills,
      insights: insights,
      workspaces: workspaces,
      memory: memory,
      downloads: downloads,
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
      case 'insights':
        state = state.copyWith(insights: value);
        break;
      case 'workspaces':
        state = state.copyWith(workspaces: value);
        break;
      case 'memory':
        state = state.copyWith(memory: value);
        break;
      case 'downloads':
        state = state.copyWith(downloads: value);
        break;
      default:
        return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$prefix$entry', value);
  }
}
