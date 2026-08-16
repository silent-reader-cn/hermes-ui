import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/models/skills.dart';
import 'skills_providers.dart';

/// 技能浏览页（对齐 Hermex SkillsView）。
///
/// Cupertino 风格：大标题 + 刷新按钮 + 搜索框（本地过滤）+ 下拉刷新 +
/// 分类分组技能列表（名称 / 描述 / 标签 / 已禁用徽标），点击行展开详情
/// （路径 / 相关技能）；含加载 / 错误 / 空态。
class SkillsPage extends ConsumerStatefulWidget {
  const SkillsPage({super.key});

  @override
  ConsumerState<SkillsPage> createState() => _SkillsPageState();
}

class _SkillsPageState extends ConsumerState<SkillsPage> {
  final TextEditingController _searchController = TextEditingController();

  /// 已展开详情的技能名（点击行切换展开/收起）。
  final Set<String> _expandedNames = {};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(skillsControllerProvider);
    final state = async.valueOrNull;
    final groups = ref.watch(skillsGroupsProvider);
    final isSearchMode = state?.searchQuery?.isNotEmpty == true;

    return CupertinoPageScaffold(
      child: CustomScrollView(
        key: const ValueKey('skills-scroll'),
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          CupertinoSliverNavigationBar(
            largeTitle: const Text('技能'),
            trailing: CupertinoButton(
              key: const ValueKey('skills-refresh'),
              padding: EdgeInsets.zero,
              onPressed: () => unawaited(
                ref.read(skillsControllerProvider.notifier).refresh(),
              ),
              child: const Icon(CupertinoIcons.arrow_clockwise),
            ),
          ),
          CupertinoSliverRefreshControl(
            onRefresh: () =>
                ref.read(skillsControllerProvider.notifier).refresh(),
          ),
          SliverToBoxAdapter(child: _buildSearchBar()),
          ..._buildContentSlivers(async, state, groups, isSearchMode),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: CupertinoSearchTextField(
        key: const ValueKey('skills-search'),
        controller: _searchController,
        placeholder: '搜索技能',
        onChanged: (value) =>
            ref.read(skillsControllerProvider.notifier).setSearchQuery(value),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // 内容 slivers：加载 / 错误 / 空态 / 分类分组列表
  // -------------------------------------------------------------------------

  List<Widget> _buildContentSlivers(
    AsyncValue<SkillsState> async,
    SkillsState? state,
    List<SkillGroup> groups,
    bool isSearchMode,
  ) {
    if (state == null) {
      if (async.isLoading) {
        return const [
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: CupertinoActivityIndicator(radius: 14)),
          ),
        ];
      }
      return [_buildErrorSliver(async.error)];
    }

    if (groups.isEmpty) {
      return [_buildEmptySliver(isSearchMode: isSearchMode)];
    }

    return [
      for (final group in groups)
        SliverToBoxAdapter(
          child: CupertinoListSection.insetGrouped(
            header: Text(group.title),
            children: [
              for (final skill in group.skills)
                _SkillRow(
                  key: ValueKey('skills-row-${skillDisplayName(skill)}'),
                  skill: skill,
                  expanded: _expandedNames.contains(skillDisplayName(skill)),
                  onTap: () => _toggleExpanded(skill),
                ),
            ],
          ),
        ),
    ];
  }

  Widget _buildErrorSliver(Object? error) {
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              CupertinoIcons.exclamationmark_triangle,
              size: 48,
              color: CupertinoColors.systemGrey,
            ),
            const SizedBox(height: 12),
            const Text(
              '加载失败',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              _errorMessage(error),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: CupertinoColors.secondaryLabel,
              ),
            ),
            const SizedBox(height: 20),
            CupertinoButton.filled(
              key: const ValueKey('skills-retry'),
              onPressed: () => unawaited(
                ref.read(skillsControllerProvider.notifier).refresh(),
              ),
              child: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptySliver({required bool isSearchMode}) {
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isSearchMode ? CupertinoIcons.search : CupertinoIcons.hammer,
              size: 48,
              color: CupertinoColors.systemGrey,
            ),
            const SizedBox(height: 12),
            Text(
              isSearchMode ? '未找到相关技能' : '暂无技能',
              style: const TextStyle(fontSize: 17),
            ),
            const SizedBox(height: 6),
            Text(
              isSearchMode ? '换个关键词试试' : '服务器的技能将显示在这里',
              style: const TextStyle(
                fontSize: 13,
                color: CupertinoColors.secondaryLabel,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // 交互
  // -------------------------------------------------------------------------

  void _toggleExpanded(SkillSummary skill) {
    final name = skillDisplayName(skill);
    setState(() {
      if (!_expandedNames.remove(name)) {
        _expandedNames.add(name);
      }
    });
  }

  String _errorMessage(Object? error) {
    if (error is ApiException) return error.message;
    return error?.toString() ?? '未知错误';
  }
}

/// 单行技能（自绘行，对齐 Hermex SkillRow：名称 / 描述 / 标签 / 已禁用
/// 徽标 + 展开箭头；点击展开详情）。
class _SkillRow extends StatelessWidget {
  const _SkillRow({
    super.key,
    required this.skill,
    required this.expanded,
    required this.onTap,
  });

  final SkillSummary skill;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final description = _trimmedOrNull(skill.description);
    final tags = (skill.tags ?? const <String>[])
        .map((tag) => tag.trim())
        .where((tag) => tag.isNotEmpty)
        .toList();
    final disabled = skill.disabled == true;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Opacity(
          opacity: disabled ? 0.55 : 1,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          skillDisplayName(skill),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (description != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            description,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              color: CupertinoColors.secondaryLabel,
                            ),
                          ),
                        ],
                        if (disabled || tags.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              if (disabled)
                                const _Badge(text: '已禁用', highlighted: false),
                              for (final tag in tags)
                                _Badge(text: tag, highlighted: true),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Icon(
                      expanded
                          ? CupertinoIcons.chevron_down
                          : CupertinoIcons.chevron_right,
                      size: 14,
                      color: CupertinoColors.tertiaryLabel,
                    ),
                  ),
                ],
              ),
              if (expanded)
                _SkillDetail(
                  key: ValueKey('skills-detail-${skillDisplayName(skill)}'),
                  skill: skill,
                ),
            ],
          ),
        ),
      ),
    );
  }

  static String? _trimmedOrNull(String? value) {
    final trimmed = value?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }
}

