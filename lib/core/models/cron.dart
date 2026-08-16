import '../utils/equality.dart';
import '../utils/lossy_json.dart';
import '../utils/uuid.dart';

/// 定时任务列表响应信封（Swift: CronJobsResponse）。
class CronJobsResponse {
  const CronJobsResponse({this.jobs});

  factory CronJobsResponse.fromJson(Map<String, Object?> json) {
    return CronJobsResponse(
      jobs: optModelList(json, 'jobs', CronJob.fromJson),
    );
  }

  final List<CronJob>? jobs;

  @override
  bool operator ==(Object other) =>
      other is CronJobsResponse && deepEquals(other.jobs, jobs);

  @override
  int get hashCode => Object.hashAll([deepHash(jobs)]);

  @override
  String toString() => 'CronJobsResponse(jobs: ${jobs?.length})';
}

/// 定时任务变更响应信封（Swift: CronMutationResponse）。
class CronMutationResponse {
  const CronMutationResponse({this.ok, this.job, this.error});

  factory CronMutationResponse.fromJson(Map<String, Object?> json) {
    return CronMutationResponse(
      ok: lossyBool(json, 'ok'),
      job: optModel(json, 'job', CronJob.fromJson),
      error: lossyString(json, 'error'),
    );
  }

  final bool? ok;
  final CronJob? job;
  final String? error;

  @override
  bool operator ==(Object other) {
    return other is CronMutationResponse &&
        other.ok == ok &&
        other.job == job &&
        other.error == error;
  }

  @override
  int get hashCode => Object.hash(ok, job, error);

  @override
  String toString() => 'CronMutationResponse(ok: $ok)';
}

/// 定时任务状态响应（Swift: CronStatusResponse）。
/// `running` 特殊：同一键两种类型——bool 或 `Map<String, double>`（runningJobs）。
class CronStatusResponse {
  const CronStatusResponse({
    this.jobId,
    this.running,
    this.elapsed,
    this.runningJobs,
    this.error,
  });

  factory CronStatusResponse.fromJson(Map<String, Object?> json) {
    bool? running;
    Map<String, double>? runningJobs;
    final rawRunning = json['running'];
    if (rawRunning is bool) {
      running = rawRunning;
    } else if (rawRunning is Map) {
      final jobs = <String, double>{};
      var allValid = true;
      for (final entry in rawRunning.entries) {
        final value = _toDouble(entry.value);
        if (value == null) {
          allValid = false;
          break;
        }
        jobs[entry.key.toString()] = value;
      }
      runningJobs = allValid ? jobs : null;
    }
    return CronStatusResponse(
      jobId: optString(json, 'job_id'),
      running: running,
      elapsed: flexibleDouble(json, 'elapsed'),
      runningJobs: runningJobs,
      error: optString(json, 'error'),
    );
  }

  final String? jobId;
  final bool? running;
  final double? elapsed;
  final Map<String, double>? runningJobs;
  final String? error;

  static double? _toDouble(Object? value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value.trim());
    return null;
  }

  @override
  bool operator ==(Object other) {
    return other is CronStatusResponse &&
        other.jobId == jobId &&
        other.running == running &&
        other.elapsed == elapsed &&
        deepEquals(other.runningJobs, runningJobs) &&
        other.error == error;
  }

  @override
  int get hashCode =>
      Object.hash(jobId, running, elapsed, deepHash(runningJobs), error);

  @override
  String toString() => 'CronStatusResponse(jobId: $jobId, running: $running)';
}

/// 定时任务输出响应信封（Swift: CronOutputResponse）。
class CronOutputResponse {
  const CronOutputResponse({this.jobId, this.outputs});

  factory CronOutputResponse.fromJson(Map<String, Object?> json) {
    return CronOutputResponse(
      jobId: optString(json, 'job_id'),
      outputs: optModelList(json, 'outputs', CronOutputItem.fromJson),
    );
  }

