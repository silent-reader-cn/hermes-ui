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
import '../../app/widgets/adaptive_action_menu.dart';
import '../../app/widgets/narrow_navigation_dropdown.dart';
import '../../l10n/app_localizations.dart';
import '../desktop/desktop_settings.dart';
import '../projects/project_picker_sheet.dart';
import '../projects/project_providers.dart';
import 'session_auto_refresh.dart';
import 'session_list_header.dart';
import 'session_list_providers.dart';
import 'session_list_utility_rows.dart';
import 'session_row_subtitle_settings.dart';

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
    this.showFab = true,
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

  /// 是否渲染悬浮新建会话按钮（FAB）。
  ///
  /// 手机单栈（窄屏）保持默认 `true`；桌面侧栏场景隐藏 FAB，新建入口由
  /// 头部右上角按钮承担（见 [SessionListHeaderDelegate.actions]）。
  final bool showFab;

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
    // 会话行副标题显示开关（设置页配置）+ projectId→名称映射（同屏一次解析）。
    final subtitleSettings = ref.watch(sessionRowSubtitleSettingsProvider);
    final projectNames = _projectNameMap(ref);

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
    final isDesktop = isDesktopPlatform();
    final isWide = MediaQuery.sizeOf(context).width >= 900;
    final showDesktopRefresh = isDesktop && isWide;
    final refreshing = ref.watch(sessionListRefreshingProvider);
    return SessionAutoRefreshObserver(
      child: CupertinoPageScaffold(
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
                  brightness:
                      CupertinoTheme.of(context).brightness ?? Brightness.light,
                  // 侧栏复用（showUtilityRows=false）→ 紧凑头部：不渲染「会话」
                  // 大标题，搜索框与操作按钮（筛选/加号）整合为单行 pinned 头部；
                  // 手机端单栈 → 宽敞大标题头部（49pt）。
                  compactHeader: !widget.showUtilityRows,
                  searchField: !widget.showUtilityRows
                      ? _buildSearchField()
                      : null,
                  actions: [
                    if (!isWide && !isSearchMode)
                      _buildNarrowNavigationAction(),
                    if (!isSearchMode) _buildFilterAction(state),
                    if (widget.showSettingsTrailing)
                      _buildSettingsOrDoneAction(state),
                    if (!widget.showUtilityRows) _buildNewSessionAction(),
                    if (showDesktopRefresh) _buildDesktopRefreshAction(refreshing),
                  ],
                ),
              ),
              // 注意：刷新指示器必须排在所有 SliverToBoxAdapter 之前
              // （视口会把 overscroll 逐级分给前面的 box sliver，导致
              // 指示器拿不到负 overlap 而无法触发）。
              CupertinoSliverRefreshControl(onRefresh: _onRefresh),
              if (widget.showUtilityRows)
                SliverToBoxAdapter(child: _buildSearchBar()),
              if (widget.showUtilityRows && !isSearchMode && isWide)
                const SliverToBoxAdapter(child: SessionListUtilityRows()),
              ..._buildContentSlivers(
                async,
                state,
                sections,
                isSearchMode,
                subtitleSettings,
                projectNames,
              ),
            ],
          ),
          if (state?.isSelectionMode == true)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _buildBatchBar(state!),
            ),
          // 桌面侧栏场景隐藏 FAB（新建入口在头部右上角，见
          // [SessionListHeaderDelegate.actions]）。
          if (widget.showFab)
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
    ),
  );
  }

  // -------------------------------------------------------------------------
  // 顶部 chrome
  // -------------------------------------------------------------------------

  Widget _buildDesktopRefreshAction(bool refreshing) {
    final l10n = AppLocalizations.of(context);
    return AccessibleButton(
      key: const ValueKey('session-list-desktop-refresh'),
      // 避免新增 l10n 键，复用刷新相关语义
      label: l10n.refreshInsights,
      padding: EdgeInsets.zero,
      minimumSize: const Size(44, 44),
      onPressed: refreshing
          ? null
          : () => unawaited(
                ref
                    .read(sessionListControllerProvider.notifier)
                    .refreshIfStale(force: true),
              ),
      child: refreshing
          ? const CupertinoActivityIndicator(radius: 10)
          : const Icon(CupertinoIcons.refresh, size: 22),
    );
  }

  Widget _buildSearchField() {
    final l10n = AppLocalizations.of(context);
    return CupertinoSearchTextField(
      key: const ValueKey('session-list-search'),
      controller: _searchController,
      placeholder: l10n.searchSessions,
      onChanged: _onSearchChanged,
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: _buildSearchField(),
    );
  }

  /// 头部窄屏快捷导航下拉按钮（大标题右侧向下箭头，点击展开 5 个功能入口）。
  Widget _buildNarrowNavigationAction() {
    return const NarrowNavigationDropdownButton(
      buttonKey: ValueKey('session-list-narrow-nav'),
    );
  }

  /// 头部筛选入口按钮（「会话」右侧向下箭头，点击展开筛选弹层）。
  Widget _buildFilterAction(SessionListState? state) {
    final l10n = AppLocalizations.of(context);
    return AccessibleButton(
      key: const ValueKey('session-list-filter-trigger'),
      label: l10n.filterSessions,
      padding: EdgeInsets.zero,
      minimumSize: const Size(44, 44),
      onPressed: () {
        if (state != null) _showFilterSheet(state);
      },
      child: const Icon(CupertinoIcons.line_horizontal_3_decrease, size: 22),
    );
  }

  /// 头部设置 / 完成选择按钮（手机单栈右侧齿轮；选择模式下切换为完成）。
  Widget _buildSettingsOrDoneAction(SessionListState? state) {
    final l10n = AppLocalizations.of(context);
    return AccessibleButton(
      key: state?.isSelectionMode == true
          ? const ValueKey('session-list-selection-done')
          : const ValueKey('session-list-settings'),
      label: state?.isSelectionMode == true
          ? l10n.doneSelecting
          : l10n.settings,
      padding: EdgeInsets.zero,
      minimumSize: const Size(44, 44),
      onPressed: () {
        final controller = ref.read(sessionListControllerProvider.notifier);
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
    );
  }

  /// 头部新建会话按钮（桌面侧栏场景替代 FAB）。
  Widget _buildNewSessionAction() {
    final l10n = AppLocalizations.of(context);
    return AccessibleButton(
      key: const ValueKey('session-list-header-new'),
      label: l10n.newSession,
      padding: EdgeInsets.zero,
      minimumSize: const Size(44, 44),
      onPressed: () => unawaited(_onNewSession(context)),
      child: const Icon(CupertinoIcons.add, size: 22),
    );
  }

  /// 打开筛选底部弹层（全部/已归档 + 渠道 + 项目）。
  void _showFilterSheet(SessionListState state) {
    unawaited(
      showCupertinoModalPopup<void>(
        context: context,
        builder: (sheetContext) => _SessionFilterSheet(
          state: state,
          onSelect: (mode, value) {
            // 先关弹层，再触发过滤（过滤失败也不卡住弹层）。
            Navigator.pop(sheetContext);
            unawaited(
              ref
                  .read(sessionListControllerProvider.notifier)
                  .setFilter(mode, value: value),
            );
          },
        ),
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

  // -------------------------------------------------------------------------
  // 内容 slivers：加载 / 错误 / 空态 / 分区列表
  // -------------------------------------------------------------------------

  List<Widget> _buildContentSlivers(
    AsyncValue<SessionListState> async,
    SessionListState? state,
    List<SessionListSection> sections,
    bool isSearchMode,
    SessionRowSubtitleSettings subtitleSettings,
    Map<String, String> projectNames,
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
          SliverToBoxAdapter(
            child: CupertinoListSection.insetGrouped(
              hasLeading: false,
              header: Text(_sectionTitle(context, section.title)),
              children: [
                for (final session in section.sessions)
                  _SessionRow(
                    key: ValueKey(
                      'session-row-${session.sessionId ?? session.id}',
                    ),
                    session: session,
                    subtitleSettings: subtitleSettings,
                    projectNames: projectNames,
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
                        : (anchorKey) => _showRowActions(
                              context,
                              session,
                              anchorKey,
                            ),
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
                style: TextStyle(
                  fontSize: 13,
                  color: secondaryText.resolveFrom(context),
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
              style: TextStyle(fontSize: 13, color: statusRedText.resolveFrom(context)),
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
              style: TextStyle(
                fontSize: 13,
                color: secondaryText.resolveFrom(context),
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

  void _showRowActions(
    BuildContext context,
    SessionSummary session,
    GlobalKey anchorKey,
  ) {
    final l10n = AppLocalizations.of(context);
    final controller = ref.read(sessionListControllerProvider.notifier);
    final items = [
      AdaptiveMenuItem(
        key: const ValueKey('session-action-pin'),
        label: session.pinned == true ? l10n.unpin : l10n.pin,
        onPressed: () => unawaited(
          controller.setPinned(session, !(session.pinned ?? false)),
        ),
      ),
      AdaptiveMenuItem(
        key: const ValueKey('session-action-archive'),
        label: l10n.archive,
        onPressed: () => unawaited(controller.setArchived(session, true)),
      ),
      AdaptiveMenuItem(
        key: const ValueKey('session-action-branch'),
        label: l10n.branch,
        onPressed: () => unawaited(_onBranch(context, controller, session)),
      ),
      AdaptiveMenuItem(
        key: const ValueKey('session-action-export'),
        label: l10n.export,
        onPressed: () => unawaited(_showExportFormat(context, session)),
      ),
      AdaptiveMenuItem(
        key: const ValueKey('session-action-move-project'),
        label: l10n.moveToProject,
        onPressed: () => unawaited(_moveToProject(context, session)),
      ),
      AdaptiveMenuItem(
        key: const ValueKey('session-action-workspace'),
        label: l10n.workspace,
        onPressed: () {
          if (context.mounted) {
            // 蓝本对应 SF Symbol: folder (CupertinoIcons.folder)
            // push 保留 Navigator 栈，返回时保留滚动/搜索状态
            unawaited(context.push('/workspace/${session.id}'));
          }
        },
      ),
      AdaptiveMenuItem(
        key: const ValueKey('session-action-git'),
        label: l10n.git,
        onPressed: () {
          if (context.mounted) {
            // 蓝本对应 SF Symbol: arrow.triangle.branch (CupertinoIcons.arrow_branch)
            // push 保留 Navigator 栈，返回时保留滚动/搜索状态
            unawaited(context.push('/git/${session.id}'));
          }
        },
      ),
      if (session.archived == true)
        AdaptiveMenuItem(
          key: const ValueKey('session-action-unarchive'),
          label: l10n.unarchive,
          onPressed: () => unawaited(controller.setArchived(session, false)),
        ),
      AdaptiveMenuItem(
        key: const ValueKey('session-action-delete'),
        isDestructive: true,
        label: l10n.delete,
        onPressed: () => unawaited(_confirmDelete(context, session)),
      ),
    ];

    unawaited(
      AdaptiveActionMenu.show(
        context,
        anchorKey: anchorKey,
        items: items,
        title: null,
        cancelLabel: l10n.cancel,
        cancelKey: const ValueKey('session-action-cancel'),
        preferredWidth: 220,
        minWidth: 180,
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
class _SessionRow extends StatefulWidget {
  const _SessionRow({
    super.key,
    required this.session,
    required this.onTap,
    required this.subtitleSettings,
    required this.projectNames,
    this.onLongPress,
    this.onActions,
    this.selectionMode = false,
    this.selected = false,
    this.highlightQuery,
  });

  final SessionSummary session;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  /// 副标题显示项开关（设置页配置）。
  final SessionRowSubtitleSettings subtitleSettings;

  /// projectId → 项目名称 映射（副标题「项目名」显示项）。
  final Map<String, String> projectNames;

  /// 行尾操作按钮回调；null = 隐藏（多选模式下）。
  final void Function(GlobalKey anchorKey)? onActions;

  /// 多选模式：显示勾选圈，点击切换勾选。
  final bool selectionMode;
  final bool selected;

  /// 搜索关键词：非空时标题与摘录中的命中片段高亮。
  final String? highlightQuery;

  @override
  State<_SessionRow> createState() => _SessionRowState();

  /// 按副标题显示开关组装元数据行（消息数 / 项目名 / 工作区 / 渠道 /
  /// 预估价钱 + 搜索命中预览），渠道与预估价钱默认关闭。
  static String? _metadataLabel(
    BuildContext context,
    SessionSummary session, {
    required SessionRowSubtitleSettings settings,
    required Map<String, String> projectNames,
  }) {
    final l10n = AppLocalizations.of(context);
    final projectName = session.projectId == null
        ? null
        : _nonEmpty(projectNames[session.projectId]);
    final parts = <String>[
      if (settings.messageCount &&
          session.messageCount != null &&
          session.messageCount! >= 0)
        l10n.messageCountLabel(session.messageCount!),
      if (settings.projectName && projectName != null) projectName,
      if (settings.workspace && _nonEmpty(session.workspace) != null)
        _lastPathComponent(_nonEmpty(session.workspace)!),
      if (settings.channel && _nonEmpty(session.sourceLabel) != null)
        '· ${_nonEmpty(session.sourceLabel)}',
      if (settings.estimatedCost && session.estimatedCost != null)
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
    final parts = workspace.replaceAll(r'\', '/').split('/');
    return parts.lastWhere((p) => p.isNotEmpty, orElse: () => workspace);
  }
}

class _SessionRowState extends State<_SessionRow> {
  final GlobalKey _actionKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final metadata = _SessionRow._metadataLabel(
      context,
      widget.session,
      settings: widget.subtitleSettings,
      projectNames: widget.projectNames,
    );
    final isStreaming = _SessionRow._isStreaming(widget.session);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            if (widget.selectionMode) ...[
              Icon(
                widget.selected
                    ? CupertinoIcons.checkmark_circle_fill
                    : CupertinoIcons.circle,
                size: 22,
                color: widget.selected
                    ? CupertinoColors.activeBlue
                    : CupertinoColors.secondaryLabel.resolveFrom(context),
              ),
              const SizedBox(width: 10),
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
                          _displayTitle(context, widget.session),
                          style: const TextStyle(fontSize: 17),
                        ),
                      ),
                      if (widget.session.pinned == true) ...[
                        const SizedBox(width: 6),
                        const Icon(
                          CupertinoIcons.pin_fill,
                          size: 12,
                          color: CupertinoColors.systemBlue,
                        ),
                      ],
                      if (widget.session.parentSessionId != null) ...[
                        const SizedBox(width: 6),
                        const Icon(
                          CupertinoIcons.arrow_2_squarepath,
                          size: 12,
                          color: CupertinoColors.secondaryLabel,
                        ),
                      ],
                      if (widget.session.readOnly == true ||
                          widget.session.isReadOnly == true) ...[
                        const SizedBox(width: 6),
                        const Icon(
                          CupertinoIcons.lock_fill,
                          size: 12,
                          color: CupertinoColors.secondaryLabel,
                        ),
                      ],

                    ],
                  ),
                  if (metadata != null) ...[
                    const SizedBox(height: 2),
                    _highlightedSpan(
                      context,
                      metadata,
                      style: TextStyle(
                        fontSize: 13,
                        color: secondaryText.resolveFrom(context),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (widget.onActions != null)
              KeyedSubtree(
                key: _actionKey,
                child: AccessibleButton(
                  key: ValueKey(
                    'session-actions-${widget.session.sessionId ?? widget.session.id}',
                  ),
                  label: isStreaming
                      ? '${l10n.sessionActions} — Active'
                      : l10n.sessionActions,
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(36, 36),
                  onPressed: () => widget.onActions!(_actionKey),
                  child: isStreaming
                      ? Semantics(
                          label: 'Active',
                          excludeSemantics: true,
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CupertinoActivityIndicator(
                              radius: 9,
                              color: CupertinoColors.activeBlue.resolveFrom(
                                context,
                              ),
                            ),
                          ),
                        )
                      : const Icon(
                          CupertinoIcons.ellipsis,
                          size: 20,
                          color: CupertinoColors.systemGrey,
                        ),
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
    final query = widget.highlightQuery;
    if (query == null ||
        query.isEmpty ||
        !text.toLowerCase().contains(query.toLowerCase())) {
      return Text(
        text,
        maxLines: 1,
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
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

String _displayTitle(BuildContext context, SessionSummary session) {
  final title = session.title?.trim();
  if (title == null || title.isEmpty) {
    return AppLocalizations.of(context).untitledSession;
  }
  return title;
}

/// 由 [projectsProvider] 构建 projectId → 名称 映射（会话行副标题「项目名」
/// 项使用；一次构建供整屏复用以避免逐行 map）。
Map<String, String> _projectNameMap(WidgetRef ref) {
  final projects = ref.watch(projectsProvider).valueOrNull ?? const [];
  return {
    for (final project in projects)
      if (project.projectId != null) project.projectId!: project.name ?? '',
  };
}

/// 筛选底部弹层：会话 / 渠道 / 项目 三段等宽 insetGrouped 列表。
///
/// 三段统一为 [CupertinoListSection.insetGrouped] 列表视觉（等宽、同边距），
/// 渠道与项目不再用 Wrap/chip 居中，改为纵向 [_SheetOptionRow] 单选列表；
/// 外层用 [ClipRRect]+[DecoratedBox] 紧凑布局，去掉底部白条与多余 padding。
class _SessionFilterSheet extends ConsumerWidget {
  const _SessionFilterSheet({required this.state, required this.onSelect});

  final SessionListState state;

  /// 选择回调（调用方负责 setFilter 并关闭弹层）。
  final void Function(SessionListFilterMode mode, String? value) onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final mode = state.filterMode;
    final projects = ref.watch(projectsProvider).valueOrNull ?? const [];
    final sheetBg = CupertinoColors.systemGroupedBackground.resolveFrom(
      context,
    );
    const sheetRadius = BorderRadius.vertical(top: Radius.circular(16));
    final headerStyle = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: secondaryText.resolveFrom(context),
      letterSpacing: 0.3,
    );

    return ClipRRect(
      borderRadius: sheetRadius,
      child: DecoratedBox(
        key: const ValueKey('session-filter-sheet'),
        decoration: BoxDecoration(color: sheetBg),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 8, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.filterSessions,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    AccessibleButton(
                      key: const ValueKey('session-filter-sheet-close'),
                      label: l10n.close,
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(36, 36),
                      onPressed: () => Navigator.pop(context),
                      child: const Icon(
                        CupertinoIcons.xmark_circle_fill,
                        size: 22,
                        color: CupertinoColors.secondaryLabel,
                      ),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      CupertinoListSection.insetGrouped(
                        key: const ValueKey('filter-section-sessions'),
                        hasLeading: false,
                        header: Text(l10n.sessions, style: headerStyle),
                        backgroundColor: CupertinoColors
                            .secondarySystemGroupedBackground
                            .resolveFrom(context),
                        separatorColor: CupertinoColors.separator.resolveFrom(
                          context,
                        ),
                        margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                        decoration: BoxDecoration(
                          color: CupertinoColors
                              .secondarySystemGroupedBackground
                              .resolveFrom(context),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        children: [
                          _SheetOptionRow(
                            key: const ValueKey('sheet-filter-all'),
                            label: l10n.all,
                            selected: mode == SessionListFilterMode.all,
                            onTap: () =>
                                onSelect(SessionListFilterMode.all, null),
                          ),
                          _SheetOptionRow(
                            key: const ValueKey('sheet-filter-archived'),
                            label:
                                '${l10n.archived}${_archivedCountLabelFor(state)}',
                            selected: mode == SessionListFilterMode.archived,
                            onTap: () =>
                                onSelect(SessionListFilterMode.archived, null),
                          ),
                          if (mode != SessionListFilterMode.all &&
                              mode != SessionListFilterMode.archived)
                            _SheetOptionRow(
                              key: const ValueKey('sheet-filter-clear'),
                              label: l10n.clearFilter,
                              selected: false,
                              onTap: () =>
                                  onSelect(SessionListFilterMode.all, null),
                            ),
                        ],
                      ),
                      if (state.sourceLabels.isNotEmpty)
                        CupertinoListSection.insetGrouped(
                          key: const ValueKey('filter-section-channels'),
                          hasLeading: false,
                          header: Text(l10n.channels, style: headerStyle),
                          backgroundColor: CupertinoColors
                              .secondarySystemGroupedBackground
                              .resolveFrom(context),
                          separatorColor: CupertinoColors.separator.resolveFrom(
                            context,
                          ),
                          margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                          decoration: BoxDecoration(
                            color: CupertinoColors
                                .secondarySystemGroupedBackground
                                .resolveFrom(context),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          children: [
                            for (final label in state.sourceLabels)
                              _SheetOptionRow(
                                key: ValueKey('filter-chip-$label'),
                                label: label,
                                selected:
                                    mode == SessionListFilterMode.source &&
                                    state.filterValue == label,
                                onTap: () => onSelect(
                                  SessionListFilterMode.source,
                                  label,
                                ),
                              ),
                          ],
                        ),
                      if (projects.isNotEmpty)
                        CupertinoListSection.insetGrouped(
                          key: const ValueKey('filter-section-projects'),
                          hasLeading: false,
                          header: Text(l10n.projects, style: headerStyle),
                          backgroundColor: CupertinoColors
                              .secondarySystemGroupedBackground
                              .resolveFrom(context),
                          separatorColor: CupertinoColors.separator.resolveFrom(
                            context,
                          ),
                          margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                          decoration: BoxDecoration(
                            color: CupertinoColors
                                .secondarySystemGroupedBackground
                                .resolveFrom(context),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          children: [
                            for (final project in projects)
                              _SheetOptionRow(
                                key: ValueKey('project-chip-${project.id}'),
                                label:
                                    project.name ?? l10n.untitledProject,
                                selected:
                                    mode == SessionListFilterMode.project &&
                                    state.filterValue == project.id,
                                onTap: () => onSelect(
                                  SessionListFilterMode.project,
                                  project.id,
                                ),
                              ),
                          ],
                        ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _archivedCountLabelFor(SessionListState state) {
    final count = state.archivedCount ?? state.archivedSessions.length;
    return count > 0 ? ' ($count)' : '';
  }
}

/// 筛选弹层中的单选行（会话 / 渠道 / 项目 共用）。
///
/// 选中态：左侧 activeBlue 浅底 pill + 文字 activeBlue 加粗，右侧 checkmark；
/// 未选中：常规 label 文字 + separator 0.5 分割。
class _SheetOptionRow extends StatelessWidget {
  const _SheetOptionRow({
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
    final activeBlue = CupertinoColors.activeBlue.resolveFrom(context);
    return CupertinoListTile(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      backgroundColor: selected
          ? activeBlue.withValues(alpha: 0.10)
          : CupertinoColors.secondarySystemGroupedBackground.resolveFrom(
              context,
            ),
      title: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 15,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          color: selected ? activeBlue : CupertinoColors.label.resolveFrom(context),
        ),
      ),
      trailing: selected
          ? Icon(
              CupertinoIcons.checkmark_alt,
              size: 18,
              color: activeBlue,
            )
          : null,
      onTap: onTap,
    );
  }
}
