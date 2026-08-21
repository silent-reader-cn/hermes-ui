import 'package:flutter/cupertino.dart';

import '../shell/adaptive_shell.dart';

/// 宽屏自动收敛的 Cupertino 导航栏（Sliver 版）。
///
/// - 窄屏（width < 900，手机）：保持系统 `CupertinoSliverNavigationBar`
///   大标题模式（展开 ~96 / 收起 44），与既有手机端视觉完全一致；
/// - 宽屏（width >= 900，桌面双栏）：收敛为 44pt 紧凑导航条
///   （`CupertinoNavigationBar`，不可随滚动收起），与左侧侧栏顶部的
///   [SidebarUtilityToolbar]（44px）高度对齐，消除双栏下内容区 Header
///   与侧栏工具条的高度参差。
///
/// 注意：`CupertinoSliverNavigationBar` 断言 largeTitle 不可为 null
/// （无大标题内容即崩溃），因此宽屏紧凑模式不能走同一组件，改为
/// `SliverToBoxAdapter` 包裹固定 44pt 的 `CupertinoNavigationBar`。
class AdaptiveSliverNavigationBar extends StatelessWidget {
  const AdaptiveSliverNavigationBar({
    super.key,
    required this.title,
    this.leading,
    this.trailing,
    this.padding,
    this.bottom,
    this.showMiddleOnNarrow = false,
  });

  /// 大标题 / 收起态中标题的共用文案。
  final String title;

  /// 导航栏左侧按钮（返回等）。
  final Widget? leading;

  /// 导航栏右侧按钮列表。
  final Widget? trailing;

  /// 内容横向内边距（仅窄屏大标题模式生效，宽屏固定条无此参数）。
  final EdgeInsetsDirectional? padding;

  /// 固定在导航栏底部的小部件（操作横幅等），收起/展开态均可见。
  final PreferredSizeWidget? bottom;

  /// 窄屏下是否同时在 44pt 条显示中标题。
  ///
  /// 少数页面原本即「大标题 + 收起态 middle」双模式（workspace 系），
  /// 传 `true` 保持窄屏行为逐像素不变。
  final bool showMiddleOnNarrow;

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= kAdaptiveBreakpoint;
    if (isWide) {
      // 桌面宽屏：44pt 固定紧凑导航条（SliverNavigationBar 不允许
      // largeTitle 为 null，改用 CupertinoNavigationBar）。
      return SliverToBoxAdapter(
        child: CupertinoNavigationBar(
          leading: leading,
          trailing: trailing,
          middle: Text(title),
          bottom: bottom,
        ),
      );
    }
    return CupertinoSliverNavigationBar(
      leading: leading,
      trailing: trailing,
      padding: padding,
      bottom: bottom,
      // 窄屏：大标题模式，中标题仅在原页面本就存在时保留。
      middle: showMiddleOnNarrow ? Text(title) : null,
      largeTitle: Text(title),
    );
  }
}
