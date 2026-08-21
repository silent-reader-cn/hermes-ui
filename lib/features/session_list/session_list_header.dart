import 'package:flutter/cupertino.dart';

/// 会话列表页头部（替换 `CupertinoSliverNavigationBar` 的大标题模式）。
///
/// Flutter 的 `CupertinoSliverNavigationBar` 在展开大标题时，`trailing`
/// 按钮固定在顶部 persistent 栏（44pt），大标题在其下方独立展开——视觉上
/// 呈现「标题一行、按钮一行」的割裂效果，且展开态顶部遗留一条无内容空带。
///
/// 本组件把大标题与右上角操作按钮放进同一个布局坐标里：
/// - **展开几何对齐系统导航栏**：maxExtent = 状态栏 + 44pt 导航栏 +
///   52pt 大标题区，大标题顶部与系统大标题位置一致（切换页面时标题
///   与顶部间距完全对齐，手机端不再贴顶）；操作按钮与大标题同行
///   （垂直中心对齐大标题文字行盒中心）。
/// - **滚动收起**：平滑过渡到导航栏高度（状态栏 + 44），大标题上移淡出、
///   中标题淡入、背景固定为主题 bar 底色（不随滚动变透明/变灰）。
/// - **多操作支持**：[actions] 为右侧按钮列表（设置 / 筛选 / 新建等），
///   由调用方按端与场景组合。
///
/// 几何基准（探针实测 MiSans 34pt 行盒高 39）：系统 `CupertinoSliverNavigationBar`
/// 展开态大标题文字的 top = 状态栏 + 44 + 5（persistent 栏 44pt + 大标题区
/// 52pt 内文字底部留白偏移），即状态栏下方固定 49pt 可见间距；按钮中心
/// 对齐该文字行盒中心（top + 39/2），保证「与左侧标题垂直居中」。
class SessionListHeaderDelegate extends SliverPersistentHeaderDelegate {
  const SessionListHeaderDelegate({
    required this.title,
    this.actions = const [],
    this.topPadding = 0,
    this.brightness = Brightness.light,
    this.compactHeader = false,
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

  /// 紧凑头部模式：不预留大标题顶部空白（大标题直接贴状态栏下方）。
  ///
  /// 电脑端双栏侧栏复用会话列表时传 `true`（侧栏空间紧凑，标题紧贴顶部）；
  /// 手机端窄屏单栈保持默认 `false`（预留 49pt 顶部空白，与任务 / 技能页
  /// 系统导航栏大标题对齐，切换页面时标题不跳位）。
  final bool compactHeader;

  /// 收起态导航栏高度（对齐 iOS `_kNavBarPersistentHeight`）。
  static const double barHeight = 44.0;

  /// 展开态大标题区高度（对齐系统 `_kNavBarLargeTitleHeightExtension`）。
  static const double largeTitleHeight = 52.0;

  /// 大标题文字顶部距状态栏的间距（紧凑模式：直接贴状态栏下方）。
  static const double _compactLargeTitleTopGap = 6.0;

  /// 展开态大标题文字顶部距状态栏的间距（宽敞模式）。
  ///
  /// 对齐系统 `CupertinoSliverNavigationBar` 展开态大标题的视觉位置
  /// （persistent 栏 44pt + 大标题区内文字偏移 5pt），保证与任务 / 技能
  /// 等使用系统导航栏的页面切换时标题顶部间距一致。仅手机端单栈使用。
  static const double _spaciousLargeTitleTopGap = 49.0;

  /// 当前生效的大标题顶部间距（据 [compactHeader]）。
  double get _largeTitleTopGap =>
      compactHeader ? _compactLargeTitleTopGap : _spaciousLargeTitleTopGap;

  /// 大标题文字行盒高度（MiSans 34pt 实测渲染高度，探针数据）。
  ///
  /// 收起态中标题（17pt）与展开态大标题的文字布局都以此类字体度量
  /// 为基准计算按钮中心，保证按钮与文字垂直居中而非依赖估算偏移。
  static const double _largeTitleLineHeight = 39.0;

  /// 按钮视觉半高（按钮 44×44 点击区，中心定位）。
  static const double _buttonHalfSize = 22.0;

  @override
  double get minExtent => topPadding + barHeight;

  @override
  double get maxExtent =>
      topPadding +
      (compactHeader ? largeTitleHeight : barHeight + largeTitleHeight);

  @override
  bool shouldRebuild(SessionListHeaderDelegate oldDelegate) =>
      oldDelegate.title != title ||
      oldDelegate.actions != actions ||
      oldDelegate.topPadding != topPadding ||
      oldDelegate.brightness != brightness ||
      oldDelegate.compactHeader != compactHeader;

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

    // 标题几何：展开态大标题从状态栏下方 49pt 处开始（与系统导航栏大标题
    // 位置一致），收起态中标题位于导航栏中线。两者起点同为 left 20，
    // 滚动时同轴缩放不跳位。
    // 大标题文字行盒中心（展开态，按钮对齐基准）。
    final largeTitleCenterY =
        topPadding + _largeTitleTopGap + _largeTitleLineHeight / 2;
    // 中标题文字中心（收起态）。
    final collapsedTitleCenterY = topPadding + barHeight / 2;
    // 按钮中心：展开态与大标题文字行盒中心对齐（垂直居中），收起态对齐
    // 导航栏中线。
    final expandedButtonCenterY = largeTitleCenterY;
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
        // 背景：固定不透明主题 bar 底色（不随滚动变灰/透明）。
        ColoredBox(color: barColor),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(height: 0.5, color: separator),
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
