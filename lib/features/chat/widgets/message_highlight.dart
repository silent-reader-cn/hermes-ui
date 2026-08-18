import 'package:flutter/cupertino.dart';

/// 搜索结果定位高亮：包裹单条消息，初始淡黄色背景后渐隐。
///
/// 仅当 [highlight] 为 true 时生效；动画只跑一次（initState 启动），
/// 渐隐时长由 [fadeDuration] 控制，结束后背景完全透明。
class SearchMessageHighlight extends StatefulWidget {
  const SearchMessageHighlight({
    super.key,
    required this.highlight,
    required this.child,
    this.fadeDuration = const Duration(milliseconds: 1400),
  });

  /// 是否启用定位高亮（匹配消息为 true）。
  final bool highlight;

  final Widget child;

  /// 背景渐隐时长。
  final Duration fadeDuration;

  @override
  State<SearchMessageHighlight> createState() =>
      _SearchMessageHighlightState();
}

class _SearchMessageHighlightState extends State<SearchMessageHighlight>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.fadeDuration,
    );
    _opacity = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    if (widget.highlight) {
      _controller.forward();
    }
  }

  @override
  void didUpdateWidget(SearchMessageHighlight oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.highlight && !oldWidget.highlight && !_controller.isAnimating) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.highlight) return widget.child;
    return FadeTransition(
      opacity: _opacity,
      child: Container(
        decoration: BoxDecoration(
          color: CupertinoColors.systemYellow.withValues(alpha: 0.28),
          borderRadius: BorderRadius.circular(10),
        ),
        child: widget.child,
      ),
    );
  }
}