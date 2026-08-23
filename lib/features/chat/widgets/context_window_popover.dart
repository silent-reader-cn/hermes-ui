import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/api_client_server_panels.dart';
import '../../../core/api/api_client_workspace.dart';
import '../../../core/connections/connection_providers.dart';
import '../../../core/models/context_window_snapshot.dart';
import '../../../core/models/workspace.dart';
import '../../../core/utils/context_window_formatter.dart';
import '../../../l10n/app_localizations.dart';
import '../chat_providers.dart';

/// 上下文详情弹层（Swift: ContextWindowPopover，对齐 WebUI _syncCtxIndicator 阈值提示）。
///
/// 宽 260、圆角 18、背景 secondarySystemBackground + separator 边框。
/// 内容：标题行（tokensLabel + 压缩 icon） / InfoRows / 模型切换 / 工作区切换 / 关闭。
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
  bool _savingWorkspace = false;
  bool _loadingModels = false;
  bool _isExpanded = false;
  bool _loadingWorkspaces = false;
  bool _workspacesFetched = false;
  bool _workspaceDropdownExpanded = false;
  bool _manualInputExpanded = false;
  List<WorkspaceRoot> _workspaces = const [];
  late final TextEditingController _workspaceController;
  List<String> _fetchedModels = const [];

  @override
  void initState() {
    super.initState();
    final initialWorkspace =
        ref.read(chatControllerProvider(widget.sessionId)).workspace ?? '';
    _workspaceController = TextEditingController(text: initialWorkspace);
    // 若 provider 模型列表为空，异步拉取真实模型以保证可切换；异步拉取工作区列表
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_maybeFetchModels());
      unawaited(_fetchWorkspaces());
    });
  }

  @override
  void didUpdateWidget(covariant ContextWindowPopover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sessionId != widget.sessionId) {
      _workspaceController.text =
          ref.read(chatControllerProvider(widget.sessionId)).workspace ?? '';
      _workspacesFetched = false;
      _workspaceDropdownExpanded = false;
      _manualInputExpanded = false;
      unawaited(_fetchWorkspaces());
    }
  }

  @override
  void dispose() {
    _workspaceController.dispose();
    super.dispose();
  }

  Future<void> _maybeFetchModels() async {
    final existing = ref.read(chatAvailableModelsProvider);
    if (existing.isNotEmpty) return;
    if (_loadingModels) return;

    final ApiClient client;
    try {
      client = ref.read(apiClientProvider);
    } catch (_) {
      // 处于测试环境或无激活连接时静默处理
      return;
    }

    setState(() => _loadingModels = true);
    try {
      final response = await client.modelsLive();
      final liveOptions = response.liveOptions;
      if (!mounted) return;
      final modelIds = <String>[];
      for (final opt in liveOptions) {
        final id = opt.id.trim();
        if (id.isNotEmpty && !modelIds.contains(id)) {
          modelIds.add(id);
        }
      }
      setState(() {
        _fetchedModels = modelIds;
      });
    } catch (_) {
      // 网络请求失败静默保留空列表（仅显示跟随服务器默认）
    } finally {
      if (mounted) setState(() => _loadingModels = false);
    }
  }

  Future<void> _fetchWorkspaces() async {
    if (_loadingWorkspaces || _workspacesFetched) return;
    setState(() => _loadingWorkspaces = true);
    try {
      final client = ref.read(apiClientProvider);
      final response = await client.workspaces();
      if (!mounted) return;
      setState(() {
        _workspaces = response.workspaces ?? const [];
        _workspacesFetched = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _workspaces = const [];
        _workspacesFetched = true;
      });
    } finally {
      if (mounted) {
        setState(() => _loadingWorkspaces = false);
      }
    }
  }

  Future<void> _selectWorkspace(String? path) async {
    final text = path?.trim() ?? '';
    _workspaceController.text = text;
    setState(() {
      _savingWorkspace = true;
      _workspaceDropdownExpanded = false;
    });
    try {
      await ref
          .read(chatControllerProvider(widget.sessionId).notifier)
          .updateSessionSettings(workspace: text);
    } finally {
      if (mounted) {
        setState(() => _savingWorkspace = false);
      }
    }
  }

  Future<void> _saveManualWorkspace() async {
    final text = _workspaceController.text.trim();
    setState(() => _savingWorkspace = true);
    try {
      await ref
          .read(chatControllerProvider(widget.sessionId).notifier)
          .updateSessionSettings(workspace: text);
      if (!mounted) return;
      setState(() => _manualInputExpanded = false);
    } finally {
      if (mounted) {
        setState(() => _savingWorkspace = false);
      }
    }
  }

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

    final isHigh = pctInt != null && pctInt >= 75;
    final isMid = pctInt != null && pctInt >= 50 && pctInt < 75;

    final bg = CupertinoColors.secondarySystemBackground.resolveFrom(context);
    final separator = CupertinoColors.separator.resolveFrom(context);
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);

    // 模型列表：优先使用 provider，空时尝试 fetched（未来扩展），至少保证跟随默认
    final providerModels = ref.watch(chatAvailableModelsProvider);
    final models = providerModels.isNotEmpty ? providerModels : _fetchedModels;
    final currentModel = widget.currentModel;
    final workspace = ref.watch(
      chatControllerProvider(widget.sessionId).select((s) => s.workspace),
    );
    // 保持输入框与外部 workspace 同步（用户未编辑时）
    if (!_savingWorkspace &&
        _workspaceController.text != (workspace ?? '') &&
        !_workspaceController.selection.isValid) {
      // 避免在 build 中直接改 controller 导致光标丢失，仅当未聚焦时同步
      // 用 postFrame 避免 build 期间 setState
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_workspaceController.text != (workspace ?? '')) {
          _workspaceController.text = workspace ?? '';
        }
      });
    }

    final currentWorkspace = workspace;
    String currentWorkspaceLabel = l10n.followSessionDefaultWorkspace;
    if (currentWorkspace != null && currentWorkspace.trim().isNotEmpty) {
      final match = _workspaces
          .where((w) => w.path == currentWorkspace)
          .firstOrNull;
      if (match != null &&
          match.name != null &&
          match.name!.trim().isNotEmpty) {
        currentWorkspaceLabel = '${match.path} — ${match.name}';
      } else {
        currentWorkspaceLabel = currentWorkspace;
      }
    }

    return Container(
      width: 260,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: separator),
        boxShadow: [
          BoxShadow(
            color: CupertinoColors.systemGrey3
                .resolveFrom(context)
                .withValues(alpha: 0.35),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header：tokensLabel + 压缩 IconButton
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    tokensLabel,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                _CompressIconButton(
                  key: const ValueKey('context-popover-compress'),
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
              ],
            ),
          ),
          Container(height: 0.5, color: separator),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _InfoRow(label: l10n.contextWindowInput, value: inputLabel),
                const SizedBox(height: 6),
                _InfoRow(label: l10n.contextWindowOutput, value: outputLabel),
                const SizedBox(height: 6),
                _InfoRow(
                  label: l10n.contextWindowThreshold,
                  value: thresholdLabel,
                ),
                const SizedBox(height: 6),
                _InfoRow(label: l10n.contextWindowCost, value: costLabel),
              ],
            ),
          ),
          Container(height: 0.5, color: separator),
          // 模型切换区
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.contextWindowCurrentModel,
                  style: TextStyle(fontSize: 12, color: secondary),
                ),
                const SizedBox(height: 6),
                Semantics(
                  button: true,
                  label: l10n.selectModel,
                  child: CupertinoButton(
                    key: const ValueKey('context-popover-model-trigger'),
                    padding: EdgeInsets.zero,
                    onPressed: () {
                      setState(() => _isExpanded = !_isExpanded);
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: CupertinoColors.systemBackground
                            .resolveFrom(context),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: separator),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              (currentModel == null || currentModel.isEmpty)
                                  ? l10n.contextWindowFollowServerDefault
                                  : currentModel,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: CupertinoColors.label
                                    .resolveFrom(context),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          AnimatedRotation(
                            turns: _isExpanded ? 0.5 : 0.0,
                            duration: const Duration(milliseconds: 200),
                            child: Icon(
                              CupertinoIcons.chevron_down,
                              size: 14,
                              color: secondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                AnimatedCrossFade(
                  firstChild: const SizedBox(
                    width: double.infinity,
                    height: 0,
                  ),
                  secondChild: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: _loadingModels
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.symmetric(vertical: 10),
                              child: CupertinoActivityIndicator(radius: 8),
                            ),
                          )
                        : ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 160),
                            child: SingleChildScrollView(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  for (final m in models)
                                    _ModelRow(
                                      key: ValueKey('context-popover-model-$m'),
                                      label: m,
                                      selected: m == currentModel,
                                      onTap: () {
                                        ref
                                            .read(
                                              chatControllerProvider(
                                                widget.sessionId,
                                              ).notifier,
                                            )
                                            .selectModel(m);
                                        setState(() => _isExpanded = false);
                                        widget.onClose();
                                      },
                                    ),
                                  _ModelRow(
                                    key: const ValueKey(
                                      'context-popover-model-default',
                                    ),
                                    label:
                                        l10n.contextWindowFollowServerDefault,
                                    selected: currentModel == null ||
                                        currentModel.isEmpty,
                                    onTap: () {
                                      ref
                                          .read(
                                            chatControllerProvider(
                                              widget.sessionId,
                                            ).notifier,
                                          )
                                          .selectModel(null);
                                      setState(() => _isExpanded = false);
                                      widget.onClose();
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),
                  ),
                  crossFadeState: _isExpanded
                      ? CrossFadeState.showSecond
                      : CrossFadeState.showFirst,
                  duration: const Duration(milliseconds: 200),
                ),
              ],
            ),
          ),
          Container(height: 0.5, color: separator),
          // 工作区切换区
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      l10n.workspace,
                      style: TextStyle(fontSize: 12, color: secondary),
                    ),
                    const Spacer(),
                    if (_savingWorkspace)
                      const CupertinoActivityIndicator(radius: 8)
                    else
                      CupertinoButton(
                        key: const ValueKey(
                          'context-popover-workspace-manual-toggle',
                        ),
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(36, 24),
                        onPressed: () {
                          setState(() {
                            _manualInputExpanded = !_manualInputExpanded;
                            if (_manualInputExpanded) {
                              _workspaceDropdownExpanded = false;
                            }
                          });
                        },
                        child: Text(
                          _manualInputExpanded
                              ? l10n.cancel
                              : l10n.manualInputWorkspace,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Semantics(
                  button: true,
                  label: l10n.selectWorkspace,
                  child: CupertinoButton(
                    key: const ValueKey('context-popover-workspace-trigger'),
                    padding: EdgeInsets.zero,
                    onPressed: () {
                      setState(() {
                        _workspaceDropdownExpanded =
                            !_workspaceDropdownExpanded;
                        if (_workspaceDropdownExpanded) {
                          _manualInputExpanded = false;
                        }
                      });
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: CupertinoColors.systemBackground
                            .resolveFrom(context),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: separator),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              currentWorkspaceLabel,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color:
                                    CupertinoColors.label.resolveFrom(context),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            _workspaceDropdownExpanded
                                ? CupertinoIcons.chevron_up
                                : CupertinoIcons.chevron_down,
                            size: 14,
                            color: secondary,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (_workspaceDropdownExpanded) ...[
                  if (_loadingWorkspaces)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Center(
                        child: CupertinoActivityIndicator(radius: 8),
                      ),
                    )
                  else ...[
                    const SizedBox(height: 6),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 160),
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_workspaces.isNotEmpty) ...[
                              for (final w in _workspaces)
                                _WorkspaceRow(
                                  key: ValueKey(
                                    'workspace-item-${w.path}',
                                  ),
                                  label: (w.name != null &&
                                          w.name!.trim().isNotEmpty)
                                      ? '${w.path} — ${w.name}'
                                      : (w.path ?? ''),
                                  selected: currentWorkspace == w.path,
                                  onTap: () => _selectWorkspace(w.path),
                                ),
                              _WorkspaceRow(
                                key: const ValueKey('workspace-item-default'),
                                label: l10n.followSessionDefaultWorkspace,
                                selected: currentWorkspace == null ||
                                    currentWorkspace.trim().isEmpty,
                                onTap: () => _selectWorkspace(null),
                              ),
                            ] else ...[
                              _WorkspaceRow(
                                key: const ValueKey('workspace-item-default'),
                                label: l10n.followSessionDefaultWorkspace,
                                selected: currentWorkspace == null ||
                                    currentWorkspace.trim().isEmpty,
                                onTap: () => _selectWorkspace(null),
                              ),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
                                child: Text(
                                  l10n.noWorkspacesAvailableHint,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: secondary,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
                if (_manualInputExpanded) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: CupertinoTextField(
                          key: const ValueKey(
                            'context-popover-workspace-field',
                          ),
                          controller: _workspaceController,
                          placeholder: l10n.workspaceOptionalPlaceholder,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          style: const TextStyle(fontSize: 13),
                          placeholderStyle: TextStyle(
                            fontSize: 13,
                            color: secondary,
                          ),
                          decoration: BoxDecoration(
                            color: CupertinoColors.systemBackground
                                .resolveFrom(context),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: separator),
                          ),
                          onSubmitted: (_) => _saveManualWorkspace(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      CupertinoButton(
                        key: const ValueKey('context-popover-workspace-save'),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        minimumSize: const Size(44, 28),
                        onPressed:
                            _savingWorkspace ? null : _saveManualWorkspace,
                        child: Text(
                          l10n.save,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
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

class _CompressIconButton extends StatelessWidget {
  const _CompressIconButton({
    super.key,
    required this.isHigh,
    required this.isMid,
    required this.compressing,
    required this.enabled,
    required this.onPressed,
  });

  final bool isHigh;
  final bool isMid;
  final bool compressing;
  final bool enabled;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    Color? iconColor;
    if (!enabled) {
      iconColor = CupertinoColors.secondaryLabel.resolveFrom(context);
    } else if (isHigh) {
      iconColor = CupertinoColors.systemRed.resolveFrom(context);
    } else if (isMid) {
      iconColor = CupertinoColors.systemOrange.resolveFrom(context);
    } else {
      iconColor = CupertinoColors.secondaryLabel.resolveFrom(context);
    }

    final child = compressing
        ? const CupertinoActivityIndicator(radius: 10)
        : Icon(
            CupertinoIcons.archivebox,
            size: 18,
            color: iconColor,
          );

    return Semantics(
      button: true,
      enabled: enabled && !compressing,
      label: 'Compress',
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: const Size(32, 32),
        onPressed: enabled && !compressing ? onPressed : null,
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: enabled
                ? (isHigh
                    ? CupertinoColors.systemRed
                        .resolveFrom(context)
                        .withValues(alpha: 0.12)
                    : isMid
                        ? CupertinoColors.systemOrange
                            .resolveFrom(context)
                            .withValues(alpha: 0.12)
                        : CupertinoColors.systemGrey5.resolveFrom(context))
                : CupertinoColors.systemGrey5
                    .resolveFrom(context)
                    .withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: enabled
                  ? (isHigh
                      ? CupertinoColors.systemRed.resolveFrom(context)
                      : isMid
                          ? CupertinoColors.systemOrange.resolveFrom(context)
                          : CupertinoColors.separator.resolveFrom(context))
                  : CupertinoColors.separator.resolveFrom(context),
              width: 0.5,
            ),
          ),
          child: Center(child: child),
        ),
      ),
    );
  }
}

class _ModelRow extends StatelessWidget {
  const _ModelRow({
    super.key,
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
              overflow: TextOverflow.ellipsis,
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

class _WorkspaceRow extends StatelessWidget {
  const _WorkspaceRow({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: CupertinoButton(
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
                overflow: TextOverflow.ellipsis,
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
      ),
    );
  }
}
