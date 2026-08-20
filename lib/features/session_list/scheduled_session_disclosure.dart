import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

/// 定时会话分区可折叠 disclosure 组件（对齐 Hermex ScheduledSessionsDisclosure）。
///
/// 默认展开状态依据蓝本实现：
/// - `.reference/hermex-src/Features/SessionList/SessionRowView.swift` L426:
///   `static let defaultScheduledSessionsAreExpanded = false`
/// - `.reference/hermex-src/Features/SessionList/SessionListView.swift` L44-45:
///   `@AppStorage(SessionSidebarDisclosureSettings.scheduledSessionsAreExpandedKey)`
///   `private var scheduledSessionsAreExpanded = SessionSidebarDisclosureSettings.defaultScheduledSessionsAreExpanded`
/// 故默认折叠状态为收起（`false`）。
class ScheduledSessionDisclosure extends StatefulWidget {
  const ScheduledSessionDisclosure({
    super.key,
    required this.title,
    required this.children,
    this.count,
    this.initialExpanded = false,
    this.onExpansionChanged,
  });

  /// 分区标题（如「定时」/「Scheduled」）。
  final String title;

  /// 定时会话数量（可选，展示于标题旁作为 badge）。
  final int? count;

  /// 该分区包含的会话列表项（通常为 [_SessionRow] 列表）。
  final List<Widget> children;

  /// 初始展开状态（对齐蓝本默认为 false：收起）。
  final bool initialExpanded;

  /// 展开/收起状态切换回调（测试/外部监听用）。
  final ValueChanged<bool>? onExpansionChanged;

  @override
  State<ScheduledSessionDisclosure> createState() =>
      _ScheduledSessionDisclosureState();
}

class _ScheduledSessionDisclosureState
    extends State<ScheduledSessionDisclosure> {
  late bool _isExpanded;

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.initialExpanded;
  }

  void _toggleExpanded() {
    unawaited(HapticFeedback.selectionClick());
    setState(() {
      _isExpanded = !_isExpanded;
    });
    widget.onExpansionChanged?.call(_isExpanded);
  }

  Widget _buildHeader(BuildContext context) {
    final secondaryLabelColor = CupertinoColors.secondaryLabel.resolveFrom(
      context,
    );
    final count = widget.count;

    return Semantics(
      button: true,
      label: widget.title,
      child: GestureDetector(
        key: const ValueKey('scheduled-disclosure-header'),
        behavior: HitTestBehavior.opaque,
        onTap: _toggleExpanded,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.max,
            children: [
              Text(
                widget.title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.normal,
                  color: secondaryLabelColor,
                ),
              ),
              if (count != null) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: CupertinoColors.systemGrey5.resolveFrom(context),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: secondaryLabelColor,
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 4),
              Icon(
                _isExpanded
                    ? CupertinoIcons.chevron_down
                    : CupertinoIcons.chevron_right,
                size: 12,
                color: secondaryLabelColor,
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isExpanded) {
      return CupertinoListSection.insetGrouped(
        key: const ValueKey('scheduled-disclosure-section'),
        header: _buildHeader(context),
        children: widget.children,
      );
    }

    return Padding(
      key: const ValueKey('scheduled-disclosure-collapsed'),
      padding: const EdgeInsetsDirectional.fromSTEB(20.0, 16.0, 20.0, 10.0),
      child: _buildHeader(context),
    );
  }
}
