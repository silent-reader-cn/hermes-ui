import 'dart:async';
import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/status_colors.dart';
import '../../core/api/api_client_sessions.dart';
import '../../core/api/api_exception.dart';
import '../../core/connections/connection_providers.dart';
import '../shared/app_back_button.dart';
import 'chat_controller.dart';
import 'chat_providers.dart';
import 'chat_state.dart';
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
        leading: const AppBackButton(),
        middle: Text(
          state.displayTitle,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: CupertinoButton(
          key: const ValueKey('chat-session-actions'),
          padding: EdgeInsets.zero,
          onPressed: () => _showSessionActions(context, ref, sessionId, state),
          child: const Icon(CupertinoIcons.ellipsis),
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

Future<void> _showSessionActions(
  BuildContext context,
  WidgetRef ref,
  String sessionId,
  ChatState state,
) async {
  if (sessionId.isEmpty) return;
  final action = await showCupertinoModalPopup<String>(
    context: context,
    builder: (sheetContext) => CupertinoActionSheet(
      title: Text(state.displayTitle),
      actions: [
        CupertinoActionSheetAction(
          key: const ValueKey('chat-action-rename'),
          onPressed: () => Navigator.pop(sheetContext, 'rename'),
          child: const Text('重命名'),
        ),
        CupertinoActionSheetAction(
          key: const ValueKey('chat-action-pin'),
          onPressed: () => Navigator.pop(sheetContext, 'pin'),
          child: const Text('置顶'),
        ),
        CupertinoActionSheetAction(
          key: const ValueKey('chat-action-archive'),
          onPressed: () => Navigator.pop(sheetContext, 'archive'),
          child: const Text('归档'),
        ),
        CupertinoActionSheetAction(
          key: const ValueKey('chat-action-branch'),
          onPressed: () => Navigator.pop(sheetContext, 'branch'),
          child: const Text('创建分支'),
        ),
        CupertinoActionSheetAction(
          key: const ValueKey('chat-action-export'),
          onPressed: () => Navigator.pop(sheetContext, 'export'),
          child: const Text('导出'),
        ),
        CupertinoActionSheetAction(
          key: const ValueKey('chat-action-delete'),
          isDestructiveAction: true,
          onPressed: () => Navigator.pop(sheetContext, 'delete'),
          child: const Text('删除'),
        ),
      ],
      cancelButton: CupertinoActionSheetAction(
        key: const ValueKey('chat-action-cancel'),
        onPressed: () => Navigator.pop(sheetContext),
        child: const Text('取消'),
      ),
    ),
  );
  if (!context.mounted || action == null) return;
  final controller = ref.read(chatControllerProvider(sessionId).notifier);
  switch (action) {
    case 'rename':
      await _renameSession(context, controller, state.displayTitle);
    case 'pin':
      await controller.setPinned(true);
    case 'archive':
      if (await controller.setArchived(true)) {
        if (context.mounted) context.go('/');
      }
    case 'branch':
      final newId = await controller.branchSession();
      if (newId != null) {
        if (context.mounted) context.go('/chat/$newId');
      }
    case 'export':
      await _exportSession(context, ref, sessionId);
    case 'delete':
      final confirmed = await _confirmSessionDelete(context, state.displayTitle);
      if (confirmed) {
        if (await controller.deleteSession()) {
          if (context.mounted) context.go('/');
        }
      }
  }
}

Future<void> _renameSession(BuildContext context, ChatController controller, String current) async {
  final input = TextEditingController(text: current);
  final title = await showCupertinoDialog<String>(
    context: context,
    builder: (dialogContext) => CupertinoAlertDialog(
      title: const Text('重命名会话'),
      content: Padding(padding: const EdgeInsets.only(top: 12), child: CupertinoTextField(controller: input, autofocus: true)),
      actions: [
        CupertinoDialogAction(
          key: const ValueKey('chat-rename-cancel'),
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('取消'),
        ),
        CupertinoDialogAction(
          key: const ValueKey('chat-rename-save'),
          onPressed: () => Navigator.pop(dialogContext, input.text),
          child: const Text('保存'),
        ),
      ],
    ),
  );
  input.dispose();
  if (title != null) await controller.renameSession(title);
}

Future<bool> _confirmSessionDelete(BuildContext context, String title) async {
  final result = await showCupertinoDialog<bool>(
    context: context,
    builder: (dialogContext) => CupertinoAlertDialog(
      title: const Text('删除会话'),
      content: Text('确定删除「$title」？此操作不可撤销。'),
      actions: [
        CupertinoDialogAction(
          key: const ValueKey('chat-delete-cancel'),
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('取消'),
        ),
        CupertinoDialogAction(
          key: const ValueKey('chat-delete-confirm'),
          isDestructiveAction: true,
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('删除'),
        ),
      ],
    ),
  );
  return result == true;
}

Future<void> _exportSession(BuildContext context, WidgetRef ref, String sessionId) async {
  try {
    final response = await ref.read(apiClientProvider).exportSession(sessionId: sessionId, format: 'md');
    final content = utf8.decode(response.data, allowMalformed: true);
    await Clipboard.setData(ClipboardData(text: content));
    if (context.mounted) {
      await showCupertinoDialog<void>(
        context: context,
        builder: (dialogContext) => CupertinoAlertDialog(
          title: const Text('导出成功'),
          content: const Text('Markdown 已复制到剪贴板。'),
          actions: [CupertinoDialogAction(onPressed: () => Navigator.pop(dialogContext), child: const Text('好'))],
        ),
      );
    }
  } on ApiException catch (error) {
    if (context.mounted) {
      await showCupertinoDialog<void>(
        context: context,
        builder: (dialogContext) => CupertinoAlertDialog(
          title: const Text('导出失败'),
          content: Text(error.message),
          actions: [CupertinoDialogAction(onPressed: () => Navigator.pop(dialogContext), child: const Text('好'))],
        ),
      );
    }
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
                color: statusRedText,
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
