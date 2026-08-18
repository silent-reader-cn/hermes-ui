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
    // 初始化时拉取 YOLO 状态（控制器内部一次性守卫，安全可重复调用）。
    unawaited(
      ref.read(chatControllerProvider(sessionId).notifier).loadYoloState(),
    );
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
            if (state.hasPendingUserMessage)
              const _PendingUserMessageBanner(),
            if (state.noticeMessage != null)
              _NoticeBanner(
                message: state.noticeMessage!,
                onDismiss: () =>
                    ref.read(chatControllerProvider(sessionId).notifier).dismissNotice(),
              ),
            ChatInputBar(sessionId: sessionId, enabled: !state.isReadOnly),
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
  final isReadOnly = state.isReadOnly;
  final action = await showCupertinoModalPopup<String>(
    context: context,
    builder: (sheetContext) => CupertinoActionSheet(
      title: Text(state.displayTitle),
      // 只读会话：仅保留 分支/导出（变更类操作全部不展示）。
      actions: [
        if (!isReadOnly) ...[
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
            key: const ValueKey('chat-action-compress'),
            onPressed: () => Navigator.pop(sheetContext, 'compress'),
            child: const Text('压缩会话'),
          ),
          CupertinoActionSheetAction(
            key: const ValueKey('chat-action-undo'),
            onPressed: () => Navigator.pop(sheetContext, 'undo'),
            child: const Text('撤销上一轮'),
          ),
          CupertinoActionSheetAction(
            key: const ValueKey('chat-action-retry'),
            onPressed: () => Navigator.pop(sheetContext, 'retry'),
            child: const Text('重试上一轮'),
          ),
          CupertinoActionSheetAction(
            key: const ValueKey('chat-action-settings'),
            onPressed: () => Navigator.pop(sheetContext, 'settings'),
            child: const Text('会话设置'),
          ),
          CupertinoActionSheetAction(
            key: const ValueKey('chat-action-yolo'),
            onPressed: () => Navigator.pop(sheetContext, 'yolo'),
            child: Text(state.yoloEnabled ? '关闭 YOLO' : '开启 YOLO'),
          ),
        ],
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
        if (!isReadOnly)
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
    case 'compress':
      await _compressSession(context, controller);
    case 'undo':
      final confirmed = await _confirmSessionUndo(context);
      if (confirmed) await controller.undoLastTurn();
    case 'retry':
      await controller.retryLastTurn();
    case 'settings':
      await _sessionSettings(context, controller, state);
    case 'yolo':
      await controller.toggleYolo(!state.yoloEnabled);
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

/// 压缩会话：可选输入聚焦主题（留空 = 全量压缩）；成功后由控制器轻提示。
Future<void> _compressSession(
  BuildContext context,
  ChatController controller,
) async {
  final input = TextEditingController();
  final focusTopic = await showCupertinoDialog<String>(
    context: context,
    builder: (dialogContext) => CupertinoAlertDialog(
      title: const Text('压缩会话'),
      content: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: CupertinoTextField(
          key: const ValueKey('chat-compress-topic'),
          controller: input,
          placeholder: '聚焦主题（可留空）',
          autofocus: true,
        ),
      ),
      actions: [
        CupertinoDialogAction(
          key: const ValueKey('chat-compress-cancel'),
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('取消'),
        ),
        CupertinoDialogAction(
          key: const ValueKey('chat-compress-confirm'),
          onPressed: () => Navigator.pop(dialogContext, input.text),
          child: const Text('压缩'),
        ),
      ],
    ),
  );
  input.dispose();
  if (focusTopic != null) {
    await controller.compressSession(focusTopic: focusTopic);
  }
}

/// 撤销上一轮确认（删除最后一轮对话，不可撤销）。
Future<bool> _confirmSessionUndo(BuildContext context) async {
  final result = await showCupertinoDialog<bool>(
    context: context,
    builder: (dialogContext) => CupertinoAlertDialog(
      title: const Text('撤销上一轮'),
      content: const Text('删除最后一轮对话？此操作不可撤销'),
      actions: [
        CupertinoDialogAction(
          key: const ValueKey('chat-undo-cancel'),
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('取消'),
        ),
        CupertinoDialogAction(
          key: const ValueKey('chat-undo-confirm'),
          isDestructiveAction: true,
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('删除'),
        ),
      ],
    ),
  );
  return result == true;
}

/// 会话设置：workspace + 模型名（文本输入，可留空）；保存后控制器乐观更新。
Future<void> _sessionSettings(
  BuildContext context,
  ChatController controller,
  ChatState state,
) async {
  final workspaceInput = TextEditingController(text: state.workspace ?? '');
  final modelInput = TextEditingController(text: state.model ?? '');
  final result = await showCupertinoDialog<({String workspace, String model})>(
    context: context,
    builder: (dialogContext) => CupertinoAlertDialog(
      title: const Text('会话设置'),
      content: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CupertinoTextField(
              key: const ValueKey('chat-settings-workspace'),
              controller: workspaceInput,
              placeholder: 'Workspace（可留空）',
            ),
            const SizedBox(height: 8),
            CupertinoTextField(
              key: const ValueKey('chat-settings-model'),
              controller: modelInput,
              placeholder: '模型名（可留空）',
            ),
          ],
        ),
      ),
      actions: [
        CupertinoDialogAction(
          key: const ValueKey('chat-settings-cancel'),
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('取消'),
        ),
        CupertinoDialogAction(
          key: const ValueKey('chat-settings-save'),
          onPressed: () => Navigator.pop(
            dialogContext,
            (workspace: workspaceInput.text, model: modelInput.text),
          ),
          child: const Text('保存'),
        ),
      ],
    ),
  );
  workspaceInput.dispose();
  modelInput.dispose();
  if (result != null) {
    await controller.updateSessionSettings(
      workspace: result.workspace,
      model: result.model,
    );
  }
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

/// 待处理消息提示条（会话有一条 pending 消息在服务端排着）。
class _PendingUserMessageBanner extends StatelessWidget {
  const _PendingUserMessageBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('chat-pending-banner'),
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: CupertinoColors.systemGrey5.resolveFrom(context),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Text(
        '（该会话有一条待处理消息…）',
        style: TextStyle(fontSize: 12, color: CupertinoColors.secondaryLabel),
      ),
    );
  }
}

/// 成功类会话操作轻提示横幅（可点 × 关闭）。
class _NoticeBanner extends StatelessWidget {
  const _NoticeBanner({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: CupertinoColors.systemGreen.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(
            CupertinoIcons.checkmark_circle,
            size: 16,
            color: CupertinoColors.systemGreen,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 13, color: statusGreenText),
            ),
          ),
          GestureDetector(
            onTap: onDismiss,
            child: const Icon(
              CupertinoIcons.xmark_circle_fill,
              size: 16,
              color: CupertinoColors.systemGrey,
            ),
          ),
        ],
      ),
    );
  }
}
