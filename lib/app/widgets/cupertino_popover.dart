import 'dart:math' as math;

import 'package:flutter/cupertino.dart';

/// Cupertino 风格锚点弹层（popover）。
///
/// 在 [anchorKey] 对应的按钮上方弹出圆角卡片（点击卡片外任意处关闭）。
/// 用于桌面/平板宽屏下替代占满整宽的输出式弹层（如底部 sheet），避免
/// 遮蔽页面主体内容；移动端窄屏仍走系统底部 sheet（见各调用方分支）。
Future<void> showCupertinoPopover({
  required BuildContext context,
  required GlobalKey anchorKey,
  required Widget Function(BuildContext context, VoidCallback close) builder,
  double preferredWidth = 360,
}) async {
  final overlay = Overlay.of(context);
  final overlayBox = overlay.context.findRenderObject() as RenderBox?;
  if (overlayBox == null) return;
  final anchorContext = anchorKey.currentContext;
  final anchorBox = anchorContext?.findRenderObject() as RenderBox?;
  if (anchorBox == null || !anchorBox.attached) return;

  final anchorTopLeft = anchorBox.localToGlobal(
    Offset.zero,
    ancestor: overlayBox,
  );
  final anchorSize = anchorBox.size;
  // 弹层可横向活动的安全区（避开屏幕边缘 8px）。
  final screenW = overlayBox.size.width;
  final safeLeft = 8.0;
  final safeRight = screenW - 8.0;
  final maxWidth = math.min(preferredWidth, screenW - 16.0);
  // 右缘与按钮右缘对齐（贴近图标），再向左收成卡片宽；越界时 clamp。
  var left = anchorTopLeft.dx + anchorSize.width - maxWidth;
  left = left.clamp(safeLeft, math.max(safeLeft, safeRight - maxWidth));
  // 卡片最大高度（含标题 + 列表 + 保存按钮）。
  const maxHeight = 420.0;
  final gap = 8.0;
  final aboveFit = anchorTopLeft.dy - maxHeight - gap >= 0;
  // 未测量前的初始 top（上方放得下则向上弹，否则向下）。
  final initialTop = aboveFit
      ? anchorTopLeft.dy - maxHeight - gap
      : anchorTopLeft.dy + anchorSize.height + gap;

  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (overlayContext) => _PopoverHost(
      left: left,
      initialTop: initialTop,
      maxHeight: maxHeight,
      gap: gap,
      screenWidth: screenW,
      anchorBottom: anchorTopLeft.dy + anchorSize.height,
      close: entry.remove,
      builder: builder,
    ),
  );
  overlay.insert(entry);
}

class _PopoverHost extends StatefulWidget {
  const _PopoverHost({
    required this.left,
    required this.initialTop,
    required this.maxHeight,
    required this.gap,
    required this.screenWidth,
    required this.anchorBottom,
    required this.close,
    required this.builder,
  });

  final double left;
  final double initialTop;
  final double maxHeight;
  final double gap;
  final double screenWidth;
  final double anchorBottom;
  final VoidCallback close;
  final Widget Function(BuildContext context, VoidCallback close) builder;

  @override
  State<_PopoverHost> createState() => _PopoverHostState();
}

class _PopoverHostState extends State<_PopoverHost> {
  final GlobalKey _cardKey = GlobalKey();
  double? _measuredHeight;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final box = _cardKey.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.attached) return;
      final height = box.size.height;
      if (height != _measuredHeight) {
        setState(() => _measuredHeight = height);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final height = math.min(
      _measuredHeight ?? widget.maxHeight,
      widget.maxHeight,
    );
    final top = _measuredHeight == null
        ? widget.initialTop
        : _computeTop(height);
    return Stack(
      children: [
        // 全屏透明屏障：点击外部关闭。
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.close,
          ),
        ),
        Positioned(
          left: widget.left,
          top: top,
          width: math.min(widget.screenWidth - 16, 400),
          child: _PopoverCard(
            key: _cardKey,
            close: widget.close,
            child: widget.builder(context, widget.close),
          ),
        ),
      ],
    );
  }

  double _computeTop(double height) {
    final screenTop = MediaQuery.of(context).padding.top + 8;
    if (widget.initialTop >= screenTop) {
      // 原计划向上弹：若真实高度比预算矮，向按钮方向贴近 gap。
      final desired = widget.anchorBottom - height - widget.gap;
      if (desired < screenTop) return screenTop;
      return desired;
    }
    // 原计划向下弹：贴住按钮下方。
    return widget.anchorBottom + widget.gap;
  }
}

class _PopoverCard extends StatelessWidget {
  const _PopoverCard({super.key, required this.close, required this.child});

  final VoidCallback close;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final bg = CupertinoColors.systemBackground.resolveFrom(context);
    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: CupertinoColors.systemGrey4.resolveFrom(context),
        ),
        boxShadow: [
          BoxShadow(
            color: CupertinoColors.systemGrey3
                .resolveFrom(context)
                .withValues(alpha: 0.5),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}
