import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/cache/cache_providers.dart';
import '../../../core/models/message_attachment.dart';
import '../../../l10n/app_localizations.dart';
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
          errorBuilder: (context, error, stackTrace) {
            return _ImageErrorPlaceholder(
              altText: alt ?? title,
              rawUri: rawUri,
              maxWidth: maxWidth,
            );
          },
        ),
        loading: () => _loadingBox(context, borderRadius),
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
    );
  }

  void _openImageLightbox(
    BuildContext context, {
    required String resolvedUrl,
    Uint8List? memoryBytes,
    String? altText,
  }) {
    Navigator.of(context).push(
      HermesPageRoute<void>(
        fullscreenDialog: true,
        builder: (dialogContext) {
          Widget viewerContent;
          if (memoryBytes != null) {
            viewerContent = Image.memory(memoryBytes, fit: BoxFit.contain);
          } else if (resolvedUrl.startsWith('http://') ||
              resolvedUrl.startsWith('https://')) {
            viewerContent = _LightboxNetworkImage(mediaUrl: resolvedUrl);
          } else if (!kIsWeb && File(resolvedUrl).existsSync()) {
            viewerContent = Image.file(File(resolvedUrl), fit: BoxFit.contain);
          } else {
            viewerContent = const Icon(
              CupertinoIcons.photo,
              size: 64,
              color: CupertinoColors.white,
            );
          }

          return CupertinoPageScaffold(
            backgroundColor: CupertinoColors.black,
            navigationBar: CupertinoNavigationBar(
              backgroundColor: CupertinoColors.black.withValues(alpha: 0.7),
              leading: CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Icon(
                  CupertinoIcons.clear_thick,
                  color: CupertinoColors.white,
                  size: 20,
                ),
              ),
              middle: altText != null && altText.isNotEmpty
                  ? Text(
                      altText,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: CupertinoColors.white,
                        fontSize: 14,
                      ),
                    )
                  : null,
            ),
            child: SafeArea(
              child: Center(
                child: InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 4.0,
                  child: viewerContent,
                ),
              ),
            ),
          );
        },
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

Widget _loadingBox(BuildContext context, BorderRadius borderRadius) {
  return Container(
    width: 160,
    height: 120,
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
          Container(
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
          ),
        ],
      ),
    );
  }
}
