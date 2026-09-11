import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show SelectableText;
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../app/theme/status_colors.dart';
import '../../app/widgets/adaptive_sliver_navigation_bar.dart';
import '../../core/api/api_exception.dart';
import '../../core/api/endpoints.dart';
import '../../core/connections/connection_providers.dart';
import '../../core/models/workspace.dart';
import '../../l10n/app_localizations.dart';
import '../chat/widgets/markdown_styles.dart';
import '../downloads/download_confirm_dialog.dart';
import '../downloads/download_providers.dart';
import '../shared/app_back_button.dart';
import '../workspace/workspace_api.dart';
import '../workspace/workspace_providers.dart';

import 'package:pdfrx/pdfrx.dart';

import 'office_document.dart';

/// 文件预览类型（镜像 WebUI `workspace.js:811-820` 的扩展名白名单思路）。
enum WorkspaceFileKind {
  /// 文本（代码/标记/纯文本），走 /api/file 文本预览。
  text,

  /// 图片，走 /api/file/raw 原始字节。
  image,

  /// 视频，media_kit 内存字节播放（mp4/mov/webm/mkv/avi/m4v）。
  video,

  /// 音频，media_kit 内存字节播放（mp3/wav/m4a/aac/ogg/flac/opus）。
  audio,

  /// PDF（pdfrx 内嵌渲染）。
  pdf,

  /// Office 文档（docx/xlsx/pptx/doc/xls/ppt）。
  office,

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
  '.csv',
  '.tsv',
  '.rtf',
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

const Set<String> _officeExts = {
  '.docx',
  '.xlsx',
  '.pptx',
  '.doc',
  '.xls',
  '.ppt',
};

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
  if (_officeExts.any(name.endsWith)) return WorkspaceFileKind.office;
  if (_archiveExts.any(name.endsWith)) return WorkspaceFileKind.archive;
  if (_textExts.any(name.endsWith)) return WorkspaceFileKind.text;
  return WorkspaceFileKind.other;
}

/// 是否可在应用内预览（文本/图片/音视频/PDF/Office）；其余类型走下载兜底。
bool workspaceFileIsPreviewable(WorkspaceEntry entry) {
  final kind = workspaceFileKindOf(entry);
  return kind == WorkspaceFileKind.text ||
      kind == WorkspaceFileKind.image ||
      kind == WorkspaceFileKind.video ||
      kind == WorkspaceFileKind.audio ||
      kind == WorkspaceFileKind.pdf ||
      kind == WorkspaceFileKind.office;
}

