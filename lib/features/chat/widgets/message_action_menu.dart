import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../../../core/models/chat_message.dart';
import '../../../l10n/app_localizations.dart';

/// 消息级操作菜单返回的动作 tag。
///
/// - `copy`：复制纯文本；
/// - `copy_md`：复制 Markdown 原文；
/// - `edit`：用户消息回填输入框；
/// - `branch`：从此处创建分支；
/// - `truncate`：从此处截断（确认对话框已通过）。
abstract final class MessageAction {
  static const String copy = 'copy';
  static const String copyMd = 'copy_md';
  static const String edit = 'edit';
  static const String branch = 'branch';
  static const String truncate = 'truncate';
}

/// 弹出的消息操作菜单；返回 [MessageAction] tag，取消返回 null。
///
/// `truncate` 动作内部先弹确认对话框，确认后才返回 tag（取消层级：菜单取消 → null）。
/// 内容为空时复制/复制MD 项禁用。
Future<String?> showMessageActionMenu(
  BuildContext context, {
  required ChatMessage message,
}) {
  final l10n = AppLocalizations.of(context);
  final hasContent = (message.content ?? '').trim().isNotEmpty;
  return showCupertinoModalPopup<String>(
    context: context,
    builder: (sheetContext) => CupertinoActionSheet(
      title: Text(l10n.messageActions, style: const TextStyle(fontSize: 15)),
      actions: [
        CupertinoActionSheetAction(
          key: const ValueKey('msg-action-copy'),
          onPressed: hasContent
              ? () => Navigator.pop(sheetContext, MessageAction.copy)
              : () {},
          child: Text(l10n.copyText),
        ),
        CupertinoActionSheetAction(
          key: const ValueKey('msg-action-copy-md'),
          onPressed: hasContent
              ? () => Navigator.pop(sheetContext, MessageAction.copyMd)
              : () {},
          child: Text(l10n.copyMarkdown),
        ),
        if (message.role == 'user')
          CupertinoActionSheetAction(
            key: const ValueKey('msg-action-edit'),
            onPressed: () => Navigator.pop(sheetContext, MessageAction.edit),
            child: Text(l10n.editAndResend),
          ),
        CupertinoActionSheetAction(
          key: const ValueKey('msg-action-branch'),
          onPressed: () => Navigator.pop(sheetContext, MessageAction.branch),
          child: Text(l10n.branchFromHere),
        ),
        CupertinoActionSheetAction(
          key: const ValueKey('msg-action-truncate'),
          isDestructiveAction: true,
          onPressed: () async {
            final confirmed = await showCupertinoDialog<bool>(
              context: sheetContext,
              builder: (dialogContext) => CupertinoAlertDialog(
                title: Text(l10n.truncateFromHere),
                content: Text(l10n.confirmTruncatePrompt),
                actions: [
                  CupertinoDialogAction(
                    key: const ValueKey('msg-truncate-cancel'),
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: Text(l10n.cancel),
                  ),
                  CupertinoDialogAction(
                    key: const ValueKey('msg-truncate-confirm'),
                    isDestructiveAction: true,
                    onPressed: () => Navigator.pop(dialogContext, true),
                    child: Text(l10n.truncate),
                  ),
                ],
              ),
            );
            if (confirmed == true && sheetContext.mounted) {
              Navigator.pop(sheetContext, MessageAction.truncate);
            }
          },
          child: Text(l10n.truncateFromHere),
        ),
      ],
      cancelButton: CupertinoActionSheetAction(
        key: const ValueKey('msg-action-cancel'),
        onPressed: () => Navigator.pop(sheetContext),
        child: Text(l10n.cancel),
      ),
    ),
  );
}

/// 把 [message] 的纯文本写入剪贴板（返回结果供提示用）。
Future<void> copyMessageText(ChatMessage message) {
  return Clipboard.setData(ClipboardData(text: message.content ?? ''));
}
