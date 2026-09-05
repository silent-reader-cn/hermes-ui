import 'package:flutter/cupertino.dart';

import '../../../app/theme/status_colors.dart';
import '../../../core/models/tool_call.dart';
import '../../../l10n/app_localizations.dart';

/// 回合完成后过程折叠胶囊组件（active.md #55，样式改版 #59，位置改版 #58）。
///
/// 将已完成回合中的思考块、工具调用卡、中间文本等过程项收敛为单行摘要胶囊，
/// 默认收起（首次折叠，会话内记忆），点击可展开/收起详情。
///
/// #59 形态定位：**轻量摘要条**——与 [ToolCallGroupCard]（实底灰盒 + 边框 +
/// 绿勾状态图标，tool_call_card.dart）刻意拉开层级：无背景盒、无边框，
/// 左侧 3px 圆角竖条 accent + 常规字重灰字 + 弱化箭头。胶囊只在回合完成态
/// 出现，状态图标与工具卡绿勾重复，故移除。
class CollapsibleProcessCapsule extends StatefulWidget {
  const CollapsibleProcessCapsule({
    super.key,
    required this.toolGroups,
    this.intermediateTextCount = 0,
    this.children = const <Widget>[],
    this.hideThinking = false,
    this.noticeCount = 0,
    this.initiallyExpanded = false,
    this.isExpanded,
    this.onToggle,
  });

  /// 归档/展示的工具调用组。
  final List<ToolCallGroup> toolGroups;

  /// 回合内中间助手文本数。
  final int intermediateTextCount;

  /// 展开时渲染的过程子卡片列表（当作为独立容器时使用）。
  final List<Widget> children;

  /// 是否隐藏思考。
  final bool hideThinking;

  /// 伴随的通知数。
  final int noticeCount;

  /// 初始展开态（默认 false）。
  final bool initiallyExpanded;

