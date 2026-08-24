import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermex_flutter/app/theme/status_colors.dart';
import 'package:hermex_flutter/core/api/api_client.dart';
import 'package:hermex_flutter/core/api/api_exception.dart';
import 'package:hermex_flutter/core/connections/connection_providers.dart';
import 'package:hermex_flutter/core/models/cron.dart';
import 'package:hermex_flutter/features/tasks/tasks_page.dart';
import 'package:hermex_flutter/features/tasks/tasks_providers.dart';

import '../../helpers/fake_tasks_api.dart';

/// 构造测试任务（jobId 必填；state/enabled/lastStatus/lastRunAt 可配）。
CronJob buildJob(
  String id, {
  String? name,
  String? state,
  bool? enabled,
  String? lastStatus,
  CronDateValue? lastRunAt,
  CronSchedule? schedule,
  CronRepeat? repeatInfo,
  CronDateValue? nextRunAt,
}) {
  return CronJob(
    jobId: id,
    name: name ?? '任务 $id',
    prompt: '提示词 $id',
    schedule: schedule ?? const CronSchedule(expression: '0 9 * * *'),
    state: state,
    enabled: enabled,
    lastStatus: lastStatus,
    lastRunAt: lastRunAt,
    repeatInfo: repeatInfo,
    nextRunAt: nextRunAt,
  );
}

/// 组装 TasksPage（注入 fake API；页面只用 Navigator push/pop，无需路由表）。
Future<void> pumpTasksPage(
  WidgetTester tester,
  FakeTasksApi api, {
  Brightness brightness = Brightness.light,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(
          ApiClient(baseUrl: 'http://test.local:30002'),
        ),
        tasksApiFactoryProvider.overrideWithValue((_) => api),
      ],
      child: CupertinoApp(
        theme: CupertinoThemeData(brightness: brightness),
        home: const TasksPage(),
      ),
    ),
  );
  // 首帧（AsyncLoading）+ 异步 build 完成（AsyncData）
  await tester.pump();
  await tester.pump();
}

