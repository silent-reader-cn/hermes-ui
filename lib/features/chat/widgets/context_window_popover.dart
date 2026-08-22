import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/context_window_snapshot.dart';
import '../../../core/utils/context_window_formatter.dart';
import '../../../l10n/app_localizations.dart';
import '../chat_providers.dart';

/// 上下文详情弹层（Swift: ContextWindowPopover）。
///
/// 宽 240、圆角 18、背景 secondarySystemBackground + separator 边框。
/// 内容：tokensLabel / Divider / InfoRows(input/output/threshold/cost)
/// + currentModel + 压缩按钮 + 模型列表 + 关闭。
class ContextWindowPopover extends ConsumerStatefulWidget {
  const ContextWindowPopover({
    super.key,
    required this.sessionId,
    required this.snapshot,
    required this.currentModel,
    required this.onClose,
  });

  final String sessionId;
  final ContextWindowSnapshot snapshot;
  final String? currentModel;
  final VoidCallback onClose;

  @override
  ConsumerState<ContextWindowPopover> createState() =>
      _ContextWindowPopoverState();
}

class _ContextWindowPopoverState extends ConsumerState<ContextWindowPopover> {
  bool _compressing = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final snapshot = widget.snapshot;
    final pct = snapshot.percentage;
    final pctInt = pct == null ? null : (pct * 100).round().clamp(0, 100);
    final tokensLabel = ContextWindowFormatter.tokensLabel(snapshot);
    final inputLabel = ContextWindowFormatter.inputTokensLabel(snapshot);
    final outputLabel = ContextWindowFormatter.outputTokensLabel(snapshot);
    final thresholdLabel = ContextWindowFormatter.thresholdLabel(snapshot);
    final costLabel = ContextWindowFormatter.costLabel(snapshot);

    // Compress threshold (web: ≥75 filled, 50-75 secondary, <50 disabled).
    final isHigh = pctInt != null && pctInt >= 75;
    final isMid = pctInt != null && pctInt >= 50 && pctInt < 75;
    final compressLabel = isHigh
        ? l10n.contextWindowCompressNow
        : isMid
            ? l10n.contextWindowCompressHint
            : l10n.compress;

    final bg = CupertinoColors.secondarySystemBackground.resolveFrom(context);
    final separator = CupertinoColors.separator.resolveFrom(context);
    final models = ref.watch(chatAvailableModelsProvider);
    final currentModel = widget.currentModel;

    return Container(
      width: 240,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: separator),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tokensLabel,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                Container(height: 0.5, color: separator),
                const SizedBox(height: 10),
                _InfoRow(label: l10n.contextWindowInput, value: inputLabel),
                const SizedBox(height: 6),
                _InfoRow(label: l10n.contextWindowOutput, value: outputLabel),
                const SizedBox(height: 6),
                _InfoRow(
                    label: l10n.contextWindowThreshold, value: thresholdLabel),
                const SizedBox(height: 6),
                _InfoRow(label: l10n.contextWindowCost, value: costLabel),
                const SizedBox(height: 10),
                Container(height: 0.5, color: separator),
                const SizedBox(height: 10),
                Text(
                  l10n.contextWindowCurrentModel,
                  style: TextStyle(
                    fontSize: 12,
                    color: CupertinoColors.secondaryLabel.resolveFrom(context),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  (currentModel == null || currentModel.isEmpty)
                      ? l10n.contextWindowFollowServerDefault
                      : currentModel,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 12),
                _CompressButton(
                  label: _compressing ? l10n.compressing : compressLabel,
                  isHigh: isHigh,
                  isMid: isMid,
                  compressing: _compressing,
                  enabled: pctInt != null && pctInt > 0,
                  onPressed: _compressing
                      ? null
                      : () async {
                          setState(() => _compressing = true);
                          try {
                            final ok = await ref
                                .read(chatControllerProvider(widget.sessionId)
                                    .notifier)
                                .compressSession();
                            if (!mounted) return;
                            if (ok) widget.onClose();
                          } finally {
                            if (mounted) {
                              setState(() => _compressing = false);
                            }
                          }
                        },
                ),
                if (models.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(height: 0.5, color: separator),
                  const SizedBox(height: 8),
                  for (final m in models)
                    _ModelRow(
                      label: m,
                      selected: m == currentModel,
                      onTap: () {
                        ref
                            .read(chatControllerProvider(widget.sessionId)
                                .notifier)
                            .selectModel(m);
                        widget.onClose();
                      },
                    ),
                  _ModelRow(
                    label: l10n.contextWindowFollowServerDefault,
                    selected: currentModel == null || currentModel.isEmpty,
                    onTap: () {
                      ref
                          .read(
                              chatControllerProvider(widget.sessionId).notifier)
                          .selectModel(null);
                      widget.onClose();
                    },
                  ),
                ],
              ],
            ),
          ),
          Container(height: 0.5, color: separator),
          CupertinoButton(
            key: const ValueKey('context-popover-close'),
            padding: const EdgeInsets.symmetric(vertical: 10),
            onPressed: widget.onClose,
            child: Text(l10n.contextWindowClose),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: CupertinoColors.secondaryLabel.resolveFrom(context),
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }
}

class _CompressButton extends StatelessWidget {
  const _CompressButton({
    required this.label,
    required this.isHigh,
    required this.isMid,
    required this.compressing,
    required this.enabled,
    required this.onPressed,
  });

  final String label;
  final bool isHigh;
  final bool isMid;
  final bool compressing;
  final bool enabled;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final child = compressing
        ? Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CupertinoActivityIndicator(radius: 8),
              const SizedBox(width: 8),
              Text(label),
            ],
          )
        : Text(label);
    if (isHigh) {
      return SizedBox(
        width: double.infinity,
        child: CupertinoButton.filled(
          key: const ValueKey('context-popover-compress'),
          padding: const EdgeInsets.symmetric(vertical: 10),
          onPressed: enabled ? onPressed : null,
          child: child,
        ),
      );
    }
    if (isMid) {
      return SizedBox(
        width: double.infinity,
        child: CupertinoButton(
          key: const ValueKey('context-popover-compress'),
          padding: const EdgeInsets.symmetric(vertical: 10),
          color: CupertinoColors.systemGrey5.resolveFrom(context),
          onPressed: enabled ? onPressed : null,
          child: DefaultTextStyle(
            style: TextStyle(
              color: CupertinoColors.label.resolveFrom(context),
            ),
            child: child,
          ),
        ),
      );
    }
    return SizedBox(
      width: double.infinity,
      child: CupertinoButton(
        key: const ValueKey('context-popover-compress'),
        padding: const EdgeInsets.symmetric(vertical: 10),
        onPressed: null,
        child: DefaultTextStyle(
          style: TextStyle(
            color: CupertinoColors.secondaryLabel.resolveFrom(context),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _ModelRow extends StatelessWidget {
  const _ModelRow({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      onPressed: onTap,
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: selected
                    ? CupertinoColors.activeBlue.resolveFrom(context)
                    : CupertinoColors.label.resolveFrom(context),
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
          if (selected)
            Icon(
              CupertinoIcons.check_mark,
              size: 16,
              color: CupertinoColors.activeBlue.resolveFrom(context),
            ),
        ],
      ),
    );
  }
}