  final String? jobId;
  final List<CronOutputItem>? outputs;

  @override
  bool operator ==(Object other) {
    return other is CronOutputResponse &&
        other.jobId == jobId &&
        deepEquals(other.outputs, outputs);
  }

  @override
  int get hashCode => Object.hash(jobId, deepHash(outputs));

  @override
  String toString() => 'CronOutputResponse(jobId: $jobId)';
}

/// 定时任务输出条目（Swift: CronOutputItem）。`id` = filename ?? uuid。
class CronOutputItem {
  const CronOutputItem({this.filename, this.content});

  factory CronOutputItem.fromJson(Map<String, Object?> json) {
    return CronOutputItem(
      filename: optString(json, 'filename'),
      content: optString(json, 'content'),
    );
  }

  final String? filename;
  final String? content;

  String get id => filename ?? uuidV4();

  @override
  bool operator ==(Object other) {
    return other is CronOutputItem &&
        other.filename == filename &&
        other.content == content;
  }

  @override
  int get hashCode => Object.hash(filename, content);

  @override
  String toString() => 'CronOutputItem(filename: $filename)';
}

/// 投递选项响应信封（Swift: CronDeliveryOptionsResponse）。
class CronDeliveryOptionsResponse {
  const CronDeliveryOptionsResponse({this.platforms});

  factory CronDeliveryOptionsResponse.fromJson(Map<String, Object?> json) {
    return CronDeliveryOptionsResponse(
      platforms: optModelList(json, 'platforms', CronDeliveryOption.fromJson),
    );
  }

  final List<CronDeliveryOption>? platforms;

  @override
  bool operator ==(Object other) =>
      other is CronDeliveryOptionsResponse && deepEquals(other.platforms, platforms);

  @override
  int get hashCode => Object.hashAll([deepHash(platforms)]);

  @override
  String toString() => 'CronDeliveryOptionsResponse(platforms: ${platforms?.length})';
}

/// 投递选项（Swift: CronDeliveryOption）。`id` = value ?? label ?? uuid。
class CronDeliveryOption {
  const CronDeliveryOption({this.value, this.label});

  factory CronDeliveryOption.fromJson(Map<String, Object?> json) {
    return CronDeliveryOption(
      value: lossyString(json, 'value'),
      label: lossyString(json, 'label'),
    );
  }

  final String? value;
  final String? label;

  String get id => value ?? label ?? uuidV4();

  @override
  bool operator ==(Object other) {
    return other is CronDeliveryOption &&
        other.value == value &&
        other.label == label;
  }

  @override
  int get hashCode => Object.hash(value, label);

  @override
  String toString() => 'CronDeliveryOption(value: $value, label: $label)';
}

/// 重复次数（Swift: CronRepeat，内嵌于 CronJob.repeat）。
class CronRepeat {
  const CronRepeat({this.times, this.completed});

  factory CronRepeat.fromJson(Map<String, Object?> json) {
    return CronRepeat(
      times: lossyInt(json, 'times'),
      completed: lossyInt(json, 'completed'),
    );
  }

  final int? times;
  final int? completed;

  @override
  bool operator ==(Object other) {
    return other is CronRepeat &&
        other.times == times &&
        other.completed == completed;
  }

  @override
  int get hashCode => Object.hash(times, completed);

  @override
  String toString() => 'CronRepeat(times: $times, completed: $completed)';
}

/// 定时任务（Swift: CronJob）。`id` = jobId ?? name ?? uuid。
class CronJob {
  const CronJob({
    this.jobId,
    this.name,
    this.prompt,
    this.schedule,
    this.scheduleDisplay,
    this.enabled,
    this.state,
    this.nextRunAt,
    this.lastRunAt,
    this.lastStatus,
    this.lastError,
    this.lastDeliveryError,
    this.repeatInfo,
    this.deliver,
    this.skills,
    this.model,
    this.provider,
    this.profile,
    this.toastNotifications,
  });

