import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/chat_message.dart';
import '../../../core/models/tool_call.dart';
import '../../chat/chat_models.dart';
import '../../chat/chat_providers.dart';
import '../../chat/chat_state.dart';
import 'message_action_menu.dart';
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
  bool _loadingOlder = false;
  bool _olderLoadQueued = false;
  bool _initialPositioned = false;
  bool _restoringOlderPosition = false;
  bool _userHasScrolled = false;
  int _layoutGeneration = 0;
  bool _initialPositionScheduled = false;

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
    if (!_restoringOlderPosition) {
      if (!nearBottom) _userHasScrolled = true;
      if (nearBottom != _nearBottom) {
        setState(() => _nearBottom = nearBottom);
      }
    }
    if (position.pixels <= 80 && _initialPositioned && !_restoringOlderPosition) {
      unawaited(_loadOlderMessages());
    }
  }

  Future<void> _loadOlderMessages() async {
    if (_loadingOlder || _olderLoadQueued || !mounted) return;
    final state = ref.read(chatControllerProvider(widget.sessionId));
    if (!state.hasOlderMessages || state.messagesOffset <= 0) return;
    _olderLoadQueued = true;
    _loadingOlder = true;
    final beforePixels = _controller.hasClients ? _controller.position.pixels : 0.0;
    final beforeExtent =
        _controller.hasClients ? _controller.position.maxScrollExtent : 0.0;
    _restoringOlderPosition = true;
    try {
      await ref
          .read(chatControllerProvider(widget.sessionId).notifier)
          .loadOlderMessages();
      if (!mounted) return;
      _restoreOlderScrollPosition(
        beforePixels: beforePixels,
        beforeExtent: beforeExtent,
        frame: 0,
      );
    } finally {
      _olderLoadQueued = false;
      _loadingOlder = false;
      // The post-frame callback owns the final reset. This fallback covers
      // request failures and unmounted controllers.
      if (!mounted) _restoringOlderPosition = false;
    }
  }

  void _restoreOlderScrollPosition({
    required double beforePixels,
    required double beforeExtent,
    required int frame,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients) {
        _restoringOlderPosition = false;
        return;
      }
      if (frame < 2) {
        _restoreOlderScrollPosition(
          beforePixels: beforePixels,
          beforeExtent: beforeExtent,
          frame: frame + 1,
        );
        return;
      }
      final delta = _controller.position.maxScrollExtent - beforeExtent;
      final target = (beforePixels + delta).clamp(
        0.0,
        _controller.position.maxScrollExtent,
      );
      _controller.jumpTo(target);
      _restoringOlderPosition = false;
      _nearBottom = _controller.position.maxScrollExtent -
              _controller.position.pixels <
          120;
    });
  }

  void _positionInitialView({required bool hasContent}) {
    if (!mounted || !hasContent || _userHasScrolled || _initialPositionScheduled) return;
    _initialPositionScheduled = true;
    final generation = ++_layoutGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initialPositionScheduled = false;
      if (!mounted || !_controller.hasClients || _userHasScrolled) return;
      if (generation != _layoutGeneration) return;
      final target = _controller.position.maxScrollExtent;
      if (target <= 0 && _controller.position.viewportDimension <= 0) {
        _initialPositionScheduled = false;
        _positionInitialView(hasContent: true);
        return;
      }
      _initialPositioned = true;
      _controller.jumpTo(target);
      _nearBottom = true;
    });
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

  /// 长按/右键消息弹操作菜单并执行动作。
  Future<void> _showMessageActions(ChatMessage message) async {
    final action = await showMessageActionMenu(context, message: message);
    if (action == null || !mounted) return;
    final controller =
        ref.read(chatControllerProvider(widget.sessionId).notifier);
    switch (action) {
      case MessageAction.copy:
      case MessageAction.copyMd:
        // 先提示，再异步写剪贴板（立即反馈，不阻塞菜单关闭）。
        unawaited(copyMessageText(message));
        if (mounted) controller.setNotice('已复制到剪贴板');
      case MessageAction.edit:
        final text = message.content;
        if (text != null && text.isNotEmpty) {
          controller.prefillComposer(text);
        }
      case MessageAction.truncate:
        final index = ref
            .read(chatControllerProvider(widget.sessionId))
            .messages
            .indexWhere((m) => m.id == message.id);
        if (index >= 0) await controller.truncateAt(index);
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
    _positionInitialView(hasContent: transcript.isNotEmpty || streaming != null);

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
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onLongPress: () => _showMessageActions(entry.message),
          onSecondaryTapDown: (_) => _showMessageActions(entry.message),
          child: ChatMessageBubble(
            key: ValueKey(entry.renderId),
            message: entry.message,
            toolGroups: groups,
            reasoningGroups: reasoning,
          ),
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
                    color: CupertinoColors.secondaryLabel,
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
                    color: CupertinoColors.secondaryLabel,
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
