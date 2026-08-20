import 'package:flutter/cupertino.dart';

/// 会话列表页头部（替换 `CupertinoSliverNavigationBar` 的大标题模式）。
///
/// Flutter 的 `CupertinoSliverNavigationBar` 在展开大标题时，`trailing`
/// 按钮固定在顶部 persistent 栏（44pt），大标题在其下方独立展开——视觉上
/// 呈现「标题一行、按钮一行」的割裂效果，且展开态顶部遗留一条无内容空带。
///
/// 本组件把大标题与右上角操作按钮放进同一个布局坐标里：
/// - **展开态无顶部空带**：maxExtent = 状态栏 + 大标题区（52），标题直接从
///   状态栏下方开始，操作按钮与大标题视觉同行（光学中心对齐）。
/// - **滚动收起**：平滑过渡到导航栏高度（状态栏 + 44），大标题上移淡出、
///   中标题淡入、背景从透明过渡为 bar 底色。
/// - **多操作支持**：[actions] 为右侧按钮列表（设置 / 筛选 / 新建等），
///   由调用方按端与场景组合。
class SessionListHeaderDelegate extends SliverPersistentHeaderDelegate {
  const SessionListHeaderDelegate({
    required this.title,
    this.actions = const [],
    this.topPadding = 0,
    this.brightness = Brightness.light,
  });

  /// 顶部安全区高度（状态栏），由页面在 build 时以
  /// `MediaQuery.paddingOf(context).top` 传入。
  final double topPadding;

  /// 大标题 / 收起态中标题共用文案。
  final String title;

  /// 右上角操作按钮列表（设置 / 筛选 / 新建会话等）。可为空（无按钮场景）。
  final List<Widget> actions;

  /// 当前主题亮度（浅/深）。参与 [shouldRebuild] 比较：主题切换时
  /// SliverPersistentHeader 不会因 InheritedWidget 变化自动重建，不参与
  /// 比较会导致标题颜色冻结在旧主题（桌面端浅深切换不跟色 bug）。
  final Brightness brightness;

  /// 收起态导航栏高度（对齐 iOS `_kNavBarPersistentHeight`）。
  static const double barHeight = 44.0;

  /// 展开态大标题区高度（对齐 iOS `_kNavBarLargeTitleHeightExtension`）。
  static const double largeTitleHeight = 52.0;

  /// 展开态大标题顶部距状态栏的间距。
  static const double _largeTitleTopGap = 6.0;

  /// 按钮视觉半高（按钮 44×44 点击区，中心定位）。
  static const double _buttonHalfSize = 22.0;

  /// 图标相对文字光学中心的微上偏移（大字号的下行高度占比小，光学中心偏上）。
  static const double _opticalLift = 3.0;

  @override
  double get minExtent => topPadding + barHeight;

  @override
  double get maxExtent => topPadding + largeTitleHeight;

  @override
  bool shouldRebuild(SessionListHeaderDelegate oldDelegate) =>
      oldDelegate.title != title ||
      oldDelegate.actions != actions ||
      oldDelegate.topPadding != topPadding ||
      oldDelegate.brightness != brightness;

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

    // 标题几何：展开态大标题紧贴状态栏下方（无 44pt 空带），收起态中标题
    // 位于导航栏中线。两者起点同为 left 20，滚动时同轴缩放不跳位。
    // 大标题文字中心（展开态）。
    final largeTitleCenterY =
        topPadding + _largeTitleTopGap + largeTitleHeight / 2 - 8;
    // 中标题文字中心（收起态）。
    final collapsedTitleCenterY = topPadding + barHeight / 2;
    // 按钮中心：展开态与大标题文字光学中心对齐（略上提），收起态对齐导航栏。
    final expandedButtonCenterY = largeTitleCenterY - _opticalLift;
    final collapsedButtonCenterY = collapsedTitleCenterY;
    final buttonCenterY =
        collapsedButtonCenterY +
        (expandedButtonCenterY - collapsedButtonCenterY) * progress;
    // 大标题垂直位置：展开到底部附近（top 定位，随滚动上移淡出）。
    final largeTitleTop =
        topPadding + _largeTitleTopGap - 4 * collapsed - 4 * (1 - progress);

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
        // 收起态中标题（左对齐）。
        Positioned(
          left: 20,
          top: collapsedTitleCenterY - 12,
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
        // 大标题（左对齐，紧贴状态栏，随滚动上移淡出）。
        Positioned(
          left: 20,
          top: largeTitleTop,
          child: Opacity(
            opacity: progress,
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
        // 右上角操作按钮：展开时与大标题同行，收起时平滑升至导航栏。
        if (actions.isNotEmpty)
          Positioned(
            right: 4,
            top: buttonCenterY - _buttonHalfSize,
            child: Row(mainAxisSize: MainAxisSize.min, children: actions),
          ),
      ],
    );
  }
}
