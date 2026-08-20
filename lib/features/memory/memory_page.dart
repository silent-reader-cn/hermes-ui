import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/status_colors.dart';
import '../../core/api/api_exception.dart';
import '../../core/models/memory.dart';
import '../../core/utils/accessibility.dart';
import '../../l10n/app_localizations.dart';
import '../shared/app_back_button.dart';
import 'memory_providers.dart';

enum _MemoryTab { memory, user, soul, projectContext }

/// 记忆查看页（对齐 Hermex MemoryView 的只读浏览形态）。
///
/// Cupertino 风格：大标题 + 刷新按钮 + 下拉刷新；顶部 4 段切换器
/// （我的笔记 / 用户画像 / 智能体灵魂 / 项目上下文）切换各分区；
/// 智能体灵魂与项目上下文支持 Markdown 渲染；
/// 长文本默认折叠 + 展开全文；宽屏限制 maxWidth: 720 居中；
/// 含加载 / 错误 / 空态。
class MemoryPage extends ConsumerStatefulWidget {
  const MemoryPage({super.key});

  @override
  ConsumerState<MemoryPage> createState() => _MemoryPageState();
}

class _MemoryPageState extends ConsumerState<MemoryPage> {
  _MemoryTab _selectedTab = _MemoryTab.memory;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(memoryControllerProvider);
    final response = async.valueOrNull;

    return CupertinoPageScaffold(
      child: CustomScrollView(
        key: const ValueKey('memory-scroll'),
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          CupertinoSliverNavigationBar(
            largeTitle: Text(l10n.memoryTitle),
            leading: const AppBackButton(),
            trailing: AccessibleButton(
              key: const ValueKey('memory-refresh'),
              label: l10n.refreshMemory,
              padding: EdgeInsets.zero,
              onPressed: () => unawaited(ref.read(memoryControllerProvider.notifier).refresh()),
              child: const Icon(CupertinoIcons.arrow_clockwise),
            ),
          ),
          CupertinoSliverRefreshControl(
            onRefresh: () => ref.read(memoryControllerProvider.notifier).refresh(),
          ),
          ..._buildContentSlivers(context, async, response),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // 内容 slivers：加载 / 错误 / 空态 / 单卡片 Tab 视图
  // -------------------------------------------------------------------------

  List<Widget> _buildContentSlivers(
    BuildContext context,
    AsyncValue<MemoryResponse> async,
    MemoryResponse? response,
  ) {
    if (response == null) {
      if (async.isLoading) {
        return const [
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: CupertinoActivityIndicator(radius: 14)),
          ),
        ];
      }
      return [_buildErrorSliver(context, async.error)];
    }

    if (!memoryHasContent(response)) {
      return [_buildEmptySliver(context)];
    }

    final hasProject = showsProjectContext(response);
    final activeTab = (_selectedTab == _MemoryTab.projectContext && !hasProject)
        ? _MemoryTab.memory
        : _selectedTab;
    final l10n = AppLocalizations.of(context);

    return [
      SliverToBoxAdapter(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: CupertinoSlidingSegmentedControl<_MemoryTab>(
                      groupValue: activeTab,
                      onValueChanged: (tab) {
                        if (tab != null) {
                          setState(() => _selectedTab = tab);
                        }
                      },
                      children: {
                        _MemoryTab.memory: Padding(
                          key: const ValueKey('memory-tab-memory'),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          child: Text(l10n.memoryNotesTitle, style: const TextStyle(fontSize: 13)),
                        ),
                        _MemoryTab.user: Padding(
                          key: const ValueKey('memory-tab-user'),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          child: Text(l10n.memoryUserTitle, style: const TextStyle(fontSize: 13)),
                        ),
                        _MemoryTab.soul: Padding(
                          key: const ValueKey('memory-tab-soul'),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          child: Text(l10n.memorySoulTitle, style: const TextStyle(fontSize: 13)),
                        ),
                        if (hasProject)
                          _MemoryTab.projectContext: Padding(
                            key: const ValueKey('memory-tab-project'),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            child: Text(
                              l10n.projectContextTitle,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                      },
                    ),
                  ),
                ),
                _buildActiveCard(context, response, activeTab),
              ],
            ),
          ),
        ),
      ),
    ];
  }

  Widget _buildActiveCard(BuildContext context, MemoryResponse response, _MemoryTab tab) {
    switch (tab) {
      case _MemoryTab.memory:
        final content = response.memory ?? '';
        return CupertinoListSection.insetGrouped(
          header: _MemorySectionHeader(
            section: MemorySection.memory,
            mtime: response.memoryMtime,
            charCount: content.trim().length,
          ),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: _MemorySectionBody(section: MemorySection.memory, content: content),
            ),
          ],
        );
      case _MemoryTab.user:
        final content = response.user ?? '';
        return CupertinoListSection.insetGrouped(
          header: _MemorySectionHeader(
            section: MemorySection.user,
            mtime: response.userMtime,
            charCount: content.trim().length,
          ),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: _MemorySectionBody(section: MemorySection.user, content: content),
            ),
          ],
        );
      case _MemoryTab.soul:
        final content = response.soul ?? '';
        return CupertinoListSection.insetGrouped(
          header: _MemorySectionHeader(
            section: MemorySection.soul,
            mtime: response.soulMtime,
            charCount: content.trim().length,
          ),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: _MemorySectionMarkdownBody(section: MemorySection.soul, content: content),
            ),
          ],
        );
      case _MemoryTab.projectContext:
        final content = response.projectContext ?? '';
        return CupertinoListSection.insetGrouped(
          header: _ProjectContextHeader(
            mtime: response.projectContextMtime,
            charCount: content.trim().length,
          ),
          footer: _ProjectContextFooter(
            detail: memoryProjectContextDetail(response),
            shadowed: response.projectContextShadowed == true,
          ),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: _CollapsibleMarkdownBody(
                data: content.trim(),
                toggleKey: const ValueKey('memory-expand-project'),
              ),
            ),
          ],
        );
    }
  }

  Widget _buildErrorSliver(BuildContext context, Object? error) {
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
              _errorMessage(context, error),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: statusRedText),
            ),
            const SizedBox(height: 20),
            CupertinoButton.filled(
              key: const ValueKey('memory-retry'),
              onPressed: () => unawaited(ref.read(memoryControllerProvider.notifier).refresh()),
              child: Text(l10n.retry),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptySliver(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(CupertinoIcons.doc_text, size: 48, color: CupertinoColors.systemGrey),
            const SizedBox(height: 12),
            Text(l10n.noMemory, style: const TextStyle(fontSize: 17)),
            const SizedBox(height: 6),
            Text(
              l10n.noMemoryContentYet,
              style: const TextStyle(color: secondaryText),
            ),
          ],
        ),
      ),
    );
  }

  String _errorMessage(BuildContext context, Object? error) {
    if (error is ApiException) return error.message;
    return error?.toString() ?? AppLocalizations.of(context).unknownError;
  }
}

