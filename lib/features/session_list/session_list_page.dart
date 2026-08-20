import 'dart:async';
import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/api_client_sessions.dart';
import '../../core/api/api_exception.dart';
import '../../core/connections/connection_providers.dart';
import '../../core/models/session.dart';
import '../../core/utils/accessibility.dart';
import '../../app/theme/status_colors.dart';
import '../../l10n/app_localizations.dart';
import '../projects/project_picker_sheet.dart';
import '../projects/project_providers.dart';
import 'scheduled_session_disclosure.dart';
import 'session_list_header.dart';
import 'session_list_providers.dart';
import 'session_list_utility_rows.dart';

/// 会话列表页（app_shell_spec.md §3：`/` 为主列表）。
///
/// Cupertino 风格：大标题 + 搜索框（防抖远程搜索）+ 下拉刷新 + 无限滚动分页 +
/// 会话分区（置顶/今天/昨天/更早）+ 行快捷操作（pin/archive/branch/delete 弹
/// 菜单）+ 悬浮新建会话按钮。会话点击 → `/chat/:sessionId`。
class SessionListPage extends ConsumerStatefulWidget {
  const SessionListPage({
    super.key,
    this.showUtilityRows = true,
    this.showSettingsTrailing = true,
  });

  /// 是否渲染顶部工具行入口（任务/看板/技能/记忆/统计）。
  ///
  /// 宽屏双栏外壳的侧栏顶部已有 [SidebarUtilityToolbar] 承担工具入口
  /// （含设置与激活高亮），故侧栏内复用的会话列表传 `false` 避免双层
  /// 入口重叠；手机单栈（窄屏）保持默认 `true`。
  final bool showUtilityRows;

  /// 是否渲染头部右侧的设置入口（齿轮）。
  ///
  /// 宽屏侧栏顶部 [SidebarUtilityToolbar] 已有设置图标，为避免桌面端双
  /// 入口，侧栏内复用的会话列表传 `false`；手机单栈保持默认 `true`。
  final bool showSettingsTrailing;

  @override
  ConsumerState<SessionListPage> createState() => _SessionListPageState();
}

