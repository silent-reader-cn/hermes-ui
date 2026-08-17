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
  });

  final String label;
  final String? hint;
  final Widget child;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: label,
      hint: hint,
      child: CupertinoButton(
        onPressed: onPressed == null
            ? null
            : () {
                unawaited(HapticFeedback.selectionClick());
                onPressed!();
              },
        padding: EdgeInsets.zero,
        child: child,
      ),
    );
  }
}

/// 为非按钮交互提供统一触觉反馈。
Future<void> selectionHaptic() => HapticFeedback.selectionClick();
Future<void> successHaptic() => HapticFeedback.lightImpact();
Future<void> errorHaptic() => HapticFeedback.heavyImpact();
