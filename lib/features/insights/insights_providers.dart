import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/connections/connection_providers.dart';
import '../../core/models/insights.dart';
import 'insights_api.dart';

/// 用量统计时间范围（对齐 Hermex `AnalyticsTimeframe`）。
enum InsightsTimeframe {
  /// 今天。
  today(1, '今天'),

  /// 近 7 天。
  last7Days(7, '近 7 天'),

  /// 近 30 天（默认）。
  last30Days(30, '近 30 天'),

  /// 全部（服务器上限 365 天）。
  allTime(365, '全部');

  const InsightsTimeframe(this.serverDays, this.title);

  /// 发给服务器的 `days` 参数。
  final int serverDays;

  /// 分段控件显示标题。
  final String title;
}

/// 用量统计状态（AsyncNotifier 的 AsyncData 载荷）。
class InsightsState {
  const InsightsState({
    required this.response,
    required this.timeframe,
    this.isLoading = false,
  });

  /// 最近一次成功加载的统计响应。
  final InsightsResponse response;

  /// 当前选中的时间范围。
  final InsightsTimeframe timeframe;

  /// 切换时间范围后的重新加载进行中（保留旧数据展示）。
  final bool isLoading;

  InsightsState copyWith({
    InsightsResponse? response,
    InsightsTimeframe? timeframe,
    bool? isLoading,
  }) {
    return InsightsState(
      response: response ?? this.response,
      timeframe: timeframe ?? this.timeframe,
      isLoading: isLoading ?? this.isLoading,
    );
  }

  @override
  String toString() =>
      'InsightsState(timeframe: $timeframe, isLoading: $isLoading)';
}

/// 用量统计控制器：加载 / 刷新 / 切换时间范围。
///
/// AsyncValue 语义：首次加载与刷新失败 → `AsyncError`（UI 展示错误态 +
/// 重试）；切换时间范围失败 → `AsyncError`（旧数据被丢弃，UI 回错误态）。
final insightsControllerProvider =
    AsyncNotifierProvider<InsightsController, InsightsState>(
      InsightsController.new,
    );

class InsightsController extends AsyncNotifier<InsightsState> {
  InsightsApi get _api =>
      ref.read(insightsApiFactoryProvider)(ref.read(apiClientProvider));

  @override
  Future<InsightsState> build() async {
    // watch：切换服务器（apiClientProvider 重建）或工厂被替换时自动重载。
    final api = ref.watch(insightsApiFactoryProvider)(
      ref.watch(apiClientProvider),
    );
    return _load(api, InsightsTimeframe.last30Days);
  }

  /// 切换时间范围：重新拉取对应天数窗口。
  Future<void> setTimeframe(InsightsTimeframe timeframe) async {
    final current = state.valueOrNull;
    if (current != null && current.timeframe == timeframe) return;
    state = AsyncData(
      (current ??
              const InsightsState(
                response: InsightsResponse(),
                timeframe: InsightsTimeframe.last30Days,
              ))
          .copyWith(timeframe: timeframe, isLoading: true),
    );
    try {
      final response = await _api.fetchInsights(days: timeframe.serverDays);
      state = AsyncData(
        InsightsState(response: response, timeframe: timeframe),
      );
    } on Exception catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
    }
  }

  /// 下拉刷新 / 错误态重试：按当前时间范围重新拉取。
  Future<void> refresh() async {
    try {
      final timeframe =
          state.valueOrNull?.timeframe ?? InsightsTimeframe.last30Days;
      state = AsyncData(await _load(_api, timeframe));
    } on Exception catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
    }
  }

  Future<InsightsState> _load(
    InsightsApi api,
    InsightsTimeframe timeframe,
  ) async {
    final response = await api.fetchInsights(days: timeframe.serverDays);
    return InsightsState(response: response, timeframe: timeframe);
  }
}
