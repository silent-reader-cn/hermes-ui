import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/cache/cache_providers.dart';
import '../../../core/models/message_attachment.dart';
import '../../../l10n/app_localizations.dart';
import '../../diagnostics/diagnostics_models.dart';
import '../../diagnostics/diagnostics_service.dart';
import 'chat_media_parser.dart';
import '../../../app/widgets/hermes_page_route.dart';

/// 单个网络媒体 URL → 本地缓存文件。
///
/// 经 [MediaCacheService] 走 dio 下载（带 cookie/自定义头/autoReauth）落盘后
/// 返回 [File]，渲染改用 `Image.file`；同一 URL 并发只下载一次（service 内
/// per-URL Future 合并）。未命中下载失败（非 2xx）时进入 error，渲染占位。
final mediaFileProvider = FutureProvider.family<File, String>((ref, url) {
  return ref.watch(mediaCacheServiceProvider).get(url);
});

/// 聊天内联媒体渲染组件（支持图片、base64 Data URI、本地文件与服务器 /api/media 路由）。
class ChatInlineMediaWidget extends ConsumerWidget {
  const ChatInlineMediaWidget({
    super.key,
    required this.rawUri,
    this.title,
    this.alt,
    this.baseUrl,
    this.sessionId,
    this.customHeaders,
    this.maxWidth = 360,
    this.maxHeight = 320,
    this.borderRadius = const BorderRadius.all(Radius.circular(8)),
  });

  final String rawUri;
  final String? title;
  final String? alt;
  final String? baseUrl;
  final String? sessionId;

  /// 兼容保留：自定义头现由 dio（ApiClient）在下载时统一处理，不再用于
  /// 内联渲染；保留参数以免破坏调用方签名。
  final Map<String, String>? customHeaders;
  final double maxWidth;
  final double maxHeight;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resolvedUrl = ChatMediaResolver.resolveMediaUrl(
      rawUri,
      baseUrl: baseUrl,
      sessionId: sessionId,
    );

    if (resolvedUrl.isEmpty) {
      return _ImageErrorPlaceholder(
        altText: alt ?? title,
        rawUri: rawUri,
        maxWidth: maxWidth,
      );
    }

    final isDataUri = resolvedUrl.startsWith('data:image/');
    final isNetworkUrl =
        resolvedUrl.startsWith('http://') || resolvedUrl.startsWith('https://');

    final placeholderSize = _calculatePlaceholderSize(
      maxWidth: maxWidth,
      maxHeight: maxHeight,
      url: resolvedUrl,
    );

    Widget imageWidget;
    Uint8List? memoryBytes;

