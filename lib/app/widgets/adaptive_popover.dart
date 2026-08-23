import 'dart:math' as math;

import 'package:flutter/cupertino.dart';

/// 弹层弹出方向。
enum PopoverPlacement {
  /// 锚点上方。
  top,

  /// 锚点下方。
  bottom,

  /// 自动：根据可用空间选择，空间不足时翻转。
  auto,
}

/// 弹层水平对齐。
enum PopoverAlign {
  /// 左缘与锚点左缘对齐。
  start,

  /// 居中与锚点居中对齐。
  center,

  /// 右缘与锚点右缘对齐（默认，贴近输入栏右侧图标）。
  end,
}

/// 全应用可复用锚点弹层（popover）。

///
/// 特性：
/// - 基于 [anchorKey] 的 overlay 定位，支持 [placement]（top/bottom/auto）与
///   [align]（start/center/end），支持 [offset] 额外偏移。
/// - 自动翻转：当 [flipOnOverflow] 为 true 且首选方向空间不足时，自动切换到另一侧。
/// - 横向 clamp：弹层始终在 `safeLeft..safeRight` 内（默认左右 8px 边距），双栏
///   1200px 视口下右缘贴近锚点也不会溢出屏幕外。
/// - 纵向 maxHeight 约束 + 单轴滚动，避免内容过高溢出。
/// - 点击屏障关闭（[barrierDismissible]），屏障颜色 [barrierColor] 默认为透明。
Future<void> showAdaptivePopover({
  required BuildContext context,
  required GlobalKey anchorKey,
  required Widget Function(BuildContext context, VoidCallback close) builder,
  double preferredWidth = 360,
  double? preferredHeight,
  PopoverPlacement placement = PopoverPlacement.auto,
  PopoverAlign align = PopoverAlign.end,
  Offset offset = Offset.zero,
  bool flipOnOverflow = true,
  bool barrierDismissible = true,
  Color? barrierColor,
  double maxHeight = 420,
  double gap = 8,
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
  final anchorRect = Rect.fromLTWH(
    anchorTopLeft.dx,
    anchorTopLeft.dy,
    anchorSize.width,
    anchorSize.height,
  );

  final screenW = overlayBox.size.width;
  final screenH = overlayBox.size.height;
  const safeMargin = 8.0;
  final safeLeft = safeMargin;
  final safeRight = screenW - safeMargin;

  final effectiveWidth = math.min(preferredWidth, screenW - safeMargin * 2);

  // 横向对齐：计算 left 并 clamp。
  double left;
  switch (align) {
    case PopoverAlign.start:
      left = anchorRect.left + offset.dx;
      break;
    case PopoverAlign.center:
      left = anchorRect.left +
          anchorRect.width / 2 -
          effectiveWidth / 2 +
          offset.dx;
      break;
    case PopoverAlign.end:
      left = anchorRect.right - effectiveWidth + offset.dx;
      break;
  }
  left = left.clamp(safeLeft, math.max(safeLeft, safeRight - effectiveWidth));

  // 纵向方向：计算可用空间并决定最终 placement。
  final spaceAbove = anchorRect.top;
  final spaceBelow = screenH - anchorRect.bottom;

  PopoverPlacement resolved = placement;
  if (placement == PopoverPlacement.auto) {
    // 自动：优先尝试上方（原 cupertino_popover 行为：贴在按钮顶部），
    // 若上方空间不足且下方更充裕则翻到底部。
    final need = (preferredHeight ?? maxHeight) + gap;
    final fitsAbove = spaceAbove >= need;
    final fitsBelow = spaceBelow >= need;
    if (!fitsAbove && fitsBelow) {
      resolved = PopoverPlacement.bottom;
    } else if (fitsAbove && !fitsBelow) {
      resolved = PopoverPlacement.top;
    } else if (!fitsAbove && !fitsBelow) {
      // 两侧都不足，选择空间更大的一侧。
      resolved = spaceBelow > spaceAbove
          ? PopoverPlacement.bottom
          : PopoverPlacement.top;
    } else {
      resolved = PopoverPlacement.top;
    }
  } else if (flipOnOverflow) {
    final need = (preferredHeight ?? maxHeight) + gap;
    if (resolved == PopoverPlacement.top && spaceAbove < need && spaceBelow > spaceAbove) {
      resolved = PopoverPlacement.bottom;
    } else if (resolved == PopoverPlacement.bottom &&
        spaceBelow < need &&
        spaceAbove > spaceBelow) {
      resolved = PopoverPlacement.top;
    }
  }

  // 纵向 offset：沿弹出方向叠加 offset.dy。
  final verticalOffset = offset.dy;

  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (overlayContext) => _AdaptivePopoverHost(
      left: left,
      anchorRect: anchorRect,
      effectiveWidth: effectiveWidth,
      screenWidth: screenW,
      screenHeight: screenH,
      placement: resolved,
      gap: gap,
      verticalOffset: verticalOffset,
      maxHeight: maxHeight,
      barrierDismissible: barrierDismissible,
      barrierColor: barrierColor,
      close: entry.remove,
      builder: builder,
    ),
  );
  overlay.insert(entry);
}

