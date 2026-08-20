import 'package:flutter/cupertino.dart';

/// 会话列表页头部（替换 `CupertinoSliverNavigationBar` 的大标题模式）。
///
/// Flutter 的 `CupertinoSliverNavigationBar` 在展开大标题时，`trailing`
/// 按钮固定在顶部 persistent 栏（44pt），大标题在其下方独立展开——视觉上
/// 呈现「标题一行、按钮一行」的割裂效果。本组件把大标题与右上角按钮放进
/// 同一个布局坐标里：展开态按钮与大标题视觉同行，滚动收起时按钮平滑上移
/// 到导航栏高度，并融合 iOS 标准的收起动效（大标题上移淡出、中标题淡入、
/// 背景从透明过渡为毛玻璃底色）。
class SessionListHeaderDelegate extends SliverPersistentHeaderDelegate {
  const SessionListHeaderDelegate({
    required this.title,
    required this.trailing,
    this.topPadding = 0,
  });

  /// 顶部安全区高度（状态栏），由页面在 build 时以
  /// `MediaQuery.paddingOf(context).top` 传入。
  final double topPadding;

  /// 大标题 / 收起态中标题共用文案。
  final String title;

  /// 右上角操作按钮（设置 / 选择完成）。为 `null` 时不渲染（宽屏侧栏场景，
  /// 由 [SidebarUtilityToolbar] 承担设置入口）。
  final Widget? trailing;

  /// 导航栏常驻高度（对齐 iOS `_kNavBarPersistentHeight`）。
  static const double barHeight = 44.0;

  /// 大标题扩展区高度（对齐 iOS `_kNavBarLargeTitleHeightExtension`）。
  static const double largeTitleHeight = 52.0;

  /// 展开态大标题区域右侧按钮的中心（距头部底部的偏移）。
  static const double _largeTitleButtonCenterInset = 28.0;

  /// 按钮视觉半高（按钮 44×44 点击区，中心定位）。
  static const double _buttonHalfSize = 22.0;

  @override
  double get minExtent => topPadding + barHeight;

  @override
  double get maxExtent => topPadding + barHeight + largeTitleHeight;

  @override
  bool shouldRebuild(SessionListHeaderDelegate oldDelegate) =>
      oldDelegate.title != title ||
      oldDelegate.trailing != trailing ||
      oldDelegate.topPadding != topPadding;

  /// 展开进度：1 = 完全展开（大标题可见），0 = 完全收起。
  double _expandProgress(double shrinkOffset) {
    final range = maxExtent - minExtent;
    return ((maxExtent - shrinkOffset) - minExtent) / range;
  }

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final progress = _expandProgress(shrinkOffset).clamp(0.0, 1.0);
    final collapsed = 1.0 - progress;
    final height = maxExtent - shrinkOffset;

    final theme = CupertinoTheme.of(context);
    final barColor = CupertinoDynamicColor.resolve(
      theme.barBackgroundColor,
      context,
    );
    final labelColor = CupertinoDynamicColor.resolve(
      theme.textTheme.textStyle.color ?? CupertinoColors.label,
      context,
    );
    final separator = CupertinoDynamicColor.resolve(
      CupertinoColors.separator,
      context,
    );

    // 按钮中心：展开时对齐大标题行，收起时对齐导航栏中线。
    final expandedCenterY = height - _largeTitleButtonCenterInset;
    final collapsedCenterY = topPadding + barHeight / 2;
    final buttonCenterY =
        collapsedCenterY + (expandedCenterY - collapsedCenterY) * progress;
    final trailingButton = trailing;

    return Stack(
      key: const ValueKey('session-list-header'),
      fit: StackFit.expand,
      children: [
        // 背景：展开透明 → 收起渐显导航栏底色 + 底部分隔线。
        ColoredBox(color: barColor.withValues(alpha: collapsed)),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Opacity(
            opacity: collapsed,
            child: Container(height: 0.5, color: separator),
          ),
        ),
        // 收起态中标题（左对齐，与展开态同起点，缩放过渡不跳位）。
        Positioned(
          left: 20,
          top: topPadding + (barHeight - 20) / 2,
          child: Opacity(
            opacity: collapsed,
            child: Text(
              title,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: labelColor,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        // 大标题（左对齐，随滚动上移淡出）。
        Positioned(
          left: 20,
          bottom: 12,
          child: Opacity(
            opacity: progress,
            child: Transform.translate(
              offset: Offset(0, collapsed * 24),
              child: Align(
                alignment: Alignment.bottomLeft,
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w700,
                    color: labelColor,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
        ),
        // 右上角按钮：展开时与大标题同行，收起时平滑升至导航栏。
        if (trailingButton != null)
          Positioned(
            right: 8,
            top: buttonCenterY - _buttonHalfSize,
            child: trailingButton,
          ),
      ],
    );
  }
}