    if (isDataUri) {
      try {
        final commaIdx = resolvedUrl.indexOf(',');
        if (commaIdx != -1) {
          final payload = resolvedUrl.substring(commaIdx + 1);
          memoryBytes = base64Decode(payload);
          imageWidget = Image.memory(
            memoryBytes,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) {
              return _ImageErrorPlaceholder(
                altText: alt ?? title,
                rawUri: rawUri,
                maxWidth: maxWidth,
              );
            },
          );
        } else {
          imageWidget = _ImageErrorPlaceholder(
            altText: alt ?? title,
            rawUri: rawUri,
            maxWidth: maxWidth,
          );
        }
      } catch (_) {
        imageWidget = _ImageErrorPlaceholder(
          altText: alt ?? title,
          rawUri: rawUri,
          maxWidth: maxWidth,
        );
      }
    } else if (isNetworkUrl) {
      final fileAsync = ref.watch(mediaFileProvider(resolvedUrl));
      imageWidget = fileAsync.when(
        data: (file) => Image.file(
          file,
          fit: BoxFit.contain,
          gaplessPlayback: true,
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            if (wasSynchronouslyLoaded || frame != null) {
              return child;
            }
            return _loadingBox(
              context,
              borderRadius,
              width: placeholderSize.width,
              height: placeholderSize.height,
            );
          },
          errorBuilder: (context, error, stackTrace) {
            return _ImageErrorPlaceholder(
              altText: alt ?? title,
              rawUri: rawUri,
              maxWidth: maxWidth,
            );
          },
        ),
        loading: () => _loadingBox(
          context,
          borderRadius,
          width: placeholderSize.width,
          height: placeholderSize.height,
        ),
        error: (error, stackTrace) => _ImageErrorPlaceholder(
          altText: alt ?? title,
          rawUri: rawUri,
          maxWidth: maxWidth,
        ),
      );
    } else if (!kIsWeb && File(resolvedUrl).existsSync()) {
      imageWidget = Image.file(
        File(resolvedUrl),
        fit: BoxFit.contain,
        gaplessPlayback: true,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (wasSynchronouslyLoaded || frame != null) {
            return child;
          }
          return _loadingBox(
            context,
            borderRadius,
            width: placeholderSize.width,
            height: placeholderSize.height,
          );
        },
        errorBuilder: (context, error, stackTrace) {
          return _ImageErrorPlaceholder(
            altText: alt ?? title,
            rawUri: rawUri,
            maxWidth: maxWidth,
          );
        },
      );
    } else {
      imageWidget = _ImageErrorPlaceholder(
        altText: alt ?? title,
        rawUri: rawUri,
        maxWidth: maxWidth,
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _openImageLightbox(
          context,
          resolvedUrl: resolvedUrl,
          memoryBytes: memoryBytes,
          altText: alt ?? title,
        ),
        child: AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          alignment: Alignment.topLeft,
          child: Container(
            constraints: BoxConstraints(
              minWidth: 32,
              minHeight: 32,
              maxWidth: maxWidth,
              maxHeight: maxHeight,
            ),
            decoration: BoxDecoration(borderRadius: borderRadius),
            clipBehavior: Clip.antiAlias,
            child: imageWidget,
          ),
        ),
      ),
    );
  }

  void _openImageLightbox(
    BuildContext context, {
    required String resolvedUrl,
    Uint8List? memoryBytes,
    String? altText,
  }) {
    showAttachmentPreview(
      context,
      resolvedUrl: resolvedUrl,
      bytes: memoryBytes,
      name: altText,
      altText: altText,
      isImage: true,
    );
  }
}

/// 打开附件预览全屏弹窗（图片走 Lightbox 大图，非图展示文档信息与下载操作）。
void showAttachmentPreview(
  BuildContext context, {
  Uint8List? bytes,
  String? resolvedUrl,
  String? name,
  bool? isImage,
  String? altText,
}) {
  final displayName = name ?? altText ?? '';
  final hasExplicitImage = isImage != null;
  final bool effectiveIsImage = hasExplicitImage
      ? isImage
      : ((bytes != null &&
              (displayName.isEmpty ||
                  MessageAttachment.isImageReference(displayName))) ||
          (resolvedUrl != null &&
              (resolvedUrl.startsWith('data:image/') ||
                  MessageAttachment.isImageReference(resolvedUrl) ||
                  (displayName.isNotEmpty &&
                      MessageAttachment.isImageReference(displayName)))));

  Navigator.of(context).push(
    HermesPageRoute<void>(
      fullscreenDialog: true,
      builder: (dialogContext) => AttachmentLightbox(
        bytes: bytes,
        resolvedUrl: resolvedUrl,
        name: displayName.isNotEmpty ? displayName : null,
        altText: altText,
        isImage: effectiveIsImage,
      ),
    ),
  );
}

/// 附件 Lightbox / 预览页面（图片缩放查看，非图文件详情与下载）。
class AttachmentLightbox extends StatelessWidget {
  const AttachmentLightbox({
    super.key,
    this.bytes,
    this.resolvedUrl,
    this.name,
    this.altText,
    this.isImage = true,
  });

  final Uint8List? bytes;
  final String? resolvedUrl;
  final String? name;
  final String? altText;
  final bool isImage;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final titleText = name ?? altText ?? '';