String _memorySectionTitle(BuildContext context, MemorySection section) {
  final l10n = AppLocalizations.of(context);
  switch (section) {
    case MemorySection.memory:
      return l10n.memoryNotesTitle;
    case MemorySection.user:
      return l10n.memoryUserTitle;
    case MemorySection.soul:
      return l10n.memorySoulTitle;
  }
}

String _memorySectionEmptyMessage(BuildContext context, MemorySection section) {
  final l10n = AppLocalizations.of(context);
  switch (section) {
    case MemorySection.memory:
      return l10n.memoryNotesEmpty;
    case MemorySection.user:
      return l10n.memoryUserEmpty;
    case MemorySection.soul:
      return l10n.memorySoulEmpty;
  }
}

/// 记忆分区头：图标 + 标题 + 字数 + 相对修改时间。
class _MemorySectionHeader extends StatelessWidget {
  const _MemorySectionHeader({required this.section, required this.mtime, required this.charCount});

  final MemorySection section;
  final double? mtime;
  final int charCount;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final modified = formatMemoryMtime(mtime);
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          Icon(_memorySectionIcon(section), size: 15, color: CupertinoColors.label),
          const SizedBox(width: 6),
          Text(
            _memorySectionTitle(context, section),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          if (charCount > 0)
            Text(
              '$charCount ${l10n.memoryCharUnit}',
              style: const TextStyle(color: secondaryText),
            ),
          if (modified != null) ...[
            const SizedBox(width: 6),
            Text(
              modified,
              style: const TextStyle(color: secondaryText),
            ),
          ],
        ],
      ),
    );
  }

  static IconData _memorySectionIcon(MemorySection section) {
    switch (section) {
      case MemorySection.memory:
        return CupertinoIcons.doc_text;
      case MemorySection.user:
        return CupertinoIcons.person;
      case MemorySection.soul:
        return CupertinoIcons.sparkles;
    }
  }
}

