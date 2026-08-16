import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/api/custom_header.dart';

/// onboarding 向导所需的最小服务器 API 面。
///
/// 生产实现 [OnboardingApiClient] 包 [ApiClient]（health/authStatus/login 走
/// 真实网络）；测试可注入纯 Dart fake，彻底绕开网络/事件循环。
abstract interface class OnboardingServerApi {
  /// GET /health → HealthResponse；成功返回含 `status` 键的 Map。
  Future<Object?> health();

  /// GET /api/auth/status → AuthStatusResponse（含 `auth_enabled`）。
  Future<Object?> authStatus();

  /// POST /api/auth/login {password} → LoginResponse；成功即种会话 cookie。
  Future<Object?> login(String password);
}

/// [OnboardingServerApi] 的生产实现（包 [ApiClient]）。
class OnboardingApiClient implements OnboardingServerApi {
  OnboardingApiClient({
    required String baseUrl,
    List<CustomHeader> initialHeaders = const [],
  }) : _client = ApiClient(baseUrl: baseUrl, initialHeaders: initialHeaders);

  final ApiClient _client;

  @override
  Future<Object?> health() => _client.health();

  @override
  Future<Object?> authStatus() => _client.authStatus();

  @override
  Future<Object?> login(String password) => _client.login(password);
}

/// 构建 onboarding 用 [OnboardingServerApi] 的工厂（测试可 override 注入 fake）。
typedef OnboardingApiFactory =
    OnboardingServerApi Function(String baseUrl, List<CustomHeader> headers);

final onboardingApiFactoryProvider = Provider<OnboardingApiFactory>(
  (ref) => (baseUrl, headers) =>
      OnboardingApiClient(baseUrl: baseUrl, initialHeaders: headers),
);