    Widget body;
    if (isImage) {
      Widget viewerContent;
      if (bytes != null) {
        viewerContent = Image.memory(bytes!, fit: BoxFit.contain);
      } else if (resolvedUrl != null &&
          (resolvedUrl!.startsWith('http://') ||
              resolvedUrl!.startsWith('https://'))) {
        viewerContent = _LightboxNetworkImage(mediaUrl: resolvedUrl!);
      } else if (resolvedUrl != null &&
          resolvedUrl!.startsWith('data:image/')) {
        Uint8List? decoded;
        try {
          final commaIdx = resolvedUrl!.indexOf(',');
          if (commaIdx != -1) {
            final payload = resolvedUrl!.substring(commaIdx + 1);
            decoded = base64Decode(payload);
          }
        } catch (_) {}
        viewerContent = decoded != null
            ? Image.memory(decoded, fit: BoxFit.contain)
            : const Icon(
                CupertinoIcons.photo,
                size: 64,
                color: CupertinoColors.white,
              );
      } else if (resolvedUrl != null &&
          !kIsWeb &&
          File(resolvedUrl!).existsSync()) {
        viewerContent = Image.file(File(resolvedUrl!), fit: BoxFit.contain);
      } else {
        viewerContent = const Icon(
          CupertinoIcons.photo,
          size: 64,
          color: CupertinoColors.white,
        );
      }

      body = Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 4.0,
          child: viewerContent,
        ),
      );
    } else {
      final kind = MessageAttachment.mediaKindForName(titleText);
      IconData iconData;
      switch (kind) {
        case MessageMediaKind.image:
          iconData = CupertinoIcons.photo;
        case MessageMediaKind.audio:
          iconData = CupertinoIcons.music_note;
        case MessageMediaKind.video:
          iconData = CupertinoIcons.film;
        case MessageMediaKind.document:
          iconData = CupertinoIcons.doc_text;
        case MessageMediaKind.file:
          iconData = CupertinoIcons.doc;
      }

      body = Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                iconData,
                size: 64,
                color: CupertinoColors.white,
              ),
              if (titleText.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  titleText,
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: CupertinoColors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                l10n.previewUnsupported,
                style: const TextStyle(
                  color: CupertinoColors.systemGrey,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 24),
              _AttachmentDownloadButton(
                resolvedUrl: resolvedUrl,
                bytes: bytes,
                filename: titleText,
              ),
            ],
          ),
        ),
      );
    }

    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.black,
      navigationBar: CupertinoNavigationBar(
        backgroundColor: CupertinoColors.black.withValues(alpha: 0.7),
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.of(context).pop(),
          child: const Icon(
            CupertinoIcons.clear_thick,
            color: CupertinoColors.white,
            size: 20,
          ),
        ),
        middle: titleText.isNotEmpty
            ? Text(
                titleText,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: CupertinoColors.white,
                  fontSize: 14,
                ),
              )
            : null,
      ),
      child: SafeArea(child: body),
    );
  }
}

class _AttachmentDownloadButton extends ConsumerStatefulWidget {
  const _AttachmentDownloadButton({
    this.resolvedUrl,
    this.bytes,
    this.filename,
  });

  final String? resolvedUrl;
  final Uint8List? bytes;
  final String? filename;

  @override
  ConsumerState<_AttachmentDownloadButton> createState() =>
      _AttachmentDownloadButtonState();
}

class _AttachmentDownloadButtonState
    extends ConsumerState<_AttachmentDownloadButton> {
  bool _isDownloading = false;
  bool _downloaded = false;

  Future<void> _handleDownload() async {
    final url = widget.resolvedUrl;
    if (_downloaded || _isDownloading) return;

    if (widget.bytes != null ||
        (url != null && !kIsWeb && File(url).existsSync())) {
      setState(() => _downloaded = true);
      return;
    }

    if (url != null &&
        (url.startsWith('http://') || url.startsWith('https://'))) {
      setState(() => _isDownloading = true);
      try {
        await ref.read(mediaFileProvider(url).future);
        if (mounted) {
          setState(() {
            _isDownloading = false;
            _downloaded = true;
          });
        }
      } catch (e) {
        DiagnosticsService.instance.log(
          level: DiagnosticsLogLevel.error,
          tag: 'attachment',
          message: 'Failed to download attachment: $e',
        );
        if (mounted) {
          setState(() => _isDownloading = false);
        }
      }
    } else {
      setState(() => _downloaded = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    if (_isDownloading) {
      return const CupertinoButton.filled(
        key: ValueKey('attachment-download-button'),
        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        onPressed: null,
        child: CupertinoActivityIndicator(color: CupertinoColors.white),
      );
    }

    if (_downloaded) {
      return CupertinoButton.filled(
        key: const ValueKey('attachment-download-button'),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        onPressed: _handleDownload,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(CupertinoIcons.check_mark, size: 16),
            const SizedBox(width: 6),
            Text(l10n.downloaded),
          ],
        ),
      );
    }

    return CupertinoButton.filled(
      key: const ValueKey('attachment-download-button'),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      onPressed: _handleDownload,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(CupertinoIcons.cloud_download, size: 16),
          const SizedBox(width: 6),
          Text(l10n.mediaDownload),
        ],
      ),
    );
  }
}

