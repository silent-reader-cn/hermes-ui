import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/status_colors.dart';
import '../../core/api/api_exception.dart';
import '../../core/connections/connection_providers.dart';
import '../../core/models/workspace.dart';
import '../../l10n/app_localizations.dart';
import '../shared/app_back_button.dart';
import '../workspace/workspace_api.dart';
import '../workspace/workspace_providers.dart';

/// 文件预览类型（镜像 WebUI `workspace.js:811-820` 的扩展名白名单思路）。
enum WorkspaceFileKind {
  /// 文本（代码/标记/纯文本），走 /api/file 文本预览。
  text,

  /// 图片，走 /api/file/raw 原始字节。
  image,

  /// 音视频（内嵌播放器后置，当前走下载兜底）。
  video,

  /// 音频（内嵌播放器后置，当前走下载兜底）。
  audio,

  /// PDF（内置渲染器后置，当前走下载兜底）。
  pdf,

  /// 归档/二进制黑名单（zip 等，点击直接下载）。
  archive,

  /// 其他未知类型（不猜测，走下载兜底）。
  other,
}

const Set<String> _textExts = {
  '.md',
  '.markdown',
  '.txt',
  '.text',
  '.log',
  '.dart',
  '.py',
  '.js',
  '.jsx',
  '.ts',
  '.tsx',
  '.json',
  '.yaml',
  '.yml',
  '.toml',
  '.ini',
  '.cfg',
  '.conf',
  '.sh',
  '.bash',
  '.bat',
  '.cmd',
  '.ps1',
  '.xml',
  '.html',
  '.htm',
  '.css',
  '.scss',
  '.sql',
  '.java',
  '.go',
  '.rs',
  '.c',
  '.cpp',
  '.h',
  '.rb',
  '.php',
  '.kt',
  '.swift',
  '.gradle',
  '.lock',
  '.env',
  '.gitignore',
  '.gitattributes',
  '.editorconfig',
  '.svg',
};

const Set<String> _imageExts = {
  '.png',
  '.jpg',
  '.jpeg',
  '.gif',
  '.webp',
  '.bmp',
  '.ico',
};

const Set<String> _videoExts = {
  '.mp4',
  '.mov',
  '.webm',
  '.mkv',
  '.avi',
  '.m4v',
};

const Set<String> _audioExts = {
  '.mp3',
  '.wav',
  '.m4a',
  '.aac',
  '.ogg',
  '.flac',
  '.opus',
};

const Set<String> _pdfExts = {'.pdf'};

/// 归档/二进制「下载优先」扩展名。
const Set<String> _archiveExts = {
  '.zip',
  '.tar',
  '.gz',
  '.tgz',
  '.bz2',
  '.tbz2',
  '.xz',
  '.txz',
  '.7z',
  '.rar',
  '.iso',
  '.exe',
  '.msi',
  '.dmg',
  '.pkg',
  '.apk',
  '.aab',
  '.ipa',
  '.dll',
  '.so',
  '.dylib',
  '.bin',
  '.dat',
  '.db',
  '.sqlite',
  '.sqlite3',
  '.woff',
  '.woff2',
  '.ttf',
  '.otf',
};

/// 按扩展名判定文件预览类型。
WorkspaceFileKind workspaceFileKindOf(WorkspaceEntry entry) {
  final name = (entry.name ?? entry.path ?? '').toLowerCase();
  if (_imageExts.any(name.endsWith)) return WorkspaceFileKind.image;
  if (_videoExts.any(name.endsWith)) return WorkspaceFileKind.video;
  if (_audioExts.any(name.endsWith)) return WorkspaceFileKind.audio;
  if (_pdfExts.any(name.endsWith)) return WorkspaceFileKind.pdf;
  if (_archiveExts.any(name.endsWith)) return WorkspaceFileKind.archive;
  if (_textExts.any(name.endsWith)) return WorkspaceFileKind.text;
  return WorkspaceFileKind.other;
}

/// 是否可在应用内预览（文本/图片）；其余类型走下载兜底。
bool workspaceFileIsPreviewable(WorkspaceEntry entry) {
  final kind = workspaceFileKindOf(entry);
  return kind == WorkspaceFileKind.text || kind == WorkspaceFileKind.image;
}