/// 文件预览页（push 进入，参数 `{sessionId, entry}`）。
///
/// - 文本（.md/.txt/.dart/...）：GET /api/file → SelectableText（monospace），
///   `.md` 用 flutter_markdown 富渲染（沿用 chat 的 Cupertino theme 化样式）；
/// - 图片：GET /api/file/raw → Image.memory（InteractiveViewer 缩放）；
/// - 音视频：GET /api/file/raw → 临时文件 + media_kit Player（Cupertino 播放控件）；
/// - PDF/归档/未知：展示「无法预览」+ 下载兜底（播放器/渲染器后置）；
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

  /// 音视频临时文件路径（video/audio）。
  String? _mediaTempPath;

  /// PDF 临时文件路径。
  String? _pdfTempPath;

  /// Office 解析文档结果。
  OfficeDocument? _officeDocument;

  /// xlsx 当前选中的 sheet 索引。
  int _selectedSheetIndex = 0;

  /// 音视频播放器（video/audio 共用 media_kit；null = 未初始化或失败）。
  Player? _player;
  VideoController? _videoController;

  bool _downloading = false;

  WorkspaceApi get _api =>
      ref.read(workspaceApiFactoryProvider)(ref.read(apiClientProvider));

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    unawaited(_disposeMedia());
    super.dispose();
  }

  Future<void> _disposeMedia() async {
    final player = _player;
    _videoController = null;
    _player = null;
    // VideoController 随 Player 释放自动清理（见 VideoController 构造中的
    // player.platform?.release 监听）；此处仅释放 Player。
    try {
      await player?.dispose();
    } catch (_) {}
    final tempPath = _mediaTempPath;
    _mediaTempPath = null;
    if (tempPath != null) {
      try {
        final file = File(tempPath);
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
    final pdfTempPath = _pdfTempPath;
    _pdfTempPath = null;
    if (pdfTempPath != null) {
      try {
        final file = File(pdfTempPath);
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
  }

  Future<void> _load() async {
    // 切换重载时先释放旧的音视频/PDF资源。
    await _disposeMedia();
    if (!mounted) return;
    setState(() {
      _loading = true;
      _loadError = null;
      _mediaTempPath = null;
      _pdfTempPath = null;
      _officeDocument = null;
      _selectedSheetIndex = 0;
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
      } else if (_kind == WorkspaceFileKind.video ||
          _kind == WorkspaceFileKind.audio) {
        final bytes = await _api.downloadFile(
          sessionId: widget.sessionId,
          path: widget.entry.path ?? '',
        );
        if (!mounted) return;
        if (bytes.isEmpty) {
          setState(() => _loading = false);
          return;
        }
        // bytes → 临时文件 → media_kit Player（mpv 解码；扩展名决定 mime）。
        final ext = _extOf(widget.entry.name ?? widget.entry.path ?? '');
        final tempDir = Directory.systemTemp;
        final tempFile = File(
          '${tempDir.path}/hermes_preview_${DateTime.now().millisecondsSinceEpoch}$ext',
        );
        await tempFile.writeAsBytes(bytes, flush: true);
        final player = Player();
        final controller = _kind == WorkspaceFileKind.video
            ? VideoController(player)
            : null;
        // 先挂载到 state 再 open，避免 open 期间 setState 丢引用。
        setState(() {
          _mediaTempPath = tempFile.path;
          _player = player;
          _videoController = controller;
        });
        await player.open(Media(tempFile.path));
        if (!mounted) return;
        setState(() => _loading = false);
      } else if (_kind == WorkspaceFileKind.pdf) {
        final bytes = await _api.downloadFile(
          sessionId: widget.sessionId,
          path: widget.entry.path ?? '',
        );
        if (!mounted) return;
        if (bytes.isEmpty) {
          setState(() {
            _loading = false;
            _loadError = const FormatException('Empty PDF file');
          });
          return;
        }
        final tempDir = Directory.systemTemp;
        final tempFile = File(
          '${tempDir.path}/hermes_preview_${DateTime.now().millisecondsSinceEpoch}.pdf',
        );
        await tempFile.writeAsBytes(bytes, flush: true);
        if (!mounted) {
          try {
            if (await tempFile.exists()) await tempFile.delete();
          } catch (_) {}
          return;
        }
        setState(() {
          _pdfTempPath = tempFile.path;
          _loading = false;
        });
      } else if (_kind == WorkspaceFileKind.office) {
        final bytes = await _api.downloadFile(
          sessionId: widget.sessionId,
          path: widget.entry.path ?? '',
        );
        if (!mounted) return;
        if (bytes.isEmpty) {
          throw const OfficeParseException('Empty office file');
        }
        final ext = _extOf(widget.entry.name ?? widget.entry.path ?? '');
        final doc = OfficeDocumentParser.parse(bytes, ext);
        if (!mounted) return;
        setState(() {
          _officeDocument = doc;
          _loading = false;
        });
      } else {
        // 归档/未知：无内嵌渲染器，直接展示下载兜底视图。
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

  static String _extOf(String name) {
    final idx = name.lastIndexOf('.');
    if (idx < 0) return '';
    return name.substring(idx).toLowerCase();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // PDF/图片预览自带滚动（pdfrx 内滚 / InteractiveViewer）。外层
    // CustomScrollView 在 iOS 回弹物理下仍会吃掉纵向拖拽做整页 overscroll
    // bounce（用户感知为「滚了外面容器、PDF 不动」），这两类锁死外层。
    final outerScrollable =
        _kind != WorkspaceFileKind.pdf && _kind != WorkspaceFileKind.image;
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
      final String message;
      if (error is OfficeParseException) {
        message = error.isTooLarge
            ? l10n.previewOfficeTooLarge
            : l10n.previewOfficeUnsupported;
      } else if (error is ApiException) {
        message = error.message;
      } else {
        message = error.toString();
      }
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: _buildFallback(
            message: message,
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
          // InteractiveViewer 的 ClipRect 采用自身盒子尺寸，松约束下会收缩为图片
          // 自然尺寸（小图放大被裁回小框，真机反馈 bug）。SliverFillRemaining +
          // SizedBox.expand 把视口钉满剩余空间；Image BoxFit.contain 初始即铺满。
          SliverFillRemaining(
            hasScrollBody: false,
            child: SizedBox.expand(
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
        return [_buildVideoSliver()];
      case WorkspaceFileKind.audio:
        return [_buildAudioSliver()];
      case WorkspaceFileKind.pdf:
        return [_buildPdfSliver()];
      case WorkspaceFileKind.office:
        return [_buildOfficeSliver()];
      case WorkspaceFileKind.archive:
      case WorkspaceFileKind.other:
        return [_buildUnsupportedSliver()];
    }
  }

  Widget _buildVideoSliver() {
    final l10n = AppLocalizations.of(context);
    final controller = _videoController;
    final player = _player;
    if (controller == null || player == null) {
      return _buildUnsupportedSliver();
    }
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      sliver: SliverToBoxAdapter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildMediaMetaLine(l10n),
            const SizedBox(height: 12),
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Video(
                key: const ValueKey('preview-video'),
                controller: controller,
                // 自带的 Material 控件与 Cupertino 视觉不统一，这里用 null
                // 禁用内置控件，改用下方统一的 _MediaControls（Cupertino 风格）。
              ),
            ),
            const SizedBox(height: 12),
            _MediaControls(
              key: const ValueKey('preview-video-controls'),
              player: player,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAudioSliver() {
    final l10n = AppLocalizations.of(context);
    final player = _player;
    if (player == null) {
      return _buildUnsupportedSliver();
    }
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 32, 16, 16),
      sliver: SliverToBoxAdapter(
        child: Column(
          children: [
            Icon(
              CupertinoIcons.music_note_2,
              size: 64,
              color: CupertinoColors.systemGrey.resolveFrom(context),
            ),
            const SizedBox(height: 12),
            Text(
              widget.entry.name ?? l10n.unnamedFile,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            _buildMediaMetaLine(l10n),
            const SizedBox(height: 20),
            _MediaControls(
              key: const ValueKey('preview-audio-controls'),
              player: player,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPdfSliver() {
    final l10n = AppLocalizations.of(context);
    final tempPath = _pdfTempPath;
    if (tempPath == null) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: _buildFallback(
          message: l10n.previewPdfFailed,
          onRetry: () => unawaited(_load()),
        ),
      );
    }
    return SliverFillRemaining(
      hasScrollBody: false,
      child: SizedBox.expand(
        child: Container(
          key: const ValueKey('preview-pdf'),
          child: PdfViewer.file(
            tempPath,
            params: PdfViewerParams(
              backgroundColor: CupertinoColors.systemBackground.resolveFrom(
                context,
              ),
              errorBannerBuilder: (context, error, stackTrace, documentRef) =>
                  _buildFallback(
                    message: l10n.previewPdfFailed,
                    onRetry: () => unawaited(_load()),
                  ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOfficeSliver() {
    final doc = _officeDocument;
    if (doc == null) {
      return _buildUnsupportedSliver();
    }
    switch (doc.kind) {
      case OfficeDocumentKind.docx:
        return _buildDocxSliver(doc);
      case OfficeDocumentKind.xlsx:
        return _buildXlsxSliver(doc);
      case OfficeDocumentKind.pptx:
        return _buildPptxSliver(doc);
      case OfficeDocumentKind.legacy:
        return _buildLegacyOfficeSliver(doc);
    }
  }

  Widget _buildDocxSliver(OfficeDocument doc) {
    final l10n = AppLocalizations.of(context);
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      sliver: SliverToBoxAdapter(
        child: Container(
          key: const ValueKey('preview-office-docx'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildMediaMetaLine(l10n),
              const SizedBox(height: 12),
              for (final block in doc.blocks) ...[
                if (block.isTable && block.table != null) ...[
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: _buildOfficeTable(block.table!),
                  ),
                  const SizedBox(height: 12),
                ] else if (block.isParagraph && block.text != null) ...[
                  if (block.heading != null) ...[
                    SelectableText(
                      block.text!,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ] else ...[
                    SelectableText(
                      block.text!,
                      style: const TextStyle(fontSize: 14, height: 1.5),
                    ),
                    const SizedBox(height: 8),
                  ],
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildXlsxSliver(OfficeDocument doc) {
    final l10n = AppLocalizations.of(context);
    final sheets = doc.sheets;
    final currentIdx = (_selectedSheetIndex < sheets.length)
        ? _selectedSheetIndex
        : 0;
    final currentSheet = sheets.isNotEmpty ? sheets[currentIdx] : null;

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      sliver: SliverToBoxAdapter(
        child: Container(
          key: const ValueKey('preview-office-xlsx'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildMediaMetaLine(l10n),
              const SizedBox(height: 12),
              if (sheets.length > 1) ...[
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: CupertinoSlidingSegmentedControl<int>(
                    groupValue: currentIdx,
                    children: {
                      for (int i = 0; i < sheets.length; i++)
                        i: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          child: Text(sheets[i].name),
                        ),
                    },
                    onValueChanged: (val) {
                      if (val != null) {
                        setState(() => _selectedSheetIndex = val);
                      }
                    },
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (currentSheet != null && currentSheet.rows.isNotEmpty)
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: _buildOfficeTable(currentSheet.rows),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPptxSliver(OfficeDocument doc) {
    final l10n = AppLocalizations.of(context);
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      sliver: SliverToBoxAdapter(
        child: Container(
          key: const ValueKey('preview-office-pptx'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildMediaMetaLine(l10n),
              const SizedBox(height: 12),
              for (int i = 0; i < doc.slides.length; i++) ...[
                if (i > 0) ...[
                  const SizedBox(height: 12),
                  Container(
                    height: 0.5,
                    color: CupertinoColors.separator.resolveFrom(context),
                  ),
                  const SizedBox(height: 12),
                ],
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: CupertinoColors.secondarySystemBackground
                        .resolveFrom(context),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: CupertinoColors.tertiarySystemFill.resolveFrom(
                            context,
                          ),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          l10n.previewOfficeSlide(doc.slides[i].index),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: secondaryText.resolveFrom(context),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      for (final line in doc.slides[i].lines) ...[
                        SelectableText(
                          line,
                          style: const TextStyle(fontSize: 14, height: 1.5),
                        ),
                        const SizedBox(height: 4),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLegacyOfficeSliver(OfficeDocument doc) {
    final l10n = AppLocalizations.of(context);
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      sliver: SliverToBoxAdapter(
        child: Container(
          key: const ValueKey('preview-office-legacy'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildMediaMetaLine(l10n),
              const SizedBox(height: 8),
              Text(
                l10n.previewOfficeLegacyHint,
                style: TextStyle(
                  fontSize: 12,
                  color: secondaryText.resolveFrom(context),
                ),
              ),
              const SizedBox(height: 12),
              SelectableText(
                doc.legacyText,
                style: const TextStyle(fontSize: 14, height: 1.5),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOfficeTable(List<List<String>> rows) {
    if (rows.isEmpty) return const SizedBox.shrink();
    return Table(
      defaultColumnWidth: const IntrinsicColumnWidth(),
      border: TableBorder.all(
        color: CupertinoColors.separator.resolveFrom(context),
        width: 0.5,
      ),
      children: [
        for (int i = 0; i < rows.length; i++)
          TableRow(
            children: [
              for (final cell in rows[i])
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: SelectableText(
                    cell,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: i == 0 ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }

  Widget _buildMediaMetaLine(AppLocalizations l10n) {
    // 复用 WorkspaceEntry 的 size（若有）作占位；时长由播放器自身展示。
    final size = widget.entry.size;
    if (size == null) return const SizedBox.shrink();
    return Text(
      _formatFileSize(size),
      textAlign: TextAlign.center,
      style: TextStyle(fontSize: 12, color: secondaryText.resolveFrom(context)),
    );
  }

  static String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(1)} GB';
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
                styleSheet: buildAssistantMarkdownStyleSheet(context),
                builders: createAssistantMarkdownBuilders(context),
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
      style: TextStyle(fontSize: 12, color: secondaryText.resolveFrom(context)),
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
            Icon(
              CupertinoIcons.doc_plaintext,
              size: 48,
              color: CupertinoColors.systemGrey.resolveFrom(context),
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
              style: TextStyle(
                fontSize: 13,
                color: secondaryText.resolveFrom(context),
              ),
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
            Icon(
              CupertinoIcons.exclamationmark_triangle,
              size: 48,
              color: CupertinoColors.systemGrey.resolveFrom(context),
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
              style: TextStyle(
                fontSize: 13,
                color: statusRedText.resolveFrom(context),
              ),
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

/// Cupertino 风格的音视频播放控件（播放/暂停、进度条、时长）。
class _MediaControls extends StatefulWidget {
  const _MediaControls({super.key, required this.player});

  final Player player;

  @override
  State<_MediaControls> createState() => _MediaControlsState();
}

class _MediaControlsState extends State<_MediaControls> {
  late final StreamSubscription<bool> _playingSub;
  late final StreamSubscription<Duration> _positionSub;
  late final StreamSubscription<Duration> _durationSub;

  bool _playing = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _playing = widget.player.state.playing;
    _position = widget.player.state.position;
    _duration = widget.player.state.duration;
    _playingSub = widget.player.stream.playing.listen((value) {
      if (mounted) setState(() => _playing = value);
    });
    _positionSub = widget.player.stream.position.listen((value) {
      if (mounted) setState(() => _position = value);
    });
    _durationSub = widget.player.stream.duration.listen((value) {
      if (mounted) setState(() => _duration = value);
    });
  }

  @override
  void dispose() {
    unawaited(_playingSub.cancel());
    unawaited(_positionSub.cancel());
    unawaited(_durationSub.cancel());
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (d.inHours > 0) {
      return '${d.inHours}:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final maxMs = _duration.inMilliseconds.toDouble();
    final posMs = _position.inMilliseconds.toDouble().clamp(
      0,
      maxMs > 0 ? maxMs : 0,
    );
    final hasDuration = maxMs > 0;
    return Column(
      children: [
        Row(
          children: [
            CupertinoButton(
              key: const ValueKey('preview-media-play-pause'),
              padding: EdgeInsets.zero,
              minimumSize: const Size(44, 44),
              onPressed: () {
                if (_playing) {
                  unawaited(widget.player.pause());
                } else {
                  unawaited(widget.player.play());
                }
              },
              child: Icon(
                _playing ? CupertinoIcons.pause_fill : CupertinoIcons.play_fill,
                size: 28,
                color: CupertinoColors.activeBlue.resolveFrom(context),
              ),
            ),
            Expanded(
              child: CupertinoSlider(
                key: const ValueKey('preview-media-slider'),
                value: hasDuration ? posMs.toDouble() : 0,
                min: 0,
                max: hasDuration ? maxMs : 1,
                onChanged: hasDuration
                    ? (value) {
                        unawaited(
                          widget.player.seek(
                            Duration(milliseconds: value.round()),
                          ),
                        );
                      }
                    : null,
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatDuration(_position),
                style: TextStyle(
                  fontSize: 12,
                  color: secondaryText.resolveFrom(context),
                ),
              ),
              Text(
                _formatDuration(_duration),
                style: TextStyle(
                  fontSize: 12,
                  color: secondaryText.resolveFrom(context),
                ),
              ),
            ],
          ),
        ),
      ],
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