/// Lightbox 中的网络图片查看器：同样消费 `mediaFileProvider`（缓存命中即
/// Image.file，不二次网络请求；失败显示占位图标而非白屏）。
class _LightboxNetworkImage extends ConsumerWidget {
  const _LightboxNetworkImage({required this.mediaUrl});

  final String mediaUrl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fileAsync = ref.watch(mediaFileProvider(mediaUrl));
    return fileAsync.when(
      data: (file) => Image.file(
        file,
        fit: BoxFit.contain,
        gaplessPlayback: true,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (wasSynchronouslyLoaded || frame != null) {
            return child;
          }
          return const Center(child: CupertinoActivityIndicator());
        },
        errorBuilder: (context, error, stackTrace) => const Icon(
          CupertinoIcons.photo,
          size: 64,
          color: CupertinoColors.white,
        ),
      ),
      loading: () => const Center(child: CupertinoActivityIndicator()),
      error: (error, stackTrace) => const Icon(
        CupertinoIcons.photo,
        size: 64,
        color: CupertinoColors.white,
      ),
    );
  }
}

/// 从 URL 查询参数中解析宽高提示（如 `?w=400&h=300` 或 `?width=400&height=300`）。
(double, double)? _parseDimensionsFromUrl(String url) {
  try {
    final uri = Uri.parse(url);
    final wStr = uri.queryParameters['w'] ?? uri.queryParameters['width'];
    final hStr = uri.queryParameters['h'] ?? uri.queryParameters['height'];
    if (wStr != null && hStr != null) {
      final w = double.tryParse(wStr);
      final h = double.tryParse(hStr);
      if (w != null && h != null && w > 0 && h > 0) {
        return (w, h);
      }
    }
  } catch (_) {
    // 忽略异常格式
  }
  return null;
}

/// 计算占位容器尺寸：若 URL 携带尺寸提示则按 contain 计算，否则回退默认 160×120。
Size _calculatePlaceholderSize({
  required double maxWidth,
  required double maxHeight,
  String? url,
}) {
  if (url != null) {
    final dims = _parseDimensionsFromUrl(url);
    if (dims != null) {
      final fitted = applyBoxFit(
        BoxFit.contain,
        Size(dims.$1, dims.$2),
        Size(maxWidth, maxHeight),
      ).destination;
      return Size(
        fitted.width.clamp(32.0, maxWidth),
        fitted.height.clamp(32.0, maxHeight),
      );
    }
  }
  return Size(
    160.0.clamp(32.0, maxWidth),
    120.0.clamp(32.0, maxHeight),
  );
}

Widget _loadingBox(
  BuildContext context,
  BorderRadius borderRadius, {
  double width = 160,
  double height = 120,
}) {
  return Container(
    width: width,
    height: height,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: CupertinoColors.systemGrey5.resolveFrom(context),
      borderRadius: borderRadius,
    ),
    child: const CupertinoActivityIndicator(radius: 10),
  );
}

/// 图片加载失败占位符（灰色图标 + 提示文案，不白屏、不抛未捕获异常）。
class _ImageErrorPlaceholder extends StatelessWidget {
  const _ImageErrorPlaceholder({
    this.altText,
    this.rawUri,
    this.maxWidth = 360,
  });

