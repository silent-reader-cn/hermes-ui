import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/git_workspace.dart';
import '../../core/utils/accessibility.dart';
import '../../app/theme/status_colors.dart';
import '../../app/widgets/adaptive_sliver_navigation_bar.dart';
import '../../l10n/app_localizations.dart';
import '../shared/app_back_button.dart';
import 'git_branch_tree.dart';
import 'git_providers.dart';

/// 会话工作区 Git 面板（对齐 Hermex GitWorkspaceView 的展示形态）。
///
/// 以 [sessionId] 定位会话工作区：分支选择（ActionSheet 切换本地分支）、
/// 状态列表（已暂存 / 未暂存分区）、文件 diff 展开查看、提交表单、
/// fetch / pull / push 按钮；含加载 / 错误 / 空态（非仓库 / 工作区干净）。
class GitPage extends ConsumerStatefulWidget {
  const GitPage({super.key, required this.sessionId});

  /// 会话 ID（服务器据此解析工作区路径）。
  final String sessionId;

  @override
  ConsumerState<GitPage> createState() => _GitPageState();
}

class _GitPageState extends ConsumerState<GitPage> {
  final TextEditingController _messageController = TextEditingController();

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(gitControllerProvider(widget.sessionId));
    final state = async.valueOrNull;

    return CupertinoPageScaffold(
      child: CustomScrollView(
        key: const ValueKey('git-scroll'),
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          AdaptiveSliverNavigationBar(
            title: l10n.gitPanelTitle,
            leading: AppBackButton(fallback: '/chat/${widget.sessionId}'),
            trailing: AccessibleButton(
              key: const ValueKey('git-refresh'),
              label: l10n.refreshGitStatus,
              padding: EdgeInsets.zero,
              onPressed: () => unawaited(
                ref
                    .read(gitControllerProvider(widget.sessionId).notifier)
                    .refresh(),
              ),
              child: const Icon(CupertinoIcons.arrow_clockwise),
            ),
            // 操作结果横幅：固定在导航栏底部，任何滚动位置都可见。
            bottom: _buildActionBanner(state),
          ),
          CupertinoSliverRefreshControl(
            onRefresh: () => ref
                .read(gitControllerProvider(widget.sessionId).notifier)
                .refresh(),
          ),
          ..._buildContentSlivers(ref, async, state),
        ],
      ),
    );
  }

  /// 操作结果横幅（错误红 / 成功绿），固定在导航栏底部，任何滚动位置可见。
  PreferredSizeWidget? _buildActionBanner(GitState? state) {
    final error = state?.actionError;
    final message = state?.actionMessage;
    if (error == null && message == null) return null;
    final isError = error != null;
    return PreferredSize(
      preferredSize: const Size.fromHeight(52),
      child: _ActionBanner(
        key: ValueKey(isError ? 'git-action-error' : 'git-action-message'),
        text: isError ? error : message!,
        color: isError
            ? CupertinoColors.systemRed
            : CupertinoColors.systemGreen,
        onDismiss: () {
          final controller = ref.read(
            gitControllerProvider(widget.sessionId).notifier,
          );
          unawaited(
            isError
                ? controller.clearActionError()
                : controller.clearActionMessage(),
          );
        },
      ),
    );
  }

  // -------------------------------------------------------------------------
  // 内容 slivers：加载 / 错误 / 空态 / 面板正文
  // -------------------------------------------------------------------------

  List<Widget> _buildContentSlivers(
    WidgetRef ref,
    AsyncValue<GitState> async,
    GitState? state,
  ) {
    final l10n = AppLocalizations.of(context);
    if (state == null) {
      if (async.isLoading) {
        return const [
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: CupertinoActivityIndicator(radius: 14)),
          ),
        ];
      }
      return [_buildErrorSliver(ref, async.error)];
    }

    if (state.isNonRepository) {
      return [_buildEmptySliver(l10n.notAGitRepo, l10n.notAGitRepoDetail)];
    }

    if (!state.isGitRepository) {
      // status 已加载但 is_git 缺失：按非仓库处理（容错）。
      return [_buildEmptySliver(l10n.notAGitRepo, l10n.notAGitRepoDetail)];
    }

    return [
      _buildSummarySliver(ref, state),
      _buildBranchTreeSliver(ref, state),
      if (!state.hasCommittableChanges)
        SliverToBoxAdapter(child: _CleanWorkspacePlaceholder())
      else ...[
        if (state.stagedFiles.isNotEmpty)
          _buildFileSectionSliver(
            ref,
            state,
            l10n.stagedSection,
            state.stagedFiles,
          ),
        if (state.unstagedFiles.isNotEmpty)
          _buildFileSectionSliver(
            ref,
            state,
            l10n.unstagedSection,
            state.unstagedFiles,
          ),
      ],
      if (state.status?.truncated == true)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Text(
              l10n.tooManyChangedFilesWarning,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: secondaryText.resolveFrom(context),
              ),
            ),
          ),
        ),
      _buildCommitSliver(ref, state),
      _buildRemoteSliver(ref, state),
    ];
  }

  Widget _buildSummarySliver(WidgetRef ref, GitState state) {
    final l10n = AppLocalizations.of(context);
    final branches = state.branches;
    final current = branches?.current ?? state.status?.branch;
    final ahead = state.status?.ahead ?? 0;
    final behind = state.status?.behind ?? 0;
    final additions = state.status?.totalAdditions ?? 0;
    final deletions = state.status?.totalDeletions ?? 0;
    final changed = state.status?.changedCount ?? 0;

    return SliverToBoxAdapter(
      child: CupertinoListSection.insetGrouped(
        children: [
          CupertinoListTile(
            leading: const Icon(
              CupertinoIcons.arrow_branch,
              color: CupertinoColors.systemBlue,
            ),
            title: Text(
              current?.isNotEmpty == true ? current! : l10n.unknownBranch,
            ),
            subtitle: Text(
              ahead > 0 || behind > 0
                  ? l10n.aheadBehind(ahead, behind)
                  : l10n.syncedWithRemote,
            ),
            trailing: CupertinoButton(
              key: const ValueKey('git-branch-picker'),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              onPressed: branches == null || state.isActionRunning
                  ? null
                  : () => unawaited(_showBranchPicker(ref, state)),
              child: Text(l10n.switchBranch),
            ),
          ),
          CupertinoListTile(
            title: Text(l10n.changesLabel),
            subtitle: Text(l10n.changesSummary(additions, deletions, changed)),
          ),
        ],
      ),
    );
  }

  Widget _buildBranchTreeSliver(WidgetRef ref, GitState state) {
    final controller = ref.read(
      gitControllerProvider(widget.sessionId).notifier,
    );
    return SliverToBoxAdapter(
      child: GitBranchTree(
        branches: state.branches,
        currentBranch: state.branches?.current ?? state.status?.branch,
        isActionRunning: state.isActionRunning,
        isLoading: state.isBranchesLoading,
        errorMessage: state.branchesError,
        onCheckout: (refName) => unawaited(controller.checkout(refName)),
        onReload: () => unawaited(controller.reloadBranches()),
      ),
    );
  }

  Widget _buildFileSectionSliver(
    WidgetRef ref,
    GitState state,
    String header,
    List<GitFile> files,
  ) {
    final controller = ref.read(
      gitControllerProvider(widget.sessionId).notifier,
    );
    return SliverToBoxAdapter(
      child: CupertinoListSection.insetGrouped(
        header: Text(header),
        children: [
          for (final file in files) ...[
            _FileTile(
              file: file,
              expanded: state.selectedFile?.id == file.id,
              isActionRunning: state.isActionRunning,
              onTap: () => unawaited(controller.selectFile(file)),
              onStage: file.staged == true
                  ? () => unawaited(controller.unstage([_filePath(file)]))
                  : () => unawaited(controller.stage([_filePath(file)])),
              onDiscard: () => unawaited(controller.discard([_filePath(file)])),
            ),
            if (state.selectedFile?.id == file.id) _DiffExpansion(state: state),
          ],
        ],
      ),
    );
  }

  Widget _buildCommitSliver(WidgetRef ref, GitState state) {
    final l10n = AppLocalizations.of(context);
    final controller = ref.read(
      gitControllerProvider(widget.sessionId).notifier,
    );
    return SliverToBoxAdapter(
      child: CupertinoListSection.insetGrouped(
        header: Text(l10n.commitSection),
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: CupertinoTextField(
                    key: const ValueKey('git-commit-message'),
                    controller: _messageController,
                    placeholder: l10n.commitMessagePlaceholder,
                    minLines: 1,
                    maxLines: 3,
                    enabled: !state.isActionRunning,
                  ),
                ),
                const SizedBox(width: 8),
                CupertinoButton.filled(
                  key: const ValueKey('git-commit-button'),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  onPressed: state.isActionRunning
                      ? null
                      : () {
                          final message = _messageController.text.trim();
                          if (message.isEmpty) return;
                          unawaited(
                            controller.commit(message).then((ok) {
                              if (ok && mounted) {
                                _messageController.clear();
                              }
                            }),
                          );
                        },
                  child: Text(l10n.commitButton),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRemoteSliver(WidgetRef ref, GitState state) {
    final l10n = AppLocalizations.of(context);
    final controller = ref.read(
      gitControllerProvider(widget.sessionId).notifier,
    );
    final running = state.isActionRunning;
    return SliverToBoxAdapter(
      child: CupertinoListSection.insetGrouped(
        header: Text(l10n.remoteOperations),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: CupertinoButton.filled(
                    key: const ValueKey('git-fetch'),
                    onPressed: running
                        ? null
                        : () => unawaited(controller.fetchRemote()),
                    child: const Text('fetch'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: CupertinoButton.filled(
                    key: const ValueKey('git-pull'),
                    onPressed: running
                        ? null
                        : () => unawaited(controller.pullRemote()),
                    child: const Text('pull'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: CupertinoButton.filled(
                    key: const ValueKey('git-push'),
                    onPressed: running
                        ? null
                        : () => unawaited(controller.pushRemote()),
                    child: const Text('push'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorSliver(WidgetRef ref, Object? error) {
    final l10n = AppLocalizations.of(context);
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              CupertinoIcons.exclamationmark_triangle,
              size: 48,
              color: CupertinoColors.systemGrey,
            ),
            const SizedBox(height: 12),
            Text(
              l10n.loadFailed,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              _errorMessage(error),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: statusRedText),
            ),
            const SizedBox(height: 20),
            CupertinoButton.filled(
              key: const ValueKey('git-retry'),
              onPressed: () => unawaited(
                ref
                    .read(gitControllerProvider(widget.sessionId).notifier)
                    .refresh(),
              ),
              child: Text(l10n.retry),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptySliver(String title, String detail) {
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              CupertinoIcons.folder_open,
              size: 48,
              color: CupertinoColors.systemGrey,
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: secondaryText.resolveFrom(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showBranchPicker(WidgetRef ref, GitState state) async {
    final l10n = AppLocalizations.of(context);
    final local = (state.branches?.local ?? const <GitBranchRef>[])
        .where((b) => b.name != null && b.name!.trim().isNotEmpty)
        .toList(growable: false);
    if (local.isEmpty) {
      await ref
          .read(gitControllerProvider(widget.sessionId).notifier)
          .reloadBranches();
      return;
    }
    final current = state.branches?.current;
    final selected = await showCupertinoModalPopup<String>(
      context: context,
      builder: (modalContext) => CupertinoActionSheet(
        title: Text(l10n.switchBranch),
        actions: [
          for (final branch in local)
            CupertinoActionSheetAction(
              key: ValueKey('git-branch-${branch.name}'),
              isDefaultAction: branch.name == current,
              onPressed: () => Navigator.pop(modalContext, branch.name),
              child: Text(branch.name!),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(modalContext),
          child: Text(l10n.cancel),
        ),
      ),
    );
    if (selected != null && selected != current && mounted) {
      unawaited(
        ref
            .read(gitControllerProvider(widget.sessionId).notifier)
            .checkout(selected),
      );
    }
  }

  static String _filePath(GitFile file) {
    final path = file.displayPath;
    return path.isEmpty ? file.oldPath ?? '' : path;
  }

  String _errorMessage(Object? error) {
    if (error is Exception) return gitFriendlyError(error);
    return error?.toString() ?? AppLocalizations.of(context).unknownError;
  }
}

// ---------------------------------------------------------------------------
// 文件行
// ---------------------------------------------------------------------------

class _FileTile extends StatelessWidget {
  const _FileTile({
    required this.file,
    required this.expanded,
    required this.isActionRunning,
    required this.onTap,
    required this.onStage,
    required this.onDiscard,
  });

  final GitFile file;
  final bool expanded;
  final bool isActionRunning;
  final VoidCallback onTap;
  final VoidCallback onStage;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final kind = file.changeKind;
    return CupertinoListTile(
      key: ValueKey('git-file-${file.id}'),
      leading: Icon(_kindIcon(kind), color: _kindColor(kind)),
      title: Text(
        file.displayPath,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${_kindLabel(context, kind)}'
        '${(file.additions ?? 0) > 0 ? ' +${file.additions}' : ''}'
        '${(file.deletions ?? 0) > 0 ? ' −${file.deletions}' : ''}',
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CupertinoButton(
            key: ValueKey(
              file.staged == true
                  ? 'git-unstage-${file.id}'
                  : 'git-stage-${file.id}',
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            onPressed: isActionRunning ? null : onStage,
            child: Text(
              file.staged == true ? l10n.unstageAction : l10n.stageAction,
              style: const TextStyle(fontSize: 13),
            ),
          ),
          AccessibleButton(
            key: ValueKey('git-discard-${file.id}'),
            label: l10n.discardChanges,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            onPressed: isActionRunning ? null : onDiscard,
            child: const Icon(
              CupertinoIcons.trash,
              size: 16,
              color: CupertinoColors.systemRed,
            ),
          ),
        ],
      ),
      onTap: onTap,
    );
  }

  static IconData _kindIcon(GitFileChangeKind kind) {
    switch (kind) {
      case GitFileChangeKind.added:
        return CupertinoIcons.plus_circle;
      case GitFileChangeKind.deleted:
        return CupertinoIcons.minus_circle;
      case GitFileChangeKind.renamed:
        return CupertinoIcons.arrow_swap;
      case GitFileChangeKind.conflict:
        return CupertinoIcons.exclamationmark_triangle;
      case GitFileChangeKind.untracked:
        return CupertinoIcons.question_circle;
      case GitFileChangeKind.ignored:
        return CupertinoIcons.eye_slash;
      case GitFileChangeKind.modified:
      case GitFileChangeKind.unknown:
        return CupertinoIcons.pencil_circle;
    }
  }

  static Color _kindColor(GitFileChangeKind kind) {
    switch (kind) {
      case GitFileChangeKind.added:
      case GitFileChangeKind.renamed:
        return CupertinoColors.systemGreen;
      case GitFileChangeKind.deleted:
        return CupertinoColors.systemRed;
      case GitFileChangeKind.conflict:
        return CupertinoColors.systemOrange;
      case GitFileChangeKind.untracked:
        return CupertinoColors.systemGrey;
      case GitFileChangeKind.ignored:
        return CupertinoColors.systemGrey2;
      case GitFileChangeKind.modified:
      case GitFileChangeKind.unknown:
        return CupertinoColors.systemBlue;
    }
  }

  static String _kindLabel(BuildContext context, GitFileChangeKind kind) {
    final l10n = AppLocalizations.of(context);
    switch (kind) {
      case GitFileChangeKind.added:
        return l10n.gitChangeAdded;
      case GitFileChangeKind.deleted:
        return l10n.gitChangeDeleted;
      case GitFileChangeKind.renamed:
        return l10n.gitChangeRenamed;
      case GitFileChangeKind.conflict:
        return l10n.gitChangeConflict;
      case GitFileChangeKind.untracked:
        return l10n.gitChangeUntracked;
      case GitFileChangeKind.ignored:
        return l10n.gitChangeIgnored;
      case GitFileChangeKind.modified:
      case GitFileChangeKind.unknown:
        return l10n.gitChangeModified;
    }
  }
}

// ---------------------------------------------------------------------------
// diff 展开区
// ---------------------------------------------------------------------------

class _DiffExpansion extends StatelessWidget {
  const _DiffExpansion({required this.state});

  final GitState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (state.isDiffLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CupertinoActivityIndicator(radius: 10)),
      );
    }
    final diff = state.diff;
    String content;
    if (diff == null) {
      content = l10n.cannotLoadDiff;
    } else if (diff.binary == true) {
      content = l10n.binaryFileCannotShowDiff;
    } else {
      final text = diff.diff ?? '';
      if (text.isEmpty) {
        content = l10n.noDiffContent;
      } else if (diff.tooLarge == true) {
        content = l10n.fileTooLargePartialContent(text);
      } else {
        content = text;
      }
    }
    return Container(
      key: const ValueKey('git-diff'),
      width: double.infinity,
      color: CupertinoColors.secondarySystemBackground,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Text(
        content,
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 11,
          height: 1.4,
        ),
      ),
    );
  }
}

class _CleanWorkspacePlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36),
      child: Column(
        children: [
          const Icon(
            CupertinoIcons.checkmark_circle,
            size: 44,
            color: CupertinoColors.systemGreen,
          ),
          const SizedBox(height: 10),
          Text(
            l10n.workspaceClean,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.noPendingChanges,
            style: TextStyle(
              fontSize: 13,
              color: secondaryText.resolveFrom(context),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 操作结果横幅
// ---------------------------------------------------------------------------

class _ActionBanner extends StatelessWidget {
  const _ActionBanner({
    super.key,
    required this.text,
    required this.color,
    required this.onDismiss,
  });

  final String text;
  final Color color;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(text, style: TextStyle(fontSize: 13, color: color)),
            ),
            AccessibleButton(
              key: const ValueKey('git-banner-dismiss'),
              label: l10n.closeNotice,
              onPressed: onDismiss,
              child: Icon(
                CupertinoIcons.xmark_circle_fill,
                size: 16,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
