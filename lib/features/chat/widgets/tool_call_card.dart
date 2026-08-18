import 'package:flutter/cupertino.dart';

import '../../../core/models/tool_call.dart';
import '../../chat/chat_models.dart';

/// 单条工具调用卡片（chat_spec.md §3.5 ToolCallCardView）。
///
/// 名称 + 参数区 + Result 区（等宽）+ 错误色（isError）。
class ToolCallCard extends StatelessWidget {
  const ToolCallCard({super.key, required this.call});

  final ToolCall call;

  @override
  Widget build(BuildContext context) {
    final content = ToolCallDisplayContent.of(call);
    final failed = call.isError == true;
    final color = failed
        ? CupertinoColors.systemRed.resolveFrom(context)
        : CupertinoColors.systemTeal.resolveFrom(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: failed
        ? CupertinoColors.systemRed.resolveFrom(context).withValues(alpha: 0.08)
        : CupertinoColors.systemTeal.resolveFrom(context).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                failed
                    ? CupertinoIcons.exclamationmark_triangle
                    : CupertinoIcons.wrench,
                size: 14,
                color: color,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  call.displayName,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ),
              if (call.isCompleted && call.duration != null)
                Text(
                  '${call.duration!.toStringAsFixed(1)}s',
                  style: const TextStyle(
                    fontSize: 11,
                    color: CupertinoColors.secondaryLabel,
                  ),
                ),
            ],
          ),
          if (content.arguments.isNotEmpty) ...[
            const SizedBox(height: 4),
            _MonospaceText(content.arguments),
          ],
          if (content.result.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: SizedBox(
                height: 1,
                width: double.infinity,
                child: _DividerLine(),
              ),
            ),
            _MonospaceText(content.result, monospaced: content.monospaced),
          ],
          if (!call.isCompleted) ...[
            const SizedBox(height: 4),
            const Row(
              children: [
                CupertinoActivityIndicator(radius: 6),
                SizedBox(width: 6),
                Text(
                  '运行中…',
                  style: TextStyle(
                    fontSize: 11,
                    color: CupertinoColors.secondaryLabel,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// 主题自适应的 1px 分隔线（ColoredBox 不 resolve 动态色，自行解析）。
class _DividerLine extends StatelessWidget {
  const _DividerLine();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: CupertinoColors.systemGrey4.resolveFrom(context),
    );
  }
}

class _MonospaceText extends StatelessWidget {
  const _MonospaceText(this.text, {this.monospaced = true});

  final String text;
  final bool monospaced;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 12,
        fontFamily: monospaced ? 'monospace' : null,
        color: CupertinoColors.label.resolveFrom(context),
        height: 1.35,
      ),
    );
  }
}

/// 工具调用分组卡（chat_spec.md §3.5："Activity: N tools"）。
class ToolCallGroupCard extends StatefulWidget {
  const ToolCallGroupCard({super.key, required this.group});

  final ToolCallGroup group;

  @override
  State<ToolCallGroupCard> createState() => _ToolCallGroupCardState();
}

class _ToolCallGroupCardState extends State<ToolCallGroupCard> {
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    // Live activity stays visible while running; completed history is compact.
    _expanded = !widget.group.isComplete;
  }

  @override
  Widget build(BuildContext context) {
    final group = widget.group;
    final failed = group.hasFailedTool;
    final running = !group.isComplete;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        // 动态色需显式 resolve：暗黑模式下不 resolve 会画成浅色亮块。
        color: CupertinoColors.systemGrey6.resolveFrom(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: CupertinoColors.systemGrey4.resolveFrom(context),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _expanded = !_expanded),
            child: Row(
              children: [
                Icon(
                  failed
                      ? CupertinoIcons.exclamationmark_triangle_fill
                      : running
                          ? CupertinoIcons.wrench
                          : CupertinoIcons.checkmark_circle_fill,
                  size: 14,
                  color: failed
                      ? CupertinoColors.systemRed
                      : CupertinoColors.secondaryLabel,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    group.activityTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: CupertinoColors.label.resolveFrom(context),
                    ),
                  ),
                ),
                if (failed)
                  Text('失败', style: TextStyle(fontSize: 11, color: CupertinoColors.systemRed.resolveFrom(context)))
                else if (running)
                  Text('运行中', style: TextStyle(fontSize: 11, color: CupertinoColors.secondaryLabel.resolveFrom(context))),
                const SizedBox(width: 6),
                Icon(
                  _expanded ? CupertinoIcons.chevron_up : CupertinoIcons.chevron_down,
                  size: 12,
                  color: CupertinoColors.secondaryLabel,
                ),
              ],
            ),
          ),
          if (_expanded) ...[
            const SizedBox(height: 8),
            for (final call in group.toolCalls) ...[
              ToolCallCard(call: call),
              if (call != group.toolCalls.last) const SizedBox(height: 6),
            ],
          ],
        ],
      ),
    );
  }
}
