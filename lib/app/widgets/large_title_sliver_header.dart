import 'package:flutter/cupertino.dart';

/// 大标题页共享头部 delegate（TASK sep03：▾ 从右上角移到大标题右侧）。
///
/// 几何与 `SessionListHeaderDelegate`（会话列表页基准）保持同一套常量：
/// 展开态 34pt 大标题（top = topPadding + 43），滚动时平滑过渡为 17pt
/// 收起态左对齐标题（persistent 44pt 行中线），[titleTrailing]（如窄屏
/// 快捷导航下拉按钮 ▾）紧贴标题右侧 4pt，随两种字号平滑移动。
///
/// 与基准的差异（针对 9 个功能页需求）：
/// - leading / trailing 固定在顶部 persistent 行（贴近原
///   `CupertinoSliverNavigationBar` 行为，不随大标题中心线移动）；
/// - 支持 `showMiddleOnNarrow`（workspace 系）收起态中标题开关；
/// - 支持 `bottom`（git 页操作横幅）：收起态紧贴 persistent 行下方，
///   展开态下移至大标题行下方（线性过渡）。
///
/// ⚠️ 若未来调整本文件或 `session_list_header.dart` 的几何常量
/// （barHeight / largeTitleHeight / 间距 / 字号），两处必须同步，
/// 否则 `session_title_alignment_test` 的同源对齐假设失效。
class LargeTitleSliverHeaderDelegate extends SliverPersistentHeaderDelegate {
  const LargeTitleSliverHeaderDelegate({
    required this.title,
    this.leading,
    this.trailing,
    this.titleTrailing,
    this.showCollapsedTitle = false,
    this.topPadding = 0,
    this.brightness = Brightness.light,
    this.padding,
    this.bottom,
    this.onTitleDoubleTap,
    this.portrait = true,
  });

  /// 大标题 / 收起态中标题共用文案。
  final String title;

  /// 导航栏左侧按钮（返回等），固定在 persistent 行。
  final Widget? leading;

  /// 导航栏右侧操作区，固定在 persistent 行。
  final Widget? trailing;

  /// 紧贴标题右侧的尾随组件（窄屏快捷导航下拉按钮 ▾），
  /// 随展开/收起与大标题同行平滑移动。
  final Widget? titleTrailing;

  /// 收起态是否显示 17pt 中标题（`showMiddleOnNarrow` 语义）。
  final bool showCollapsedTitle;

  /// 顶部安全区高度（状态栏），由组件在 build 时以
  /// `MediaQuery.paddingOf(context).top` 传入。
  final double topPadding;

  /// 主题亮度（参与 shouldRebuild：主题切换时 delegate 需重建，
  /// 否则标题颜色冻结在旧主题）。
  final Brightness brightness;

  /// 内容横向内边距（leading/trailing 行），对齐系统组件默认 16。
  final EdgeInsetsDirectional? padding;

  /// 固定在导航栏底部的横幅（git 页操作横幅），收起/展开态均可见。
  final PreferredSizeWidget? bottom;

  /// 双击标题回调（回顶）。
  final VoidCallback? onTitleDoubleTap;

  /// 是否竖屏大标题模式（对齐系统行为：`CupertinoSliverNavigationBar` 在
  /// 横屏下 largeTitle 扩展高度为 0，标题以 17pt 中标题呈现）。
  final bool portrait;

  /// 收起态导航栏高度（对齐 iOS `_kNavBarPersistentHeight`）。
  static const double barHeight = 44.0;

  /// 展开态大标题区高度（对齐系统 `_kNavBarLargeTitleHeightExtension`）。
  static const double largeTitleHeight = 52.0;

  /// 展开态大标题文字顶部距状态栏的间距（与 SessionListHeaderDelegate
  /// 同源：2026-08-29 #24 真 MiSans 探针定标 43px）。
  static const double _spaciousLargeTitleTopGap = 43.0;

  /// 大标题文字行盒高度（MiSans 34pt 实测渲染高度，同源基准）。
  static const double _largeTitleLineHeight = 39.0;

  /// 按钮视觉半高（44×44 点击区中心定位，同源基准）。
  static const double _buttonHalfSize = 22.0;

  /// 大标题左缘（同源基准：会话列表 left = 20）。
  static const double _titleLeft = 20.0;

  double get _bottomHeight => bottom?.preferredSize.height ?? 0.0;

  /// 横屏（对齐系统）：largeTitle 扩展高度为 0，仅 persistent 44 行。
  double get _largeExtension => portrait ? largeTitleHeight : 0.0;

  @override
  double get minExtent => topPadding + barHeight + _bottomHeight;

  @override
  double get maxExtent =>
      topPadding + barHeight + _largeExtension + _bottomHeight;

  @override
  bool shouldRebuild(covariant LargeTitleSliverHeaderDelegate oldDelegate) =>
      oldDelegate.title != title ||
      oldDelegate.leading != leading ||
      oldDelegate.trailing != trailing ||
      oldDelegate.titleTrailing != titleTrailing ||
      oldDelegate.showCollapsedTitle != showCollapsedTitle ||
      oldDelegate.topPadding != topPadding ||
      oldDelegate.brightness != brightness ||
      oldDelegate.padding != padding ||
      oldDelegate.bottom != bottom ||
      oldDelegate.onTitleDoubleTap != onTitleDoubleTap ||
      oldDelegate.portrait != portrait;

