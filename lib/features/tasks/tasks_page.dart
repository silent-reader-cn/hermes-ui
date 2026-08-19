import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/status_colors.dart';
import '../../core/api/api_exception.dart';
import '../../core/models/cron.dart';
import '../../core/utils/accessibility.dart';
import '../shared/app_back_button.dart';
import 'tasks_providers.dart';

/// 任务状态文案（运行中 / 已暂停 / 已停用 / 出错 / 需关注 / 正常）。
///
/// `state == 'running'` 优先于 [CronJob.status]（运行是瞬时态，status 枚举
/// 不区分）。
String taskStatusLabel(CronJob job) {
  if (job.state == 'running') return '运行中';
  switch (job.status) {
    case CronJobStatus.active:
      return '正常';
    case CronJobStatus.paused:
      return '已暂停';
    case CronJobStatus.off:
      return '已停用';
    case CronJobStatus.error:
      return '出错';
    case CronJobStatus.needsAttention:
      return '需关注';
  }
}

/// 任务状态标识颜色（与 [taskStatusLabel] 一一对应）。
///
/// 返回 [CupertinoDynamicColor]：圆点与文字共用，浅色/深色均满足 WCAG AA
/// （浅色用深变体、深色用亮变体，见 theme/status_colors.dart）。
Color taskStatusColor(CronJob job) {
  if (job.state == 'running') return statusGreenText;
  switch (job.status) {
    case CronJobStatus.active:
      return statusBlueText;
    case CronJobStatus.paused:
      return statusOrangeText;
    case CronJobStatus.off:
      return statusGreyText;
    case CronJobStatus.error:
      return CupertinoColors.systemRed;
    case CronJobStatus.needsAttention:
      return CupertinoColors.systemYellow;
  }
}

/// 定时任务管理页（`/tasks`）。
///
/// Cupertino 风格：大标题 + 新建按钮 + 下拉刷新 + 任务列表（状态圆点 + 名称 +
/// 调度/上次运行 + ellipsis 行菜单：运行 / 暂停 / 恢复 / 编辑 / 查看输出 / 删除）
/// + 加载 / 错误 / 空态。新建与编辑共用 [TasksEditPage] 表单页。
class TasksPage extends ConsumerStatefulWidget {
  const TasksPage({super.key});

