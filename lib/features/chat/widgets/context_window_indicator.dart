import 'dart:math' as math;

import 'package:flutter/cupertino.dart';

import '../../../core/models/context_window_snapshot.dart';
import '../../../l10n/app_localizations.dart';

/// 30px 环形进度指示器（Swift: ContextWindowIndicatorView）。
///
/// - 视觉：stroke 3、起始 -90°、ring 30、命中 44。
/// - 颜色：track 白16%/黑12%、progress 白92%/黑82%。
/// - 中心：9pt w600，百分比或“·”。
/// - a11y：label/value、命中 44、禁用态。
class ContextWindowIndicator extends StatelessWidget {
  const ContextWindowIndicator({
    super.key,
    required this.snapshot,
    required this.onTap,
  });

  final ContextWindowSnapshot? snapshot;
  final VoidCallback? onTap;

  static const double ringSize = 30;
  static const double tapTargetSize = 44;

  @override
  Widget build(BuildContext context) {
    final percentage = snapshot?.percentage;
    final isInteractive = percentage != null;
    final pct = isInteractive ? (percentage * 100).round().clamp(0, 100) : null;
    final label = isInteractive ? '$pct' : '·';
    final brightness = CupertinoTheme.of(context).brightness ??
        MediaQuery.platformBrightnessOf(context);
    final isDark = brightness == Brightness.dark;
    final trackColor = isDark
        ? CupertinoColors.white.withValues(alpha: 0.16)
        : CupertinoColors.black.withValues(alpha: 0.12);
    final progressColor = isDark
        ? CupertinoColors.white.withValues(alpha: 0.92)
        : CupertinoColors.black.withValues(alpha: 0.82);
    final textColor = isInteractive
        ? CupertinoColors.label.resolveFrom(context)
        : CupertinoColors.secondaryLabel.resolveFrom(context);
    final l10n = AppLocalizations.of(context);

    final ring = SizedBox(
      width: ringSize,
      height: ringSize,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: const Size(ringSize, ringSize),
            painter: _RingPainter(
              percentage: percentage?.clamp(0.0, 1.0),
              trackColor: trackColor,
              progressColor: progressColor,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: textColor,
              decoration: TextDecoration.none,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );

    final hit = SizedBox(
      width: tapTargetSize,
      height: tapTargetSize,
      child: Center(child: ring),
    );

    return Semantics(
      button: true,
      enabled: isInteractive,
      label: isInteractive
          ? l10n.contextWindowUsage
          : l10n.contextWindowUsageLoading,
      value: isInteractive ? '$pct percent' : '',
      child: CupertinoButton(
        key: const ValueKey('chat-context-indicator-button'),
        padding: EdgeInsets.zero,
        minimumSize: const Size(tapTargetSize, tapTargetSize),
        onPressed: isInteractive ? onTap : null,
        child: hit,
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.percentage,
    required this.trackColor,
    required this.progressColor,
  });

  final double? percentage;
  final Color trackColor;
  final Color progressColor;

  @override
  void paint(Canvas canvas, Size size) {
    const strokeWidth = 3.0;
    final radius = (size.width - strokeWidth) / 2;
    final center = Offset(size.width / 2, size.height / 2);
    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(center, radius, trackPaint);
    final pct = percentage;
    if (pct != null && pct > 0) {
      final progressPaint = Paint()
        ..color = progressColor
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = strokeWidth;
      final sweep = 2 * math.pi * pct.clamp(0.0, 1.0);
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        sweep,
        false,
        progressPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) {
    return oldDelegate.percentage != percentage ||
        oldDelegate.trackColor != trackColor ||
        oldDelegate.progressColor != progressColor;
  }
}
