import 'dart:async';

import 'package:hermes_ui/core/models/insights.dart';
import 'package:hermes_ui/features/insights/insights_api.dart';

/// 可配置的 [InsightsApi] fake（测试注入，彻底绕开网络）。
///
/// 默认返回空 [InsightsResponse]；测试可按需配置 [response] / [fetchError] /
/// [fetchGate]，并通过 [fetchCount] 与 [requestedDays] 断言调用次数与参数。
class FakeInsightsApi implements InsightsApi {
  FakeInsightsApi({this.response = const InsightsResponse()});

  /// `fetchInsights` 返回的响应。
  InsightsResponse response;

  /// `fetchInsights` 抛出的异常（非 null 时优先于 [response]）。
  Object? fetchError;

  /// 非 null 时 `fetchInsights` 挂起等待该 gate（测试加载态用）。
  Completer<void>? fetchGate;

  /// `fetchInsights` 调用次数。
  int fetchCount = 0;

  /// 每次调用收到的 `days` 参数（按调用顺序）。
  final List<int> requestedDays = [];

  @override
  Future<InsightsResponse> fetchInsights({required int days}) async {
    fetchCount++;
    requestedDays.add(days);
    final error = fetchError;
    if (error != null) throw error;
    final gate = fetchGate;
    if (gate != null) await gate.future;
    return response;
  }
}