  final String? altText;
  final String? rawUri;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final displayName =
        altText ?? rawUri?.split('/').last.split(r'\\').last ?? l10n.mediaImage;

    return Container(
      constraints: BoxConstraints(maxWidth: maxWidth),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: CupertinoColors.systemGrey5.resolveFrom(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: CupertinoColors.systemGrey4.resolveFrom(context),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            CupertinoIcons.photo,
            size: 20,
            color: CupertinoColors.secondaryLabel.resolveFrom(context),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.imageLoadFailed,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: CupertinoColors.secondaryLabel.resolveFrom(context),
                  ),
                ),
                if (displayName.isNotEmpty)
                  Text(
                    displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: CupertinoColors.tertiaryLabel.resolveFrom(context),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 附件芯片组件（图片/音频/视频/文档）。
class ChatAttachmentChipView extends StatelessWidget {
  const ChatAttachmentChipView({
    super.key,
    required this.attachment,
    this.baseUrl,
    this.sessionId,
    this.customHeaders,
    this.isUserMessage = false,
  });

  final MessageAttachment attachment;
  final String? baseUrl;
  final String? sessionId;
  final Map<String, String>? customHeaders;
  final bool isUserMessage;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final name = attachment.name ?? attachment.path ?? l10n.attachmentFallback;
    final isImage = attachment.isImage == true;
    final pathOrName = attachment.path ?? attachment.name ?? '';
    final kind = MessageAttachment.mediaKindForName(pathOrName);

    IconData iconData;
    switch (kind) {
      case MessageMediaKind.image:
        iconData = CupertinoIcons.photo;
      case MessageMediaKind.audio:
        iconData = CupertinoIcons.music_note;
      case MessageMediaKind.video:
        iconData = CupertinoIcons.film;
      case MessageMediaKind.document:
        iconData = CupertinoIcons.doc_text;
      case MessageMediaKind.file:
        iconData = CupertinoIcons.paperclip;
    }

    final bgColor = isUserMessage
        ? CupertinoColors.white.withValues(alpha: 0.22)
        : CupertinoColors.systemGrey5.resolveFrom(context);
    final fgColor = isUserMessage
        ? CupertinoColors.white
        : CupertinoColors.label.resolveFrom(context);
    final iconColor = isUserMessage
        ? CupertinoColors.white
        : CupertinoColors.secondaryLabel.resolveFrom(context);

    // 用户消息中的图片附件：若有具体路径则展示内联预览与芯片
    final hasImagePath =
        isImage &&
        attachment.path != null &&
        attachment.path!.isNotEmpty &&
        (attachment.path!.contains('/') ||
            attachment.path!.contains(r'\\') ||
            attachment.path!.startsWith('data:'));
    final resolvedUrl = pathOrName.isNotEmpty
        ? ChatMediaResolver.resolveMediaUrl(
            pathOrName,
            baseUrl: baseUrl,
            sessionId: sessionId,
          )
        : '';

    final identityKey =
        attachment.identityKey ?? attachment.name ?? attachment.path ?? 'chip';

    final chipWidget = Container(
      key: ValueKey('attachment-chip-preview-$identityKey'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(iconData, size: 13, color: iconColor),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              name,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: fgColor),
            ),
          ),
        ],
      ),
    );

    final interactiveChip = Semantics(
      button: true,
      label: 'Preview $name',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => showAttachmentPreview(
          context,
          resolvedUrl: resolvedUrl.isNotEmpty ? resolvedUrl : null,
          name: name,
          altText: name,
          isImage: isImage || kind == MessageMediaKind.image,
        ),
        child: chipWidget,
      ),
    );

    return Container(
      margin: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: isUserMessage
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          if (hasImagePath)
            ChatInlineMediaWidget(
              rawUri: pathOrName,
              title: name,
              alt: name,
              baseUrl: baseUrl,
              sessionId: sessionId,
              customHeaders: customHeaders,
              maxWidth: 240,
              maxHeight: 180,
            ),
          interactiveChip,
        ],
      ),
    );
  }
}
