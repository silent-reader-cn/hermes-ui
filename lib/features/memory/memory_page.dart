import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/models/memory.dart';
import '../../core/utils/accessibility.dart';
import '../../app/theme/status_colors.dart';
import '../../l10n/app_localizations.dart';
import '../shared/app_back_button.dart';
import 'memory_providers.dart';

/// 记忆查看页（对齐 Hermex MemoryView 的只读浏览形态）。
///
/// Cupertino 风格：大标题 + 刷新按钮 + 下拉刷新；按 [MemoryResponse] 的
/// 分区结构展示（我的笔记 / 用户画像 / 智能体灵魂 / 项目上下文），
/// 分区空内容显示占位文案，项目上下文带只读锁与覆盖警告；
/// 含加载 / 错误 / 空态。
class MemoryPage extends ConsumerWidget {
  const MemoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
              onPressed: () => unawaited(
                ref.read(memoryControllerProvider.notifier).refresh(),
              ),
              child: const Icon(CupertinoIcons.arrow_clockwise),
            ),
          ),
          CupertinoSliverRefreshControl(
            onRefresh: () =>
                ref.read(memoryControllerProvider.notifier).refresh(),
          ),
          ..._buildContentSlivers(context, ref, async, response),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // 内容 slivers：加载 / 错误 / 空态 / 分区列表
  // -------------------------------------------------------------------------

  List<Widget> _buildContentSlivers(
    BuildContext context,
    WidgetRef ref,
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
      return [_buildErrorSliver(context, ref, async.error)];
    }

    if (!memoryHasContent(response)) {
      return [_buildEmptySliver(context)];
    }

    return [
      for (final section in MemorySection.values)
        SliverToBoxAdapter(
          child: CupertinoListSection.insetGrouped(
            header: _MemorySectionHeader(
              section: section,
              mtime: _sectionMtime(response, section),
            ),
            children: [
              _MemorySectionBody(
                section: section,
                content: _sectionContent(response, section),
              ),
            ],
          ),
        ),
      if (showsProjectContext(response))
        SliverToBoxAdapter(
          child: CupertinoListSection.insetGrouped(
            header: _ProjectContextHeader(mtime: response.projectContextMtime),
            footer: _ProjectContextFooter(
              detail: memoryProjectContextDetail(response),
              shadowed: response.projectContextShadowed == true,
            ),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  response.projectContext!.trim(),
                  style: const TextStyle(fontSize: 15, height: 1.4),
                ),
              ),
            ],
          ),
        ),
    ];
  }

  Widget _buildErrorSliver(BuildContext context, WidgetRef ref, Object? error) {
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
              style: const TextStyle(
                fontSize: 13,
                color: statusRedText,
              ),
            ),
            const SizedBox(height: 20),
            CupertinoButton.filled(
              key: const ValueKey('memory-retry'),
              onPressed: () => unawaited(
                ref.read(memoryControllerProvider.notifier).refresh(),
              ),
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
            const Icon(
              CupertinoIcons.doc_text,
              size: 48,
              color: CupertinoColors.systemGrey,
            ),
            const SizedBox(height: 12),
            Text(l10n.noMemory, style: const TextStyle(fontSize: 17)),
            const SizedBox(height: 6),
            Text(
              l10n.noMemoryContentYet,
              style: const TextStyle(
                fontSize: 13,
                color: CupertinoColors.secondaryLabel,
              ),
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

  String _sectionContent(MemoryResponse response, MemorySection section) {
    switch (section) {
      case MemorySection.memory:
        return response.memory ?? '';
      case MemorySection.user:
        return response.user ?? '';
      case MemorySection.soul:
        return response.soul ?? '';
    }
  }

  double? _sectionMtime(MemoryResponse response, MemorySection section) {
    switch (section) {
      case MemorySection.memory:
        return response.memoryMtime;
      case MemorySection.user:
        return response.userMtime;
      case MemorySection.soul:
        return response.soulMtime;
    }
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

/// 记忆分区头：图标 + 标题 + 相对修改时间。
class _MemorySectionHeader extends StatelessWidget {
  const _MemorySectionHeader({required this.section, required this.mtime});

  final MemorySection section;
  final double? mtime;

  @override
  Widget build(BuildContext context) {
    final modified = formatMemoryMtime(mtime);
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          Icon(
            _memorySectionIcon(section),
            size: 15,
            color: CupertinoColors.label,
          ),
          const SizedBox(width: 6),
          Text(
            _memorySectionTitle(context, section),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          if (modified != null)
            Text(
              modified,
              style: const TextStyle(
                fontSize: 12,
                color: CupertinoColors.secondaryLabel,
              ),
            ),
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

/// 分区内容：非空 → 正文；空 → 斜体占位文案。
class _MemorySectionBody extends StatelessWidget {
  const _MemorySectionBody({required this.section, required this.content});

  final MemorySection section;
  final String content;

  @override
  Widget build(BuildContext context) {
    final trimmed = content.trim();
    if (trimmed.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          _memorySectionEmptyMessage(context, section),
          style: const TextStyle(
            fontSize: 15,
            fontStyle: FontStyle.italic,
            color: CupertinoColors.secondaryLabel,
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(trimmed, style: const TextStyle(fontSize: 15, height: 1.4)),
    );
  }
}

/// 项目上下文分区头：图标 + 标题 + 修改时间 + 只读锁。
class _ProjectContextHeader extends StatelessWidget {
  const _ProjectContextHeader({required this.mtime});

  final double? mtime;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final modified = formatMemoryMtime(mtime);
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          const Icon(
            CupertinoIcons.folder,
            size: 15,
            color: CupertinoColors.label,
          ),
          const SizedBox(width: 6),
          Text(
            l10n.projectContextTitle,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          if (modified != null) ...[
            Text(
              modified,
              style: const TextStyle(
                fontSize: 12,
                color: CupertinoColors.secondaryLabel,
              ),
            ),
            const SizedBox(width: 8),
          ],
          const Icon(
            CupertinoIcons.lock_fill,
            size: 13,
            color: CupertinoColors.secondaryLabel,
          ),
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
            style: const TextStyle(
              fontSize: 12,
              color: CupertinoColors.secondaryLabel,
            ),
          ),
        if (shadowed) ...[
          const SizedBox(height: 4),
          Text(
            l10n.projectContextShadowedWarning,
            style: const TextStyle(
              fontSize: 12,
              color: CupertinoColors.secondaryLabel,
            ),
          ),
        ],
      ],
    );
  }
}
