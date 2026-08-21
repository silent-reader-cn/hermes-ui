import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/accessibility.dart';
import '../../l10n/app_localizations.dart';
import 'session_entry_visibility.dart';

/// 会话列表顶部工具行入口组件（对齐 Hermex SessionSidebarUtilityRows）。
///
/// 提供 4 个核心功能模块的快捷跳转（记忆入口已移至设置页）：
/// 1. 任务 (Tasks) → /tasks (CupertinoIcons.clock, 对齐 LucideCalendarClock)
/// 2. 看板 (Kanban) → /kanban (CupertinoIcons.square_list, 对齐 LucideColumns3)
/// 3. 技能 (Skills) → /skills (CupertinoIcons.hammer, 对齐 LucideHammer)
/// 4. 统计 (Insights) → /insights (CupertinoIcons.chart_bar_square, 对齐 LucideChartColumnIncreasing)
///
/// 视觉采用纯 Cupertino 风格，支持深浅色自适应及 VoiceOver 语义与触觉反馈。
class SessionListUtilityRows extends ConsumerWidget {
  const SessionListUtilityRows({
    super.key,
    this.onTapTasks,
    this.onTapKanban,
    this.onTapSkills,
    this.onTapInsights,
  });

  /// 任务入口自定义点击回调（为空时默认 context.go('/tasks')）。
  final VoidCallback? onTapTasks;

  /// 看板入口自定义点击回调（为空时默认 context.go('/kanban')）。
  final VoidCallback? onTapKanban;

  /// 技能入口自定义点击回调（为空时默认 context.go('/skills')）。
  final VoidCallback? onTapSkills;

  /// 统计入口自定义点击回调（为空时默认 context.go('/insights')）。
  final VoidCallback? onTapInsights;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visibility = ref.watch(sessionEntryVisibilityProvider);
    if (!visibility.showsAny) {
      return const SizedBox.shrink();
    }

    final l10n = AppLocalizations.of(context);
    final items = <Widget>[
      if (visibility.tasks)
        _buildUtilityItem(
          context,
          key: const ValueKey('session-list-utility-tasks'),
          icon: CupertinoIcons.clock,
          label: l10n.tasks,
          route: '/tasks',
          customCallback: onTapTasks,
        ),
      if (visibility.kanban)
        _buildUtilityItem(
          context,
          key: const ValueKey('session-list-utility-kanban'),
          icon: CupertinoIcons.square_list,
          label: l10n.kanban,
          route: '/kanban',
          customCallback: onTapKanban,
        ),
      if (visibility.skills)
        _buildUtilityItem(
          context,
          key: const ValueKey('session-list-utility-skills'),
          icon: CupertinoIcons.hammer,
          label: l10n.skills,
          route: '/skills',
          customCallback: onTapSkills,
        ),
      if (visibility.insights)
        _buildUtilityItem(
          context,
          key: const ValueKey('session-list-utility-insights'),
          icon: CupertinoIcons.chart_bar_square,
          label: l10n.insights,
          route: '/insights',
          customCallback: onTapInsights,
        ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Container(
        key: const ValueKey('session-list-utility-rows'),
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        decoration: BoxDecoration(
          color: CupertinoColors.secondarySystemGroupedBackground.resolveFrom(
            context,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: items,
        ),
      ),
    );
  }

  Widget _buildUtilityItem(
    BuildContext context, {
    required Key key,
    required IconData icon,
    required String label,
    required String route,
    required VoidCallback? customCallback,
  }) {
    return Expanded(
      child: AccessibleButton(
        key: key,
        label: label,
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
        onPressed: () {
          if (customCallback != null) {
            customCallback();
          } else {
            context.go(route);
          }
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 22,
              color: CupertinoColors.activeBlue.resolveFrom(context),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: CupertinoColors.label.resolveFrom(context),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