class _SessionListPageState extends ConsumerState<SessionListPage> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(sessionListControllerProvider);
    final state = async.valueOrNull;
    final sections = ref.watch(sessionListSectionsProvider);
    final isSearchMode = state?.searchQuery?.trim().isNotEmpty == true;

    ref.listen<AsyncValue<SessionListState>>(sessionListControllerProvider, (
      previous,
      next,
    ) {
      final error = next.valueOrNull?.actionError;
      if (error != null && error != previous?.valueOrNull?.actionError) {
        unawaited(_showActionError(context, error));
      }
    });

    // 首帧后自动补充分页窗口，直到填满视口或耗尽（内容不足一屏时也能翻页）。
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeLoadMore());

    final l10n = AppLocalizations.of(context);
    return CupertinoPageScaffold(
      child: Stack(
        children: [
          CustomScrollView(
            key: const ValueKey('session-list-scroll'),
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPersistentHeader(
                pinned: true,
                delegate: SessionListHeaderDelegate(
                  title: l10n.sessions,
                  topPadding: MediaQuery.paddingOf(context).top,
                  trailing: widget.showSettingsTrailing
                      ? AccessibleButton(
                          key: state?.isSelectionMode == true
                              ? const ValueKey('session-list-selection-done')
                              : const ValueKey('session-list-settings'),
                          label: state?.isSelectionMode == true
                              ? l10n.doneSelecting
                              : l10n.settings,
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(44, 44),
                          onPressed: () {
                            final controller = ref.read(
                              sessionListControllerProvider.notifier,
                            );
                            if (state?.isSelectionMode == true) {
                              controller.clearSelection();
                            } else {
                              context.go('/settings');
                            }
                          },
                          child: Icon(
                            state?.isSelectionMode == true
                                ? CupertinoIcons.xmark
                                : CupertinoIcons.gear_alt,
                            size: 22,
                          ),
                        )
                      : null,
                ),
              ),
              // 注意：刷新指示器必须排在所有 SliverToBoxAdapter 之前
              // （视口会把 overscroll 逐级分给前面的 box sliver，导致
              // 指示器拿不到负 overlap 而无法触发）。
              CupertinoSliverRefreshControl(onRefresh: _onRefresh),
              SliverToBoxAdapter(child: _buildSearchBar()),
              if (widget.showUtilityRows && !isSearchMode)
                const SliverToBoxAdapter(child: SessionListUtilityRows()),
              if (state != null && !isSearchMode)
                SliverToBoxAdapter(child: _buildFilterBar(state)),
              ..._buildContentSlivers(async, state, sections, isSearchMode),
            ],
          ),
          if (state?.isSelectionMode == true)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _buildBatchBar(state!),
            ),
          Positioned(
            right: 20,
            bottom: state?.isSelectionMode == true ? 76 : 24,
            child: AccessibleButton.filled(
              key: const ValueKey('session-list-new'),
              label: l10n.newSession,
              onPressed: () => unawaited(_onNewSession(context)),
              padding: EdgeInsets.zero,
              minimumSize: const Size(56, 56),
              borderRadius: BorderRadius.circular(28),
              child: const Icon(CupertinoIcons.add, size: 26),
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // 顶部 chrome
  // -------------------------------------------------------------------------

  /// 已归档 count 角标文案（无数据时不显示）。
  String _archivedCountLabel(SessionListState state) {
    final count = state.archivedCount ?? state.archivedSessions.length;
    return count > 0 ? ' ($count)' : '';
  }

  Widget _buildSearchBar() {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: CupertinoSearchTextField(
        key: const ValueKey('session-list-search'),
        controller: _searchController,
        placeholder: l10n.searchSessions,
        onChanged: _onSearchChanged,
      ),
    );
  }

  /// 筛选栏：全部 / 已归档(count) / 来源标签（横向滚动 chips）/ 项目 chips。
  Widget _buildFilterBar(SessionListState state) {
    final l10n = AppLocalizations.of(context);
    final controller = ref.read(sessionListControllerProvider.notifier);
    final mode = state.filterMode;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
          child: CupertinoSlidingSegmentedControl<SessionListFilterMode>(
            key: const ValueKey('session-list-filter-mode'),
            // source/project 模式不属于分段键 → null（无段高亮）。
            groupValue:
                (mode == SessionListFilterMode.all ||
                    mode == SessionListFilterMode.archived)
                ? mode
                : null,
            children: {
              SessionListFilterMode.all: Text(l10n.all),
              SessionListFilterMode.archived: Text(
                '${l10n.archived}${_archivedCountLabel(state)}',
              ),
            },
            onValueChanged: (value) {
              if (value != null) {
                unawaited(controller.setFilter(value));
              }
            },
          ),
        ),
        SizedBox(
          height: 34,
          child: ListView(
            key: const ValueKey('session-list-filter-chips'),
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              for (final label in state.sourceLabels)
                _filterChip(
                  key: ValueKey('filter-chip-$label'),
                  label: label,
                  selected:
                      mode == SessionListFilterMode.source &&
                      state.filterValue == label,
                  onTap: () => unawaited(
                    controller.setFilter(
                      SessionListFilterMode.source,
                      value: label,
                    ),
                  ),
                ),
              const SizedBox(width: 4),
              if (mode == SessionListFilterMode.archived)
                _filterChip(
                  key: const ValueKey('filter-chip-archived-all'),
                  label:
                      '${l10n.archived} ${state.archivedCount ?? state.archivedSessions.length}',
                  selected: true,
                  onTap: () => unawaited(
                    controller.setFilter(SessionListFilterMode.all),
                  ),
                ),
              if (state.filterMode != SessionListFilterMode.all &&
                  state.filterMode != SessionListFilterMode.archived) ...[
                const SizedBox(width: 4),
                _filterChip(
                  key: const ValueKey('filter-chip-clear'),
                  label: l10n.clearFilter,
                  selected: false,
                  onTap: () => unawaited(
                    controller.setFilter(SessionListFilterMode.all),
                  ),
                ),
              ],
            ],
          ),
        ),
        _buildProjectFilterRow(state),
      ],
    );
  }

  /// 项目筛选 chips（有项目才显示）。
  Widget _buildProjectFilterRow(SessionListState state) {
    final l10n = AppLocalizations.of(context);
    final projects = ref.watch(projectsProvider).valueOrNull ?? const [];
    if (projects.isEmpty) return const SizedBox.shrink();
    final controller = ref.read(sessionListControllerProvider.notifier);
    final mode = state.filterMode;
    return SizedBox(
      height: 34,
      child: ListView(
        key: const ValueKey('session-list-project-chips'),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          for (final project in projects)
            _filterChip(
              key: ValueKey('project-chip-${project.id}'),
              label: project.name ?? l10n.untitledProject,
              selected:
                  mode == SessionListFilterMode.project &&
                  state.filterValue == project.id,
              onTap: () => unawaited(
                controller.setFilter(
                  SessionListFilterMode.project,
                  value: project.id,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 底部批量操作栏（多选模式）：选中计数 + 全选 / 归档 / 删除 / 移动项目。
  Widget _buildBatchBar(SessionListState state) {
    final l10n = AppLocalizations.of(context);
    final controller = ref.read(sessionListControllerProvider.notifier);
    final count = state.selectedSessionIds.length;
    return Container(
      decoration: BoxDecoration(
        color: CupertinoColors.systemBackground.resolveFrom(context),
        border: Border(
          top: BorderSide(
            color: CupertinoColors.separator.resolveFrom(context),
            width: 0.5,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l10n.selectedCount(count),
                  style: const TextStyle(fontSize: 14),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              CupertinoButton(
                key: const ValueKey('batch-select-all'),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                onPressed: controller.selectAllInSection,
                child: Text(
                  l10n.selectAll,
                  style: const TextStyle(fontSize: 14),
                ),
              ),
              CupertinoButton(
                key: const ValueKey('batch-archive'),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                onPressed: count == 0
                    ? null
                    : () => unawaited(_confirmBatchArchive(context)),
                child: Text(l10n.archive, style: const TextStyle(fontSize: 14)),
              ),
              CupertinoButton(
                key: const ValueKey('batch-delete'),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                onPressed: count == 0
                    ? null
                    : () => unawaited(_confirmBatchDelete(context)),
                child: Text(
                  l10n.delete,
                  style: TextStyle(
                    fontSize: 14,
                    color: CupertinoColors.systemRed.resolveFrom(context),
                  ),
                ),
              ),
              CupertinoButton(
                key: const ValueKey('batch-move'),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                onPressed: count == 0
                    ? null
                    : () => unawaited(_batchMoveToProject(context)),
                child: Text(
                  l10n.batchMoveProject,
                  style: const TextStyle(fontSize: 14),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 单个筛选 chip（自绘圆角胶囊）。
  Widget _filterChip({
    Key? key,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Padding(
      key: key,
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: selected
                ? CupertinoColors.activeBlue.resolveFrom(context)
                : CupertinoColors.systemGrey5.resolveFrom(context),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: selected
                  ? CupertinoColors.white
                  : CupertinoColors.label.resolveFrom(context),
            ),
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // 内容 slivers：加载 / 错误 / 空态 / 分区列表
  // -------------------------------------------------------------------------

  List<Widget> _buildContentSlivers(
    AsyncValue<SessionListState> async,
    SessionListState? state,
    List<SessionListSection> sections,
    bool isSearchMode,
  ) {
    if (state == null) {
      if (async.isLoading) {
        return const [
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: CupertinoActivityIndicator(radius: 14)),
          ),
        ];
      }
      return [_buildErrorSliver(async.error)];
    }

    final hasVisible = sections.any((section) => section.sessions.isNotEmpty);
    if (!hasVisible) {
      return [_buildEmptySliver(isSearchMode: isSearchMode)];
    }

    final l10n = AppLocalizations.of(context);
    return [
      for (final section in sections)
        if (section.sessions.isNotEmpty)
          if (section.title == '定时')
            SliverToBoxAdapter(
              child: ScheduledSessionDisclosure(
                title: _sectionTitle(context, section.title),
                count: section.sessions.length,
                children: [
                  for (final session in section.sessions)
                    _SessionRow(
                      key: ValueKey(
                        'session-row-${session.sessionId ?? session.id}',
                      ),
                      session: session,
                      highlightQuery: isSearchMode
                          ? state.searchQuery?.trim()
                          : null,
                      selectionMode: state.isSelectionMode,
                      selected: state.selectedSessionIds.contains(
                        session.sessionId ?? session.id,
                      ),
                      onTap: () => state.isSelectionMode
                          ? ref
                                .read(sessionListControllerProvider.notifier)
                                .toggleSelection(
                                  session.sessionId ?? session.id,
                                )
                          : _openSession(context, session),
                      onLongPress: () => ref
                          .read(sessionListControllerProvider.notifier)
                          .toggleSelection(session.sessionId ?? session.id),
                      onActions: state.isSelectionMode
                          ? null
                          : () => _showRowActions(context, session),
                    ),
                ],
              ),
            )
          else
            SliverToBoxAdapter(
              child: CupertinoListSection.insetGrouped(
                header: Text(_sectionTitle(context, section.title)),
                children: [
                  for (final session in section.sessions)
                    _SessionRow(
                      key: ValueKey(
                        'session-row-${session.sessionId ?? session.id}',
                      ),
                      session: session,
                      highlightQuery: isSearchMode
                          ? state.searchQuery?.trim()
                          : null,
                      selectionMode: state.isSelectionMode,
                      selected: state.selectedSessionIds.contains(
                        session.sessionId ?? session.id,
                      ),
                      onTap: () => state.isSelectionMode
                          ? ref
                                .read(sessionListControllerProvider.notifier)
                                .toggleSelection(
                                  session.sessionId ?? session.id,
                                )
                          : _openSession(context, session),
                      onLongPress: () => ref
                          .read(sessionListControllerProvider.notifier)
                          .toggleSelection(session.sessionId ?? session.id),
                      onActions: state.isSelectionMode
                          ? null
                          : () => _showRowActions(context, session),
                    ),
                ],
              ),
            ),
      if (state.hasMore)
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CupertinoActivityIndicator(radius: 12)),
          ),
        ),
      if (!state.hasMore &&
          state.displaySessions.length > SessionListState.pageSize)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Center(
              child: Text(
                l10n.noMore,
                style: const TextStyle(
                  fontSize: 13,
                  color: CupertinoColors.secondaryLabel,
                ),
              ),
            ),
          ),
        ),
    ];
  }

  Widget _buildErrorSliver(Object? error) {
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
              key: const ValueKey('session-list-retry'),
              onPressed: () => unawaited(
                ref.read(sessionListControllerProvider.notifier).refresh(),
              ),
              child: Text(l10n.retry),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptySliver({required bool isSearchMode}) {
    final l10n = AppLocalizations.of(context);
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isSearchMode
                  ? CupertinoIcons.search
                  : CupertinoIcons.chat_bubble_2,
              size: 48,
              color: CupertinoColors.systemGrey,
            ),
            const SizedBox(height: 12),
            Text(
              isSearchMode ? l10n.noMatchingSessionsFound : l10n.noSessions,
              style: const TextStyle(fontSize: 17),
            ),
            const SizedBox(height: 6),
            Text(
              isSearchMode
                  ? l10n.tryAnotherKeyword
                  : l10n.tapButtonToStartNewChat,
              style: const TextStyle(
                fontSize: 13,
                color: CupertinoColors.secondaryLabel,
              ),
            ),
            if (!isSearchMode) ...[
              const SizedBox(height: 20),
              CupertinoButton.filled(
                key: const ValueKey('session-list-empty-new'),
                onPressed: () => unawaited(_onNewSession(context)),
                child: Text(l10n.newSession),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // 交互：刷新 / 分页 / 搜索 / 新建 / 打开 / 行操作
  // -------------------------------------------------------------------------

  Future<void> _onRefresh() =>
      ref.read(sessionListControllerProvider.notifier).refresh();

  void _onScroll() {
    _maybeLoadMore();
  }

  void _maybeLoadMore() {
    final controller = ref.read(sessionListControllerProvider.notifier);
    final state = ref.read(sessionListControllerProvider).valueOrNull;
    if (state == null || !state.hasMore) return;
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.extentAfter < 200 || position.maxScrollExtent == 0) {
      unawaited(controller.loadMore());
    }
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      unawaited(ref.read(sessionListControllerProvider.notifier).search(value));
    });
  }

  Future<void> _onNewSession(BuildContext context) async {
    final controller = ref.read(sessionListControllerProvider.notifier);
    final id = await controller.createSession();
    if (!context.mounted) return;
    if (id != null) {
      context.go('/chat/$id');
    }
  }

  void _openSession(BuildContext context, SessionSummary session) {
    context.go('/chat/${session.sessionId ?? session.id}');
  }

  void _showRowActions(BuildContext context, SessionSummary session) {
    final l10n = AppLocalizations.of(context);
    final controller = ref.read(sessionListControllerProvider.notifier);
    unawaited(
      showCupertinoModalPopup<void>(
        context: context,
        builder: (sheetContext) => CupertinoActionSheet(
          title: Text(_displayTitle(context, session)),
          actions: [
            CupertinoActionSheetAction(
              key: const ValueKey('session-action-pin'),
              onPressed: () {
                Navigator.pop(sheetContext);
                unawaited(
                  controller.setPinned(session, !(session.pinned ?? false)),
                );
              },
              child: Text(session.pinned == true ? l10n.unpin : l10n.pin),
            ),
            CupertinoActionSheetAction(
              key: const ValueKey('session-action-archive'),
              onPressed: () {
                Navigator.pop(sheetContext);
                unawaited(controller.setArchived(session, true));
              },
              child: Text(l10n.archive),
            ),
            CupertinoActionSheetAction(
              key: const ValueKey('session-action-branch'),
              onPressed: () {
                Navigator.pop(sheetContext);
                unawaited(_onBranch(context, controller, session));
              },
              child: Text(l10n.branch),
            ),
            CupertinoActionSheetAction(
              key: const ValueKey('session-action-export'),
              onPressed: () {
                Navigator.pop(sheetContext);
                unawaited(_showExportFormat(context, session));
              },
              child: Text(l10n.export),
            ),
            CupertinoActionSheetAction(
              key: const ValueKey('session-action-move-project'),
              onPressed: () {
                Navigator.pop(sheetContext);
                unawaited(_moveToProject(context, session));
              },
              child: Text(l10n.moveToProject),
            ),
            CupertinoActionSheetAction(
              key: const ValueKey('session-action-workspace'),
              onPressed: () {
                Navigator.pop(sheetContext);
                if (context.mounted) {
                  // 蓝本对应 SF Symbol: folder (CupertinoIcons.folder)
                  // push 保留 Navigator 栈，返回时保留滚动/搜索状态
                  unawaited(context.push('/workspace/${session.id}'));
                }
              },
              child: Text(l10n.workspace),
            ),
            CupertinoActionSheetAction(
              key: const ValueKey('session-action-git'),
              onPressed: () {
                Navigator.pop(sheetContext);
                if (context.mounted) {
                  // 蓝本对应 SF Symbol: arrow.triangle.branch (CupertinoIcons.arrow_branch)
                  // push 保留 Navigator 栈，返回时保留滚动/搜索状态
                  unawaited(context.push('/git/${session.id}'));
                }
              },
              child: Text(l10n.git),
            ),
            if (session.archived == true)
              CupertinoActionSheetAction(
                key: const ValueKey('session-action-unarchive'),
                onPressed: () {
                  Navigator.pop(sheetContext);
                  unawaited(controller.setArchived(session, false));
                },
                child: Text(l10n.unarchive),
              ),
            CupertinoActionSheetAction(
              key: const ValueKey('session-action-delete'),
              isDestructiveAction: true,
              onPressed: () {
                Navigator.pop(sheetContext);
                unawaited(_confirmDelete(context, session));
              },
              child: Text(l10n.delete),
            ),
          ],
          cancelButton: CupertinoActionSheetAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(sheetContext),
            child: Text(l10n.cancel),
          ),
        ),
      ),
    );
  }

  Future<void> _showExportFormat(
    BuildContext context,
    SessionSummary session,
  ) async {
    final l10n = AppLocalizations.of(context);
    final format = await showCupertinoModalPopup<String>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: Text(l10n.exportSession),
        actions: [
          CupertinoActionSheetAction(
            key: const ValueKey('session-export-markdown'),
            onPressed: () => Navigator.pop(sheetContext, 'markdown'),
            child: Text(l10n.markdownFormat),
          ),
          CupertinoActionSheetAction(
            key: const ValueKey('session-export-json'),
            onPressed: () => Navigator.pop(sheetContext, 'json'),
            child: Text(l10n.jsonFormat),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(sheetContext),
          child: Text(l10n.cancel),
        ),
      ),
    );
    if (format == null || !context.mounted) return;

    final sessionId = session.sessionId ?? session.id;
    try {
      final response = await ref
          .read(apiClientProvider)
          .exportSession(
            sessionId: sessionId,
            format: format == 'markdown' ? 'md' : 'json',
          );
      if (!context.mounted) return;
      final content = utf8.decode(response.data, allowMalformed: true);
      await showCupertinoDialog<void>(
        context: context,
        builder: (dialogContext) => CupertinoAlertDialog(
          title: Text(l10n.exportSuccess(format)),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 260),
            child: SingleChildScrollView(
              child: Text(content.isEmpty ? l10n.exportContentEmpty : content),
            ),
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: content));
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              },
              child: Text(l10n.copyContent),
            ),
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(l10n.close),
            ),
          ],
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      await showCupertinoDialog<void>(
        context: context,
        builder: (dialogContext) => CupertinoAlertDialog(
          title: Text(l10n.exportFailed),
          content: Text(
            error is ApiException ? error.message : '$error',
            style: TextStyle(color: statusRedText.resolveFrom(context)),
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(l10n.ok),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _onBranch(
    BuildContext context,
    SessionListController controller,
    SessionSummary session,
  ) async {
    final newId = await controller.branch(session);
    if (newId != null && context.mounted) {
      context.go('/chat/$newId');
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    SessionSummary session,
  ) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: Text(l10n.deleteSession),
        content: Text(
          l10n.confirmDeleteSession(_displayTitle(context, session)),
        ),
        actions: [
          CupertinoDialogAction(
            key: const ValueKey('session-delete-cancel'),
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.cancel),
          ),
          CupertinoDialogAction(
            key: const ValueKey('session-delete-confirm'),
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await ref.read(sessionListControllerProvider.notifier).delete(session);
    }
  }

  Future<void> _confirmBatchArchive(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        key: const ValueKey('batch-archive-dialog'),
        title: Text(l10n.batchArchiveTitle),
        content: Text(l10n.confirmBatchArchivePrompt),
        actions: [
          CupertinoDialogAction(
            key: const ValueKey('batch-archive-cancel'),
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.cancel),
          ),
          CupertinoDialogAction(
            key: const ValueKey('batch-archive-confirm'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l10n.archive),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await ref
          .read(sessionListControllerProvider.notifier)
          .batchArchive(archived: true);
    }
  }

  Future<void> _confirmBatchDelete(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final count =
        ref
            .read(sessionListControllerProvider)
            .valueOrNull
            ?.selectedSessionIds
            .length ??
        0;
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        key: const ValueKey('batch-delete-dialog'),
        title: Text(l10n.batchDeleteTitle),
        content: Text(l10n.confirmBatchDeletePrompt(count)),
        actions: [
          CupertinoDialogAction(
            key: const ValueKey('batch-delete-cancel'),
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.cancel),
          ),
          CupertinoDialogAction(
            key: const ValueKey('batch-delete-confirm'),
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await ref.read(sessionListControllerProvider.notifier).batchDelete();
    }
  }

  Future<void> _batchMoveToProject(BuildContext context) async {
    final projectId = await showProjectPicker(context);
    if (projectId == null || !context.mounted) return;
    await ref
        .read(sessionListControllerProvider.notifier)
        .batchMove(projectId.isEmpty ? null : projectId);
  }

  Future<void> _moveToProject(
    BuildContext context,
    SessionSummary session,
  ) async {
    final projectId = await showProjectPicker(context);
    if (projectId == null || !context.mounted) return;
    await ref
        .read(sessionListControllerProvider.notifier)
        .moveToProject(session, projectId.isEmpty ? null : projectId);
  }

  Future<void> _showActionError(BuildContext context, String message) async {
    final l10n = AppLocalizations.of(context);
    await showCupertinoDialog<void>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: Text(l10n.actionFailed),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(l10n.ok),
          ),
        ],
      ),
    );
    await ref.read(sessionListControllerProvider.notifier).clearActionError();
  }

  String _errorMessage(Object? error) {
    if (error is ApiException) return error.message;
    return error?.toString() ?? AppLocalizations.of(context).unknownError;
  }
}

String _sectionTitle(BuildContext context, String rawTitle) {
  final l10n = AppLocalizations.of(context);
  switch (rawTitle) {
    case '定时':
      return l10n.scheduledSection;
    case '置顶':
      return l10n.pinnedSection;
    case '今天':
      return l10n.todaySection;
    case '昨天':
      return l10n.yesterdaySection;
    case '更早':
      return l10n.earlierSection;
    case '搜索结果':
      return l10n.searchResultsSection;
    default:
      return rawTitle;
  }
}

/// 单行会话（自绘行而非 CupertinoListTile，便于独立 ellipsis 按钮命中测试）。
class _SessionRow extends StatelessWidget {
  const _SessionRow({
    super.key,
    required this.session,
    required this.onTap,
    this.onLongPress,
    this.onActions,
    this.selectionMode = false,
    this.selected = false,
    this.highlightQuery,
  });

  final SessionSummary session;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  /// 行尾操作按钮回调；null = 隐藏（多选模式下）。
  final VoidCallback? onActions;

  /// 多选模式：显示勾选圈，点击切换勾选。
  final bool selectionMode;
  final bool selected;

  /// 搜索关键词：非空时标题与摘录中的命中片段高亮。
  final String? highlightQuery;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final metadata = _metadataLabel(context, session);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            if (selectionMode) ...[
              Icon(
                selected
                    ? CupertinoIcons.checkmark_circle_fill
                    : CupertinoIcons.circle,
                size: 22,
                color: selected
                    ? CupertinoColors.activeBlue
                    : CupertinoColors.secondaryLabel.resolveFrom(context),
              ),
              const SizedBox(width: 10),
            ],
            if (_isStreaming(session)) ...[
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: CupertinoColors.systemGreen,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: _highlightedSpan(
                          context,
                          _displayTitle(context, session),
                          style: const TextStyle(fontSize: 17),
                        ),
                      ),
                      if (session.pinned == true) ...[
                        const SizedBox(width: 6),
                        const Icon(
                          CupertinoIcons.pin_fill,
                          size: 12,
                          color: CupertinoColors.systemBlue,
                        ),
                      ],
                      if (session.parentSessionId != null) ...[
                        const SizedBox(width: 6),
                        const Icon(
                          CupertinoIcons.arrow_2_squarepath,
                          size: 12,
                          color: CupertinoColors.secondaryLabel,
                        ),
                      ],
                      if (session.readOnly == true ||
                          session.isReadOnly == true) ...[
                        const SizedBox(width: 6),
                        const Icon(
                          CupertinoIcons.lock_fill,
                          size: 12,
                          color: CupertinoColors.secondaryLabel,
                        ),
                      ],
                      if (session.hasPendingUserMessage == true) ...[
                        const SizedBox(width: 6),
                        Text(
                          l10n.pendingInput,
                          style: const TextStyle(
                            fontSize: 11,
                            color: CupertinoColors.systemOrange,
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (metadata != null) ...[
                    const SizedBox(height: 2),
                    _highlightedSpan(
                      context,
                      metadata,
                      style: const TextStyle(
                        fontSize: 13,
                        color: CupertinoColors.secondaryLabel,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (onActions != null)
              AccessibleButton(
                key: ValueKey(
                  'session-actions-${session.sessionId ?? session.id}',
                ),
                label: l10n.sessionActions,
                padding: EdgeInsets.zero,
                minimumSize: const Size(36, 36),
                onPressed: onActions,
                child: const Icon(
                  CupertinoIcons.ellipsis,
                  size: 20,
                  color: CupertinoColors.systemGrey,
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 构造标题/摘要文本：搜索模式下把 [query] 命中片段染成高亮。
  Widget _highlightedSpan(
    BuildContext context,
    String text, {
    TextStyle? style,
  }) {
    final query = highlightQuery;
    if (query == null ||
        query.isEmpty ||
        !text.toLowerCase().contains(query.toLowerCase())) {
      return Text(
        text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }
    final spans = <TextSpan>[];
    final lower = text.toLowerCase();
    final q = query.toLowerCase();
    var index = 0;
    while (true) {
      final hit = lower.indexOf(q, index);
      if (hit < 0) {
        spans.add(TextSpan(text: text.substring(index)));
        break;
      }
      if (hit > index) {
        spans.add(TextSpan(text: text.substring(index, hit)));
      }
      spans.add(
        TextSpan(
          text: text.substring(hit, hit + query.length),
          style: TextStyle(
            color: CupertinoColors.activeBlue.resolveFrom(context),
            fontWeight: FontWeight.w600,
          ),
        ),
      );
      index = hit + query.length;
    }
    return Text.rich(
      TextSpan(style: style, children: spans),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }

  static String? _metadataLabel(BuildContext context, SessionSummary session) {
    final l10n = AppLocalizations.of(context);
    final parts = <String>[
      if (session.messageCount != null && session.messageCount! >= 0)
        l10n.messageCountLabel(session.messageCount!),
      if (_nonEmpty(session.workspace) != null)
        _lastPathComponent(_nonEmpty(session.workspace)!),
      if (_nonEmpty(session.sourceLabel) != null)
        '· ${_nonEmpty(session.sourceLabel)}',
      if (session.estimatedCost != null)
        '· \$${session.estimatedCost!.toStringAsFixed(2)}',
      if (_nonEmpty(session.matchPreview) != null)
        _nonEmpty(session.matchPreview)!,
    ];
    return parts.isEmpty ? null : parts.join(' ');
  }

  static bool _isStreaming(SessionSummary session) =>
      session.isStreaming == true || _nonEmpty(session.activeStreamId) != null;

  static String? _nonEmpty(String? value) {
    final trimmed = value?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  static String _lastPathComponent(String workspace) {
    final normalized = workspace.replaceAll('\\', '/');
    final last = normalized.split('/').last;
    return last.isEmpty ? workspace : last;
  }
}

String _displayTitle(BuildContext context, SessionSummary session) {
  final title = session.title?.trim();
  if (title == null || title.isEmpty) {
    return AppLocalizations.of(context).untitledSession;
  }
  return title;
}
