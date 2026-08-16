import 'package:flutter_test/flutter_test.dart';
import 'package:hermex_flutter/core/models/cron.dart';

void main() {
  group('CronJobsResponse / CronMutationResponse', () {
    test('正常 + 畸形', () {
      final jobs = CronJobsResponse.fromJson({
        'jobs': [
          {'id': 'cron_9', 'name': '备份'},
        ],
      });
      expect(jobs.jobs, hasLength(1));
      expect(jobs.jobs!.single.id, 'cron_9');
      expect(CronJobsResponse.fromJson({'jobs': 'bad'}).jobs, isNull);

      final mutation = CronMutationResponse.fromJson(
        {'ok': true, 'job': {'id': 'cron_9'}, 'error': null},
      );
      expect(mutation.ok, true);
      expect(mutation.job!.jobId, 'cron_9');
    });
  });

  group('CronStatusResponse.running 双形态', () {
    test('bool 形态（附录 A.2）', () {
      final response = CronStatusResponse.fromJson({
        'job_id': 'cron_9',
        'running': true,
        'elapsed': 12.5,
        'error': null,
      });
      expect(response.jobId, 'cron_9');
      expect(response.running, true);
      expect(response.elapsed, 12.5);
      expect(response.runningJobs, isNull);
    });

    test('Map 形态 → runningJobs', () {
      final response = CronStatusResponse.fromJson({
        'job_id': 'cron_9',
        'running': {'cron_9': 12.5},
        'elapsed': 12.5,
      });
      expect(response.running, isNull);
      expect(response.runningJobs, {'cron_9': 12.5});
    });

    test('elapsed 字符串灵活解析 / 缺失 → null', () {
      expect(
        CronStatusResponse.fromJson({'elapsed': '3.5'}).elapsed,
        3.5,
      );
      expect(CronStatusResponse.fromJson(const {}).elapsed, isNull);
      expect(CronStatusResponse.fromJson(const {}).running, isNull);
    });
  });

  group('CronOutputResponse / CronOutputItem / CronDeliveryOption', () {
    test('正常 + 畸形', () {
      final response = CronOutputResponse.fromJson({
        'job_id': 'cron_9',
        'outputs': [
          {'filename': 'out.txt', 'content': '…'},
        ],
      });
      expect(response.outputs!.single.id, 'out.txt');
      expect(CronOutputResponse.fromJson({'outputs': [42]}).outputs, isNull);

      final options = CronDeliveryOptionsResponse.fromJson({
        'platforms': [
          {'value': 'local', 'label': '本地'},
        ],
      });
      expect(options.platforms!.single.id, 'local');
      expect(options.platforms!.single.label, '本地');
      expect(CronDeliveryOptionsResponse.fromJson(const {}).platforms, isNull);
    });

    test('CronRepeat', () {
      final repeat = CronRepeat.fromJson({'times': 30, 'completed': 12});
      expect(repeat.times, 30);
      expect(repeat.completed, 12);
      expect(CronRepeat.fromJson({'times': '30'}).times, 30);
      expect(CronRepeat.fromJson(const {}).times, isNull);
    });
  });

  group('CronJob', () {
    test('规格示例正常解析', () {
      final job = CronJob.fromJson({
        'id': 'cron_9',
        'name': '每日备份',
        'prompt': '备份数据',
        'schedule': '0 3 * * *',
        'schedule_display': '每天 03:00',
        'enabled': true,
        'state': 'active',
        'next_run_at': 1723798800.0,
        'last_run_at': '2026-08-15T03:00:00Z',
        'last_status': 'success',
        'last_error': null,
        'repeat': {'times': 30, 'completed': 12},
        'deliver': 'local',
        'skills': ['backup'],
        'model': 'gpt-4o',
        'provider': 'openai',
        'profile': 'default',
        'toast_notifications': true,
      });
      expect(job.id, 'cron_9');
      expect(job.jobId, 'cron_9');
      expect(job.name, '每日备份');
      expect(job.scheduleDisplay, '每天 03:00');
      expect(job.enabled, true);
      expect(job.schedule!.expression, '0 3 * * *');
      expect(job.nextRunAt!.date.millisecondsSinceEpoch, 1723798800000);
      expect(job.lastRunAt!.date.toUtc(), DateTime.utc(2026, 8, 15, 3));
      expect(job.repeatInfo!.times, 30);
      expect(job.skills, ['backup']);
      expect(job.toastNotifications, true);
      expect(job.scheduleText, '每天 03:00');
      expect(job.editableScheduleText, '0 3 * * *');
      expect(job.displayName, '每日备份');
    });

    test('jobId 先 id 后 job_id', () {
      expect(CronJob.fromJson({'id': 'a', 'job_id': 'b'}).jobId, 'a');
      expect(CronJob.fromJson({'job_id': 'b'}).jobId, 'b');
    });

    test('裸字符串 schedule 解码', () {
      final job = CronJob.fromJson({'schedule': '0 3 * * *'});
      expect(job.schedule!.expression, '0 3 * * *');
      expect(job.schedule!.kind, isNull);
    });

    test('畸形输入：日期坏值 → null，其余 lossy 容错', () {
      final job = CronJob.fromJson({
        'name': 42,
        'enabled': 'yes',
        'next_run_at': 'not-a-date',
        'last_run_at': {'bad': true},
        'repeat': 'bad',
        'skills': ['ok', 1],
      });
      expect(job.name, '42');
      expect(job.enabled, true);
      expect(job.nextRunAt, isNull);
      expect(job.lastRunAt, isNull);
      expect(job.repeatInfo, isNull);
      expect(job.skills, isNull);
      expect(CronJob.fromJson(const {}).id, isNotEmpty);
    });

    test('CronDateValue.tryParse 三种形态', () {
      expect(
        CronDateValue.tryParse(1723798800.0)!.date.millisecondsSinceEpoch,
        1723798800000,
      );
      expect(
        CronDateValue.tryParse(1723798800)!.date.millisecondsSinceEpoch,
        1723798800000,
      );
      expect(
        CronDateValue.tryParse('1723798800')!.date.millisecondsSinceEpoch,
        1723798800000,
      );
      expect(
        CronDateValue.tryParse('2026-08-15T03:00:00Z')!.date,
        DateTime.utc(2026, 8, 15, 3),
      );
      expect(CronDateValue.tryParse('garbage'), isNull);
      expect(CronDateValue.tryParse(null), isNull);
      expect(CronDateValue.tryParse(true), isNull);
    });

    test('status 判定顺序照抄 Swift', () {
      // 重复任务完成 → needsAttention
      expect(
        CronJob.fromJson({
          'schedule': {'kind': 'cron'},
          'enabled': false,
          'state': 'completed',
          'next_run_at': null,
        }).status,
        CronJobStatus.needsAttention,
      );
      // 重复任务错误 → needsAttention
      expect(
        CronJob.fromJson({
          'schedule': {'kind': 'interval'},
          'state': 'error',
          'next_run_at': null,
        }).status,
        CronJobStatus.needsAttention,
      );
      expect(
        CronJob.fromJson({'state': 'paused'}).status,
        CronJobStatus.paused,
      );
      expect(
        CronJob.fromJson({'enabled': false}).status,
        CronJobStatus.off,
      );
      expect(
        CronJob.fromJson({'last_status': 'error'}).status,
        CronJobStatus.error,
      );
      expect(
        CronJob.fromJson({'enabled': true}).status,
        CronJobStatus.active,
      );
      // 非重复任务的 completed 不触发 needsAttention
      expect(
        CronJob.fromJson({
          'schedule': {'kind': 'once'},
          'enabled': false,
          'state': 'completed',
          'next_run_at': null,
        }).status,
        CronJobStatus.off,
      );
    });

    test('isRecurring / displayName 兜底', () {
      expect(
        CronJob.fromJson({'schedule': {'kind': 'cron'}}).isRecurring,
        true,
      );
      expect(
        CronJob.fromJson({'schedule': {'kind': 'once'}}).isRecurring,
        false,
      );
      expect(
        CronJob.fromJson({'name': '', 'schedule_display': '每天'}).displayName,
        '每天',
      );
      expect(CronJob.fromJson(const {}).displayName, 'Untitled Task');
    });
  });

  group('CronSchedule', () {
    test('对象解码 + displayText', () {
      final schedule = CronSchedule.fromJson({
        'kind': 'cron',
        'expression': '0 3 * * *',
        'expr': 'e',
        'run_at': 'r',
        'every': 'v',
      });
      expect(schedule.kind, 'cron');
      expect(schedule.displayText, '0 3 * * *');
      expect(
        CronSchedule.fromJson({'every': 'v'}).displayText,
        'v',
      );
    });

    test('裸字符串 → expression', () {
      final schedule = CronSchedule.fromJson('0 3 * * *');
      expect(schedule.expression, '0 3 * * *');
      expect(schedule.kind, isNull);
    });

    test('畸形输入：非对象非字符串 → 空', () {
      final schedule = CronSchedule.fromJson(42);
      expect(schedule.expression, isNull);
      expect(schedule.displayText, isNull);
    });
  });

  test('== / hashCode / toString', () {
    final a = CronJob.fromJson({'id': 'c1', 'name': 'n'});
    final b = CronJob.fromJson({'id': 'c1', 'name': 'n'});
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a.toString(), contains('CronJob'));
  });
}
