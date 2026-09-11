import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/widgets/adaptive_sliver_navigation_bar.dart';
import '../../core/api/api_exception.dart';
import '../../core/api/endpoints.dart';
import '../../core/connections/connection_providers.dart';
import '../../core/models/workspace.dart';
import '../../l10n/app_localizations.dart';
import '../downloads/download_confirm_dialog.dart';
import '../downloads/download_providers.dart';
import '../shared/app_back_button.dart';
import 'file_preview_body.dart';

export 'file_preview_body.dart';

/// 文件预览页（push 进入，参数 `{sessionId, entry}`）。
///
/// 作为展示容器薄壳，渲染正文委托至 [FilePreviewBody]；
/// 页面层负责头部导航条、下载入队弹窗以及针对 PDF/图片的锁滚手势处理。
class FilePreviewPage extends ConsumerStatefulWidget {
  const FilePreviewPage({
    super.key,
    required this.sessionId,
    required this.entry,
  });

  /// 会话 ID（端点以它定位工作区根）。
  final String sessionId;

  /// 待预览条目（name/path/size）。
  final WorkspaceEntry entry;

  @override
  ConsumerState<FilePreviewPage> createState() => _FilePreviewPageState();
}

class _FilePreviewPageState extends ConsumerState<FilePreviewPage> {
  late final WorkspaceFileKind _kind = workspaceFileKindOf(widget.entry);
  bool _downloading = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // PDF/图片预览自带滚动（pdfrx 内滚 / InteractiveViewer）。外层
    // CustomScrollView 在 iOS 回弹物理下仍会吃掉纵向拖拽做整页 overscroll
    // bounce（用户感知为「滚了外面容器、PDF 不动」），这两类锁死外层。
    final outerScrollable =
        _kind != WorkspaceFileKind.pdf && _kind != WorkspaceFileKind.image;
    final fileName = widget.entry.name ?? widget.entry.path ?? '';
    final body = FilePreviewBody(
      fileName: fileName,
      sizeBytes: widget.entry.size,
      source: FilePreviewSource.workspaceFile(
        widget.sessionId,
        widget.entry.path ?? '',
      ),
      onDownload: () => unawaited(_onDownload()),
    );

    return CupertinoPageScaffold(
      child: CustomScrollView(
        key: const ValueKey('preview-scroll'),
        physics: outerScrollable ? null : const NeverScrollableScrollPhysics(),
        slivers: [
          AdaptiveSliverNavigationBar(
            title: widget.entry.name ?? l10n.unnamedFile,
            alwaysCollapsed: true,
            leading: const AppBackButton(),
            trailing: _DownloadButton(
              downloading: _downloading,
              onPressed: () => unawaited(_onDownload()),
            ),
          ),
          if (_kind == WorkspaceFileKind.pdf ||
              _kind == WorkspaceFileKind.image)
            SliverFillRemaining(
              hasScrollBody: false,
              child: SizedBox.expand(child: body),
            )
          else
            SliverToBoxAdapter(child: body),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }

  Future<void> _onDownload() async {
    if (_downloading) return;
    final path = widget.entry.path;
    if (path == null || path.isEmpty) return;

    final fileName = widget.entry.name ?? path.split('/').last;

    final modifiedAt = widget.entry.mtimeNs != null
        ? widget.entry.mtimeNs! / 1e9
        : widget.entry.modified;
    final confirmed = await showDownloadConfirmationDialog(
      context,
      fileName: fileName,
      mimeType: widget.entry.type,
      expectedBytes: widget.entry.size,
      sessionId: widget.sessionId,
      modifiedAtSeconds: modifiedAt,
    );
    if (confirmed != true || !mounted) return;

    final l10n = AppLocalizations.of(context);
    setState(() => _downloading = true);
    try {
      final client = ref.read(apiClientProvider);
      final rawUrl = Endpoint.rawFile(
        sessionId: widget.sessionId,
        path: path,
      ).url(client.baseUrl).toString();

      await ref
          .read(downloadControllerProvider.notifier)
          .enqueue(
            sourceUrl: rawUrl,
            fileName: fileName,
            mimeType: widget.entry.type,
            expectedBytes: widget.entry.size,
            sessionId: widget.sessionId,
          );
      if (!mounted) return;
      setState(() => _downloading = false);
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() => _downloading = false);
      final message = error is ApiException ? error.message : error.toString();
      await _showInfoDialog(l10n.actionFailed, message);
    }
  }

  Future<void> _showInfoDialog(String title, String message) {
    final l10n = AppLocalizations.of(context);
    return showCupertinoDialog<void>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            key: const ValueKey('preview-dialog-ok'),
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.ok),
          ),
        ],
      ),
    );
  }
}

/// 导航栏下载按钮（下载中显示 ActivityIndicator）。
class _DownloadButton extends StatelessWidget {
  const _DownloadButton({required this.downloading, required this.onPressed});

  final bool downloading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    if (downloading) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 8),
        child: CupertinoActivityIndicator(radius: 10),
      );
    }
    return CupertinoButton(
      key: const ValueKey('preview-download'),
      padding: EdgeInsets.zero,
      onPressed: onPressed,
      child: const Icon(CupertinoIcons.arrow_down_doc),
    );
  }
}
