import 'package:flutter/cupertino.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/connections/connection_providers.dart';
import '../../../core/models/chat_message.dart';
import '../../../core/models/message_attachment.dart';
import '../../../core/models/tool_call.dart';
import '../../../core/utils/injected_message.dart';
import '../../../l10n/app_localizations.dart';
import '../../chat/chat_models.dart';
import '../../../core/utils/selected_context.dart';
import 'chat_media_parser.dart';
import 'chat_media_view.dart';
import 'injected_notice_card.dart';
import 'markdown_styles.dart';
import 'selected_context_card.dart';
import 'tool_call_card.dart';

/// 单条消息气泡（chat_spec.md §6.3 渲染分支）。
///
/// - user：右对齐蓝色气泡，content 去 `[Attached files: …]` 标记，附件条渲染；
/// - assistant：左对齐，Markdown 渲染（支持 MEDIA: 与内联媒体）+ 工具卡片（锚定本消息）+ reasoning 折叠块 + tps 徽标；
/// - local_notice：notice 卡片；
/// - local_assistant：普通 assistant 气泡；
/// - injected_notice：当 role in {user,system} 且命中 [InjectedMessage.isInjectedNotice]
///   时直接透传 [InjectedNoticeCard]（受控优先，无透传时内部兜底），见 spec §2.1。
class ChatMessageBubble extends StatelessWidget {
  const ChatMessageBubble({
    super.key,
    required this.message,
    this.toolGroups = const [],
    this.reasoningGroups = const [],
    this.baseUrl,
    this.sessionId,
    this.customHeaders,
    this.injectedExpanded,
    this.onToggleInjected,
    this.collapseInjectedEnabled = true,
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

  /// 注入卡片受控展开态（由 [ChatMessageList] 传入，保持滚动复用不丢状态）。
  final bool? injectedExpanded;

  /// 注入卡片切换回调（由 [ChatMessageList] 传入）。
  final VoidCallback? onToggleInjected;

  /// 是否启用注入卡片折叠（受设置开关控制，OFF 时退化为普通气泡）。
  final bool collapseInjectedEnabled;

  @override
  Widget build(BuildContext context) {
    final role = message.role;
    if (role == 'local_notice') return _NoticeCard(message: message);
    if (collapseInjectedEnabled && InjectedMessage.isInjectedNotice(message)) {
      if (injectedExpanded != null && onToggleInjected != null) {
        return InjectedNoticeCard(
          message: message,
          expanded: injectedExpanded!,
          onToggle: onToggleInjected!,
        );
      }
      return _FallbackInjectedNoticeCard(message: message);
    }
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
        // 会话样式（对齐 WebUI 惯例，深浅色一致）：
        // - user：蓝色气泡 + 白字（深浅模式同款蓝泡）
        // - assistant：不包裹气泡，裸文本与子卡片直接上背景 —— 浅色模式下
        //   若给 assistant 加浅灰气泡会与页面背景同色「隐形」，而深色模式下
        //   又显形，视觉上深浅不一致；改按 WebUI 惯例统一「user 有泡、
        //   assistant 无泡」后，深浅模式样式天然一致（正文/代码块/卡片
        //   各有自身的色块与间距承载层级）。
        final bubble = Container(
          key: const ValueKey('chat-message-bubble'),
          constraints: BoxConstraints(maxWidth: constraints.maxWidth * 0.78),
          padding: isUser
              ? const EdgeInsets.symmetric(horizontal: 12, vertical: 9)
              : EdgeInsets.zero,
          decoration: isUser
              ? BoxDecoration(
                  color: CupertinoColors.activeBlue.resolveFrom(context),
                  borderRadius: BorderRadius.circular(16),
                )
              : null,
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

    // SelectedContext 解析闭环：行级扫描 marker + label + > 引用，围栏保护
    // 顺序：先解析选中上下文，再对剩余 cleanText 做媒体标记解析
    // 渲染：卡片区置顶（gap8），cleanText 在下，两者间 6px 间隙
    final selected = SelectedContextParser.parse(display);
    final blocks = selected.blocks;
    final cleanText = selected.cleanText;
    final hasMediaMarker =
        cleanText.contains('MEDIA:') || cleanText.contains('file://');
    final parsedDisplay = hasMediaMarker
        ? ChatMediaParser.parseMediaMarkers(cleanText)
        : cleanText;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (blocks.isNotEmpty) SelectedContextCardGroup(blocks: blocks),
        if (blocks.isNotEmpty && parsedDisplay.isNotEmpty)
          const SizedBox(height: 6),
        if (parsedDisplay.isNotEmpty)
          if (hasMediaMarker)
            MarkdownBody(
              data: parsedDisplay,
              selectable: true,
              styleSheet: buildUserMarkdownStyleSheet(context),
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
          if (blocks.isNotEmpty || parsedDisplay.isNotEmpty)
            const SizedBox(height: 6),
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
    // SelectedContext 解析：assistant 历史内容也可能包含同格式块（兼容性）
    // 同样先解析选中块，再对 cleanText 做媒体解析，渲染顺序：卡片→正文
    final selected = SelectedContextParser.parse(content);
    final blocks = selected.blocks;
    final cleanText = selected.cleanText;
    final parsedContent = ChatMediaParser.parseMediaMarkers(cleanText);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (blocks.isNotEmpty) ...[
          SelectedContextCardGroup(blocks: blocks),
          if (parsedContent.isNotEmpty || toolGroups.isNotEmpty || reasoningGroups.isNotEmpty)
            const SizedBox(height: 6),
        ],
        for (final group in reasoningGroups) _ReasoningBlock(group: group),
        if (parsedContent.isNotEmpty)
          MarkdownBody(
            data: parsedContent,
            selectable: true,
            styleSheet: buildAssistantMarkdownStyleSheet(context),
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

/// 注入通知兜底卡片（无受控展开态时内部 State 兜底，保持受控优先）。
class _FallbackInjectedNoticeCard extends StatefulWidget {
  const _FallbackInjectedNoticeCard({required this.message});

  final ChatMessage message;

  @override
  State<_FallbackInjectedNoticeCard> createState() =>
      _FallbackInjectedNoticeCardState();
}

class _FallbackInjectedNoticeCardState
    extends State<_FallbackInjectedNoticeCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return InjectedNoticeCard(
      message: widget.message,
      expanded: _expanded,
      onToggle: () => setState(() => _expanded = !_expanded),
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
