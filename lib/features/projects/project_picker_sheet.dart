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
          CupertinoActionSheetAction(
            key: ValueKey('project-picker-${project.id}'),
            onPressed: () => Navigator.pop(context, project.id),
            child: Text(project.name ?? '未命名项目'),
          ),
        CupertinoActionSheetAction(
          key: const ValueKey('project-picker-create'),
          onPressed: () async {
            final name = await _promptProjectName(context);
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

Future<String?> _promptProjectName(BuildContext context) async {
  final controller = TextEditingController();
  final name = await showCupertinoDialog<String>(
    context: context,
    builder: (dialogContext) => CupertinoAlertDialog(
      key: const ValueKey('project-create-dialog'),
      title: const Text('新建项目'),
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
          child: const Text('创建'),
        ),
      ],
    ),
  );
  controller.dispose();
  return name;
}