/// 分区内容（纯文本）：非空 → 正文（长文折叠）；空 → 斜体占位文案。
class _MemorySectionBody extends StatelessWidget {
  const _MemorySectionBody({required this.section, required this.content});

  final MemorySection section;
  final String content;

  @override
  Widget build(BuildContext context) {
    final trimmed = content.trim();
    if (trimmed.isEmpty) {
      return Text(
        _memorySectionEmptyMessage(context, section),
        style: const TextStyle(
          fontSize: 15,
          fontStyle: FontStyle.italic,
          color: secondaryText,
        ),
      );
    }
    return _CollapsibleBodyText(
      text: trimmed,
      style: const TextStyle(fontSize: 15, height: 1.4),
      toggleKey: ValueKey('memory-expand-${section.name}'),
    );
  }
}

/// 分区内容（Markdown）：非空 → Markdown 渲染（长文折叠）；空 → 斜体占位文案。
class _MemorySectionMarkdownBody extends StatelessWidget {
  const _MemorySectionMarkdownBody({required this.section, required this.content});

  final MemorySection section;
  final String content;

  @override
  Widget build(BuildContext context) {
    final trimmed = content.trim();
    if (trimmed.isEmpty) {
      return Text(
        _memorySectionEmptyMessage(context, section),
        style: const TextStyle(
          fontSize: 15,
          fontStyle: FontStyle.italic,
          color: secondaryText,
        ),
      );
    }
    return _CollapsibleMarkdownBody(
      data: trimmed,
      toggleKey: ValueKey('memory-expand-${section.name}'),
    );
  }
}

/// 正文折叠块（纯文本）：超出 [kCollapsedLines] 行显示「展开全文」，点击展开/收起；
/// 短文本不显示切换按钮，保持全量展示。
class _CollapsibleBodyText extends StatefulWidget {
  const _CollapsibleBodyText({required this.text, required this.style, this.toggleKey});

  final String text;
  final TextStyle style;
  final Key? toggleKey;

  @override
  State<_CollapsibleBodyText> createState() => _CollapsibleBodyTextState();
}

class _CollapsibleBodyTextState extends State<_CollapsibleBodyText> {
  static const int kCollapsedLines = 5;

  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final foldable = _isFoldable(context, widget.text, widget.style, constraints.maxWidth);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.text,
              style: widget.style,
              maxLines: _expanded ? null : kCollapsedLines,
              overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
            ),
            if (foldable) ...[
              const SizedBox(height: 8),
              AccessibleButton(
                key: widget.toggleKey,
                label: _expanded ? l10n.collapseText : l10n.expandText,
                padding: const EdgeInsets.symmetric(vertical: 2),
                onPressed: () => setState(() => _expanded = !_expanded),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _expanded ? l10n.collapseText : l10n.expandText,
                      style: const TextStyle(fontSize: 13, color: statusBlueText),
                    ),
                    const SizedBox(width: 2),
                    Icon(
                      _expanded ? CupertinoIcons.chevron_up : CupertinoIcons.chevron_down,
                      size: 12,
                      color: statusBlueText,
                    ),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  bool _isFoldable(BuildContext context, String text, TextStyle style, double maxWidth) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: kCollapsedLines,
      textDirection: Directionality.of(context),
    )..layout(maxWidth: maxWidth);
    return painter.didExceedMaxLines;
  }
}

/// Markdown 正文折叠块：超出 [kCollapsedMarkdownHeight] 像素显示「展开全文」，点击展开/收起；
/// 短文本不显示切换按钮，保持全量展示。
class _CollapsibleMarkdownBody extends StatefulWidget {
  const _CollapsibleMarkdownBody({required this.data, this.toggleKey});

  final String data;
  final Key? toggleKey;

  @override
  State<_CollapsibleMarkdownBody> createState() => _CollapsibleMarkdownBodyState();
}