/// 展开的技能详情：路径 / 相关技能（本地元数据，无额外网络请求）。
class _SkillDetail extends StatelessWidget {
  const _SkillDetail({super.key, required this.skill});

  final SkillSummary skill;

  @override
  Widget build(BuildContext context) {
    final path = skill.path?.trim();
    final related = (skill.relatedSkills ?? const <String>[])
        .map((name) => name.trim())
        .where((name) => name.isNotEmpty)
        .toList();
    final hasDetail = (path != null && path.isNotEmpty) || related.isNotEmpty;

    if (!hasDetail) {
      return const Padding(
        padding: EdgeInsets.only(top: 8),
        child: Text(
          '该技能没有更多详情',
          style: TextStyle(fontSize: 13, color: CupertinoColors.secondaryLabel),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (path != null && path.isNotEmpty) ...[
            _DetailLine(label: '路径', value: path),
            const SizedBox(height: 4),
          ],
          if (related.isNotEmpty)
            _DetailLine(label: '相关技能', value: related.join('、')),
        ],
      ),
    );
  }
}

/// 「标签：值」详情行。
class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$label：',
            style: const TextStyle(color: CupertinoColors.secondaryLabel),
          ),
          TextSpan(text: value),
        ],
      ),
      style: const TextStyle(fontSize: 13),
    );
  }
}

/// 小徽标（已禁用 / 标签）。
class _Badge extends StatelessWidget {
  const _Badge({required this.text, required this.highlighted});

  final String text;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: highlighted
            ? CupertinoColors.secondarySystemFill
            : CupertinoColors.tertiarySystemFill,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: CupertinoColors.secondaryLabel,
        ),
      ),
    );
  }
}
