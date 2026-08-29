import 'package:flutter/cupertino.dart';

import '../../../core/models/tool_call.dart';
import '../../../l10n/app_localizations.dart';

/// 回合完成后过程折叠胶囊组件（active.md §过程折叠）。
///
/// 将已完成回合中的思考块、工具调用卡等过程项收敛为单行摘要胶囊，
/// 默认收起（首次折叠，不记忆展开偏好），点击可展开/收起详情。
class CollapsibleProcessCapsule extends StatefulWidget {
  const CollapsibleProcessCapsule({
    super.key,
    required this.toolGroups,
    required this.children,
    this.hideThinking = false,
    this.noticeCount = 0,
    this.initiallyExpanded = false,
    this.onToggle,
  });

  /// 归档/展示的工具调用组。
  final List<ToolCallGroup> toolGroups;

  /// 展开时渲染的过程子卡片列表（如 [ToolCallGroupCard]）。
  final List<Widget> children;

  /// 是否隐藏思考。
  final bool hideThinking;

  /// 伴随的通知数。
  final int noticeCount;

  /// 初始展开态（默认 false）。
  final bool initiallyExpanded;

  /// 切换展开回调。
  final VoidCallback? onToggle;

  @override
  State<CollapsibleProcessCapsule> createState() =>
      _CollapsibleProcessCapsuleState();
}

class _CollapsibleProcessCapsuleState extends State<CollapsibleProcessCapsule> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
  }

  void _toggle() {
    setState(() {
      _expanded = !_expanded;
    });
    widget.onToggle?.call();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final allCalls = [
      for (final g in widget.toolGroups) ...g.toolCalls,
    ];

    final hasThinking =
        !widget.hideThinking && allCalls.any((c) => c.isThinking);
    final toolCount = allCalls.where((c) => !c.isThinking).length;
    final hasFailed = widget.toolGroups.any((g) => g.hasFailedTool) ||
        allCalls.any((c) => c.isError == true);
    final isRunning = widget.toolGroups.any((g) => !g.isComplete);

    final durationSeconds = allCalls
        .map((c) => c.duration)
        .whereType<double>()
        .fold<double>(0.0, (a, b) => a + b);

    final title = l10n.formatProcessCapsuleSummary(
      hasThinking: hasThinking,
      toolCount: toolCount,
      noticeCount: widget.noticeCount,
      durationSeconds: hasThinking && durationSeconds > 0 ? durationSeconds : null,
    );

    final statusColor = hasFailed
        ? CupertinoColors.systemRed.resolveFrom(context)
        : (isRunning
            ? CupertinoColors.activeBlue.resolveFrom(context)
            : CupertinoColors.systemGreen.resolveFrom(context));

    final trailingDuration = (durationSeconds > 0 && !hasThinking)
        ? '${durationSeconds.toStringAsFixed(1)}s'
        : null;

    return Container(
      key: const ValueKey('collapsible-process-capsule'),
      width: double.infinity,
      decoration: BoxDecoration(
        color: CupertinoColors.systemGrey6.resolveFrom(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: CupertinoColors.systemGrey4.resolveFrom(context),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            button: true,
            label: title,
            child: GestureDetector(
              key: const ValueKey('process-capsule-header'),
              behavior: HitTestBehavior.opaque,
              onTap: _toggle,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Row(
                  children: [
                    if (isRunning)
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CupertinoActivityIndicator(
                          radius: 7,
                          color: CupertinoColors.activeBlue.resolveFrom(context),
                        ),
                      )
                    else
                      Icon(
                        hasFailed
                            ? CupertinoIcons.exclamationmark_triangle_fill
                            : CupertinoIcons.checkmark_circle_fill,
                        size: 14,
                        color: statusColor,
                      ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: CupertinoColors.label.resolveFrom(context),
                        ),
                      ),
                    ),
                    if (trailingDuration != null) ...[
                      Text(
                        trailingDuration,
                        style: TextStyle(
                          fontSize: 11,
                          color: CupertinoColors.secondaryLabel
                              .resolveFrom(context),
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Icon(
                      _expanded
                          ? CupertinoIcons.chevron_up
                          : CupertinoIcons.chevron_down,
                      size: 12,
                      color:
                          CupertinoColors.secondaryLabel.resolveFrom(context),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 4),
                  ...widget.children,
                ],
              ),
            ),
        ],
      ),
    );
  }
}
