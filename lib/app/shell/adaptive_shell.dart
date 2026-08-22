import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'empty_detail_pane.dart';
import 'session_sidebar.dart';
import 'sidebar_resize_handle.dart';

export 'sidebar_resize_handle.dart';

/// 宽屏双栏断点阈值（像素）。
///
/// 避开 Flutter 测试默认视口（800×600），确保现有单测与页面 widget 测试保持窄屏单栈分支。
const double kAdaptiveBreakpoint = 900.0;

/// 宽屏左侧栏默认宽度（像素）。
const double kAdaptiveSidebarDefaultWidth = 320.0;

/// 宽屏左侧栏最小宽度（像素）。
const double kAdaptiveSidebarMinWidth = 280.0;

/// 宽屏左侧栏最大宽度（像素）。
const double kAdaptiveSidebarMaxWidth = 420.0;

/// 兼容旧常量：宽屏左侧栏默认宽度（像素）。
///
/// 对齐 iOS 原生 NavigationSplitView 理想宽度（ideal: 340 / min: 280 / max: 420）。
const double kAdaptiveSidebarWidth = kAdaptiveSidebarDefaultWidth;

/// 侧栏宽度在 [SharedPreferences] 中的持久化键名。
const String kAdaptiveSidebarWidthStorageKey = 'adaptive_sidebar_width';

/// 自适应宽屏双栏外壳（TASK W2 / TASK-SIDEBAR-RESIZE）。
///
/// - 窄屏（width < 900）：直接展示当前页面 [child]，保持单栈 Cupertino 体验。
/// - 宽屏（width >= 900）：左侧展示常驻 [SessionSidebar]（宽度可拖拽调整并在 [280, 420] 之间 clamp，且持久化到本地存储），
///   中间展示拖拽手柄 [SidebarResizeHandle]，右侧展示详情内容 [child]（若路由为 `/` 则展示 [EmptyDetailPane]）。
class AdaptiveShell extends StatefulWidget {
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
  State<AdaptiveShell> createState() => _AdaptiveShellState();
}

class _AdaptiveShellState extends State<AdaptiveShell> {
  double _sidebarWidth = kAdaptiveSidebarDefaultWidth;

  @override
  void initState() {
    super.initState();
    unawaited(_loadPersistedWidth());
  }

  Future<void> _loadPersistedWidth() async {
    final prefs = await SharedPreferences.getInstance();
    final rawWidth = prefs.get(kAdaptiveSidebarWidthStorageKey);
    if (rawWidth is num && mounted) {
      final resolved = rawWidth.toDouble().clamp(
            kAdaptiveSidebarMinWidth,
            kAdaptiveSidebarMaxWidth,
          );
      if (resolved == _sidebarWidth) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final again = resolved.clamp(
          kAdaptiveSidebarMinWidth,
          kAdaptiveSidebarMaxWidth,
        );
        if (again == _sidebarWidth) return;
        setState(() {
          _sidebarWidth = again;
        });
      });
    }
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    // 高频拖拽：只做布局更新，不做磁盘 I/O，避免每帧 SharedPreferences
    // 写入阻塞 UI 线程并放大窗口重绘压力（Windows EGL Context Lost）。
    final nextWidth = (_sidebarWidth + details.delta.dx).clamp(
      kAdaptiveSidebarMinWidth,
      kAdaptiveSidebarMaxWidth,
    );
    if ((nextWidth - _sidebarWidth).abs() < 0.5) return;
    if (nextWidth != _sidebarWidth) {
      setState(() {
        _sidebarWidth = nextWidth;
      });
    }
  }

  void _handleDragEnd(DragEndDetails details) {
    unawaited(_persistWidth(_sidebarWidth));
  }

  Future<void> _persistWidth(double width) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(kAdaptiveSidebarWidthStorageKey, width);
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= kAdaptiveBreakpoint;
    if (!isWide) {
      return widget.child;
    }

    final isRootSessionList = widget.state.matchedLocation == '/';

    return ColoredBox(
      color: CupertinoTheme.of(context).scaffoldBackgroundColor,
      child: Row(
        key: const ValueKey('adaptive-shell-wide-layout'),
        children: [
          SizedBox(
            key: const ValueKey('adaptive-shell-sidebar-container'),
            width: _sidebarWidth,
            child: SessionSidebar(
              currentLocation: widget.state.matchedLocation,
            ),
          ),
          SidebarResizeHandle(
            onDragUpdate: _handleDragUpdate,
            onDragEnd: _handleDragEnd,
          ),
          Expanded(
            child: isRootSessionList ? const EmptyDetailPane() : widget.child,
          ),
        ],
      ),
    );
  }
}