  factory CronJob.fromJson(Map<String, Object?> json) {
    return CronJob(
      // 先 `id` 后 `job_id`（Swift 顺序）。
      jobId: firstKey(json, ['id', 'job_id'], lossyString),
      name: lossyString(json, 'name'),
      prompt: lossyString(json, 'prompt'),
      schedule: CronSchedule.tryParse(json['schedule']),
      scheduleDisplay: lossyString(json, 'schedule_display'),
      enabled: lossyBool(json, 'enabled'),
      state: lossyString(json, 'state'),
      nextRunAt: CronDateValue.tryParse(json['next_run_at']),
      lastRunAt: CronDateValue.tryParse(json['last_run_at']),
      lastStatus: lossyString(json, 'last_status'),
      lastError: lossyString(json, 'last_error'),
      lastDeliveryError: lossyString(json, 'last_delivery_error'),
      // 显式 rawValue `repeat`，注意不是 `repeat_info`。
      repeatInfo: optModel(json, 'repeat', CronRepeat.fromJson),
      deliver: lossyString(json, 'deliver'),
      skills: optStringList(json, 'skills'),
      model: lossyString(json, 'model'),
      provider: lossyString(json, 'provider'),
      profile: lossyString(json, 'profile'),
      toastNotifications: lossyBool(json, 'toast_notifications'),
    );
  }

  final String? jobId;
  final String? name;
  final String? prompt;
  final CronSchedule? schedule;
  final String? scheduleDisplay;
  final bool? enabled;
  final String? state;
  final CronDateValue? nextRunAt;
  final CronDateValue? lastRunAt;
  final String? lastStatus;
  final String? lastError;
  final String? lastDeliveryError;
  final CronRepeat? repeatInfo;
  final String? deliver;
  final List<String>? skills;
  final String? model;
  final String? provider;
  final String? profile;
  final bool? toastNotifications;

  String get id => jobId ?? name ?? uuidV4();

  /// name → scheduleText → 'Untitled Task'。
  String get displayName {
    if (name != null && name!.isNotEmpty) return name!;
    final text = scheduleText;
    if (text != null && text.isNotEmpty) return text;
    return 'Untitled Task';
  }

  String? get scheduleText => scheduleDisplay ?? schedule?.displayText;

  /// schedule.expression ?? expr ?? runAt ?? every ?? scheduleDisplay。
  String? get editableScheduleText {
    return schedule?.expression ??
        schedule?.expr ??
        schedule?.runAt ??
        schedule?.every ??
        scheduleDisplay;
  }

  /// 状态判定顺序照抄 Swift。
  CronJobStatus get status {
    if (isRecurring &&
        repeatInfo?.times == null &&
        enabled == false &&
        state == 'completed' &&
        nextRunAt == null) {
      return CronJobStatus.needsAttention;
    }
    if (isRecurring &&
        nextRunAt == null &&
        (state == 'error' || lastStatus == 'error')) {
      return CronJobStatus.needsAttention;
    }
    if (state == 'paused') return CronJobStatus.paused;
    if (enabled == false) return CronJobStatus.off;
    if (lastStatus == 'error') return CronJobStatus.error;
    return CronJobStatus.active;
  }

  bool get isRecurring =>
      schedule?.kind == 'cron' || schedule?.kind == 'interval';

  @override
  bool operator ==(Object other) {
    return other is CronJob &&
        other.jobId == jobId &&
        other.name == name &&
        other.prompt == prompt &&
        other.schedule == schedule &&
        other.scheduleDisplay == scheduleDisplay &&
        other.enabled == enabled &&
        other.state == state &&
        other.nextRunAt == nextRunAt &&
        other.lastRunAt == lastRunAt &&
        other.lastStatus == lastStatus &&
        other.lastError == lastError &&
        other.lastDeliveryError == lastDeliveryError &&
        other.repeatInfo == repeatInfo &&
        other.deliver == deliver &&
        _listEquals(other.skills, skills) &&
        other.model == model &&
        other.provider == provider &&
        other.profile == profile &&
        other.toastNotifications == toastNotifications;
  }

