import '../utils/lossy_json.dart';

/// insights 响应（Swift: InsightsResponse）。
///
/// 服务器键名：真实服务器（hermes-webui）发送 snake_case，Swift 模型用
/// camelCase CodingKeys（在真实服务器上会静默解出 nil）——按 models_spec
/// §0.1 规则 3 双键容错：snake_case 主键 + camelCase 别名。
class InsightsResponse {
  const InsightsResponse({
    this.periodDays,
    this.totalSessions,
    this.totalMessages,
    this.totalInputTokens,
    this.totalOutputTokens,
    this.totalTokens,
    this.totalCost,
    this.totalCacheReadTokens,
    this.totalCacheHitPercent,
    this.models,
    this.dailyTokens,
    this.activityByDay,
    this.activityByHour,
  });

  factory InsightsResponse.fromJson(Map<String, Object?> json) {
    return InsightsResponse(
      periodDays: firstKey(json, ['period_days', 'periodDays'], lossyInt),
      totalSessions: firstKey(json, [
        'total_sessions',
        'totalSessions',
      ], lossyInt),
      totalMessages: firstKey(json, [
        'total_messages',
        'totalMessages',
      ], lossyInt),
      totalInputTokens: firstKey(json, [
        'total_input_tokens',
        'totalInputTokens',
      ], lossyInt),
      totalOutputTokens: firstKey(json, [
        'total_output_tokens',
        'totalOutputTokens',
      ], lossyInt),
      totalTokens: firstKey(json, ['total_tokens', 'totalTokens'], lossyInt),
      totalCost: firstKey(json, ['total_cost', 'totalCost'], lossyDouble),
      totalCacheReadTokens: firstKey(json, [
        'total_cache_read_tokens',
        'totalCacheReadTokens',
      ], lossyInt),
      totalCacheHitPercent: firstKey(json, [
        'total_cache_hit_percent',
        'totalCacheHitPercent',
      ], lossyDouble),
      models: optModelList(json, 'models', InsightsModelBreakdown.fromJson),
      dailyTokens:
          optModelList(json, 'daily_tokens', InsightsDailyToken.fromJson) ??
          optModelList(json, 'dailyTokens', InsightsDailyToken.fromJson),
      activityByDay:
          optModelList(
            json,
            'activity_by_day',
            InsightsActivityByDay.fromJson,
          ) ??
          optModelList(json, 'activityByDay', InsightsActivityByDay.fromJson),
      activityByHour:
          optModelList(
            json,
            'activity_by_hour',
            InsightsActivityByHour.fromJson,
          ) ??
          optModelList(json, 'activityByHour', InsightsActivityByHour.fromJson),
    );
  }

  /// 统计窗口天数。
  final int? periodDays;

  /// 窗口内会话总数。
  final int? totalSessions;

  /// 窗口内消息总数。
  final int? totalMessages;

  /// 窗口内输入令牌总数。
  final int? totalInputTokens;

  /// 窗口内输出令牌总数。
  final int? totalOutputTokens;

  /// 输入 + 输出令牌总数。
  final int? totalTokens;

  /// 估算总费用（美元）。
  final double? totalCost;

  /// 缓存读取令牌总数（旧服务器可能不返回 → null）。
  final int? totalCacheReadTokens;

  /// 缓存命中率（0~100）。
  final double? totalCacheHitPercent;

  /// 按模型拆分。
  final List<InsightsModelBreakdown>? models;

  /// 逐日令牌（最新在前）。
  final List<InsightsDailyToken>? dailyTokens;

  /// 逐日活动（按天）。
  final List<InsightsActivityByDay>? activityByDay;

  /// 逐日活动（按小时）。
  final List<InsightsActivityByHour>? activityByHour;

  /// 是否有任何可展示的统计内容（任一指标非空）。
  bool get hasData =>
      totalSessions != null ||
      totalMessages != null ||
      totalTokens != null ||
      totalInputTokens != null ||
      totalOutputTokens != null ||
      totalCost != null ||
      (models?.isNotEmpty ?? false) ||
      (dailyTokens?.isNotEmpty ?? false);

  @override
  bool operator ==(Object other) {
    return other is InsightsResponse &&
        other.periodDays == periodDays &&
        other.totalSessions == totalSessions &&
        other.totalMessages == totalMessages &&
        other.totalInputTokens == totalInputTokens &&
        other.totalOutputTokens == totalOutputTokens &&
        other.totalTokens == totalTokens &&
        other.totalCost == totalCost &&
        other.totalCacheReadTokens == totalCacheReadTokens &&
        other.totalCacheHitPercent == totalCacheHitPercent &&
        _deepEquals(other.models, models) &&
        _deepEquals(other.dailyTokens, dailyTokens) &&
        _deepEquals(other.activityByDay, activityByDay) &&
        _deepEquals(other.activityByHour, activityByHour);
  }

  @override
  int get hashCode => Object.hash(
    periodDays,
    totalSessions,
    totalMessages,
    totalInputTokens,
    totalOutputTokens,
    totalTokens,
    totalCost,
    totalCacheReadTokens,
    totalCacheHitPercent,
    _deepHash(models),
    _deepHash(dailyTokens),
    _deepHash(activityByDay),
    _deepHash(activityByHour),
  );

  @override
  String toString() =>
      'InsightsResponse(periodDays: $periodDays, totalSessions: $totalSessions)';
}

/// insights 模型拆分（Swift: InsightsModelBreakdown）。
class InsightsModelBreakdown {
  const InsightsModelBreakdown({
    this.model,
    this.sessions,
    this.inputTokens,
    this.outputTokens,
    this.totalTokens,
    this.cost,
    this.cacheHitPercent,
    this.sessionShare,
    this.tokenShare,
    this.costShare,
  });

