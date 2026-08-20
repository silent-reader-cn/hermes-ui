import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/connections/connection_providers.dart';
import '../../core/models/skills.dart';
import 'skills_api.dart';

/// 技能列表状态（AsyncNotifier 的 AsyncData 载荷）。
///
/// 搜索为客户端本地过滤（对齐 Hermex `filteredGroupedSkills`），
/// [searchQuery] 非空即过滤模式；空串视为退出过滤。
class SkillsState {
  const SkillsState({
    this.skills = const [],
    this.searchQuery,
    this.busySkillNames = const {},
    this.actionError,
  });

  /// 全部已加载技能（服务端顺序）。
  final List<SkillSummary> skills;

  /// 非空 = 搜索过滤模式（trim 后的关键词）。
  final String? searchQuery;

  /// 正在切换启停状态的技能名称（UI 期间禁用开关，避免并发连点）。
  final Set<String> busySkillNames;

  /// 最近一次操作错误信息（UI 弹窗展示后清除）。
  final String? actionError;

  /// 指定技能是否正在执行变更。
  bool isBusy(String name) => busySkillNames.contains(name);

  SkillsState copyWith({
    List<SkillSummary>? skills,
    String? Function()? searchQuery,
    Set<String>? busySkillNames,
    String? Function()? actionError,
  }) {
    return SkillsState(
      skills: skills ?? this.skills,
      searchQuery: searchQuery != null ? searchQuery() : this.searchQuery,
      busySkillNames: busySkillNames ?? this.busySkillNames,
      actionError: actionError != null ? actionError() : this.actionError,
    );
  }

  @override
  String toString() =>
      'SkillsState(skills: ${skills.length}, searchQuery: $searchQuery, '
      'busy: ${busySkillNames.length}, actionError: $actionError)';
}

/// 技能控制器：加载 / 刷新 / 本地搜索过滤 / 技能启停切换。
///
/// AsyncValue 语义：初始加载与刷新失败 → `AsyncError`（UI 展示错误态 +
/// 重试）；搜索为同步本地过滤，不产生网络错误；启停操作采用乐观更新与回滚。
final skillsControllerProvider =
    AsyncNotifierProvider<SkillsController, SkillsState>(SkillsController.new);

class SkillsController extends AsyncNotifier<SkillsState> {
  SkillsApi get _api =>
      ref.read(skillsApiFactoryProvider)(ref.read(apiClientProvider));

  @override
  Future<SkillsState> build() async {
    // watch：切换服务器（apiClientProvider 重建）或工厂被替换时自动重载。
    final api = ref.watch(skillsApiFactoryProvider)(
      ref.watch(apiClientProvider),
    );
    return _load(api, null);
  }

  Future<SkillsState> _load(SkillsApi api, String? previousQuery) async {
    final response = await api.fetchSkills();
    return SkillsState(
      skills: response.skills ?? const <SkillSummary>[],
      searchQuery: previousQuery,
    );
  }

