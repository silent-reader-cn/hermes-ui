import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/session.dart';
import '../projects/project_providers.dart';

/// 弹出项目选择器（底部 ActionSheet 列表 + 新建项目入口）。
///
/// 返回选中的 `projectId`（选择「无项目」返回空串）；取消返回 null。
/// 新建项目成功后立即返回新项目 id。
Future<String?> showProjectPicker(BuildContext context) {
  return showCupertinoModalPopup<String>(
    context: context,
    builder: (sheetContext) => const _ProjectPickerSheet(),
  );
}

class _ProjectPickerSheet extends ConsumerWidget {
  const _ProjectPickerSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(projectsProvider);
    final projects = async.valueOrNull ?? const <ProjectSummary>[];

    return CupertinoActionSheet(
      title: const Text('移动到项目'),
      message: async.isLoading
          ? const CupertinoActivityIndicator(radius: 12)
          : null,
      actions: [
        CupertinoActionSheetAction(
          key: const ValueKey('project-picker-none'),
          onPressed: () => Navigator.pop(context, ''),
          child: const Text('无项目'),
        ),
        for (final project in projects)
          GestureDetector(
            key: ValueKey('project-picker-${project.id}'),
            behavior: HitTestBehavior.opaque,
            onLongPress: () => _showProjectActions(context, ref, project),
            child: CupertinoActionSheetAction(
              onPressed: () => Navigator.pop(context, project.id),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      project.name ?? '未命名项目',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    CupertinoIcons.ellipsis,
                    size: 14,
                    color: CupertinoColors.secondaryLabel.resolveFrom(context),
                  ),
                ],
              ),
            ),
          ),
        CupertinoActionSheetAction(
          key: const ValueKey('project-picker-create'),
          onPressed: () async {
            final name = await _promptProjectName(
              context,
              title: '新建项目',
              confirmText: '创建',
            );
            if (name == null || !context.mounted) return;
            final created = await ref
                .read(projectsProvider.notifier)
                .createProject(name: name);
            if (!context.mounted) return;
            if (created != null) {
              Navigator.pop(context, created.id);
            }
          },
          child: const Text('新建项目…'),
        ),
      ],
      cancelButton: CupertinoActionSheetAction(
        key: const ValueKey('project-picker-cancel'),
        isDefaultAction: true,
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
    );
  }
}

Future<String?> _promptProjectName(
  BuildContext context, {
  required String title,
  required String confirmText,
}) async {
  final controller = TextEditingController();
  final name = await showCupertinoDialog<String>(
    context: context,
    builder: (dialogContext) => CupertinoAlertDialog(
      key: const ValueKey('project-create-dialog'),
      title: Text(title),
      content: CupertinoTextField(
        key: const ValueKey('project-create-name'),
        controller: controller,
        autofocus: true,
        placeholder: '项目名称',
      ),
      actions: [
        CupertinoDialogAction(
          key: const ValueKey('project-create-cancel'),
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('取消'),
        ),
        CupertinoDialogAction(
          key: const ValueKey('project-create-confirm'),
          onPressed: () => Navigator.pop(dialogContext, controller.text),
          child: Text(confirmText),
        ),
      ],
    ),
  );
  controller.dispose();
  return name;
}

/// 长按项目行：弹管理菜单（重命名 / 删除，删除需确认）。
Future<void> _showProjectActions(
  BuildContext context,
  WidgetRef ref,
  ProjectSummary project,
) async {
  final action = await showCupertinoModalPopup<String>(
    context: context,
    builder: (sheetContext) => CupertinoActionSheet(
      title: Text(project.name ?? '未命名项目'),
      message: const Text('项目管理'),
      actions: [
        CupertinoActionSheetAction(
          key: const ValueKey('project-action-rename'),
          onPressed: () => Navigator.pop(sheetContext, 'rename'),
          child: const Text('重命名'),
        ),
        CupertinoActionSheetAction(
          key: const ValueKey('project-action-delete'),
          isDestructiveAction: true,
          onPressed: () => Navigator.pop(sheetContext, 'delete'),
          child: const Text('删除'),
        ),
      ],
      cancelButton: CupertinoActionSheetAction(
        key: const ValueKey('project-action-cancel'),
        isDefaultAction: true,
        onPressed: () => Navigator.pop(sheetContext),
        child: const Text('取消'),
      ),
    ),
  );
  if (action == null || !context.mounted) return;
  final notifier = ref.read(projectsProvider.notifier);
  if (action == 'rename') {
    final name = await _promptProjectName(
      context,
      title: '重命名项目',
      confirmText: '保存',
    );
    if (name == null || name.trim().isEmpty || !context.mounted) return;
    await notifier.renameProject(projectId: project.id, name: name.trim());
  } else if (action == 'delete') {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: const Text('删除项目'),
        content: const Text('删除后项目内会话不会被删除，仅解除归类。'),
        actions: [
          CupertinoDialogAction(
            key: const ValueKey('project-delete-cancel'),
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            key: const ValueKey('project-delete-confirm'),
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await notifier.deleteProject(project.id);
    }
  }
}