  @override
  ConsumerState<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends ConsumerState<TasksPage> {
  @override
  Widget build(BuildContext context) {
    final async = ref.watch(tasksControllerProvider);
    final state = async.valueOrNull;

    ref.listen<AsyncValue<TasksState>>(
      tasksControllerProvider,
      (previous, next) {
        final error = next.valueOrNull?.actionError;
        if (error != null && error != previous?.valueOrNull?.actionError) {
          unawaited(_showActionError(context, error));
        }
      },
    );

    return CupertinoPageScaffold(
      child: CustomScrollView(
        key: const ValueKey('tasks-scroll'),
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          CupertinoSliverNavigationBar(
            largeTitle: const Text('定时任务'),
            leading: const AppBackButton(),
            trailing: AccessibleButton(
              key: const ValueKey('tasks-create'),
              label: '新建定时任务',
              padding: EdgeInsets.zero,
              onPressed: () => _openEditor(context),
              child: const Icon(CupertinoIcons.add),
            ),
          ),
          // 刷新指示器必须排在所有 SliverToBoxAdapter 之前（对齐会话列表页）。
          CupertinoSliverRefreshControl(onRefresh: _onRefresh),
          ..._buildContentSlivers(async, state),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // 内容 slivers：加载 / 错误 / 空态 / 任务列表
  // -------------------------------------------------------------------------

  List<Widget> _buildContentSlivers(
    AsyncValue<TasksState> async,
    TasksState? state,
  ) {
    if (state == null) {
      if (async.isLoading) {
        return const [
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: CupertinoActivityIndicator(radius: 14)),
          ),
        ];
      }
      return [_buildErrorSliver(async.error)];
    }

    if (state.jobs.isEmpty) {
      return [_buildEmptySliver()];
    }

    return [
      SliverToBoxAdapter(
        child: CupertinoListSection.insetGrouped(
          header: Text('共 ${state.jobs.length} 个任务'),
          children: [
            for (final job in state.jobs)
              _TaskRow(
                key: ValueKey('tasks-row-${job.jobId ?? job.id}'),
                job: job,
                busy: state.isBusy(job.jobId ?? ''),
                onActions: () => _showRowActions(context, job),
              ),
          ],
        ),
      ),
    ];
  }

  Widget _buildErrorSliver(Object? error) {
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              CupertinoIcons.exclamationmark_triangle,
              size: 48,
              color: CupertinoColors.systemGrey,
            ),
            const SizedBox(height: 12),
            const Text(
              '加载失败',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              _errorMessage(error),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: statusRedText,
              ),
            ),
            const SizedBox(height: 20),
            CupertinoButton.filled(
              key: const ValueKey('tasks-retry'),
              onPressed: () => unawaited(_onRefresh()),
              child: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptySliver() {
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              CupertinoIcons.clock,
              size: 48,
              color: CupertinoColors.systemGrey,
            ),
            const SizedBox(height: 12),
            const Text('暂无任务', style: TextStyle(fontSize: 17)),
            const SizedBox(height: 6),
            const Text(
              '创建定时任务，让助手按调度自动执行',
              style: TextStyle(
                fontSize: 13,
                color: CupertinoColors.secondaryLabel,
              ),
            ),
            const SizedBox(height: 20),
            CupertinoButton.filled(
              key: const ValueKey('tasks-empty-create'),
              onPressed: () => _openEditor(context),
              child: const Text('新建任务'),
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // 交互：刷新 / 行菜单 / 输出 / 删除 / 表单
  // -------------------------------------------------------------------------

  Future<void> _onRefresh() =>
      ref.read(tasksControllerProvider.notifier).refresh();

  void _openEditor(BuildContext context, {CronJob? job}) {
    Navigator.of(context).push(
      CupertinoPageRoute<void>(builder: (_) => TasksEditPage(job: job)),
    );
  }

  void _showRowActions(BuildContext context, CronJob job) {
    final controller = ref.read(tasksControllerProvider.notifier);
    final paused = job.state == 'paused' || job.enabled == false;
    unawaited(
      showCupertinoModalPopup<void>(
        context: context,
        builder: (sheetContext) => CupertinoActionSheet(
          title: Text(job.displayName),
          actions: [
            CupertinoActionSheetAction(
              key: const ValueKey('tasks-action-run'),
              onPressed: () {
                Navigator.pop(sheetContext);
                unawaited(controller.run(job));
              },
              child: const Text('运行'),
            ),
            if (paused)
              CupertinoActionSheetAction(
                key: const ValueKey('tasks-action-resume'),
                onPressed: () {
                  Navigator.pop(sheetContext);
                  unawaited(controller.resume(job));
                },
                child: const Text('恢复'),
              )
            else
              CupertinoActionSheetAction(
                key: const ValueKey('tasks-action-pause'),
                onPressed: () {
                  Navigator.pop(sheetContext);
                  unawaited(controller.pause(job));
                },
                child: const Text('暂停'),
              ),
            CupertinoActionSheetAction(
              key: const ValueKey('tasks-action-edit'),
              onPressed: () {
                Navigator.pop(sheetContext);
                _openEditor(context, job: job);
              },
              child: const Text('编辑'),
            ),
            CupertinoActionSheetAction(
              key: const ValueKey('tasks-action-output'),
              onPressed: () {
                Navigator.pop(sheetContext);
                unawaited(_showOutput(context, job));
              },
              child: const Text('查看输出'),
            ),
            CupertinoActionSheetAction(
              key: const ValueKey('tasks-action-delete'),
              isDestructiveAction: true,
              onPressed: () {
                Navigator.pop(sheetContext);
                unawaited(_confirmDelete(context, job));
              },
              child: const Text('删除'),
            ),
          ],
          cancelButton: CupertinoActionSheetAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(sheetContext),
            child: const Text('取消'),
          ),
        ),
      ),
    );
  }

  Future<void> _showOutput(BuildContext context, CronJob job) async {
    final future = ref.read(tasksControllerProvider.notifier).fetchOutput(job);
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (sheetContext) => _TaskOutputSheet(outputFuture: future),
    );
  }

  Future<void> _confirmDelete(BuildContext context, CronJob job) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: const Text('删除任务'),
        content: Text('确定删除「${job.displayName}」？此操作不可撤销。'),
        actions: [
          CupertinoDialogAction(
            key: const ValueKey('tasks-delete-cancel'),
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          CupertinoDialogAction(
            key: const ValueKey('tasks-delete-confirm'),
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await ref.read(tasksControllerProvider.notifier).delete(job);
    }
  }

  Future<void> _showActionError(BuildContext context, String message) async {
    await showCupertinoDialog<void>(
      context: context,
      builder: (dialogContext) => CupertinoAlertDialog(
        title: const Text('操作失败'),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('好'),
          ),
        ],
      ),
    );
    await ref.read(tasksControllerProvider.notifier).clearActionError();
  }

