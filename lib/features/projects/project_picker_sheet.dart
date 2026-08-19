import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/session.dart';
import '../../l10n/app_localizations.dart';
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
    final l10n = AppLocalizations.of(context);
    final async = ref.watch(projectsProvider);
    final projects = async.valueOrNull ?? const <ProjectSummary>[];

    return CupertinoActionSheet(
      title: Text(l10n.moveToProject),
      message: async.isLoading
          ? const CupertinoActivityIndicator(radius: 12)
          : null,
      actions: [
        CupertinoActionSheetAction(
          key: const ValueKey('project-picker-none'),
          onPressed: () => Navigator.pop(context, ''),
          child: Text(l10n.noProject),
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
                      project.name ?? l10n.unnamedProject,
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
              title: l10n.newProject,
              confirmText: l10n.create,
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
          child: Text(l10n.newProjectEllipsis),
        ),
      ],
      cancelButton: CupertinoActionSheetAction(
        key: const ValueKey('project-picker-cancel'),
        isDefaultAction: true,
        onPressed: () => Navigator.pop(context),
        child: Text(l10n.cancel),
      ),
    );
  }
}

Future<String?> _promptProjectName(
  BuildContext context, {
  required String title,
  required String confirmText,
}) async {
  final l10n = AppLocalizations.of(context);
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
        placeholder: l10n.projectNamePlaceholder,
      ),
      actions: [
        CupertinoDialogAction(
          key: const ValueKey('project-create-cancel'),
          onPressed: () => Navigator.pop(dialogContext),
          child: Text(l10n.cancel),
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
  final l10n = AppLocalizations.of(context);
  final action = await showCupertinoModalPopup<String>(
    context: context,
    builder: (sheetContext) => CupertinoActionSheet(
      title: Text(project.name ?? l10n.unnamedProject),
      message: Text(l10n.projectManagement),
      actions: [
        CupertinoActionSheetAction(
          key: const ValueKey('project-action-rename'),
          onPressed: () => Navigator.pop(sheetContext, 'rename'),
          child: Text(l10n.rename),
        ),
        CupertinoActionSheetAction(
          key: const ValueKey('project-action-delete'),
          isDestructiveAction: true,
          onPressed: () => Navigator.pop(sheetContext, 'delete'),
          child: Text(l10n.delete),
        ),
      ],
      cancelButton: CupertinoActionSheetAction(
        key: const ValueKey('project-action-cancel'),
        isDefaultAction: true,
        onPressed: () => Navigator.pop(sheetContext),
        child: Text(l10n.cancel),
      ),
    ),
  );
  if (action == null || !context.mounted) return;
  final notifier = ref.read(projectsProvider.notifier);
  if (action == 'rename') {
    final name = await _promptProjectName(
      context,
      title: l10n.renameProject,
      confirmText: l10n.save,
    );
    if (name == null || name.trim().isEmpty || !context.mounted) return;
    await notifier.renameProject(projectId: project.id, name: name.trim());
  } else if (action == 'delete') {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: Text(l10n.deleteProject),
        content: Text(l10n.deleteProjectWarning),
        actions: [
          CupertinoDialogAction(
            key: const ValueKey('project-delete-cancel'),
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.cancel),
          ),
          CupertinoDialogAction(
            key: const ValueKey('project-delete-confirm'),
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await notifier.deleteProject(project.id);
    }
  }
}
