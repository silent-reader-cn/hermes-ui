import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../chat/chat_providers.dart';
import '../../chat/chat_state.dart';

/// 输入栏（chat_spec.md §4.2：idle 发送；流式期间 steer/停止；模型选择；附件）。
///
/// - idle：附件按钮 + 输入框 + 发送；
/// - 流式：附件按钮 + 输入框 + steer 发送 + 停止；
/// - sending：输入禁用（发送请求在途）。
class ChatInputBar extends ConsumerStatefulWidget {
  const ChatInputBar({super.key, required this.sessionId});

  final String sessionId;

  @override
  ConsumerState<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends ConsumerState<ChatInputBar> {
  final TextEditingController _textController = TextEditingController();
  bool _hasText = false;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _textController.text;
    if (text.trim().isEmpty) return;
    _textController.clear();
    setState(() => _hasText = false);
    // 控制器自动分派：idle → 普通发送；流式 → steer。
    await ref
        .read(chatControllerProvider(widget.sessionId).notifier)
        .send(text);
  }

  Future<void> _stop() async {
    await ref.read(chatControllerProvider(widget.sessionId).notifier).stop();
  }

  void _showModelPicker() {
    final models = ref.read(chatAvailableModelsProvider);
    unawaited(showCupertinoModalPopup<void>(
      context: context,
      builder: (context) => CupertinoActionSheet(
        title: const Text('选择模型'),
        actions: [
          CupertinoActionSheetAction(
            key: const ValueKey('chat-model-default'),
            onPressed: () {
              ref
                  .read(chatControllerProvider(widget.sessionId).notifier)
                  .selectModel(null);
              Navigator.of(context).pop();
            },
            child: const Text('跟随服务器默认'),
          ),
          for (final model in models)
            CupertinoActionSheetAction(
              key: ValueKey('chat-model-$model'),
              onPressed: () {
                ref
                    .read(chatControllerProvider(widget.sessionId).notifier)
                    .selectModel(model);
                Navigator.of(context).pop();
              },
              child: Text(model),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
      ),
    ));
  }

  void _showAttachmentNotice() {
    unawaited(showCupertinoDialog<void>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('附件功能'),
        content: const Text('附件上传将在后续版本提供。'),
        actions: [
          CupertinoDialogAction(
            child: const Text('好'),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final phase = ref.watch(chatPhaseProvider(widget.sessionId));
    final isStreaming = phase == ChatPhase.streaming ||
        phase == ChatPhase.steered ||
        phase == ChatPhase.approvalPending ||
        phase == ChatPhase.clarifyPending ||
        phase == ChatPhase.recovering;
    final isSending = phase == ChatPhase.sending;

    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: CupertinoColors.systemGrey4.resolveFrom(context),
            width: 0.5,
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            CupertinoButton(
              key: const ValueKey('chat-attach-button'),
              onPressed: isSending ? null : _showAttachmentNotice,
              padding: EdgeInsets.zero,
              child: const Icon(
                CupertinoIcons.plus_circle,
                color: CupertinoColors.systemGrey,
              ),
            ),
            Expanded(
              child: CupertinoTextField(
                key: const ValueKey('chat-input-field'),
                controller: _textController,
                placeholder: isStreaming ? '提示当前回复（steer）…' : '发送消息…',
                enabled: !isSending,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                onChanged: (value) {
                  final hasText = value.trim().isNotEmpty;
                  if (hasText != _hasText) setState(() => _hasText = hasText);
                },
                onSubmitted: (_) => _submit(),
              ),
            ),
            if (isStreaming) ...[
              CupertinoButton(
                key: const ValueKey('chat-steer-button'),
                onPressed: _hasText ? _submit : null,
                padding: EdgeInsets.zero,
                child: const Icon(
                  CupertinoIcons.arrow_right_circle,
                  color: CupertinoColors.activeBlue,
                ),
              ),
              CupertinoButton(
                key: const ValueKey('chat-stop-button'),
                onPressed: _stop,
                padding: EdgeInsets.zero,
                child: const Icon(
                  CupertinoIcons.stop_circle,
                  color: CupertinoColors.systemRed,
                ),
              ),
            ] else if (!isSending)
              CupertinoButton(
                key: const ValueKey('chat-send-button'),
                onPressed: _hasText ? _submit : null,
                padding: EdgeInsets.zero,
                child: const Icon(
                  CupertinoIcons.arrow_up_circle,
                  color: CupertinoColors.activeBlue,
                ),
              ),
            CupertinoButton(
              key: const ValueKey('chat-model-button'),
              onPressed: _showModelPicker,
              padding: EdgeInsets.zero,
              child: const Icon(
                CupertinoIcons.textformat,
                color: CupertinoColors.systemGrey,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