  factory InsightsModelBreakdown.fromJson(Map<String, Object?> json) {
    return InsightsModelBreakdown(
      model: lossyString(json, 'model'),
      sessions: lossyInt(json, 'sessions'),
      inputTokens: firstKey(json, ['input_tokens', 'inputTokens'], lossyInt),
      outputTokens: firstKey(json, ['output_tokens', 'outputTokens'], lossyInt),
      totalTokens: firstKey(json, ['total_tokens', 'totalTokens'], lossyInt),
      cost: lossyDouble(json, 'cost'),
      cacheHitPercent: firstKey(json, [
        'cache_hit_percent',
        'cacheHitPercent',
      ], lossyDouble),
      sessionShare: firstKey(json, ['session_share', 'sessionShare'], lossyInt),
      tokenShare: firstKey(json, ['token_share', 'tokenShare'], lossyInt),
      costShare: firstKey(json, ['cost_share', 'costShare'], lossyInt),
    );
  }

  final String? model;
  final int? sessions;
  final int? inputTokens;
  final int? outputTokens;
  final int? totalTokens;
  final double? cost;
  final double? cacheHitPercent;
  final int? sessionShare;
  final int? tokenShare;
  final int? costShare;

  /// 展示用的占比（Swift `displayShare`）：costShare → tokenShare →
  /// sessionShare 第一个 > 0 的，否则第一个非空。
  int? get displayShare {
    final shares = [
      costShare,
      tokenShare,
      sessionShare,
    ].whereType<int>().toList(growable: false);
    for (final share in shares) {
      if (share > 0) return share;
    }
    return shares.isEmpty ? null : shares.first;
  }

  @override
  bool operator ==(Object other) {
    return other is InsightsModelBreakdown &&
        other.model == model &&
        other.sessions == sessions &&
        other.inputTokens == inputTokens &&
        other.outputTokens == outputTokens &&
        other.totalTokens == totalTokens &&
        other.cost == cost &&
        other.cacheHitPercent == cacheHitPercent &&
        other.sessionShare == sessionShare &&
        other.tokenShare == tokenShare &&
        other.costShare == costShare;
  }

  @override
  int get hashCode => Object.hash(
    model,
    sessions,
    inputTokens,
    outputTokens,
    totalTokens,
    cost,
    cacheHitPercent,
    sessionShare,
    tokenShare,
    costShare,
  );

  @override
  String toString() => 'InsightsModelBreakdown(model: $model)';
}

/// 逐日令牌（Swift: InsightsDailyToken）。
class InsightsDailyToken {
  const InsightsDailyToken({
    this.date,
    this.inputTokens,
    this.outputTokens,
    this.sessions,
    this.cost,
  });

  factory InsightsDailyToken.fromJson(Map<String, Object?> json) {
    return InsightsDailyToken(
      date: lossyString(json, 'date'),
      inputTokens: firstKey(json, ['input_tokens', 'inputTokens'], lossyInt),
      outputTokens: firstKey(json, ['output_tokens', 'outputTokens'], lossyInt),
      sessions: lossyInt(json, 'sessions'),
      cost: lossyDouble(json, 'cost'),
    );
  }

  final String? date;
  final int? inputTokens;
  final int? outputTokens;
  final int? sessions;
  final double? cost;

  /// 当日令牌合计（输入 + 输出；null 视为 0）。
  int get totalTokens => (inputTokens ?? 0) + (outputTokens ?? 0);

  @override
  bool operator ==(Object other) {
    return other is InsightsDailyToken &&
        other.date == date &&
        other.inputTokens == inputTokens &&
        other.outputTokens == outputTokens &&
        other.sessions == sessions &&
        other.cost == cost;
  }

  @override
  int get hashCode =>
      Object.hash(date, inputTokens, outputTokens, sessions, cost);

  @override
  String toString() => 'InsightsDailyToken(date: $date)';
}

/// 逐日活动（按天）（Swift: InsightsActivityByDay）。
class InsightsActivityByDay {
  const InsightsActivityByDay({this.day, this.sessions});

  factory InsightsActivityByDay.fromJson(Map<String, Object?> json) {
    return InsightsActivityByDay(
      day: lossyString(json, 'day'),
      sessions: lossyInt(json, 'sessions'),
    );
  }

  final String? day;
  final int? sessions;

  @override
  bool operator ==(Object other) =>
      other is InsightsActivityByDay &&
      other.day == day &&
      other.sessions == sessions;

  @override
  int get hashCode => Object.hash(day, sessions);

  @override
  String toString() => 'InsightsActivityByDay(day: $day)';
}

/// 逐日活动（按小时）（Swift: InsightsActivityByHour）。
class InsightsActivityByHour {
  const InsightsActivityByHour({this.hour, this.sessions});

  factory InsightsActivityByHour.fromJson(Map<String, Object?> json) {
    return InsightsActivityByHour(
      hour: lossyInt(json, 'hour'),
      sessions: lossyInt(json, 'sessions'),
    );
  }

  final int? hour;
  final int? sessions;

  @override
  bool operator ==(Object other) =>
      other is InsightsActivityByHour &&
      other.hour == hour &&
      other.sessions == sessions;

  @override
  int get hashCode => Object.hash(hour, sessions);

  @override
  String toString() => 'InsightsActivityByHour(hour: $hour)';
}

bool _deepEquals<T>(List<T>? a, List<T>? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return false;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

int _deepHash<T>(List<T>? list) => Object.hashAll(list ?? const []);