/// 文件预览页（push 进入，参数 `{sessionId, entry}`）。
///
/// - 文本（.md/.txt/.dart/...）：GET /api/file → SelectableText（monospace），
///   `.md` 用 flutter_markdown 富渲染（沿用 chat 的 Cupertino theme 化样式）；
/// - 图片：GET /api/file/raw → Image.memory（InteractiveViewer 缩放）；
/// - 音视频/PDF/归档/未知：展示「无法预览」+ 下载兜底（播放器/渲染器后置）；
/// - 加载失败：statusRedText 错误详情 + 重试 + 「改用下载」兜底。
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

  bool _loading = true;
  Object? _loadError;

  /// 文本内容响应（仅 text 类型）。
  FileResponse? _file;

  /// 图片原始字节（仅 image 类型）。
  Uint8List? _imageBytes;

  bool _downloading = false;

  WorkspaceApi get _api =>
      ref.read(workspaceApiFactoryProvider)(ref.read(apiClientProvider));

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      if (_kind == WorkspaceFileKind.text) {
        final response = await _api.fetchFileContent(
          sessionId: widget.sessionId,
          path: widget.entry.path ?? '',
        );
        if (!mounted) return;
        setState(() {
          _file = response;
          _loading = false;
        });
      } else if (_kind == WorkspaceFileKind.image) {
        final bytes = await _api.downloadFile(
          sessionId: widget.sessionId,
          path: widget.entry.path ?? '',
        );
        if (!mounted) return;
        setState(() {
          _imageBytes = bytes;
          _loading = false;
        });
      } else {
        // 音视频/PDF/归档/未知：无内嵌渲染器，直接展示下载兜底视图。
        setState(() => _loading = false);
      }
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return CupertinoPageScaffold(
      child: CustomScrollView(
        key: const ValueKey('preview-scroll'),
        slivers: [
          CupertinoSliverNavigationBar(
            largeTitle: Text(widget.entry.name ?? l10n.unnamedFile),
            middle: Text(widget.entry.name ?? l10n.unnamedFile),
            leading: const AppBackButton(),
            trailing: _DownloadButton(
              downloading: _downloading,
              onPressed: () => unawaited(_onDownload()),
            ),
          ),
          ..._buildContentSlivers(),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }

  List<Widget> _buildContentSlivers() {
    final l10n = AppLocalizations.of(context);
    if (_loading) {
      return const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: CupertinoActivityIndicator(radius: 14)),
        ),
      ];
    }
    final error = _loadError;
    if (error != null) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: _buildFallback(
            message: error is ApiException ? error.message : error.toString(),
            onRetry: () => unawaited(_load()),
          ),
        ),
      ];
    }

    switch (_kind) {
      case WorkspaceFileKind.text:
        return [_buildTextSliver()];
      case WorkspaceFileKind.image:
        final bytes = _imageBytes;
        if (bytes == null || bytes.isEmpty) {
          return [_buildUnsupportedSliver()];
        }
        return [
          SliverToBoxAdapter(
            child: Center(
              child: InteractiveViewer(
                key: const ValueKey('preview-image-viewer'),
                minScale: 0.5,
                maxScale: 4,
                child: Image.memory(
                  bytes,
                  key: const ValueKey('preview-image'),
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) =>
                      _buildUnsupportedBody(l10n),
                ),
              ),
            ),
          ),
        ];
      case WorkspaceFileKind.video:
      case WorkspaceFileKind.audio:
      case WorkspaceFileKind.pdf:
      case WorkspaceFileKind.archive:
      case WorkspaceFileKind.other:
        return [_buildUnsupportedSliver()];
    }
  }

  Widget _buildTextSliver() {
    final l10n = AppLocalizations.of(context);
    final file = _file;
    final serverError = file?.error;
    if (serverError != null && serverError.isNotEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: _buildFallback(
          message: serverError,
          onRetry: () => unawaited(_load()),
        ),
      );
    }
    final name = (widget.entry.name ?? '').toLowerCase();
    final content = file?.content ?? '';
    final isMarkdown = name.endsWith('.md') || name.endsWith('.markdown');
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      sliver: SliverToBoxAdapter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildMetaLine(l10n, file),
            const SizedBox(height: 8),
            if (isMarkdown)
              MarkdownBody(
                key: const ValueKey('preview-markdown'),
                data: content,
                selectable: true,
                styleSheet: MarkdownStyleSheet.fromCupertinoTheme(
                  CupertinoTheme.of(context),
                ),
              )
            else
              Text(
                content.isEmpty ? l10n.emptyFile : content,
                key: const ValueKey('preview-text'),
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetaLine(AppLocalizations l10n, FileResponse? file) {
    final parts = <String>[
      if (file?.size != null) '${file!.size} B',
      if (file?.lines != null) '${file!.lines} ${l10n.linesShort}',
      if (file?.truncated == true) l10n.previewTruncated,
    ];
    if (parts.isEmpty) return const SizedBox.shrink();
    return Text(
      parts.join(' · '),
      style: const TextStyle(fontSize: 12, color: secondaryText),
    );
  }

  Widget _buildUnsupportedSliver() {
    final l10n = AppLocalizations.of(context);
    return SliverFillRemaining(
      hasScrollBody: false,
      child: _buildUnsupportedBody(l10n),
    );
  }

  Widget _buildUnsupportedBody(AppLocalizations l10n) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              CupertinoIcons.doc_plaintext,
              size: 48,
              color: CupertinoColors.systemGrey,
            ),
            const SizedBox(height: 12),
            Text(
              l10n.previewUnavailable,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              l10n.previewUnavailableHint,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: secondaryText),
            ),
            const SizedBox(height: 20),
            CupertinoButton.filled(
              key: const ValueKey('preview-download-fallback'),
              onPressed: _downloading ? null : () => unawaited(_onDownload()),
              child: Text(l10n.download),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFallback({
    required String message,
    required VoidCallback onRetry,
  }) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: statusRedText),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CupertinoButton.filled(
                  key: const ValueKey('preview-retry'),
                  onPressed: onRetry,
                  child: Text(l10n.retry),
                ),
                const SizedBox(width: 12),
                CupertinoButton(
                  key: const ValueKey('preview-download-fallback'),
                  onPressed: _downloading
                      ? null
                      : () => unawaited(_onDownload()),
                  child: Text(l10n.download),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _onDownload() async {
    if (_downloading) return;
    final path = widget.entry.path;
    if (path == null || path.isEmpty) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _downloading = true);
    try {
      final bytes = await _api.downloadFile(
        sessionId: widget.sessionId,
        path: path,
      );
      if (!mounted) return;
      setState(() => _downloading = false);
      await _showInfoDialog(
        l10n.download,
        '已下载「${widget.entry.name ?? path}」（${bytes.length} 字节），'
        '保存到本地待平台通道接入。',
      );
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
