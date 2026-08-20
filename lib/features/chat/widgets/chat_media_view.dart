import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';

import '../../../core/models/message_attachment.dart';
import '../../../l10n/app_localizations.dart';
import 'chat_media_parser.dart';

/// 聊天内联媒体渲染组件（支持图片、base64 Data URI、本地文件与服务器 /api/media 路由）。
class ChatInlineMediaWidget extends StatelessWidget {
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
  final Map<String, String>? customHeaders;
  final double maxWidth;
  final double maxHeight;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
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
    } else if (resolvedUrl.startsWith('http://') ||
        resolvedUrl.startsWith('https://')) {
      imageWidget = Image.network(
        resolvedUrl,
        headers: customHeaders,
        fit: BoxFit.contain,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
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
        },
        errorBuilder: (context, error, stackTrace) {
          return _ImageErrorPlaceholder(
            altText: alt ?? title,
            rawUri: rawUri,
            maxWidth: maxWidth,
          );
        },
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
          headers: customHeaders,
        ),
        child: Container(
          constraints: BoxConstraints(
            minWidth: 32,
            minHeight: 32,
            maxWidth: maxWidth,
            maxHeight: maxHeight,
          ),
          decoration: BoxDecoration(
            borderRadius: borderRadius,
          ),
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
    Map<String, String>? headers,
  }) {
    Navigator.of(context).push(
      CupertinoPageRoute<void>(
        fullscreenDialog: true,
        builder: (dialogContext) {
          Widget viewerContent;
          if (memoryBytes != null) {
            viewerContent = Image.memory(memoryBytes, fit: BoxFit.contain);
          } else if (resolvedUrl.startsWith('http://') ||
              resolvedUrl.startsWith('https://')) {
            viewerContent = Image.network(
              resolvedUrl,
              headers: headers,
              fit: BoxFit.contain,
            );
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
    final displayName = altText ??
        rawUri?.split('/').last.split(r'\').last ??
        l10n.mediaImage;

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
    final hasImagePath = isImage &&
        attachment.path != null &&
        attachment.path!.isNotEmpty &&
        (attachment.path!.contains('/') ||
            attachment.path!.contains(r'\') ||
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
                Icon(
                  iconData,
                  size: 13,
                  color: iconColor,
                ),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    name,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: fgColor,
                    ),
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
