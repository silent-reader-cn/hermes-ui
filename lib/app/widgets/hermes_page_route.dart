import 'package:flutter/widgets.dart';

/// 自定义页面路由：push 从右滑入（对齐 Cupertino），pop 时当前页向左滑出。
///
/// 与 [CupertinoPageRoute] 默认转场的差异（todo #17「详情页返回动画」）：
/// - push 进入：新页从右滑入（x: +width → 0），保持 Cupertino 观感不变；
/// - pop 返回：当前页向左滑出（x: 0 → -width），底层页保持静止、当前页叠轻微淡出；
/// - 时长 400ms、缓动 `Curves.easeOut`，对齐 Cupertino 风格。
///
/// 生成路由复用的 `HermesPage` 供 go_router `pageBuilder` 使用，
/// 使 `context.push(...)` 的转场与本路由一致。
class HermesPageRoute<T> extends PageRouteBuilder<T> {
  /// 构造一个使用 Hermes 转场的页面路由。
  HermesPageRoute({
    required WidgetBuilder builder,
    super.settings,
    super.fullscreenDialog,
    super.transitionDuration = const Duration(milliseconds: 400),
    super.reverseTransitionDuration = const Duration(milliseconds: 400),
  }) : super(
          pageBuilder: (context, animation, secondaryAnimation) =>
              builder(context),
          transitionsBuilder: _transitionsBuilder,
        );

  /// 退出时当前页淡出的最低透明度（轻微淡出，用于 pop 滑出过程）。
  static const double _exitFadeTarget = 0.8;

  /// 转场 SlideTransition 的定位 key（供转场方向测试定位）。
  static const Key slideKey = ValueKey('hermes-page-slide');

  static Widget _transitionsBuilder(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return _HermesPageTransition(
      primaryRouteAnimation: animation,
      secondaryRouteAnimation: secondaryAnimation,
      child: child,
    );
  }
}

class _HermesPageTransition extends StatelessWidget {
  const _HermesPageTransition({
    required this.primaryRouteAnimation,
    required this.secondaryRouteAnimation,
    required this.child,
  });

  /// 当前页动画：push 时 0→1（正向），pop 时 1→0（反向）。
  final Animation<double> primaryRouteAnimation;

  /// 底层页动画：本路由不驱动底层页，保持静止。
  final Animation<double> secondaryRouteAnimation;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final bool isReverse =
        primaryRouteAnimation.status == AnimationStatus.reverse;
    final Animation<double> curved = CurvedAnimation(
      parent: primaryRouteAnimation,
      curve: Curves.easeOut,
      reverseCurve: Curves.easeOut,
    );
    // 全屏宽位移：Cupertino 默认转场从右缘滑入/向左滑出，用屏幕宽做 offset。
    // 直接用 MediaQuery 拿尺寸（与 CupertinoPageTransition 行为一致），
    // 勿写死 Offset(±1,0) —— 那只是 1 像素，动画几乎不可见。
    final Size size = MediaQuery.maybeSizeOf(context) ?? const Size(800, 600);
    // 正向（push，t 0→1）：x +width→0 从右滑入；
    // 反向（pop，t 1→0）：x 0→-width 向左滑出。方向推导：动画 t=1 时页面
    // 在原位（dx 0）、t=0 时完全滑出（dx -width），故反向 Tween 必须
    // begin=(-width,0)、end=zero（begin 对应 t=0，end 对应 t=1）。
    final Animation<Offset> position = isReverse
        ? Tween<Offset>(
            begin: Offset(-size.width, 0),
            end: Offset.zero,
          ).animate(curved)
        : Tween<Offset>(
            begin: Offset(size.width, 0),
            end: Offset.zero,
          ).animate(curved);
    // pop 滑出时叠轻微淡出；push 进入保持不透明。
    // reverse 时 t 1→0：begin 对应 t=0（完全滑出，最淡）、end 对应 t=1
    // （原位不透明），故 begin=0.8 / end=1 —— 若写反会导致 pop 伊始
    // 透明度瞬间跳 0.8、滑出中反而回 1.0。
    final Animation<double> opacity = isReverse
        ? Tween<double>(
            begin: HermesPageRoute._exitFadeTarget,
            end: 1,
          ).animate(curved)
        : const AlwaysStoppedAnimation<double>(1);
    return SlideTransition(
      key: HermesPageRoute.slideKey,
      position: position,
      child: FadeTransition(opacity: opacity, child: child),
    );
  }
}

/// go_router `pageBuilder` 用的 [Page]，转场与 [HermesPageRoute] 一致。
///
/// 用于 `/workspace/:sessionId`、`/git/:sessionId` 等被 `context.push(...)`
/// 进入的路由，保证 push/pop 转场语义与详情页统一。
class HermesPage<T> extends Page<T> {
  /// 构造一个 Hermes 转场页。
  const HermesPage({
    required this.builder,
    super.key,
    super.name,
    super.arguments,
    super.restorationId,
  });

  final WidgetBuilder builder;

  @override
  Route<T> createRoute(BuildContext context) =>
      HermesPageRoute<T>(builder: builder, settings: this);
}