void main() {
  group('taskStatusLabel 与 taskStatusColor 状态与配色', () {
    test('运行中 / 已暂停 / 正常 / 已停用 / 出错 / 需关注', () {
      final runningJob = buildJob('a', state: 'running');
      final pausedJob = buildJob('b', state: 'paused');
      final normalJob = buildJob('c');
      final offJob = buildJob('d', enabled: false);
      final errorJob = buildJob('e', lastStatus: 'error');
      final needsAttentionJob = buildJob(
        'f',
        schedule: const CronSchedule(kind: 'cron', expression: '0 9 * * *'),
        enabled: false,
        state: 'completed',
      );

      expect(taskStatusLabel(runningJob), '运行中');
      expect(taskStatusLabel(pausedJob), '已暂停');
      expect(taskStatusLabel(normalJob), '正常');
      expect(taskStatusLabel(offJob), '已停用');
      expect(taskStatusLabel(errorJob), '出错');
      expect(taskStatusLabel(needsAttentionJob), '需关注');

      expect(taskStatusColor(runningJob), statusGreenText);
      expect(taskStatusColor(normalJob), statusBlueText);
      expect(taskStatusColor(pausedJob), statusOrangeText);
      expect(taskStatusColor(offJob), statusGreyText);
      expect(taskStatusColor(errorJob), statusRedText);
      expect(taskStatusColor(needsAttentionJob), statusOrangeText);
    });
  });

  group('TasksPage widget', () {
    testWidgets('列表渲染：任务名 + 状态标签 + 调度文本与上次运行副标 + 新建按钮', (tester) async {
      final api = FakeTasksApi(
        jobs: [
          buildJob('j1', name: '运行中的任务', state: 'running'),
          buildJob('j2', name: '暂停的任务', state: 'paused'),
          buildJob(
            'j3',
            name: '正常的任务',
            lastRunAt: CronDateValue(DateTime(2026, 8, 20, 9, 30)),
          ),
          buildJob('j4', name: '已停用任务', enabled: false),
        ],
      );
      await pumpTasksPage(tester, api, brightness: Brightness.dark);

      expect(find.text('定时任务'), findsOneWidget);
      expect(find.text('运行中的任务'), findsOneWidget);
      expect(find.text('暂停的任务'), findsOneWidget);
      expect(find.text('正常的任务'), findsOneWidget);
      expect(find.text('已停用任务'), findsOneWidget);
      expect(find.text('运行中'), findsOneWidget);
      expect(find.text('已暂停'), findsOneWidget);
      expect(find.text('正常'), findsOneWidget);
      expect(find.text('已停用'), findsOneWidget);
      expect(find.text('0 9 * * *'), findsNWidgets(3));
      expect(find.text('0 9 * * * · 上次运行 09:30'), findsOneWidget);
      expect(find.text('正常（3）'), findsOneWidget);
      expect(find.text('已暂停（1）'), findsOneWidget);
      expect(find.byKey(const ValueKey('tasks-create')), findsOneWidget);

      // 验证副标使用 secondaryText 颜色（内联动态色需 resolveFrom，测试环境浅色）
      final subtitleFinder = find.text('0 9 * * * · 上次运行 09:30');
      final subtitleWidget = tester.widget<Text>(subtitleFinder);
      expect(
        subtitleWidget.style?.color?.toARGB32(),
        secondaryText.resolveFrom(tester.element(subtitleFinder)).toARGB32(),
      );
    });

    testWidgets('加载态：数据到达前显示 ActivityIndicator，到达后渲染列表', (tester) async {
      final api = FakeTasksApi(jobs: [buildJob('j1', name: '到了')]);
      api.fetchGate = Completer<void>();
      await pumpTasksPage(tester, api);

      expect(find.byType(CupertinoActivityIndicator), findsOneWidget);

      api.fetchGate!.complete();
      await tester.pump();
      await tester.pump();
      expect(find.text('到了'), findsOneWidget);
      expect(find.byType(CupertinoActivityIndicator), findsNothing);
    });

    testWidgets('空态：暂无任务 + 新建任务入口', (tester) async {
      await pumpTasksPage(tester, FakeTasksApi());

      expect(find.text('暂无任务'), findsOneWidget);
      expect(find.byKey(const ValueKey('tasks-empty-create')), findsOneWidget);
      expect(find.byKey(const ValueKey('tasks-create')), findsOneWidget);
    });

    testWidgets('错误态：加载失败展示错误信息，重试恢复', (tester) async {
      final api = FakeTasksApi(jobs: [buildJob('j1', name: '恢复的任务')]);
      api.fetchError = NetworkException(NetworkExceptionKind.cannotConnect);
      await pumpTasksPage(tester, api);

      expect(find.text('加载失败'), findsOneWidget);
      expect(find.textContaining('无法连接'), findsOneWidget);

      api.fetchError = null;
      await tester.tap(find.byKey(const ValueKey('tasks-retry')));
      await tester.pump();
      await tester.pump();

      expect(find.text('恢复的任务'), findsOneWidget);
      expect(find.text('加载失败'), findsNothing);
    });

    testWidgets('行菜单：运行/暂停/编辑/查看输出/删除；暂停任务显示「恢复」', (tester) async {
      final api = FakeTasksApi(
        jobs: [
          buildJob('j1', name: '普通任务'),
          buildJob('j2', name: '暂停任务', state: 'paused'),
        ],
      );
      await pumpTasksPage(tester, api);

      await tester.tap(find.byKey(const ValueKey('tasks-actions-j1')));
      await tester.pumpAndSettle();
      expect(find.text('运行'), findsOneWidget);
      expect(find.text('暂停'), findsOneWidget);
      expect(find.text('编辑'), findsOneWidget);
      expect(find.text('查看输出'), findsOneWidget);
      expect(find.text('删除'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('tasks-actions-j2')));
      await tester.pumpAndSettle();
      expect(find.text('恢复'), findsOneWidget);
      expect(find.text('暂停'), findsNothing);
    });

    testWidgets('运行：菜单 → 运行 → 调 API 且行状态变为运行中', (tester) async {
      final api = FakeTasksApi(jobs: [buildJob('j1', name: '任务一')]);
      await pumpTasksPage(tester, api);

      await tester.tap(find.byKey(const ValueKey('tasks-actions-j1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('tasks-action-run')));
      await tester.pumpAndSettle();

      expect(api.runCalls, ['j1']);
      expect(find.text('运行中'), findsOneWidget);
      expect(find.text('正常'), findsNothing);
    });

    testWidgets('暂停：菜单 → 暂停 → 调 API 且行状态变为已暂停', (tester) async {
      final api = FakeTasksApi(jobs: [buildJob('j1', name: '任务一')]);
      await pumpTasksPage(tester, api);

      await tester.tap(find.byKey(const ValueKey('tasks-actions-j1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('tasks-action-pause')));
      await tester.pumpAndSettle();

      expect(api.pauseCalls, ['j1']);
      expect(find.text('已暂停'), findsOneWidget);
    });

    testWidgets('恢复：暂停任务菜单 → 恢复 → 调 API 且行状态回到正常', (tester) async {
      final api = FakeTasksApi(
        jobs: [buildJob('j1', name: '任务一', state: 'paused')],
      );
      await pumpTasksPage(tester, api);

      await tester.tap(find.byKey(const ValueKey('tasks-actions-j1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('tasks-action-resume')));
      await tester.pumpAndSettle();

      expect(api.resumeCalls, ['j1']);
      expect(find.text('已暂停'), findsNothing);
      expect(find.text('正常'), findsOneWidget);
    });

    testWidgets('删除：确认弹窗 → 确认后移除行并显示空态', (tester) async {
      final api = FakeTasksApi(jobs: [buildJob('j1', name: '任务一')]);
      await pumpTasksPage(tester, api);

      await tester.tap(find.byKey(const ValueKey('tasks-actions-j1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('tasks-action-delete')));
      await tester.pumpAndSettle();

      expect(find.text('删除任务'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('tasks-delete-confirm')));
      await tester.pumpAndSettle();

      expect(api.deleteCalls, ['j1']);
      expect(find.text('暂无任务'), findsOneWidget);
    });

    testWidgets('删除：取消不调 API', (tester) async {
      final api = FakeTasksApi(jobs: [buildJob('j1', name: '任务一')]);
      await pumpTasksPage(tester, api);

      await tester.tap(find.byKey(const ValueKey('tasks-actions-j1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('tasks-action-delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('tasks-delete-cancel')));
      await tester.pumpAndSettle();

      expect(api.deleteCalls, isEmpty);
      expect(find.text('任务一'), findsOneWidget);
    });

    testWidgets('行操作失败：弹窗提示错误并可在点击「好」后关闭', (tester) async {
      final api = FakeTasksApi(jobs: [buildJob('j1', name: '任务一')]);
      api.runError = HttpException(500, null, message: '触发服务不可用');
      await pumpTasksPage(tester, api);

      await tester.tap(find.byKey(const ValueKey('tasks-actions-j1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('tasks-action-run')));
      await tester.pumpAndSettle();

      expect(find.text('操作失败'), findsOneWidget);
      expect(find.textContaining('触发服务不可用'), findsOneWidget);

      await tester.tap(find.text('好'));
      await tester.pumpAndSettle();
      expect(find.text('操作失败'), findsNothing);
    });

    testWidgets('查看输出：底部面板显示输出内容并可关闭', (tester) async {
      final api = FakeTasksApi(jobs: [buildJob('j1', name: '任务一')]);
      api.outputResponse = const CronOutputResponse(
        jobId: 'j1',
        outputs: [CronOutputItem(filename: 'out.md', content: '输出内容')],
      );
      await pumpTasksPage(tester, api);

      await tester.tap(find.byKey(const ValueKey('tasks-actions-j1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('tasks-action-output')));
      await tester.pumpAndSettle();

      expect(api.outputCalls, ['j1:5']);
      expect(find.text('任务输出'), findsOneWidget);
      expect(find.text('out.md'), findsOneWidget);
      expect(find.text('输出内容'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('tasks-output-close')));
      await tester.pumpAndSettle();
      expect(find.text('out.md'), findsNothing);
    });

    testWidgets('查看输出：无输出时显示空态', (tester) async {
      final api = FakeTasksApi(jobs: [buildJob('j1', name: '任务一')]);
      await pumpTasksPage(tester, api);

      await tester.tap(find.byKey(const ValueKey('tasks-actions-j1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('tasks-action-output')));
      await tester.pumpAndSettle();

      expect(find.text('暂无输出'), findsOneWidget);
    });

    testWidgets('行点击：点击任务行主体直接打开输出面板', (tester) async {
      final api = FakeTasksApi(jobs: [buildJob('j1', name: '任务一')]);
      api.outputResponse = const CronOutputResponse(
        jobId: 'j1',
        outputs: [CronOutputItem(filename: 'cron.log', content: '执行完毕：OK')],
      );
      await pumpTasksPage(tester, api);

      await tester.tap(find.byKey(const ValueKey('tasks-row-j1')));
      await tester.pumpAndSettle();

      expect(api.outputCalls, ['j1:5']);
      expect(find.byKey(const ValueKey('tasks-output-sheet')), findsOneWidget);
      expect(find.text('任务输出'), findsOneWidget);
      expect(find.text('cron.log'), findsOneWidget);
      expect(find.text('执行完毕：OK'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('tasks-output-close')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('tasks-output-sheet')), findsNothing);
    });

    testWidgets('行点击：点击行尾操作按钮只弹出操作菜单，不触发行点击打开输出面板', (tester) async {
      final api = FakeTasksApi(jobs: [buildJob('j1', name: '任务一')]);
      await pumpTasksPage(tester, api);

      await tester.tap(find.byKey(const ValueKey('tasks-actions-j1')));
      await tester.pumpAndSettle();

      expect(find.text('运行'), findsOneWidget);
      expect(find.byKey(const ValueKey('tasks-output-sheet')), findsNothing);
      expect(api.outputCalls, isEmpty);
    });

    testWidgets('暗色模式：输出面板在暗色主题下正常渲染且可交互', (tester) async {
      final api = FakeTasksApi(jobs: [buildJob('j1', name: '暗色任务')]);
      api.outputResponse = const CronOutputResponse(
        jobId: 'j1',
        outputs: [
          CronOutputItem(filename: 'dark.log', content: 'Dark mode test'),
        ],
      );
      await pumpTasksPage(tester, api, brightness: Brightness.dark);

      await tester.tap(find.byKey(const ValueKey('tasks-row-j1')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('tasks-output-sheet')), findsOneWidget);
      expect(find.text('任务输出'), findsOneWidget);
      expect(find.text('dark.log'), findsOneWidget);
      expect(find.text('Dark mode test'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('tasks-output-close')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('tasks-output-sheet')), findsNothing);
    });
  });

  group('TasksEditPage 表单', () {
    testWidgets('新建：+ → 表单填写 → 创建 → 返回列表并显示新任务', (tester) async {
      final api = FakeTasksApi(jobs: [buildJob('j1', name: '已有任务')]);
      api.mutationJob = const CronJob(
        jobId: 'j2',
        name: '每日总结',
        prompt: '总结',
        schedule: CronSchedule(expression: '0 9 * * *'),
      );
      await pumpTasksPage(tester, api);

      await tester.tap(find.byKey(const ValueKey('tasks-create')));
      await tester.pumpAndSettle();
      expect(find.text('新建任务'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('tasks-form-name')),
        '每日总结',
      );
      await tester.enterText(
        find.byKey(const ValueKey('tasks-form-schedule')),
        '0 9 * * *',
      );
      await tester.enterText(
        find.byKey(const ValueKey('tasks-form-prompt')),
        '总结今天的工作',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('tasks-form-save')));
      await tester.pumpAndSettle();

      expect(api.createCount, 1);
      expect(api.createCalls, ['每日总结|0 9 * * *|总结今天的工作|true']);
      expect(find.text('新建任务'), findsNothing); // 表单已关闭
      expect(find.text('每日总结'), findsOneWidget); // 列表顶部显示新任务
    });

    testWidgets('新建：调度/提示词为空时保存按钮禁用', (tester) async {
      await pumpTasksPage(tester, FakeTasksApi());

      await tester.tap(find.byKey(const ValueKey('tasks-create')));
      await tester.pumpAndSettle();

      CupertinoButton saveButton() => tester.widget<CupertinoButton>(
        find.byKey(const ValueKey('tasks-form-save')),
      );
      expect(saveButton().onPressed, isNull);

      await tester.enterText(
        find.byKey(const ValueKey('tasks-form-schedule')),
        '0 9 * * *',
      );
      await tester.pump();
      expect(saveButton().onPressed, isNull); // 提示词仍为空

      await tester.enterText(
        find.byKey(const ValueKey('tasks-form-prompt')),
        '提示词',
      );
      await tester.pump();
      expect(saveButton().onPressed, isNotNull);
    });

    testWidgets('编辑：行菜单 → 编辑 → 字段预填 → 保存 → 调 update API', (tester) async {
      final api = FakeTasksApi(
        jobs: [buildJob('j1', name: '旧名字', state: 'paused')],
      );
      api.mutationJob = const CronJob(
        jobId: 'j1',
        name: '新名字',
        prompt: '提示词 j1',
        schedule: CronSchedule(expression: '0 9 * * *'),
      );
      await pumpTasksPage(tester, api);

      await tester.tap(find.byKey(const ValueKey('tasks-actions-j1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('tasks-action-edit')));
      await tester.pumpAndSettle();

      expect(find.text('编辑任务'), findsOneWidget);
      // 预填校验
      expect(
        tester
            .widget<CupertinoTextField>(
              find.byKey(const ValueKey('tasks-form-name')),
            )
            .controller!
            .text,
        '旧名字',
      );
      expect(
        tester
            .widget<CupertinoTextField>(
              find.byKey(const ValueKey('tasks-form-schedule')),
            )
            .controller!
            .text,
        '0 9 * * *',
      );
      expect(
        tester
            .widget<CupertinoTextField>(
              find.byKey(const ValueKey('tasks-form-prompt')),
            )
            .controller!
            .text,
        '提示词 j1',
      );

      await tester.enterText(
        find.byKey(const ValueKey('tasks-form-name')),
        '新名字',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('tasks-form-save')));
      await tester.pumpAndSettle();

      expect(api.updateCount, 1);
      expect(api.updateCalls, ['j1|新名字|0 9 * * *|提示词 j1|true']);
      expect(find.text('编辑任务'), findsNothing);
      expect(find.text('新名字'), findsOneWidget);
    });

    testWidgets('保存失败：弹窗提示错误，表单保持打开', (tester) async {
      final api = FakeTasksApi();
      api.createError = HttpException(500, null, message: '创建服务不可用');
      await pumpTasksPage(tester, api);

      await tester.tap(find.byKey(const ValueKey('tasks-create')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('tasks-form-schedule')),
        '0 9 * * *',
      );
      await tester.enterText(
        find.byKey(const ValueKey('tasks-form-prompt')),
        '提示词',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('tasks-form-save')));
      await tester.pumpAndSettle();

      expect(api.createCount, 1);
      expect(find.text('操作失败'), findsOneWidget);
      expect(find.textContaining('创建服务不可用'), findsOneWidget);

      await tester.tap(find.text('好'));
      await tester.pumpAndSettle();
      expect(find.text('新建任务'), findsOneWidget); // 表单仍在
    });
  });
}