  String _errorMessage(Object? error) {
    if (error is ApiException) return error.message;
    return error?.toString() ?? '未知错误';
  }
}

/// 单行任务：状态圆点 + 名称 + 状态标签 + 调度/上次运行 + ellipsis 操作按钮。
class _TaskRow extends StatelessWidget {
  const _TaskRow({
    super.key,
    required this.job,
    required this.busy,
    required this.onActions,
  });

  final CronJob job;
  final bool busy;
  final VoidCallback onActions;

  @override
  Widget build(BuildContext context) {
    final subtitle = _subtitle(job);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: taskStatusColor(job),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        job.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 17),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      taskStatusLabel(job),
                      style: TextStyle(
                        fontSize: 12,
                        color: taskStatusColor(job),
                      ),
                    ),
                  ],
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      color: CupertinoColors.secondaryLabel,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (busy)
            const Padding(
              padding: EdgeInsets.all(10),
              child: CupertinoActivityIndicator(radius: 9),
            )
          else
            AccessibleButton(
              key: ValueKey('tasks-actions-${job.jobId ?? job.id}'),
              label: '任务操作',
              padding: EdgeInsets.zero,
              minimumSize: const Size(36, 36),
              onPressed: onActions,
              child: const Icon(
                CupertinoIcons.ellipsis,
                size: 20,
                color: CupertinoColors.systemGrey,
              ),
            ),
        ],
      ),
    );
  }

  static String? _subtitle(CronJob job) {
    final parts = <String>[
      if (job.scheduleText != null && job.scheduleText!.isNotEmpty)
        job.scheduleText!,
      if (job.lastRunAt != null) '上次运行 ${_formatTime(job.lastRunAt!.date)}',
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  static String _formatTime(DateTime date) {
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}

/// 任务输出底部面板：加载中 → 输出列表（文件名 + 内容预览）→ 空态。
class _TaskOutputSheet extends StatelessWidget {
  const _TaskOutputSheet({required this.outputFuture});

  final Future<CronOutputResponse?> outputFuture;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.6,
        ),
        decoration: BoxDecoration(
          // 动态色需显式 resolve：暗黑模式下不 resolve 会画成白色面板。
          color: CupertinoColors.secondarySystemBackground.resolveFrom(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      '任务输出',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  AccessibleButton(
                    key: const ValueKey('tasks-output-close'),
                    label: '关闭输出面板',
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(36, 36),
                    onPressed: () => Navigator.pop(context),
                    child: const Icon(CupertinoIcons.xmark_circle_fill),
                  ),
                ],
              ),
            ),
            Flexible(
              child: FutureBuilder<CronOutputResponse?>(
                future: outputFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(
                        child: CupertinoActivityIndicator(radius: 12),
                      ),
                    );
                  }
                  final outputs =
                      snapshot.data?.outputs ?? const <CronOutputItem>[];
                  if (outputs.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: Text('暂无输出')),
                    );
                  }
                  return ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    itemCount: outputs.length,
                    separatorBuilder: (_, _) => Container(
                      height: 1,
                      color: CupertinoColors.separator,
                    ),
                    itemBuilder: (context, index) {
                      final item = outputs[index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.filename ?? '输出 ${index + 1}',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (item.content != null &&
                                item.content!.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                item.content!,
                                maxLines: 8,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: CupertinoColors.secondaryLabel,
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 新建 / 编辑定时任务表单页（CupertinoPageRoute push 进入）。
///
/// 字段：名称（可选）/ 调度表达式（必填）/ 提示词（必填）/ 推送通知。
/// 调度表达式与提示词为空时保存按钮禁用（对齐 Hermex 编辑草稿校验）。
class TasksEditPage extends ConsumerStatefulWidget {
  const TasksEditPage({super.key, this.job});

  /// 非 null = 编辑模式（字段预填）；null = 新建。
  final CronJob? job;

  @override
  ConsumerState<TasksEditPage> createState() => _TasksEditPageState();
}

class _TasksEditPageState extends ConsumerState<TasksEditPage> {
  late final TextEditingController _nameController;
  late final TextEditingController _scheduleController;
  late final TextEditingController _promptController;
  late bool _toastNotifications;
  bool _saving = false;

  bool get _isEdit => widget.job != null;

  bool get _canSave =>
      !_saving &&
      _scheduleController.text.trim().isNotEmpty &&
      _promptController.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    final job = widget.job;
    _nameController = TextEditingController(text: job?.name ?? '');
    _scheduleController = TextEditingController(
      text: job?.editableScheduleText ?? '',
    );
    _promptController = TextEditingController(text: job?.prompt ?? '');
    _toastNotifications = job?.toastNotifications ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _scheduleController.dispose();
    _promptController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(_isEdit ? '编辑任务' : '新建任务'),
        trailing: CupertinoButton(
          key: const ValueKey('tasks-form-save'),
          padding: EdgeInsets.zero,
          onPressed: _canSave ? () => unawaited(_save(context)) : null,
          child: Text(_isEdit ? '保存' : '创建'),
        ),
      ),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildField(
            label: '名称',
            fieldKey: const ValueKey('tasks-form-name'),
            controller: _nameController,
            placeholder: '任务名称（可选）',
          ),
          const SizedBox(height: 16),
          _buildField(
            label: '调度表达式',
            fieldKey: const ValueKey('tasks-form-schedule'),
            controller: _scheduleController,
            placeholder: '例如 0 9 * * * 或 every 2 hours',
          ),
          const SizedBox(height: 16),
          _buildField(
            label: '提示词',
            fieldKey: const ValueKey('tasks-form-prompt'),
            controller: _promptController,
            placeholder: '定时执行时发送给助手的提示词',
            maxLines: 6,
          ),
          const SizedBox(height: 16),
          CupertinoListTile(
            title: const Text('推送通知'),
            trailing: CupertinoSwitch(
              key: const ValueKey('tasks-form-toast'),
              value: _toastNotifications,
              onChanged: (value) => setState(() => _toastNotifications = value),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildField({
    required String label,
    required Key fieldKey,
    required TextEditingController controller,
    required String placeholder,
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            color: CupertinoColors.secondaryLabel,
          ),
        ),
        const SizedBox(height: 6),
        CupertinoTextField(
          key: fieldKey,
          controller: controller,
          placeholder: placeholder,
          maxLines: maxLines,
          onChanged: (_) => setState(() {}),
        ),
      ],
    );
  }

  Future<void> _save(BuildContext context) async {
    setState(() => _saving = true);
    final controller = ref.read(tasksControllerProvider.notifier);
    final job = widget.job;
    final ok = job == null
        ? await controller.create(
            name: _nameController.text,
            schedule: _scheduleController.text.trim(),
            prompt: _promptController.text.trim(),
            toastNotifications: _toastNotifications,
          )
        : await controller.save(
            job,
            name: _nameController.text,
            schedule: _scheduleController.text.trim(),
            prompt: _promptController.text.trim(),
            toastNotifications: _toastNotifications,
          );
    if (!context.mounted) return;
    setState(() => _saving = false);
    if (ok) {
      Navigator.maybePop(context);
    }
  }
}