  @override
  int get hashCode {
    return Object.hash(
      jobId,
      name,
      prompt,
      schedule,
      scheduleDisplay,
      enabled,
      state,
      nextRunAt,
      lastRunAt,
      lastStatus,
      lastError,
      lastDeliveryError,
      repeatInfo,
      deliver,
      Object.hashAll(skills ?? const []),
      model,
      provider,
      profile,
      toastNotifications,
    );
  }

  @override
  String toString() => 'CronJob(jobId: $jobId, name: $name)';
}

/// 定时任务状态枚举（Swift `CronJobStatus`）。
enum CronJobStatus { active, paused, off, error, needsAttention }

/// 定时调度（Swift: CronSchedule）。**支持裸字符串解码**：
/// 整个元素是字符串时 → expression = 该字符串，其余 null。
class CronSchedule {
  const CronSchedule({
    this.kind,
    this.expression,
    this.expr,
    this.runAt,
    this.every,
  });

  factory CronSchedule.fromJson(Object? json) {
    final parsed = tryParse(json);
    return parsed ?? const CronSchedule();
  }

  /// 解析：裸字符串 → expression；对象 → 各字段；其余（含 null）→ null。
  static CronSchedule? tryParse(Object? json) {
    if (json is String) {
      return CronSchedule(expression: json);
    }
    if (json is! Map) return null;
    final map = Map<String, Object?>.from(json);
    return CronSchedule(
      kind: lossyString(map, 'kind'),
      expression: lossyString(map, 'expression'),
      expr: lossyString(map, 'expr'),
      runAt: lossyString(map, 'run_at'),
      every: lossyString(map, 'every'),
    );
  }

  final String? kind;
  final String? expression;
  final String? expr;
  final String? runAt;
  final String? every;

  /// expression ?? expr ?? runAt ?? every ?? kind。
  String? get displayText =>
      expression ?? expr ?? runAt ?? every ?? kind;

  @override
  bool operator ==(Object other) {
    return other is CronSchedule &&
        other.kind == kind &&
        other.expression == expression &&
        other.expr == expr &&
        other.runAt == runAt &&
        other.every == every;
  }

  @override
  int get hashCode => Object.hash(kind, expression, expr, runAt, every);

  @override
  String toString() => 'CronSchedule(kind: $kind, expression: $expression)';
}

/// 定时日期值（Swift: CronDateValue）。**特殊解码**（单值容器）：
/// 1. 值为 num（int/double）→ Unix 秒；2. 值为 String → 先 double.tryParse
/// （数值时间戳），失败再试 ISO8601；3. 全部失败 → null（父模型容错，
/// 对齐 Swift 的 `try?` 语义）。
class CronDateValue {
  const CronDateValue(this.date);

  /// 解析失败返回 null（父模型容错用）。
  static CronDateValue? tryParse(Object? json) {
    if (json is num) {
      return CronDateValue(
        DateTime.fromMillisecondsSinceEpoch((json.toDouble() * 1000).round()),
      );
    }
    if (json is String) {
      final asNumber = double.tryParse(json.trim());
      if (asNumber != null) {
        return CronDateValue(
          DateTime.fromMillisecondsSinceEpoch((asNumber * 1000).round()),
        );
      }
      final parsed = DateTime.tryParse(json);
      if (parsed != null) return CronDateValue(parsed);
    }
    return null;
  }

  final DateTime date;

  @override
  bool operator ==(Object other) =>
      other is CronDateValue && other.date == date;

  @override
  int get hashCode => Object.hashAll([date]);

  @override
  String toString() => 'CronDateValue($date)';
}

bool _listEquals(List<String>? a, List<String>? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return false;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
