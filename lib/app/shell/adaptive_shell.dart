import 'package:flutter/cupertino.dart';
import 'package:go_router/go_router.dart';

import 'empty_detail_pane.dart';
import 'session_sidebar.dart';

/// 宽屏双栏断点阈值（像素）。
///
/// 避开 Flutter 测试默认视口（800×600），确保现有单测与页面 widget 测试保持窄屏单栈分支。
const double kAdaptiveBreakpoint = 900.0;

/// 宽屏左侧栏固定宽度（像素）。
///
/// 对齐 iOS 原生 NavigationSplitView 理想宽度（ideal: 340 / min: 280）。
const double kAdaptiveSidebarWidth = 320.0;

/// 自适应宽屏双栏外壳（TASK W2）。
///
/// - 窄屏（width < 900）：直接展示当前页面 [child]，保持单栈 Cupertino 体验。
/// - 宽屏（width >= 900）：左侧展示常驻 [SessionSidebar]，右侧展示详情内容 [child]（若路由为 `/` 则展示 [EmptyDetailPane]）。
class AdaptiveShell extends StatelessWidget {
  const AdaptiveShell({
    super.key,
    required this.state,
    required this.child,
  });

  /// 当前路由状态。
  final GoRouterState state;

  /// 当前路由对应的主页面组件。
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= kAdaptiveBreakpoint;
    if (!isWide) {
      return child;
    }

    final isRootSessionList = state.matchedLocation == '/';

    return ColoredBox(
      color: CupertinoTheme.of(context).scaffoldBackgroundColor,
      child: Row(
        key: const ValueKey('adaptive-shell-wide-layout'),
        children: [
          SizedBox(
            width: kAdaptiveSidebarWidth,
            child: SessionSidebar(
              currentLocation: state.matchedLocation,
            ),
          ),
          Container(
            width: 1.0,
            color: CupertinoColors.separator.resolveFrom(context),
          ),
          Expanded(
            child: isRootSessionList ? const EmptyDetailPane() : child,
          ),
        ],
      ),
    );
  }
}
