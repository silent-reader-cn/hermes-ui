import 'package:flutter/cupertino.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/app_localizations.dart';

/// 侧栏顶部工具条项配置。
class _UtilityItem {
  const _UtilityItem({
    required this.id,
    required this.path,
    required this.icon,
    required this.getTitle,
  });

  final String id;
  final String path;
  final IconData icon;
  final String Function(AppLocalizations l10n) getTitle;
}

/// 侧栏常驻工具入口行（TASK W2 / 蓝本 SessionListComponents.swift §SessionSidebarUtilityRows）。
///
/// 宽屏下展示在会话列表顶部，提供任务、看板、技能、记忆、统计、设置的快捷跳转与激活高亮。
class SidebarUtilityToolbar extends StatelessWidget {
  const SidebarUtilityToolbar({
    super.key,
    required this.currentLocation,
  });

  /// 当前激活的路由路径。
  final String currentLocation;

  static final List<_UtilityItem> _items = [
    _UtilityItem(
      id: 'tasks',
      path: '/tasks',
      icon: CupertinoIcons.clock,
      getTitle: (l10n) => l10n.tasksTitle,
    ),
    _UtilityItem(
      id: 'kanban',
      path: '/kanban',
      icon: CupertinoIcons.square_split_2x2,
      getTitle: (l10n) => l10n.kanbanTitle,
    ),
    _UtilityItem(
      id: 'skills',
      path: '/skills',
      icon: CupertinoIcons.hammer,
      getTitle: (l10n) => l10n.skillsTitle,
    ),
    _UtilityItem(
      id: 'memory',
      path: '/memory',
      icon: CupertinoIcons.sparkles,
      getTitle: (l10n) => l10n.memoryTitle,
    ),
    _UtilityItem(
      id: 'insights',
      path: '/insights',
      icon: CupertinoIcons.chart_bar,
      getTitle: (l10n) => l10n.insightsTitle,
    ),
    _UtilityItem(
      id: 'settings',
      path: '/settings',
      icon: CupertinoIcons.gear_alt,
      getTitle: (l10n) => l10n.settingsTitle,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = CupertinoTheme.of(context);
    final primaryColor = theme.primaryColor;
    final inactiveColor = CupertinoColors.secondaryLabel.resolveFrom(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: _items.map((item) {
              final isSelected = currentLocation == item.path ||
                  currentLocation.startsWith('${item.path}/');
              final title = item.getTitle(l10n);

              return Expanded(
                child: Semantics(
                  label: title,
                  selected: isSelected,
                  button: true,
                  child: CupertinoButton(
                    key: ValueKey('sidebar-utility-${item.id}'),
                    padding: const EdgeInsets.symmetric(vertical: 6.0),
                    borderRadius: BorderRadius.circular(8.0),
                    color: isSelected
                        ? primaryColor.withValues(alpha: 0.12)
                        : CupertinoColors.transparent,
                    onPressed: () {
                      context.go(item.path);
                    },
                    child: Icon(
                      item.icon,
                      size: 20.0,
                      color: isSelected ? primaryColor : inactiveColor,
                    ),
                  ),
                ),
              );
            }).toList(growable: false),
          ),
        ),
        Container(
          height: 0.5,
          color: CupertinoColors.separator.resolveFrom(context),
        ),
      ],
    );
  }
}
