import 'package:flutter/cupertino.dart';

import '../../../l10n/app_localizations.dart';
import '../chat_models.dart';

/// 思考卡（思考按工具卡样式折叠渲染）。
///
/// 历史消息（assistant 气泡内锚定）与 live 时间线思考段共用同一组件，
/// 视觉：systemGrey6 底 + systemGrey4 边框圆角 10 + sparkles 图标 +
/// 展开/收起（chevron）+ 单行预览。
class ReasoningBlock extends StatefulWidget {
  const ReasoningBlock({super.key, required this.group});

  final ReasoningGroup group;

  @override
  State<ReasoningBlock> createState() => _ReasoningBlockState();
}

class _ReasoningBlockState extends State<ReasoningBlock> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = widget.group.text.trim();
    if (text.isEmpty) return const SizedBox.shrink();
    final summary = text.replaceAll(RegExp(r'\s+'), ' ');
    final preview = summary.length > 80
        ? '${summary.substring(0, 80)}…'
        : summary;
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        // 与工具调用卡片同款视觉（思考按 tool 样式折叠卡渲染）。
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
                  CupertinoIcons.sparkles,
                  size: 14,
                  color: CupertinoColors.systemPurple.resolveFrom(context),
                ),
                const SizedBox(width: 6),
                Text(
                  l10n.thinkingLabel,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: CupertinoColors.label.resolveFrom(context),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    preview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: secondary),
                  ),
                ),
                Icon(
                  _expanded
                      ? CupertinoIcons.chevron_up
                      : CupertinoIcons.chevron_down,
                  size: 12,
                  color: secondary,
                ),
              ],
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                text,
                style: const TextStyle(fontSize: 12, height: 1.4),
              ),
            ),
        ],
      ),
    );
  }
}