  /// 下拉刷新 / 错误态重试：重新拉取列表，保留当前搜索词。
  Future<void> refresh() async {
    final query = state.valueOrNull?.searchQuery;
    try {
      state = AsyncData(await _load(_api, query));
    } on Exception catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
    }
  }

  /// 本地搜索过滤（客户端同步过滤，对齐 Hermex `filteredGroupedSkills`）；
  /// 空串退出过滤模式。
  void setSearchQuery(String query) {
    final current = state.valueOrNull;
    if (current == null) return;
    final trimmed = query.trim();
    state = AsyncData(
      current.copyWith(searchQuery: () => trimmed.isEmpty ? null : trimmed),
    );
  }

  /// 切换技能启用 / 禁用状态。
  ///
  /// 乐观更新：先在本地翻转技能的 `disabled` 状态；若后端返回失败或抛出异常，
  /// 则回滚到之前的值并设置 [SkillsState.actionError] 供页面展示。
  Future<bool> toggleSkill(SkillSummary skill, {bool? enabled}) async {
    final name = skill.name;
    if (name == null || name.isEmpty) {
      await _setActionError('技能名称为空，无法切换');
      return false;
    }

    final current = state.valueOrNull;
    if (current == null) return false;
    if (current.isBusy(name)) return false;

    final oldDisabled = skill.disabled ?? false;
    final targetEnabled = enabled ?? oldDisabled;
    final newDisabled = !targetEnabled;

    await _setBusy(name, true);
    _replaceSkill(name, skill.copyWith(disabled: newDisabled));

    try {
      final response = await _api.toggleSkill(
        name: name,
        enabled: targetEnabled,
      );
      if (response.ok == false) {
        _replaceSkill(name, skill);
        await _setActionError('切换失败，服务器未确认');
        return false;
      }
      if (response.enabled != null) {
        _replaceSkill(name, skill.copyWith(disabled: !response.enabled!));
      }
      return true;
    } on ApiException catch (error) {
      _replaceSkill(name, skill);
      await _setActionError(error.message);
      return false;
    } on Exception catch (error) {
      _replaceSkill(name, skill);
      await _setActionError(error.toString());
      return false;
    } finally {
      await _setBusy(name, false);
    }
  }

  /// 清除操作错误标记（UI 弹窗展示完后调用）。
  Future<void> clearActionError() async {
    final current = state.valueOrNull;
    if (current == null || current.actionError == null) return;
    state = AsyncData(current.copyWith(actionError: () => null));
  }

  Future<void> _setBusy(String skillName, bool busy) async {
    final current = state.valueOrNull;
    if (current == null) return;
    final next = Set<String>.of(current.busySkillNames);
    if (busy) {
      next.add(skillName);
    } else {
      next.remove(skillName);
    }
    state = AsyncData(current.copyWith(busySkillNames: next));
  }

  Future<void> _setActionError(String message) async {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData(current.copyWith(actionError: () => message));
  }

  void _replaceSkill(String name, SkillSummary replacement) {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData(
      current.copyWith(
        skills: [
          for (final item in current.skills)
            (item.name == name) ? replacement : item,
        ],
      ),
    );
  }
}

/// 技能展示名：trim 后非空取原名，否则「未命名技能」（对齐 Hermex displayName）。
String skillDisplayName(SkillSummary skill) {
  final name = skill.name?.trim();
  return (name == null || name.isEmpty) ? '未命名技能' : name;
}

/// 技能分类名：trim 后非空取原分类，否则「未分类」（对齐 Hermex categoryName）。
String skillCategoryName(SkillSummary skill) {
  final category = skill.category?.trim();
  return (category == null || category.isEmpty) ? '未分类' : category;
}

/// 搜索匹配：名称 / 描述 / 分类 / 标签任一包含 query（大小写不敏感，
/// 对齐 Hermex `filteredGroupedSkills` 的四路匹配）。
bool skillMatchesQuery(SkillSummary skill, String query) {
  final lower = query.toLowerCase();
  bool contains(String? value) => (value ?? '').toLowerCase().contains(lower);
  if (contains(skill.name)) return true;
  if (contains(skill.description)) return true;
  if (contains(skill.category)) return true;
  return (skill.tags ?? const []).any(
    (tag) => tag.toLowerCase().contains(lower),
  );
}

/// 技能分组（对齐 Hermex `groupedSkills`：分类名升序，组内按展示名升序，
/// 均大小写不敏感）。
class SkillGroup {
  const SkillGroup({required this.title, required this.skills});

  /// 分类标题（缺失分类 → 「未分类」）。
  final String title;

  /// 组内技能（已按展示名升序）。
  final List<SkillSummary> skills;
}

/// 把技能列表分组；[query] 非空时先按四路匹配过滤（无命中 → 空分组）。
List<SkillGroup> buildSkillGroups(List<SkillSummary> skills, {String? query}) {
  final trimmed = query?.trim();
  final filtered = (trimmed == null || trimmed.isEmpty)
      ? skills
      : skills.where((skill) => skillMatchesQuery(skill, trimmed)).toList();
  if (filtered.isEmpty) return const [];

  final byCategory = <String, List<SkillSummary>>{};
  for (final skill in filtered) {
    byCategory.putIfAbsent(skillCategoryName(skill), () => []).add(skill);
  }
  final titles = byCategory.keys.toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

  return [
    for (final title in titles)
      SkillGroup(
        title: title,
        skills: [...byCategory[title]!]
          ..sort(
            (a, b) =>
                skillDisplayName(a)
                    .toLowerCase()
                    .compareTo(skillDisplayName(b).toLowerCase()),
          ),
      ),
  ];
}

/// 按分类分组的技能（应用搜索过滤）；控制器未加载完成 → 空。
final skillsGroupsProvider = Provider<List<SkillGroup>>((ref) {
  final state = ref.watch(skillsControllerProvider).valueOrNull;
  if (state == null) return const [];
  return buildSkillGroups(state.skills, query: state.searchQuery);
});