  /// 外部受控展开态（若提供则优先于内部状态）。
  final bool? isExpanded;

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
    _expanded = widget.isExpanded ?? widget.initiallyExpanded;
  }

  @override
  void didUpdateWidget(CollapsibleProcessCapsule oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isExpanded != null) {
      _expanded = widget.isExpanded!;
    }
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
    final effectiveExpanded = widget.isExpanded ?? _expanded;

    final titleStyle = TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w400,
      color: secondaryText.resolveFrom(context),
    );

    return SizedBox(
      key: const ValueKey('collapsible-process-capsule'),
      width: double.infinity,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // #59 左侧竖条 accent：标识「这是一段可展开的过程摘要」，
          // 与工具卡（实底盒）形成层级区分。
          Container(
            width: 3,
            height: 32,
            margin: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              color: statusBlueText.resolveFrom(context),
              borderRadius: BorderRadius.circular(1.5),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    // 可用标题宽度：容器宽 - 左右内边距 - 箭头 - 间距（- 耗时）
                    var availableWidth = constraints.maxWidth - 20 - 12 - 6;
                    final trailingDuration = _trailingDuration();
                    if (trailingDuration != null) {
                      availableWidth -= 44;
                    }
                    if (availableWidth < 0) availableWidth = 0;

                    final title = formatProcessCapsuleSummary(
                      toolGroups: widget.toolGroups,
                      intermediateTextCount: widget.intermediateTextCount,
                      hideThinking: widget.hideThinking,
                      l10n: l10n,
                      maxWidth: constraints.maxWidth.isFinite
                          ? availableWidth
                          : null,
                      style: titleStyle,
                      textScaler: MediaQuery.textScalerOf(context),
                      textDirection: Directionality.of(context),
                    );

                    return Semantics(
                      button: true,
                      label: effectiveExpanded
                          ? l10n.turn55CollapseProcess
                          : l10n.turn55ExpandProcess,
                      child: GestureDetector(
                        key: const ValueKey('process-capsule-header'),
                        behavior: HitTestBehavior.opaque,
                        onTap: _toggle,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: titleStyle,
                                ),
                              ),
                              if (trailingDuration != null) ...[
                                Text(
                                  trailingDuration,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: secondaryText.resolveFrom(context),
                                  ),
                                ),
                                const SizedBox(width: 6),
                              ],
                              Icon(
                                effectiveExpanded
                                    ? CupertinoIcons.chevron_up
                                    : CupertinoIcons.chevron_down,
                                size: 12,
                                color: CupertinoColors.tertiaryLabel
                                    .resolveFrom(context),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
                if (effectiveExpanded && widget.children.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [const SizedBox(height: 4), ...widget.children],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 耗时尾缀（无思考且总耗时 > 0 时展示）。
  String? _trailingDuration() {
    final allCalls = [for (final g in widget.toolGroups) ...g.toolCalls];
    final hasThinking =
        !widget.hideThinking && allCalls.any((c) => c.isThinking);
    final durationSeconds = allCalls
        .map((c) => c.duration)
        .whereType<double>()
        .fold<double>(0.0, (a, b) => a + b);
    return (durationSeconds > 0 && !hasThinking)
        ? '${durationSeconds.toStringAsFixed(1)}s'
        : null;
  }
}

/// 根据可用宽度自适应计算过程胶囊标题（对齐 [_adaptiveActivityTitle] 风格）。
String formatProcessCapsuleSummary({
  required List<ToolCallGroup> toolGroups,
  required int intermediateTextCount,
  required bool hideThinking,
  required AppLocalizations l10n,
  double? maxWidth,
  TextStyle? style,
  TextScaler? textScaler,
  TextDirection? textDirection,
}) {
  final allCalls = [for (final g in toolGroups) ...g.toolCalls];

  final counts = <String, int>{};
  final initialIndex = <String, int>{};

  for (var i = 0; i < allCalls.length; i++) {
    final call = allCalls[i];
    if (call.isThinking && hideThinking) continue;
    final name = call.isThinking
        ? l10n.thinkingLabel
        : l10n.localizeToolName(call.displayName);
    initialIndex.putIfAbsent(name, () => initialIndex.length);
    counts[name] = (counts[name] ?? 0) + 1;
  }

  if (intermediateTextCount > 0) {
    final name = l10n.turn55IntermediateText;
    initialIndex.putIfAbsent(name, () => initialIndex.length);
    counts[name] = (counts[name] ?? 0) + intermediateTextCount;
  }

  if (counts.isEmpty) {
    return l10n.turn55ProcessLabel;
  }

  final entries = counts.entries.toList()
    ..sort((a, b) {
      final cmp = b.value.compareTo(a.value);
      if (cmp != 0) return cmp;
      return (initialIndex[a.key] ?? 0).compareTo(initialIndex[b.key] ?? 0);
    });

  if (maxWidth == null ||
      style == null ||
      textScaler == null ||
      textDirection == null) {
    return entries.map((e) => '${e.key} \u00D7${e.value}').join(', ');
  }

  bool fits(String text) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: 1,
      textDirection: textDirection,
      textScaler: textScaler,
    )..layout(minWidth: 0, maxWidth: double.infinity);
    return painter.width <= maxWidth;
  }

  final visible = <String>[];
  for (var i = 0; i < entries.length; i++) {
    final entry = entries[i];
    final itemText = '${entry.key} \u00D7${entry.value}';
    final candidateVisible = [...visible, itemText];
    final remaining = entries.length - candidateVisible.length;
    final candidateString = remaining > 0
        ? '${candidateVisible.join(', ')} \u2026'
        : candidateVisible.join(', ');

    if (fits(candidateString)) {
      visible.add(itemText);
    } else {
      break;
    }
  }

  if (visible.isNotEmpty) {
    final remaining = entries.length - visible.length;
    if (remaining > 0) {
      return '${visible.join(', ')} \u2026';
    }
    return visible.join(', ');
  }

  return '${entries.first.key} \u2026';
}
