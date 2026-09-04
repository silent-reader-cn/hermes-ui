import 'package:flutter/cupertino.dart';

import '../../../app/shell/adaptive_shell.dart';
import '../../../app/theme/status_colors.dart';
import '../../../l10n/app_localizations.dart';

/// 引导与安装体系的通用宽屏双栏骨架 Widget。
///
/// 遵循宽屏双栏铁律：
/// - 窗口宽 >= [kAdaptiveBreakpoint]（900）时：左 45% 品牌氛围区 + 右单列功能区（maxWidth 460，水平垂直居中）；
/// - 窗口宽 < 900（Android / 窄窗）时：完全渲染 [child]，现状单列形态零变化。
class WideDualPane extends StatelessWidget {
  const WideDualPane({
    super.key,
    required this.child,
    this.wideChild,
    this.brandPane,
    this.maxWidth = 460.0,
  });

  /// 窄屏回退 Widget（<900 宽时直接返回渲染）。
  final Widget child;

  /// 宽屏右侧栏功能区 Widget（若为空则回退到 [child]）。
  final Widget? wideChild;

  /// 可选自定义左侧品牌区 Widget。
  final Widget? brandPane;

  /// 右侧单列功能区的最大宽度（铁律规格 420~480，默认 460）。
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= kAdaptiveBreakpoint;
    if (!isWide) {
      return child;
    }

    final effectiveRightChild = wideChild ?? child;
    final isDark = CupertinoTheme.of(context).brightness == Brightness.dark;

    return Row(
      children: [
        // 左品牌氛围区（占 40-50%，此处采用 flex 45:55，即约 45%）
        Expanded(
          flex: 45,
          child: brandPane ?? OnboardingBrandPane(isDark: isDark),
        ),
        // 极简灰白分割线
        Container(
          width: 0.5,
          color: CupertinoColors.separator.resolveFrom(context),
        ),
        // 右单列功能区（maxWidth 420~480 列内水平垂直居中，可滚动）
        Expanded(
          flex: 55,
          child: Center(
            child: ConstrainedBox(
              key: const ValueKey('wide-dual-pane-form-container'),
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: effectiveRightChild,
            ),
          ),
        ),
      ],
    );
  }
}

/// 默认左侧品牌氛围区 Widget。
class OnboardingBrandPane extends StatelessWidget {
  const OnboardingBrandPane({
    super.key,
    required this.isDark,
  });

  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Container(
      key: const ValueKey('onboarding-brand-pane'),
      color: isDark
          ? const Color(0xFF0A0A0C)
          : CupertinoColors.systemGroupedBackground.resolveFrom(context),
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
      child: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Image.asset(
                  'assets/branding/hermes-agent-icon-1024.png',
                  width: 88,
                  height: 88,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) =>
                      _buildFallbackLogo(context),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Hermes',
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                  color: CupertinoColors.label.resolveFrom(context),
                ),
              ),
              const SizedBox(height: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: Text(
                  l10n.onboardingBrandSlogan,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.4,
                    color: secondaryText.resolveFrom(context),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFallbackLogo(BuildContext context) {
    return Container(
      width: 88,
      height: 88,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : const Color(0xFFE5E5EA),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: CupertinoColors.separator.resolveFrom(context),
          width: 0.5,
        ),
      ),
      child: Center(
        child: Text(
          'H',
          style: TextStyle(
            fontSize: 44,
            fontWeight: FontWeight.bold,
            color: isDark ? CupertinoColors.white : CupertinoColors.black,
          ),
        ),
      ),
    );
  }
}