class _CollapsibleMarkdownBodyState extends State<_CollapsibleMarkdownBody> {
  static const double kCollapsedMarkdownHeight = 200.0;
  static const int kCollapsedLines = 5;

  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final foldable = _isFoldable(context, widget.data, constraints.maxWidth);
        final markdownWidget = MarkdownBody(
          data: widget.data,
          styleSheet: _buildMarkdownStyleSheet(context),
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!foldable || _expanded)
              markdownWidget
            else
              ClipRect(
                child: SizedBox(
                  height: kCollapsedMarkdownHeight,
                  child: OverflowBox(
                    alignment: Alignment.topCenter,
                    minWidth: 0,
                    maxWidth: constraints.maxWidth,
                    minHeight: 0,
                    maxHeight: double.infinity,
                    child: markdownWidget,
                  ),
                ),
              ),
            if (foldable) ...[
              const SizedBox(height: 8),
              AccessibleButton(
                key: widget.toggleKey,
                label: _expanded ? l10n.collapseText : l10n.expandText,
                padding: const EdgeInsets.symmetric(vertical: 2),
                onPressed: () => setState(() => _expanded = !_expanded),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _expanded ? l10n.collapseText : l10n.expandText,
                      style: const TextStyle(fontSize: 13, color: statusBlueText),
                    ),
                    const SizedBox(width: 2),
                    Icon(
                      _expanded ? CupertinoIcons.chevron_up : CupertinoIcons.chevron_down,
                      size: 12,
                      color: statusBlueText,
                    ),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  bool _isFoldable(BuildContext context, String text, double maxWidth) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: const TextStyle(fontSize: 15, height: 1.4)),
      maxLines: kCollapsedLines,
      textDirection: Directionality.of(context),
    )..layout(maxWidth: maxWidth);
    return painter.didExceedMaxLines;
  }
}

/// Markdown 样式：以 Cupertino 主题为基底，显式配置正文语义色 label。
MarkdownStyleSheet _buildMarkdownStyleSheet(BuildContext context) {
  final theme = CupertinoTheme.of(context);
  final label = CupertinoColors.label.resolveFrom(context);
  final grey5 = CupertinoColors.systemGrey5.resolveFrom(context);
  return MarkdownStyleSheet.fromCupertinoTheme(theme).copyWith(
    p: theme.textTheme.textStyle.copyWith(
      fontSize: 15,
      height: 1.4,
      color: label,
    ),
    listBullet: theme.textTheme.textStyle.copyWith(
      fontSize: 15,
      color: label,
    ),
    code: TextStyle(
      fontSize: 13,
      fontFamily: 'monospace',
      color: label,
      backgroundColor: grey5,
    ),
    codeblockDecoration: BoxDecoration(
      color: grey5,
      borderRadius: BorderRadius.circular(6),
    ),
    blockquoteDecoration: BoxDecoration(
      color: grey5,
      borderRadius: BorderRadius.circular(6),
    ),
    blockquotePadding: const EdgeInsets.all(8),
  );
}

/// 项目上下文分区头：图标 + 标题 + 字数 + 修改时间 + 只读锁。
class _ProjectContextHeader extends StatelessWidget {
  const _ProjectContextHeader({required this.mtime, required this.charCount});

  final double? mtime;
  final int charCount;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final modified = formatMemoryMtime(mtime);
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          const Icon(CupertinoIcons.folder, size: 15, color: CupertinoColors.label),
          const SizedBox(width: 6),
          Text(
            l10n.projectContextTitle,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          if (charCount > 0)
            Text(
              '$charCount ${l10n.memoryCharUnit}',
              style: const TextStyle(color: secondaryText),
            ),
          if (modified != null) ...[
            const SizedBox(width: 6),
            Text(
              modified,
              style: const TextStyle(color: secondaryText),
            ),
            const SizedBox(width: 8),
          ],
          const Icon(CupertinoIcons.lock_fill, size: 13, color: CupertinoColors.secondaryLabel),
        ],
      ),
    );
  }
}

/// 项目上下文分区尾：明细行「名称 — 工作区」+ 覆盖警告
/// （对齐 Hermex ProjectContextSectionFooter）。
class _ProjectContextFooter extends StatelessWidget {
  const _ProjectContextFooter({required this.detail, required this.shadowed});

  final String? detail;
  final bool shadowed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (detail != null)
          Text(
            detail!,
            style: const TextStyle(color: secondaryText),
          ),
        if (shadowed) ...[
          const SizedBox(height: 4),
          Text(
            l10n.projectContextShadowedWarning,
            style: const TextStyle(color: secondaryText),
          ),
        ],
      ],
    );
  }
}
