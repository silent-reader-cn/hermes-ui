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
        ? CupertinoColors.systemRed
        : CupertinoColors.systemTeal;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: failed
            ? CupertinoColors.systemRed.withValues(alpha: 0.08)
            : CupertinoColors.systemTeal.withValues(alpha: 0.08),
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
                    color: CupertinoColors.systemGrey,
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
                child: ColoredBox(color: CupertinoColors.systemGrey4),
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
                    color: CupertinoColors.systemGrey,
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
        color: CupertinoColors.label,
        height: 1.35,
      ),
    );
  }
}

/// 工具调用分组卡（chat_spec.md §3.5："Activity: N tools"）。
class ToolCallGroupCard extends StatelessWidget {
  const ToolCallGroupCard({super.key, required this.group});

  final ToolCallGroup group;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: CupertinoColors.systemGrey6,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: CupertinoColors.systemGrey4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            group.activityTitle,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: CupertinoColors.systemGrey,
            ),
          ),
          const SizedBox(height: 6),
          for (final call in group.toolCalls) ...[
            ToolCallCard(call: call),
            if (call != group.toolCalls.last) const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }
}
