import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/chat_message.dart';
import '../../../core/models/tool_call.dart';
import '../../chat/chat_models.dart';
import '../../chat/chat_providers.dart';
import '../../chat/chat_state.dart';
import 'message_bubble.dart';

/// 消息列表（ListView.builder + 稳定 renderId key + 自动滚动跟随）。
///
/// 流式消息由独立气泡层渲染（transcriptMessagesProvider 已隐藏它），
/// 工具卡片/reasoning 折叠块按 anchorMessageID 锚定到对应气泡。
class ChatMessageList extends ConsumerStatefulWidget {
  const ChatMessageList({super.key, required this.sessionId});

  final String sessionId;

  @override
  ConsumerState<ChatMessageList> createState() => _ChatMessageListState();
}

class _ChatMessageListState extends ConsumerState<ChatMessageList> {
  final ScrollController _controller = ScrollController();
  bool _nearBottom = true;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_controller.hasClients) return;
    final position = _controller.position;
    final nearBottom = position.maxScrollExtent - position.pixels < 120;
    if (nearBottom != _nearBottom) {
      setState(() => _nearBottom = nearBottom);
    }
  }

  void _scrollToBottom({bool animated = true}) {
    if (!_controller.hasClients) return;
    final target = _controller.position.maxScrollExtent;
    if (target <= 0) return;
    if (animated) {
      _controller.animateTo(
        target,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    } else {
      _controller.jumpTo(target);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sessionId = widget.sessionId;
    final transcript = ref.watch(transcriptMessagesProvider(sessionId));
    final streaming = ref.watch(streamingMessageProvider(sessionId));
    final toolGroups = ref.watch(toolGroupsProvider(sessionId));
    final reasoningGroups = ref.watch(reasoningGroupsProvider(sessionId));
    final phase = ref.watch(chatPhaseProvider(sessionId));

    // 滚动跟随：每次 flush 出内容（16ms 合并节流）后，若用户在底部则跟随。
    ref.listen<int>(
      chatControllerProvider(sessionId)
          .select((s) => s.streamingScrollTrigger),
      (_, _) {
        if (_nearBottom) _scrollToBottom();
      },
    );
    // 发送/流开始：回到底部。
    ref.listen<ChatPhase>(chatPhaseProvider(sessionId), (previous, next) {
      if (next == ChatPhase.sending || next == ChatPhase.streaming) {
        _scrollToBottom();
      }
    });

    final streamingTools = streaming == null
        ? const <ToolCallGroup>[]
        : toolGroups
            .where((g) => g.anchorMessageID == streaming.messageId)
            .toList();
    final streamingReasoning = streaming == null
        ? const <ReasoningGroup>[]
        : reasoningGroups
            .where((g) => g.anchorMessageId == streaming.messageId)
            .toList();

    var itemCount = transcript.length;
    if (streaming != null) itemCount++;
    if (phase == ChatPhase.sending) itemCount++;

    return ListView.builder(
      controller: _controller,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        if (phase == ChatPhase.sending && index == itemCount - 1) {
          return const _SendingIndicator();
        }
        if (streaming != null && index == itemCount - (phase == ChatPhase.sending ? 2 : 1)) {
          return _StreamingBubble(
            message: streaming,
            toolGroups: streamingTools,
            reasoningGroups: streamingReasoning,
          );
        }
        final entry = transcript[index];
        final groups = toolGroups
            .where((g) => g.anchorMessageID == entry.message.messageId)
            .toList();
        final reasoning = reasoningGroups
            .where((g) => g.anchorMessageId == entry.message.messageId)
            .toList();
        return ChatMessageBubble(
          key: ValueKey(entry.renderId),
          message: entry.message,
          toolGroups: groups,
          reasoningGroups: reasoning,
        );
      },
    );
  }
}

/// 流式气泡（独立渲染层：思考中指示器 + 流式文本 + 实时工具卡片）。
class _StreamingBubble extends StatelessWidget {
  const _StreamingBubble({
    required this.message,
    required this.toolGroups,
    required this.reasoningGroups,
  });

  final ChatMessage message;
  final List<ToolCallGroup> toolGroups;
  final List<ReasoningGroup> reasoningGroups;

  @override
  Widget build(BuildContext context) {
    final hasContent = (message.content ?? '').isNotEmpty;
    final isEmpty = !hasContent &&
        toolGroups.isEmpty &&
        reasoningGroups.isEmpty;
    if (!isEmpty) {
      return ChatMessageBubble(
        message: message,
        toolGroups: toolGroups,
        reasoningGroups: reasoningGroups,
      );
    }
    // 空流式气泡 → 思考中指示器。
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: Row(
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(
              children: [
                CupertinoActivityIndicator(radius: 8),
                SizedBox(width: 8),
                Text(
                  '思考中…',
                  style: TextStyle(
                    fontSize: 14,
                    color: CupertinoColors.systemGrey,
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

/// 发送中指示器（sending 相位，未拿到 stream_id）。
class _SendingIndicator extends StatelessWidget {
  const _SendingIndicator();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: Row(
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(
              children: [
                CupertinoActivityIndicator(radius: 8),
                SizedBox(width: 8),
                Text(
                  '发送中…',
                  style: TextStyle(
                    fontSize: 14,
                    color: CupertinoColors.systemGrey,
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
