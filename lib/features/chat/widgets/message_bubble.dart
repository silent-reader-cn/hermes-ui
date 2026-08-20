import 'package:flutter/cupertino.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/connections/connection_providers.dart';
import '../../../core/models/chat_message.dart';
import '../../../core/models/message_attachment.dart';
import '../../../core/models/tool_call.dart';
import '../../../l10n/app_localizations.dart';
import '../../chat/chat_models.dart';
import 'chat_media_parser.dart';
import 'chat_media_view.dart';
import 'tool_call_card.dart';

/// 单条消息气泡（chat_spec.md §6.3 渲染分支）。
///
/// - user：右对齐蓝色气泡，content 去 `[Attached files: …]` 标记，附件条渲染；
/// - assistant：左对齐，Markdown 渲染（支持 MEDIA: 与内联媒体）+ 工具卡片（锚定本消息）+ reasoning 折叠块 + tps 徽标；
/// - local_notice：notice 卡片；
/// - local_assistant：普通 assistant 气泡。
class ChatMessageBubble extends StatelessWidget {
  const ChatMessageBubble({
    super.key,
    required this.message,
    this.toolGroups = const [],
    this.reasoningGroups = const [],
    this.baseUrl,
    this.sessionId,
    this.customHeaders,
  });

  final ChatMessage message;

  /// 锚定本消息的工具调用组（由列表按 anchorMessageId 分组后传入）。
  final List<ToolCallGroup> toolGroups;

  /// 锚定本消息的推理段。
  final List<ReasoningGroup> reasoningGroups;

  /// 可选服务端 baseUrl（未传时从 ProviderScope 读取激活连接）。
  final String? baseUrl;

  /// 可选会话 ID。
  final String? sessionId;

  /// 可选请求头。
  final Map<String, String>? customHeaders;

  @override
  Widget build(BuildContext context) {
    final role = message.role;
    if (role == 'local_notice') return _NoticeCard(message: message);
    final isUser = role == 'user';

    String? effectiveBaseUrl = baseUrl;
    Map<String, String>? effectiveHeaders = customHeaders;
    if (effectiveBaseUrl == null) {
      try {
        final container = ProviderScope.containerOf(context, listen: false);
        final conn = container.read(activeConnectionProvider);
        effectiveBaseUrl = conn?.baseUrl;
        effectiveHeaders ??= conn?.customHeaders;
      } catch (_) {
        // 无 ProviderScope 环境（如独立轻量测试），静默使用 null
      }
    }

    // 双栏外壳下 MediaQuery.width 是整个窗口宽，而气泡实际可用宽度是
    // 「窗口宽 − 侧栏宽」。用 LayoutBuilder 取真实槽位宽，避免 0.78 比例
    // 在电脑端双栏里超出屏幕（right overflow）。
    return LayoutBuilder(
      builder: (context, constraints) {
        final bubble = Container(
          key: const ValueKey('chat-message-bubble'),
          constraints: BoxConstraints(maxWidth: constraints.maxWidth * 0.78),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            // 动态色必须显式 resolve：BoxDecoration paint 不做主题解析，
            // 直塞 CupertinoColors.* 在暗黑模式下会画成 light 值（白/亮块）。
            color: isUser
                ? CupertinoColors.activeBlue.resolveFrom(context)
                : CupertinoColors.systemGrey6.resolveFrom(context),
            borderRadius: BorderRadius.circular(16),
          ),
          child: isUser
              ? _UserContent(
                  message: message,
                  baseUrl: effectiveBaseUrl,
                  sessionId: sessionId,
                  customHeaders: effectiveHeaders,
                )
              : _AssistantContent(
                  message: message,
                  toolGroups: toolGroups,
                  reasoningGroups: reasoningGroups,
                  baseUrl: effectiveBaseUrl,
                  sessionId: sessionId,
                  customHeaders: effectiveHeaders,
                ),
        );
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          child: Row(
            mainAxisAlignment: isUser
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            // Flexible 确保气泡被限制在行内（非 flex 子项在 unbounded
            // 链上会忽略自身 maxWidth，导致长文气泡顶出右侧）。
            children: [Flexible(child: bubble)],
          ),
        );
      },
    );
  }
}

class _UserContent extends StatelessWidget {
  const _UserContent({
    required this.message,
    this.baseUrl,
    this.sessionId,
    this.customHeaders,
  });

  final ChatMessage message;
  final String? baseUrl;
  final String? sessionId;
  final Map<String, String>? customHeaders;

  @override
  Widget build(BuildContext context) {
    final content = message.content == null ? '' : message.content!.trim();
    final display = content.isEmpty
        ? ''
        : MessageAttachment.contentWithoutAttachedFilesMarker(content);

    final hasMediaMarker =
        display.contains('MEDIA:') || display.contains('file://');
    final parsedDisplay =
        hasMediaMarker ? ChatMediaParser.parseMediaMarkers(display) : display;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (parsedDisplay.isNotEmpty)
          if (hasMediaMarker)
            MarkdownBody(
              data: parsedDisplay,
              selectable: true,
              styleSheet: _buildUserMarkdownStyleSheet(context),
              // ignore: deprecated_member_use
              imageBuilder: (uri, title, alt) {
                return ChatInlineMediaWidget(
                  rawUri: uri.toString(),
                  title: title,
                  alt: alt,
                  baseUrl: baseUrl,
                  sessionId: sessionId,
                  customHeaders: customHeaders,
                );
              },
            )
          else
            Text(
              parsedDisplay,
              style: const TextStyle(
                fontSize: 15,
                height: 1.4,
                color: CupertinoColors.white,
              ),
            ),
        if (message.attachments?.isNotEmpty == true) ...[
          if (parsedDisplay.isNotEmpty) const SizedBox(height: 6),
          for (final attachment in message.attachments!)
            _AttachmentChip(
              attachment: attachment,
              baseUrl: baseUrl,
              sessionId: sessionId,
              customHeaders: customHeaders,
            ),
        ],
      ],
    );
  }

  static MarkdownStyleSheet _buildUserMarkdownStyleSheet(BuildContext context) {
    return MarkdownStyleSheet.fromCupertinoTheme(CupertinoTheme.of(context))
        .copyWith(
          p: const TextStyle(
            fontSize: 15,
            height: 1.4,
            color: CupertinoColors.white,
          ),
          listBullet: const TextStyle(
            fontSize: 15,
            color: CupertinoColors.white,
          ),
          code: TextStyle(
            fontSize: 13,
            fontFamily: 'monospace',
            color: CupertinoColors.white,
            backgroundColor: CupertinoColors.white.withValues(alpha: 0.22),
          ),
        );
  }
}

