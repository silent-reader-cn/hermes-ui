import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'chat_providers.dart';
import 'widgets/chat_input_bar.dart';
import 'widgets/chat_message_list.dart';

/// 聊天页（chat_spec.md §6：消息气泡列表 + 流式渲染 + 工具卡片 + 输入栏）。
///
/// `/chat/:sessionId`，sessionId 为空串表示新会话。
class ChatPage extends ConsumerWidget {
  const ChatPage({super.key, required this.sessionId});

  /// 会话 id；空串 = 新会话。
  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(chatControllerProvider(sessionId));
    final queued = ref.watch(queuedCountProvider(sessionId));
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(
          state.displayTitle,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            if (state.pendingAction.hasPendingPrompt)
              _PendingPromptCard(sessionId: sessionId),
            Expanded(child: ChatMessageList(sessionId: sessionId)),
            if (state.sendErrorMessage != null)
              _ErrorBanner(
                message: state.sendErrorMessage!,
                onDismiss: () =>
                    ref.read(chatControllerProvider(sessionId).notifier).dismissError(),
              ),
            if (queued > 0)
              _QueuedBanner(count: queued),
            ChatInputBar(sessionId: sessionId),
          ],
        ),
      ),
    );
  }
}

/// 审批/澄清卡片（chat_spec.md §2.3：approval/clarify 是主流报警事件，流不中断）。
class _PendingPromptCard extends ConsumerWidget {
  const _PendingPromptCard({required this.sessionId});

  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(chatControllerProvider(sessionId));
    final pending = state.pendingAction;
    final isApproval = pending.approvalPrompt != null;
    final prompt = isApproval
        ? pending.approvalPrompt!
        : pending.clarificationPrompt!;
    final question = _stringOf(prompt, const ['question', 'prompt', 'text']);
    final choices = _stringListOf(prompt, const [
      'choices_offered',
      'choicesOffered',
      'choices',
    ]);
    final controller = ref.read(chatControllerProvider(sessionId).notifier);

    Future<void> respond(String answer) async {
      if (isApproval) {
        await controller.respondToApproval(answer);
      } else {
        await controller.respondToClarification(answer);
      }
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isApproval
            ? CupertinoColors.systemOrange.withValues(alpha: 0.12)
            : CupertinoColors.systemIndigo.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isApproval ? '需要审批' : '需要澄清',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: CupertinoColors.systemOrange,
            ),
          ),
          if (question != null) ...[
            const SizedBox(height: 4),
            Text(question, style: const TextStyle(fontSize: 14)),
          ],
          if (choices.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final choice in choices)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: CupertinoButton.filled(
                  key: ValueKey('chat-prompt-choice-$choice'),
                  onPressed: () => respond(choice),
                  child: Text(choice),
                ),
              ),
          ],
        ],
      ),
    );
  }

  static String? _stringOf(Map<String, Object?> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value is String && value.trim().isNotEmpty) return value;
    }
    return null;
  }

  static List<String> _stringListOf(Map<String, Object?> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value is List) {
        final items = value.whereType<String>().toList();
        if (items.isNotEmpty) return items;
      }
    }
    return const [];
  }
}

/// 发送错误横幅（error/apperror 事件、send/stop 失败）。
class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: CupertinoColors.systemRed.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(
            CupertinoIcons.exclamationmark_circle,
            size: 16,
            color: CupertinoColors.systemRed,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 13,
                color: CupertinoColors.systemRed,
              ),
            ),
          ),
          GestureDetector(
            onTap: onDismiss,
            child: const Icon(
              CupertinoIcons.xmark_circle_fill,
              size: 16,
              color: CupertinoColors.systemRed,
            ),
          ),
        ],
      ),
    );
  }
}

/// 排队待发送横幅（queue 行为 / steer 失败入队）。
class _QueuedBanner extends StatelessWidget {
  const _QueuedBanner({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: CupertinoColors.systemYellow.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '已排队 $count 条消息，将在当前回复结束后自动发送',
        style: const TextStyle(fontSize: 12, color: CupertinoColors.systemBrown),
      ),
    );
  }
}
