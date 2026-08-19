import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

/// 统一的可访问性按钮包装：补充语义标签、提示和触觉反馈。
class AccessibleButton extends StatelessWidget {
  const AccessibleButton({
    super.key,
    required this.label,
    required this.child,
    required this.onPressed,
    this.hint,
    this.padding = EdgeInsets.zero,
    this.minimumSize,
    this.color,
    this.disabledColor = CupertinoColors.quaternarySystemFill,
    this.borderRadius = const BorderRadius.all(Radius.circular(8.0)),
    this.alignment = Alignment.center,
  }) : _filled = false;

  const AccessibleButton.filled({
    super.key,
    required this.label,
    required this.child,
    required this.onPressed,
    this.hint,
    this.padding = EdgeInsets.zero,
    this.minimumSize,
    this.disabledColor = CupertinoColors.quaternarySystemFill,
    this.borderRadius = const BorderRadius.all(Radius.circular(8.0)),
    this.alignment = Alignment.center,
  }) : color = null,
       _filled = true;

  final String label;
  final String? hint;
  final Widget child;
  final VoidCallback? onPressed;
  final EdgeInsetsGeometry? padding;
  final Size? minimumSize;
  final Color? color;
  final Color disabledColor;
  final BorderRadius? borderRadius;
  final AlignmentGeometry alignment;
  final bool _filled;

  @override
  Widget build(BuildContext context) {
    final VoidCallback? callback = onPressed == null
        ? null
        : () {
            unawaited(HapticFeedback.selectionClick());
            onPressed!();
          };

    final Widget button = _filled
        ? CupertinoButton.filled(
            onPressed: callback,
            padding: padding,
            minimumSize: minimumSize,
            disabledColor: disabledColor,
            borderRadius: borderRadius,
            alignment: alignment,
            child: child,
          )
        : CupertinoButton(
            onPressed: callback,
            padding: padding,
            minimumSize: minimumSize,
            color: color,
            disabledColor: disabledColor,
            borderRadius: borderRadius,
            alignment: alignment,
            child: child,
          );

    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: label,
      hint: hint,
      child: button,
    );
  }
}

/// 为非按钮交互提供统一触觉反馈。
Future<void> selectionHaptic() => HapticFeedback.selectionClick();
Future<void> successHaptic() => HapticFeedback.lightImpact();
Future<void> errorHaptic() => HapticFeedback.heavyImpact();