  /// 展开进度：1 = 完全展开（大标题可见），0 = 完全收起。
  double _expandProgress(double shrinkOffset) {
    final range = maxExtent - minExtent;
    if (range <= 0) return 0.0;
    return ((maxExtent - shrinkOffset) - minExtent) / range;
  }

  Widget _wrapTitle(Widget child) {
    if (onTitleDoubleTap == null) return child;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onDoubleTap: onTitleDoubleTap,
      child: child,
    );
  }

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final theme = CupertinoTheme.of(context);
    final barColor = CupertinoDynamicColor.resolve(
      theme.barBackgroundColor,
      context,
    );
    final labelColor = CupertinoDynamicColor.resolve(
      theme.textTheme.textStyle.color ?? CupertinoColors.label,
      context,
    );

    final progress = _expandProgress(shrinkOffset).clamp(0.0, 1.0);
    final collapsed = 1.0 - progress;
    // 横屏对齐系统：largeTitle 不渲染（扩展高度 0，标题以居中 17pt 呈现）。
    final showLargeTitle = portrait;

    // 标题几何（与 SessionListHeaderDelegate 同式）：
    final largeTitleCenterY =
        topPadding + _spaciousLargeTitleTopGap + _largeTitleLineHeight / 2;
    final collapsedTitleCenterY = topPadding + barHeight / 2;
    final buttonCenterY =
        collapsedTitleCenterY +
        (largeTitleCenterY - collapsedTitleCenterY) * progress;
    final largeTitleTop =
        topPadding +
        _spaciousLargeTitleTopGap -
        4 * collapsed -
        4 * (1 - progress);

    // ▾ 水平位置 = 标题右缘 + 4（按当前字号插值宽度）。
    double largeTitleWidth = 0.0;
    double collapsedTitleWidth = 0.0;
    if (titleTrailing != null) {
      final direction = Directionality.maybeOf(context) ?? TextDirection.ltr;
      final textScaler =
          MediaQuery.maybeTextScalerOf(context) ?? TextScaler.noScaling;
      final largePainter = TextPainter(
        text: TextSpan(
          text: title,
          style: TextStyle(
            fontSize: 34,
            fontWeight: FontWeight.w700,
            color: labelColor,
          ),
        ),
        textDirection: direction,
        textScaler: textScaler,
        maxLines: 1,
      )..layout();
      largeTitleWidth = largePainter.width;
      final collapsedPainter = TextPainter(
        text: TextSpan(
          text: title,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: labelColor,
          ),
        ),
        textDirection: direction,
        textScaler: textScaler,
        maxLines: 1,
      )..layout();
      collapsedTitleWidth = collapsedPainter.width;
    }
    final trailingLeft =
        _titleLeft +
        (collapsedTitleWidth + (largeTitleWidth - collapsedTitleWidth) * progress) +
        4.0;
    final trailingTop = buttonCenterY - _buttonHalfSize;

    // leading/trailing 固定在顶部 persistent 行（不随大标题移动），
    // 与大标题展开/收起无关：中心 = topPadding + 22。
    final padStart = padding?.start ?? 16.0;
    final padEnd = padding?.end ?? 16.0;
    final persistentRowTop = topPadding + (barHeight - _buttonHalfSize * 2) / 2;

    return Stack(
      key: const ValueKey('large-title-header'),
      fit: StackFit.expand,
      children: [
        // 背景：固定不透明主题 bar 底色。bottom 横幅区同样垫底。
        ColoredBox(color: barColor),
        // bottom 横幅：收起态贴 persistent 行下缘，展开态下移到大标题行
        // 下方（与系统组件 Column 序一致），线性过渡。
        if (bottom != null)
          Positioned(
            left: 0,
            right: 0,
            top: topPadding + barHeight + _largeExtension * progress,
            height: _bottomHeight,
            child: bottom!,
          ),
        // 收起态中标题（仅 showMiddleOnNarrow 页面，如 workspace 系）。
        // 横屏对齐系统：标题以居中 17pt 呈现（无大标题扩展行）。
        if (showCollapsedTitle || !showLargeTitle)
          Positioned(
            left: showLargeTitle ? _titleLeft : 0,
            right: showLargeTitle ? null : 0,
            top: collapsedTitleCenterY - 12,
            child: _wrapTitle(
              Opacity(
                opacity: showLargeTitle ? collapsed : 1.0,
                child: Text(
                  title,
                  textAlign: showLargeTitle ? TextAlign.start : TextAlign.center,
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
          ),
        // 大标题（左对齐，随滚动上移淡出）。
        if (showLargeTitle)
          Positioned(
            left: _titleLeft,
            top: largeTitleTop,
            child: _wrapTitle(
              Opacity(
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
          ),
        // 紧贴标题右侧的 ▾，随展开/收起平滑过渡（本任务核心；横屏无大标题
        // 行时不渲染，对齐「窄屏竖屏快捷导航」的产品语义）。
        if (titleTrailing != null && showLargeTitle)
          Positioned(
            left: trailingLeft,
            top: trailingTop,
            child: titleTrailing!,
          ),
        // leading / trailing：persistent 行左右两端。
        Positioned(
          left: padStart,
          right: padEnd,
          top: persistentRowTop,
          height: barHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ?leading,
              const Spacer(),
              ?trailing,
            ],
          ),
        ),
      ],
    );
  }
}
