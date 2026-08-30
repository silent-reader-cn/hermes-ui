import 'package:flutter/cupertino.dart';

import '../../../core/models/tool_call.dart';
import '../../../l10n/app_localizations.dart';
import 'tool_call_card.dart';

/// 回合完成后过程折叠组件（active.md §过程折叠 / 历史工具一二级标题退化）。
///
/// 将已完成回合中的思考块、工具调用卡等过程项收敛为单行明细自适应摘要按钮行，
/// 默认收起（首次折叠，不记忆展开偏好），点击可展开/收起平铺子卡片列表。
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

  /// 展开时渲染的过程子卡片列表（如 [ToolCallCard] / [ThinkingRow]）。
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

    final hasFailed = widget.toolGroups.any((g) => g.hasFailedTool) ||
        allCalls.any((c) => c.isError == true);
    final isRunning = widget.toolGroups.any((g) => !g.isComplete);

    final durationSeconds = allCalls
        .map((c) => c.duration)
        .whereType<double>()
        .fold<double>(0.0, (a, b) => a + b);

    final statusColor = hasFailed
        ? CupertinoColors.systemRed.resolveFrom(context)
        : (isRunning
            ? CupertinoColors.activeBlue.resolveFrom(context)
            : CupertinoColors.systemGreen.resolveFrom(context));

    final trailingDuration = (durationSeconds > 0)
        ? '${durationSeconds.toStringAsFixed(1)}s'
        : null;

    final titleStyle = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: CupertinoColors.label.resolveFrom(context),
    );

    return SizedBox(
      key: const ValueKey('collapsible-process-capsule'),
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            button: true,
            child: GestureDetector(
              key: const ValueKey('process-capsule-header'),
              behavior: HitTestBehavior.opaque,
              onTap: _toggle,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
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
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final title = adaptiveActivityTitle(
                            toolCalls: allCalls,
                            hideThinking: widget.hideThinking,
                            l10n: l10n,
                            maxWidth: constraints.maxWidth,
                            style: titleStyle,
                            textScaler: MediaQuery.textScalerOf(context),
                            textDirection:
                                Directionality.maybeOf(context) ??
                                TextDirection.ltr,
                          );
                          return Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: titleStyle,
                          );
                        },
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
          if (_expanded) ...[
            const SizedBox(height: 6),
            ...widget.children,
          ],
        ],
      ),
    );
  }
}
