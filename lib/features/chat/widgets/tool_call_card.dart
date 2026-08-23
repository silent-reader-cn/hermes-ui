import 'package:flutter/cupertino.dart';

import '../../../core/models/tool_call.dart';
import '../../../l10n/app_localizations.dart';
import '../../chat/chat_models.dart';

/// 单条工具调用卡片（chat_spec.md §3.5 ToolCallCardView）。
///
/// 内层二次折叠：标题行始终可见，点击展开 arguments / result。
/// 默认收起（collapsed），不管 live 还是 completed。
class ToolCallCard extends StatefulWidget {
  const ToolCallCard({super.key, required this.call});

  final ToolCall call;

  @override
  State<ToolCallCard> createState() => _ToolCallCardState();
}

class _ToolCallCardState extends State<ToolCallCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final call = widget.call;
    final content = ToolCallDisplayContent.of(call);
    final failed = call.isError == true;
    final running = !call.isCompleted;
    final accentColor = failed
        ? CupertinoColors.systemRed.resolveFrom(context)
        : running
            ? CupertinoColors.activeBlue.resolveFrom(context)
            : CupertinoColors.systemGreen.resolveFrom(context);
    final bgColor = failed
        ? CupertinoColors.systemRed.resolveFrom(context).withValues(alpha: 0.08)
        : running
            ? CupertinoColors.activeBlue.resolveFrom(context).withValues(alpha: 0.08)
            : CupertinoColors.systemTeal.resolveFrom(context).withValues(alpha: 0.08);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _expanded = !_expanded),
            child: Row(
              children: [
                if (running)
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
                    failed ? CupertinoIcons.exclamationmark_triangle : CupertinoIcons.wrench,
                    size: 14,
                    color: accentColor,
                  ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    call.displayName,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: accentColor,
                    ),
                  ),
                ),
                if (call.isCompleted && call.duration != null)
                  Text(
                    '${call.duration!.toStringAsFixed(1)}s',
                    style: TextStyle(
                      fontSize: 11,
                      color: CupertinoColors.secondaryLabel.resolveFrom(context),
                    ),
                  ),
                const SizedBox(width: 6),
                Icon(
                  _expanded ? CupertinoIcons.chevron_up : CupertinoIcons.chevron_down,
                  size: 12,
                  color: CupertinoColors.secondaryLabel.resolveFrom(context),
                ),
              ],
            ),
          ),
          if (_expanded) ...[
            if (content.arguments.isNotEmpty) ...[
              const SizedBox(height: 6),
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
            // running 状态在 inner 展开时仍显示底部指示（提供文字语义）
            if (running) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CupertinoActivityIndicator(
                      radius: 6,
                      color: CupertinoColors.activeBlue.resolveFrom(context),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    AppLocalizations.of(context).runningIndicator,
                    style: TextStyle(
                      fontSize: 11,
                      color: CupertinoColors.secondaryLabel.resolveFrom(context),
                    ),
                  ),
                ],
              ),
            ],
            // 没有可展开内容时不额外渲染（保持紧凑）
          ] else if (running) ...[
            // 收起态仍保留一行 running 提示，保证语义可见
            const SizedBox(height: 4),
            Row(
              children: [
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CupertinoActivityIndicator(
                    radius: 6,
                    color: CupertinoColors.activeBlue.resolveFrom(context),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  AppLocalizations.of(context).runningIndicator,
                  style: TextStyle(
                    fontSize: 11,
                    color: CupertinoColors.secondaryLabel.resolveFrom(context),
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
///
/// 外层折叠 + 内层每个 ToolCallCard 二次折叠，默认全部收起（包括 live）。
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
    // 默认一律收起（含 live），需用户手动展开查看（task 追加需求）
    _expanded = false;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
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
                if (running)
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
                    failed
                        ? CupertinoIcons.exclamationmark_triangle_fill
                        : CupertinoIcons.checkmark_circle_fill,
                    size: 14,
                    color: failed
                        ? CupertinoColors.systemRed.resolveFrom(context)
                        : CupertinoColors.systemGreen.resolveFrom(context),
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
                  Text(
                    l10n.toolFailedStatus,
                    style: TextStyle(
                      fontSize: 11,
                      color: CupertinoColors.systemRed.resolveFrom(context),
                    ),
                  )
                else if (running)
                  Text(
                    l10n.toolRunningStatus,
                    style: TextStyle(
                      fontSize: 11,
                      color: CupertinoColors.secondaryLabel.resolveFrom(context),
                    ),
                  ),
                const SizedBox(width: 6),
                Icon(
                  _expanded ? CupertinoIcons.chevron_up : CupertinoIcons.chevron_down,
                  size: 12,
                  color: CupertinoColors.secondaryLabel.resolveFrom(context),
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
