import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import '../../../core/models/chat_message.dart';

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
  final hasContent = (message.content ?? '').trim().isNotEmpty;
  return showCupertinoModalPopup<String>(
    context: context,
    builder: (sheetContext) => CupertinoActionSheet(
      title: const Text('消息操作', style: TextStyle(fontSize: 15)),
      actions: [
        CupertinoActionSheetAction(
          key: const ValueKey('msg-action-copy'),
          onPressed: hasContent
              ? () => Navigator.pop(sheetContext, MessageAction.copy)
              : () {},
          child: const Text('复制文本'),
        ),
        CupertinoActionSheetAction(
          key: const ValueKey('msg-action-copy-md'),
          onPressed: hasContent
              ? () => Navigator.pop(sheetContext, MessageAction.copyMd)
              : () {},
          child: const Text('复制 Markdown'),
        ),
        if (message.role == 'user')
          CupertinoActionSheetAction(
            key: const ValueKey('msg-action-edit'),
            onPressed: () => Navigator.pop(sheetContext, MessageAction.edit),
            child: const Text('编辑并重新发送'),
          ),
        CupertinoActionSheetAction(
          key: const ValueKey('msg-action-branch'),
          onPressed: () => Navigator.pop(sheetContext, MessageAction.branch),
          child: const Text('从此处创建分支'),
        ),
        CupertinoActionSheetAction(
          key: const ValueKey('msg-action-truncate'),
          isDestructiveAction: true,
          onPressed: () async {
            final confirmed = await showCupertinoDialog<bool>(
              context: sheetContext,
              builder: (dialogContext) => CupertinoAlertDialog(
                title: const Text('从此处截断'),
                content: const Text('删除此消息之后的所有消息？此操作不可撤销。'),
                actions: [
                  CupertinoDialogAction(
                    key: const ValueKey('msg-truncate-cancel'),
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('取消'),
                  ),
                  CupertinoDialogAction(
                    key: const ValueKey('msg-truncate-confirm'),
                    isDestructiveAction: true,
                    onPressed: () => Navigator.pop(dialogContext, true),
                    child: const Text('截断'),
                  ),
                ],
              ),
            );
            if (confirmed == true && sheetContext.mounted) {
              Navigator.pop(sheetContext, MessageAction.truncate);
            }
          },
          child: const Text('从此处截断'),
        ),
      ],
      cancelButton: CupertinoActionSheetAction(
        key: const ValueKey('msg-action-cancel'),
        onPressed: () => Navigator.pop(sheetContext),
        child: const Text('取消'),
      ),
    ),
  );
}

/// 把 [message] 的纯文本写入剪贴板（返回结果供提示用）。
Future<void> copyMessageText(ChatMessage message) {
  return Clipboard.setData(ClipboardData(text: message.content ?? ''));
}
