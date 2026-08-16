import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermex_flutter/core/api/api_client.dart';
import 'package:hermex_flutter/core/api/api_exception.dart';
import 'package:hermex_flutter/core/connections/connection_providers.dart';
import 'package:hermex_flutter/core/models/cron.dart';
import 'package:hermex_flutter/features/tasks/tasks_providers.dart';

import '../../helpers/fake_tasks_api.dart';

/// 构造测试任务（jobId 必填；state/enabled/lastStatus 可配）。
CronJob buildJob(
  String id, {
  String? name,
  String? state,
  bool? enabled,
  String? lastStatus,
}) {
  return CronJob(
    jobId: id,
    name: name ?? '任务 $id',
    prompt: '提示词 $id',
    schedule: const CronSchedule(expression: '0 9 * * *'),
    state: state,
    enabled: enabled,
    lastStatus: lastStatus,
  );
}

/// 组装 ProviderContainer：注入 fake API（apiClientProvider 用占位客户端，
/// 工厂 override 忽略它，不发任何网络请求）。
ProviderContainer makeContainer(FakeTasksApi api) {
  final container = ProviderContainer(
    overrides: [
      apiClientProvider.overrideWithValue(
        ApiClient(baseUrl: 'http://test.local:30002'),
      ),
      tasksApiFactoryProvider.overrideWithValue((_) => api),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('TasksController 状态机', () {
    test('初始加载成功：AsyncData + 任务列表 + 派生 provider', () async {
      final api = FakeTasksApi(
        jobs: [
          buildJob('j1', state: 'running'),
          buildJob('j2'),
        ],
      );
      final container = makeContainer(api);

      await container.read(tasksControllerProvider.future);
      final state = container.read(tasksControllerProvider).valueOrNull!;

      expect(api.fetchCount, 1);
      expect(state.jobs, hasLength(2));
      expect(state.busyJobIds, isEmpty);
      expect(state.actionError, isNull);
      expect(container.read(tasksJobCountProvider), 2);
      expect(
        container.read(tasksRunningJobsProvider).map((j) => j.jobId),
        ['j1'],
      );
    });

    test('初始加载失败 → AsyncError；refresh 重试成功', () async {
      final api = FakeTasksApi(jobs: [buildJob('j1')]);
      api.fetchError = NetworkException(NetworkExceptionKind.cannotConnect);
      final container = makeContainer(api);

      await expectLater(
        container.read(tasksControllerProvider.future),
        throwsA(isA<ApiException>()),
      );
      expect(container.read(tasksControllerProvider).hasError, isTrue);
      expect(container.read(tasksControllerProvider).valueOrNull, isNull);

      api.fetchError = null;
      await container.read(tasksControllerProvider.notifier).refresh();

      final state = container.read(tasksControllerProvider).valueOrNull!;
      expect(state.jobs, hasLength(1));
      expect(api.fetchCount, 2);
    });

    test('刷新：重新拉取并替换列表', () async {
      final api = FakeTasksApi(jobs: [buildJob('j1')]);
      final container = makeContainer(api);
      await container.read(tasksControllerProvider.future);

      api.jobs = [buildJob('j2'), buildJob('j3')];
      await container.read(tasksControllerProvider.notifier).refresh();

      final state = container.read(tasksControllerProvider).valueOrNull!;
      expect(state.jobs.map((j) => j.jobId), ['j2', 'j3']);
      expect(api.fetchCount, 2);
    });

    test('运行：调 run API + busy 标记 → 本地 state=running', () async {
      final api = FakeTasksApi(jobs: [buildJob('j1')]);
      final container = makeContainer(api);
      await container.read(tasksControllerProvider.future);
      final controller = container.read(tasksControllerProvider.notifier);

      final job = container.read(tasksControllerProvider).valueOrNull!.jobs.single;
      final ok = await controller.run(job);

      expect(ok, isTrue);
      expect(api.runCalls, ['j1']);
      final updated =
          container.read(tasksControllerProvider).valueOrNull!.jobs.single;
      expect(updated.state, 'running');
      expect(updated.enabled, isTrue);
      expect(
        container.read(tasksControllerProvider).valueOrNull!.busyJobIds,
        isEmpty,
      );
    });

    test('变更期间：busyJobIds 标记该任务，完成后清除', () async {
      final api = FakeTasksApi(jobs: [buildJob('j1')]);
      api.mutationGate = Completer<void>();
      final container = makeContainer(api);
      await container.read(tasksControllerProvider.future);
      final controller = container.read(tasksControllerProvider.notifier);

      final future = controller.run(
        container.read(tasksControllerProvider).valueOrNull!.jobs.single,
      );
      await pumpEventQueue();
      expect(
        container.read(tasksControllerProvider).valueOrNull!.busyJobIds,
        {'j1'},
      );

      api.mutationGate!.complete();
      await future;
      expect(
        container.read(tasksControllerProvider).valueOrNull!.busyJobIds,
        isEmpty,
      );
      expect(api.runCalls, ['j1']);
    });

    test('暂停：调 pause API → 本地 state=paused / enabled=false', () async {
      final api = FakeTasksApi(jobs: [buildJob('j1')]);
      final container = makeContainer(api);
      await container.read(tasksControllerProvider.future);
      final controller = container.read(tasksControllerProvider.notifier);

      final ok = await controller.pause(
        container.read(tasksControllerProvider).valueOrNull!.jobs.single,
      );

      expect(ok, isTrue);
      expect(api.pauseCalls, ['j1']);
      final updated =
          container.read(tasksControllerProvider).valueOrNull!.jobs.single;
      expect(updated.state, 'paused');
      expect(updated.enabled, isFalse);
    });

    test('恢复：调 resume API → 清除 paused 标记 / enabled=true', () async {
      final api = FakeTasksApi(jobs: [buildJob('j1', state: 'paused', enabled: false)]);
      final container = makeContainer(api);
      await container.read(tasksControllerProvider.future);
      final controller = container.read(tasksControllerProvider.notifier);

      final ok = await controller.resume(
        container.read(tasksControllerProvider).valueOrNull!.jobs.single,
      );

      expect(ok, isTrue);
      expect(api.resumeCalls, ['j1']);
      final updated =
          container.read(tasksControllerProvider).valueOrNull!.jobs.single;
      expect(updated.state, isNull);
      expect(updated.enabled, isTrue);
      expect(updated.status, CronJobStatus.active);
    });

    test('删除：调 delete API 并从列表移除', () async {
      final api = FakeTasksApi(jobs: [buildJob('j1'), buildJob('j2')]);
      final container = makeContainer(api);
      await container.read(tasksControllerProvider.future);
      final controller = container.read(tasksControllerProvider.notifier);

      final ok = await controller.delete(
        container.read(tasksControllerProvider).valueOrNull!.jobs.first,
      );

      expect(ok, isTrue);
      expect(api.deleteCalls, ['j1']);
      expect(
        container
            .read(tasksControllerProvider)
            .valueOrNull!
            .jobs
            .map((j) => j.jobId),
        ['j2'],
      );
    });

    test('变更返回服务器 job：优先采用服务器数据', () async {
      final api = FakeTasksApi(jobs: [buildJob('j1')]);
      api.mutationJob = const CronJob(
        jobId: 'j1',
        name: '服务器改名',
        state: 'running',
        enabled: true,
      );
      final container = makeContainer(api);
      await container.read(tasksControllerProvider.future);
      final controller = container.read(tasksControllerProvider.notifier);

      final ok = await controller.run(
        container.read(tasksControllerProvider).valueOrNull!.jobs.single,
      );

      expect(ok, isTrue);
      final updated =
          container.read(tasksControllerProvider).valueOrNull!.jobs.single;
      expect(updated.name, '服务器改名');
      expect(updated.state, 'running');
    });

    test('新建：调 create API 并插入列表顶部', () async {
      final api = FakeTasksApi(jobs: [buildJob('j1')]);
      api.mutationJob = const CronJob(
        jobId: 'j2',
        name: '每日总结',
        prompt: '总结',
        schedule: CronSchedule(expression: '0 9 * * *'),
      );
      final container = makeContainer(api);
      await container.read(tasksControllerProvider.future);
      final controller = container.read(tasksControllerProvider.notifier);

      final ok = await controller.create(
        name: '每日总结',
        schedule: '0 9 * * *',
        prompt: '总结',
      );

      expect(ok, isTrue);
      expect(api.createCalls, ['每日总结|0 9 * * *|总结|false']);
      final jobs = container.read(tasksControllerProvider).valueOrNull!.jobs;
      expect(jobs.first.jobId, 'j2');
      expect(jobs.first.name, '每日总结');
    });

    test('新建（空名称）：name 传 null；服务器未返回 job → 重新拉取列表', () async {
      final api = FakeTasksApi(jobs: [buildJob('j1')]);
      final container = makeContainer(api);
      await container.read(tasksControllerProvider.future);

      api.jobs = [buildJob('j0', name: '新建任务'), buildJob('j1')];
      final ok = await container.read(tasksControllerProvider.notifier).create(
            name: '   ',
            schedule: '0 9 * * *',
            prompt: '提示',
            toastNotifications: true,
          );

      expect(ok, isTrue);
      expect(api.createCalls, ['|0 9 * * *|提示|true']);
      expect(api.fetchCount, 2);
      expect(
        container.read(tasksControllerProvider).valueOrNull!.jobs.first.name,
        '新建任务',
      );
    });

    test('编辑：调 update API 并用服务器返回 job 替换', () async {
      final api = FakeTasksApi(jobs: [buildJob('j1')]);
      api.mutationJob = const CronJob(
        jobId: 'j1',
        name: '改名后',
        prompt: '新提示词',
        schedule: CronSchedule(expression: '0 8 * * *'),
      );
      final container = makeContainer(api);
      await container.read(tasksControllerProvider.future);
      final controller = container.read(tasksControllerProvider.notifier);

      final ok = await controller.save(
        container.read(tasksControllerProvider).valueOrNull!.jobs.single,
        name: '改名后',
        schedule: '0 8 * * *',
        prompt: '新提示词',
        toastNotifications: false,
      );

      expect(ok, isTrue);
      expect(api.updateCalls, ['j1|改名后|0 8 * * *|新提示词|false']);
      final updated =
          container.read(tasksControllerProvider).valueOrNull!.jobs.single;
      expect(updated.name, '改名后');
      expect(updated.prompt, '新提示词');
    });

    test('编辑：服务器未返回 job → 本地补丁保留其余字段', () async {
      final api = FakeTasksApi(jobs: [buildJob('j1', state: 'paused')]);
      final container = makeContainer(api);
      await container.read(tasksControllerProvider.future);
      final controller = container.read(tasksControllerProvider.notifier);

      final ok = await controller.save(
        container.read(tasksControllerProvider).valueOrNull!.jobs.single,
        name: '改名',
        schedule: '0 9 * * *',
        prompt: '提示',
        toastNotifications: true,
      );

      expect(ok, isTrue);
      final updated =
          container.read(tasksControllerProvider).valueOrNull!.jobs.single;
      expect(updated.name, '改名');
      expect(updated.scheduleText, '0 9 * * *');
      expect(updated.state, 'paused'); // 未编辑字段保留
      expect(updated.toastNotifications, isTrue);
    });

    test('变更失败（API 抛错）：actionError + 列表不变 + busy 清除', () async {
      final api = FakeTasksApi(jobs: [buildJob('j1')]);
      api.runError = HttpException(500, null, message: '触发服务不可用');
      final container = makeContainer(api);
      await container.read(tasksControllerProvider.future);
      final controller = container.read(tasksControllerProvider.notifier);

      final ok = await controller.run(
        container.read(tasksControllerProvider).valueOrNull!.jobs.single,
      );

      expect(ok, isFalse);
      final state = container.read(tasksControllerProvider).valueOrNull!;
      expect(state.actionError, contains('触发服务不可用'));
      expect(state.jobs, hasLength(1));
      expect(state.jobs.single.state, isNull); // 未被本地补丁污染
      expect(state.busyJobIds, isEmpty);

      await controller.clearActionError();
      expect(
        container.read(tasksControllerProvider).valueOrNull!.actionError,
        isNull,
      );
    });

    test('变更失败（ok:false）：使用服务器 error 文案', () async {
      final api = FakeTasksApi(jobs: [buildJob('j1')]);
      final container = makeContainer(api);
      await container.read(tasksControllerProvider.future);
      // Fake 直接抛错模拟 ok:false 的路径：改用 pauseError 验证 error 展示。
      api.pauseError = HttpException(400, null, message: '任务已暂停');

      final ok = await container.read(tasksControllerProvider.notifier).pause(
            container.read(tasksControllerProvider).valueOrNull!.jobs.single,
          );

      expect(ok, isFalse);
      expect(
        container.read(tasksControllerProvider).valueOrNull!.actionError,
        contains('任务已暂停'),
      );
    });

    test('服务器 job 缺失 ID：actionError 且不调 API', () async {
      final api = FakeTasksApi(jobs: [const CronJob(name: '无 ID 任务')]);
      final container = makeContainer(api);
      await container.read(tasksControllerProvider.future);
      final controller = container.read(tasksControllerProvider.notifier);

      final ok = await controller.run(
        container.read(tasksControllerProvider).valueOrNull!.jobs.single,
      );

      expect(ok, isFalse);
      expect(api.runCalls, isEmpty);
      expect(
        container.read(tasksControllerProvider).valueOrNull!.actionError,
        contains('任务 ID'),
      );
    });

    test('查看输出：返回输出响应', () async {
      final api = FakeTasksApi(jobs: [buildJob('j1')]);
      api.outputResponse = const CronOutputResponse(
        jobId: 'j1',
        outputs: [CronOutputItem(filename: 'out.md', content: '内容')],
      );
      final container = makeContainer(api);
      await container.read(tasksControllerProvider.future);
      final controller = container.read(tasksControllerProvider.notifier);

      final response = await controller.fetchOutput(
        container.read(tasksControllerProvider).valueOrNull!.jobs.single,
      );

      expect(api.outputCalls, ['j1:5']);
      expect(response?.outputs, hasLength(1));
      expect(response?.outputs!.single.filename, 'out.md');
    });

    test('查看输出失败：actionError + 返回 null', () async {
      final api = FakeTasksApi(jobs: [buildJob('j1')]);
      api.outputError = HttpException(500, null, message: '输出服务不可用');
      final container = makeContainer(api);
      await container.read(tasksControllerProvider.future);
      final controller = container.read(tasksControllerProvider.notifier);

      final response = await controller.fetchOutput(
        container.read(tasksControllerProvider).valueOrNull!.jobs.single,
      );

      expect(response, isNull);
      expect(
        container.read(tasksControllerProvider).valueOrNull!.actionError,
        contains('输出服务不可用'),
      );
    });
  });
}