class _AssistantContent extends StatelessWidget {
  const _AssistantContent({
    required this.message,
    required this.toolGroups,
    required this.reasoningGroups,
    this.baseUrl,
    this.sessionId,
    this.customHeaders,
  });

  final ChatMessage message;
  final List<ToolCallGroup> toolGroups;
  final List<ReasoningGroup> reasoningGroups;
  final String? baseUrl;
  final String? sessionId;
  final Map<String, String>? customHeaders;

  @override
  Widget build(BuildContext context) {
    final content = message.content ?? '';
    final parsedContent = ChatMediaParser.parseMediaMarkers(content);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final group in reasoningGroups) _ReasoningBlock(group: group),
        if (parsedContent.isNotEmpty)
          MarkdownBody(
            data: parsedContent,
            selectable: true,
            styleSheet: _buildMarkdownStyleSheet(context),
            // ignore: deprecated_member_use
            imageBuilder: (uri, title, alt) {
              return ChatInlineMediaWidget(
                rawUri: uri.toString(),
                title: title,
                alt: alt,
                baseUrl: baseUrl,
                sessionId: sessionId,
                customHeaders: customHeaders,
              );
            },
          ),
        for (final group in toolGroups) ToolCallGroupCard(group: group),
        if (message.turnTps != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '${message.turnTps!.toStringAsFixed(1)} tok/s',
              style: const TextStyle(
                fontSize: 11,
                color: CupertinoColors.secondaryLabel,
              ),
            ),
          ),
      ],
    );
  }

  /// Markdown 样式：以 Cupertino 主题为基底（标题/链接/表格等自动随深浅色），
  /// 再叠加项目尺寸定制。正文/代码块显式用解析后的语义色：
  /// - 文字色 `label` 保证深浅色下都是高对比正文色（fallback 样式在纯
  ///   CupertinoApp 下会回退到浅色 Material 主题的黑色，暗黑模式翻车）；
  /// - 背景块 `systemGrey5` 必须 resolve —— BoxDecoration/paint 不自动解析
  ///   动态色，直塞会在暗黑模式下画成浅灰亮块。
  static MarkdownStyleSheet _buildMarkdownStyleSheet(BuildContext context) {
    final label = CupertinoColors.label.resolveFrom(context);
    final grey5 = CupertinoColors.systemGrey5.resolveFrom(context);
    return MarkdownStyleSheet.fromCupertinoTheme(CupertinoTheme.of(context))
        .copyWith(
          p: TextStyle(fontSize: 15, height: 1.4, color: label),
          listBullet: TextStyle(fontSize: 15, color: label),
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
}

/// 附件条（图片/文件芯片）。
class _AttachmentChip extends StatelessWidget {
  const _AttachmentChip({
    required this.attachment,
    this.baseUrl,
    this.sessionId,
    this.customHeaders,
  });

  final MessageAttachment attachment;
  final String? baseUrl;
  final String? sessionId;
  final Map<String, String>? customHeaders;

  @override
  Widget build(BuildContext context) {
    return ChatAttachmentChipView(
      attachment: attachment,
      baseUrl: baseUrl,
      sessionId: sessionId,
      customHeaders: customHeaders,
      isUserMessage: true,
    );
  }
}

/// 本地 notice 卡片（深色，不等同用户消息）。
class _NoticeCard extends StatelessWidget {
  const _NoticeCard({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: CupertinoColors.systemGrey6.resolveFrom(context),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                message.content ?? '',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  color: CupertinoColors.label,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// reasoning 折叠块（默认折叠，点击展开）。
class _ReasoningBlock extends StatefulWidget {
  const _ReasoningBlock({required this.group});

  final ReasoningGroup group;

  @override
  State<_ReasoningBlock> createState() => _ReasoningBlockState();
}

class _ReasoningBlockState extends State<_ReasoningBlock> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = widget.group.text.trim();
    if (text.isEmpty) return const SizedBox.shrink();
    final summary = text.replaceAll(RegExp(r'\s+'), ' ');
    final preview = summary.length > 80
        ? '${summary.substring(0, 80)}…'
        : summary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: GestureDetector(
        onTap: () => setState(() => _expanded = !_expanded),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: CupertinoColors.systemGrey5.resolveFrom(context),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    _expanded
                        ? CupertinoIcons.chevron_down
                        : CupertinoIcons.chevron_right,
                    size: 12,
                    color: CupertinoColors.systemGrey,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    l10n.thinkingLabel,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: CupertinoColors.secondaryLabel,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      preview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: CupertinoColors.secondaryLabel,
                      ),
                    ),
                  ),
                ],
              ),
              if (_expanded)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    text,
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: CupertinoColors.label,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
