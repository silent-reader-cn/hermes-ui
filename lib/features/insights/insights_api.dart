import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_client_server_panels.dart';
import '../../core/models/insights.dart';

/// 用量统计所需的最小服务器 API 面（insights 域 1 个端点：
/// `GET /api/insights?days=`）。
///
/// 生产实现 [InsightsApiClient] 包 [ApiClient]（模型在客户端解码）；
/// 测试注入纯 Dart fake，彻底绕开网络（对齐 session_list 的
/// `SessionListApi` 模式）。
abstract interface class InsightsApi {
  /// GET /api/insights?days= → 指定天数窗口的用量统计。
  Future<InsightsResponse> fetchInsights({required int days});
}

/// [InsightsApi] 的生产实现：包 [ApiClient]，把 `Object?` JSON 解码为模型。
class InsightsApiClient implements InsightsApi {
  InsightsApiClient(this._client);

  final ApiClient _client;

  @override
  Future<InsightsResponse> fetchInsights({required int days}) async {
    return _client.insights(days);
  }
}

/// 构建 [InsightsApi] 的工厂（测试可 override 注入 fake）。
typedef InsightsApiFactory = InsightsApi Function(ApiClient client);

final insightsApiFactoryProvider = Provider<InsightsApiFactory>(
  (ref) => InsightsApiClient.new,
);
