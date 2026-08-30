import 'package:flutter/cupertino.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/connections/connection_providers.dart';
import '../../../core/models/chat_message.dart';
import '../../../core/models/message_attachment.dart';
import '../../../core/models/tool_call.dart';
import '../../../core/utils/injected_message.dart';
import '../../chat/chat_models.dart';
import '../../../core/utils/selected_context.dart';
import 'chat_media_parser.dart';
import 'chat_media_view.dart';
import 'collapsible_process_capsule.dart';
import 'injected_notice_card.dart';
import 'markdown_styles.dart';
import 'selected_context_card.dart';
import 'tool_call_card.dart';

/// 消息内区块统一间距（思考卡 / 工具卡 / 正文 / 选中上下文卡之间固定间隔）。
const double kMessageSectionGap = 8.0;

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
    this.hideThinking = false,
    this.collapseCompletedProcess = true,
    this.isStreaming = false,
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

  /// 隐藏思考子卡行（设置「隐藏思考」开启时透传工具卡）。
  final bool hideThinking;

  /// 是否在完成后自动折叠过程（思考/工具/通知）。
  final bool collapseCompletedProcess;

  /// 是否处于流式中（流式中过程不提前折叠）。
  final bool isStreaming;

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
    // user 保持 0.78 右对齐气泡；assistant 为 full-width（可用宽度 − 水平 padding），
    // 文本与卡片撑满，仅左右 12px 对齐 padding。
    return LayoutBuilder(
      builder: (context, constraints) {
        // 会话样式（对齐 WebUI 惯例，深浅色一致）：
        // - user：蓝色气泡 + 白字（深浅模式同款蓝泡）
        // - assistant：不包裹气泡，裸文本与子卡片直接上背景 —— 浅色模式下
        //   若给 assistant 加浅灰气泡会与页面背景同色「隐形」，而深色模式下
        //   又显形，视觉上深浅不一致；改按 WebUI 惯例统一「user 有泡、
        //   assistant 无泡」后，深浅模式样式天然一致（正文/代码块/卡片
        //   各有自身的色块与间距承载层级）。
        if (isUser) {
          final bubble = Container(
            key: const ValueKey('chat-message-bubble'),
            constraints: BoxConstraints(maxWidth: constraints.maxWidth * 0.78),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: CupertinoColors.activeBlue.resolveFrom(context),
              borderRadius: BorderRadius.circular(16),
            ),
            child: _UserContent(
              message: message,
              baseUrl: effectiveBaseUrl,
              sessionId: sessionId,
              customHeaders: effectiveHeaders,
            ),
          );
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              // Flexible 确保气泡被限制在行内（非 flex 子项在 unbounded
              // 链上会忽略自身 maxWidth，导致长文气泡顶出右侧）。
              children: [Flexible(child: bubble)],
            ),
          );
        }
        // assistant: full width, constrained to 可用宽度 − 水平 padding，仅左右 12px 对齐
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          child: SizedBox(
            key: const ValueKey('chat-message-bubble'),
            width: double.infinity,
            child: _AssistantContent(
              message: message,
              toolGroups: toolGroups,
              reasoningGroups: reasoningGroups,
              hideThinking: hideThinking,
              collapseCompletedProcess: collapseCompletedProcess,
              isStreaming: isStreaming,
              baseUrl: effectiveBaseUrl,
              sessionId: sessionId,
              customHeaders: effectiveHeaders,
            ),
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
    // 纯文本与块级内容两态（#34 气泡宽度自适应）：
    // - 块级内容态（选中上下文卡片 / 内联媒体标记 / 附件芯片）保持
    //   [CrossAxisAlignment.stretch]：卡片与媒体区横向撑满，排版不受误伤；
    // - 纯文本态改 [CrossAxisAlignment.start]：Column 宽度由内容收缩决定
    //   （外层 Container maxWidth = 0.78 槽宽封顶不变），不足一行的短消息
    //   气泡收窄贴右（IM 惯例），长文本依旧在 0.78 内折行撑满。
    final hasBlockContent =
        blocks.isNotEmpty ||
        hasMediaMarker ||
        message.attachments?.isNotEmpty == true;
    return Column(
      crossAxisAlignment: hasBlockContent
          ? CrossAxisAlignment.stretch
          : CrossAxisAlignment.start,
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
              builders: createUserMarkdownBuilders(context),
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
    required this.hideThinking,
    this.collapseCompletedProcess = true,
    this.isStreaming = false,
    this.baseUrl,
    this.sessionId,
    this.customHeaders,
  });

  final ChatMessage message;
  final List<ToolCallGroup> toolGroups;
  final List<ReasoningGroup> reasoningGroups;
  final bool hideThinking;
  final bool collapseCompletedProcess;
  final bool isStreaming;
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

    // 渲染层去重兜底：completed 与 live 双份（重连/重放场景）时只显示一份。
    // 思考子卡已由 provider 融合进工具组（ToolCallGroup 内 think 行），
    // 不再独立渲染思考卡。
    final distinctTools = _distinctToolGroups(toolGroups);

    // 统一间距模型：各区块（选中上下文卡片 / 工具卡(思考+工具) / 正文 / 速率）
    // 之间固定 [kMessageSectionGap]。
    final sections = <Widget>[];
    if (blocks.isNotEmpty) {
      sections.add(SelectedContextCardGroup(blocks: blocks));
    }
    // 真实时序对齐（Hermes 流序：思考 → 工具 → 文本）：工具卡
    // （含思考子卡行）渲染在正文文本上方——遇 think/tool 建卡吸收连续
    // think/tool，遇 text 打断为独立正文段。
    final hasVisibleTools = distinctTools.any((g) => g.toolCalls.any(
        (c) => !c.isThinking || (!hideThinking && c.isThinking)));

    if (hasVisibleTools) {
      final toolCards = <Widget>[
        for (final group in distinctTools)
          for (final call in group.toolCalls)
            if (call.isThinking) ...[
              if (!hideThinking) ThinkingRow(call: call),
            ] else ...[
              ToolCallCard(call: call),
            ],
      ];
      final spacedToolCards = <Widget>[
        for (var i = 0; i < toolCards.length; i++) ...[
          toolCards[i],
          if (i < toolCards.length - 1) const SizedBox(height: 6),
        ],
      ];

      if (collapseCompletedProcess && !isStreaming) {
        sections.add(
          CollapsibleProcessCapsule(
            toolGroups: distinctTools,
            hideThinking: hideThinking,
            children: spacedToolCards,
          ),
        );
      } else {
        sections.addAll(spacedToolCards);
      }
    }
    if (parsedContent.isNotEmpty) {
      sections.add(
        MarkdownBody(
          data: parsedContent,
          selectable: true,
          styleSheet: buildAssistantMarkdownStyleSheet(context),
          builders: createAssistantMarkdownBuilders(context),
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
      );
    }
    if (message.turnTps != null) {
      sections.add(
        Text(
          '${message.turnTps!.toStringAsFixed(1)} tok/s',
          style: TextStyle(
            fontSize: 11,
            color: CupertinoColors.secondaryLabel.resolveFrom(context),
          ),
        ),
      );
    }

    final children = <Widget>[];
    for (var i = 0; i < sections.length; i++) {
      if (i > 0) children.add(const SizedBox(height: kMessageSectionGap));
      children.add(sections[i]);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  static List<ToolCallGroup> _distinctToolGroups(List<ToolCallGroup> groups) {
    final seen = <String>{};
    final out = <ToolCallGroup>[];
    for (final g in groups) {
      final key =
          '${g.anchorMessageID ?? ''}:${g.toolCalls.map((t) => t.id).join(',')}';
      if (seen.add(key)) out.add(g);
    }
    return out;
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
                style: TextStyle(
                  fontSize: 13,
                  color: CupertinoColors.label.resolveFrom(context),
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

/// 发送中指示器（sending 相位，未拿到 stream_id）。