/// 兼容旧 API 的别名，转发到 [showAdaptivePopover]。
Future<void> showCupertinoPopoverCompat({
  required BuildContext context,
  required GlobalKey anchorKey,
  required Widget Function(BuildContext context, VoidCallback close) builder,
  double preferredWidth = 360,
}) {
  return showAdaptivePopover(
    context: context,
    anchorKey: anchorKey,
    builder: builder,
    preferredWidth: preferredWidth,
    placement: PopoverPlacement.top,
    align: PopoverAlign.end,
  );
}

class _AdaptivePopoverHost extends StatefulWidget {
  const _AdaptivePopoverHost({
    required this.left,
    required this.anchorRect,
    required this.effectiveWidth,
    required this.screenWidth,
    required this.screenHeight,
    required this.placement,
    required this.gap,
    required this.verticalOffset,
    required this.maxHeight,
    required this.barrierDismissible,
    required this.barrierColor,
    required this.close,
    required this.builder,
  });

  final double left;
  final Rect anchorRect;
  final double effectiveWidth;
  final double screenWidth;
  final double screenHeight;
  final PopoverPlacement placement;
  final double gap;
  final double verticalOffset;
  final double maxHeight;
  final bool barrierDismissible;
  final Color? barrierColor;
  final VoidCallback close;
  final Widget Function(BuildContext context, VoidCallback close) builder;

  @override
  State<_AdaptivePopoverHost> createState() => _AdaptivePopoverHostState();
}

class _AdaptivePopoverHostState extends State<_AdaptivePopoverHost> {
  @override
  Widget build(BuildContext context) {
    final isTop = widget.placement == PopoverPlacement.top;
    // 计算弹层位置：top 弹层用 bottom 锚定，bottom 弹层用 top 锚定。
    // 这样高度由内容自适应，无需预先测量。
    Widget positioned;
    if (isTop) {
      // 顶部：底部贴在锚点顶部 - gap + offset
      final bottom = widget.screenHeight -
          widget.anchorRect.top +
          widget.gap -
          widget.verticalOffset;
      positioned = Positioned(
        left: widget.left,
        bottom: bottom,
        width: widget.effectiveWidth,
        child: _constrainedCard(),
      );
    } else {
      // 底部：顶部贴在锚点底部 + gap + offset
      final top = widget.anchorRect.bottom + widget.gap + widget.verticalOffset;
      positioned = Positioned(
        left: widget.left,
        top: top,
        width: widget.effectiveWidth,
        child: _constrainedCard(),
      );
    }

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.barrierDismissible ? widget.close : null,
            child: ColoredBox(
              color: widget.barrierColor ?? const Color(0x00000000),
            ),
          ),
        ),
        positioned,
      ],
    );
  }

  Widget _constrainedCard() {
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: widget.maxHeight),
      child: SingleChildScrollView(
        child: _PopoverCard(
          child: widget.builder(context, widget.close),
        ),
      ),
    );
  }
}

class _PopoverCard extends StatelessWidget {
  const _PopoverCard({required this.child});

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

/// 计算 popover 左侧 clamp 后的位置（纯逻辑，可测试）。

///
/// [anchorLeft] / [anchorRight] 为锚点左右缘，[preferredWidth] 为期望宽度，
/// [screenWidth] 为 overlay 宽度，返回 clamp 后的 left。
double computePopoverLeft({
  required double anchorLeft,
  required double anchorRight,
  required double anchorWidth,
  required double preferredWidth,
  required double screenWidth,
  PopoverAlign align = PopoverAlign.end,
  double offsetX = 0,
  double safeMargin = 8,
}) {
  final safeLeft = safeMargin;
  final safeRight = screenWidth - safeMargin;
  final effectiveWidth = math.min(preferredWidth, screenWidth - safeMargin * 2);
  double left;
  switch (align) {
    case PopoverAlign.start:
      left = anchorLeft + offsetX;
      break;
    case PopoverAlign.center:
      left = anchorLeft + anchorWidth / 2 - effectiveWidth / 2 + offsetX;
      break;
    case PopoverAlign.end:
      left = anchorRight - effectiveWidth + offsetX;
      break;
  }
  return left.clamp(safeLeft, math.max(safeLeft, safeRight - effectiveWidth));
}
