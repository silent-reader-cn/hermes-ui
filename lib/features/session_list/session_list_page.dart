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
import '../../app/theme/status_colors.dart';
import 'session_list_providers.dart';

/// 会话列表页（app_shell_spec.md §3：`/` 为主列表）。
///
/// Cupertino 风格：大标题 + 搜索框（防抖远程搜索）+ 下拉刷新 + 无限滚动分页 +
/// 会话分区（置顶/今天/昨天/更早）+ 行快捷操作（pin/archive/branch/delete 弹
/// 菜单）+ 悬浮新建会话按钮。会话点击 → `/chat/:sessionId`。
class SessionListPage extends ConsumerStatefulWidget {
  const SessionListPage({super.key});

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

    ref.listen<AsyncValue<SessionListState>>(
      sessionListControllerProvider,
      (previous, next) {
        final error = next.valueOrNull?.actionError;
        if (error != null && error != previous?.valueOrNull?.actionError) {
          unawaited(_showActionError(context, error));
        }
      },
    );

    // 首帧后自动补充分页窗口，直到填满视口或耗尽（内容不足一屏时也能翻页）。
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeLoadMore());

    return CupertinoPageScaffold(
      child: Stack(
        children: [
          CustomScrollView(
            key: const ValueKey('session-list-scroll'),
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              CupertinoSliverNavigationBar(
                largeTitle: const Text('会话'),
                trailing: CupertinoButton(
                  key: const ValueKey('session-list-settings'),
                  padding: EdgeInsets.zero,
                  onPressed: () => context.go('/settings'),
                  child: const Icon(CupertinoIcons.gear_alt),
                ),
              ),
              // 注意：刷新指示器必须排在所有 SliverToBoxAdapter 之前
              // （视口会把 overscroll 逐级分给前面的 box sliver，导致
              // 指示器拿不到负 overlap 而无法触发）。
              CupertinoSliverRefreshControl(onRefresh: _onRefresh),
              SliverToBoxAdapter(child: _buildSearchBar()),
              ..._buildContentSlivers(async, state, sections, isSearchMode),
            ],
          ),
          Positioned(
            right: 20,
            bottom: 24,
            child: CupertinoButton.filled(
              key: const ValueKey('session-list-new'),
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

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: CupertinoSearchTextField(
        key: const ValueKey('session-list-search'),
        controller: _searchController,
        placeholder: '搜索会话',
        onChanged: _onSearchChanged,
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
      return [
        _buildErrorSliver(async.error),
      ];
    }

    final hasVisible = sections.any((section) => section.sessions.isNotEmpty);
    if (!hasVisible) {
      return [_buildEmptySliver(isSearchMode: isSearchMode)];
    }

    return [
      for (final section in sections)
        if (section.sessions.isNotEmpty)
          SliverToBoxAdapter(
            child: CupertinoListSection.insetGrouped(
              header: Text(section.title),
              children: [
                for (final session in section.sessions)
                  _SessionRow(
                    key: ValueKey(
                      'session-row-${session.sessionId ?? session.id}',
                    ),
                    session: session,
                    onTap: () => _openSession(context, session),
                    onActions: () => _showRowActions(context, session),
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
      if (!state.hasMore && state.displaySessions.length > SessionListState.pageSize)
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Center(
              child: Text(
                '没有更多了',
                style: TextStyle(
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
            const Text(
              '加载失败',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              _errorMessage(error),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: statusRedText,
              ),
            ),
            const SizedBox(height: 20),
            CupertinoButton.filled(
              key: const ValueKey('session-list-retry'),
              onPressed: () => unawaited(
                ref.read(sessionListControllerProvider.notifier).refresh(),
              ),
              child: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptySliver({required bool isSearchMode}) {
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
              isSearchMode ? '未找到相关会话' : '暂无会话',
              style: const TextStyle(fontSize: 17),
            ),
            const SizedBox(height: 6),
            Text(
              isSearchMode ? '换个关键词试试' : '点击下方按钮开始新对话',
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
                child: const Text('新建会话'),
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
    final controller = ref.read(sessionListControllerProvider.notifier);
    unawaited(
      showCupertinoModalPopup<void>(
        context: context,
        builder: (sheetContext) => CupertinoActionSheet(
          title: Text(_displayTitle(session)),
          actions: [
            CupertinoActionSheetAction(
              key: const ValueKey('session-action-pin'),
              onPressed: () {
                Navigator.pop(sheetContext);
                unawaited(
                  controller.setPinned(session, !(session.pinned ?? false)),
                );
              },
              child: Text(session.pinned == true ? '取消置顶' : '置顶'),
            ),
            CupertinoActionSheetAction(
              key: const ValueKey('session-action-archive'),
              onPressed: () {
                Navigator.pop(sheetContext);
                unawaited(controller.setArchived(session, true));
              },
              child: const Text('归档'),
            ),
            CupertinoActionSheetAction(
              key: const ValueKey('session-action-branch'),
              onPressed: () {
                Navigator.pop(sheetContext);
                unawaited(_onBranch(context, controller, session));
              },
              child: const Text('分支'),
            ),
            CupertinoActionSheetAction(
              key: const ValueKey('session-action-export'),
              onPressed: () {
                Navigator.pop(sheetContext);
                unawaited(_showExportFormat(context, session));
              },
              child: const Text('导出'),
            ),
            CupertinoActionSheetAction(
              key: const ValueKey('session-action-delete'),
              isDestructiveAction: true,
              onPressed: () {
                Navigator.pop(sheetContext);
                unawaited(_confirmDelete(context, session));
              },
              child: const Text('删除'),
            ),
          ],
          cancelButton: CupertinoActionSheetAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(sheetContext),
            child: const Text('取消'),
          ),
        ),
      ),
    );
  }

  Future<void> _showExportFormat(
    BuildContext context,
    SessionSummary session,
  ) async {
    final format = await showCupertinoModalPopup<String>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: const Text('导出会话'),
        actions: [
          CupertinoActionSheetAction(
            key: const ValueKey('session-export-markdown'),
            onPressed: () => Navigator.pop(sheetContext, 'markdown'),
            child: const Text('Markdown'),
          ),
          CupertinoActionSheetAction(
            key: const ValueKey('session-export-json'),
            onPressed: () => Navigator.pop(sheetContext, 'json'),
            child: const Text('JSON'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(sheetContext),
          child: const Text('取消'),
        ),
      ),
    );
    if (format == null || !context.mounted) return;

    final sessionId = session.sessionId ?? session.id;
    try {
      final response = await ref.read(apiClientProvider).exportSession(
        sessionId: sessionId,
        format: format == 'markdown' ? 'md' : 'json',
      );
      if (!context.mounted) return;
      final content = utf8.decode(response.data, allowMalformed: true);
      await showCupertinoDialog<void>(
        context: context,
        builder: (dialogContext) => CupertinoAlertDialog(
          title: Text('$format 导出成功'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 260),
            child: SingleChildScrollView(
              child: Text(content.isEmpty ? '导出内容为空' : content),
            ),
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: content));
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              },
              child: const Text('复制内容'),
            ),
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('关闭'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      await showCupertinoDialog<void>(
        context: context,
        builder: (dialogContext) => CupertinoAlertDialog(
          title: const Text('导出失败'),
          content: Text(
            error is ApiException ? error.message : '$error',
            style: TextStyle(color: statusRedText.resolveFrom(context)),
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('好'),
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

  Future<void> _confirmDelete(BuildContext context, SessionSummary session) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: const Text('删除会话'),
        content: Text('确定删除「${_displayTitle(session)}」？此操作不可撤销。'),
        actions: [
          CupertinoDialogAction(
            key: const ValueKey('session-delete-cancel'),
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            key: const ValueKey('session-delete-confirm'),
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await ref.read(sessionListControllerProvider.notifier).delete(session);
    }
  }

  Future<void> _showActionError(BuildContext context, String message) async {
    await showCupertinoDialog<void>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: const Text('操作失败'),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('好'),
          ),
        ],
      ),
    );
    await ref.read(sessionListControllerProvider.notifier).clearActionError();
  }

  String _errorMessage(Object? error) {
    if (error is ApiException) return error.message;
    return error?.toString() ?? '未知错误';
  }
}

/// 单行会话（自绘行而非 CupertinoListTile，便于独立 ellipsis 按钮命中测试）。
class _SessionRow extends StatelessWidget {
  const _SessionRow({
    super.key,
    required this.session,
    required this.onTap,
    required this.onActions,
  });

  final SessionSummary session;
  final VoidCallback onTap;
  final VoidCallback onActions;

  @override
  Widget build(BuildContext context) {
    final metadata = _metadataLabel(session);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
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
                        child: Text(
                          _displayTitle(session),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
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
                    ],
                  ),
                  if (metadata != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      metadata,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        color: CupertinoColors.secondaryLabel,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            CupertinoButton(
              key: ValueKey(
                'session-actions-${session.sessionId ?? session.id}',
              ),
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

  static String _displayTitle(SessionSummary session) {
    final title = session.title?.trim();
    if (title == null || title.isEmpty) return '未命名会话';
    return title;
  }

  static String? _metadataLabel(SessionSummary session) {
    final parts = <String>[
      if (session.messageCount != null && session.messageCount! >= 0)
        '${session.messageCount} 条消息',
      if (_nonEmpty(session.workspace) != null)
        _lastPathComponent(_nonEmpty(session.workspace)!),
    ];
    return parts.isEmpty ? null : parts.join(' · ');
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

String _displayTitle(SessionSummary session) {
  final title = session.title?.trim();
  if (title == null || title.isEmpty) return '未命名会话';
  return title;
}
