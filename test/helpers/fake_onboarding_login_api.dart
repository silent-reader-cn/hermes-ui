import 'package:hermex_flutter/core/api/api_exception.dart';
import 'package:hermex_flutter/core/models/server_info.dart';
import 'package:hermex_flutter/features/onboarding/onboarding_providers.dart';

/// 登录 fake：记录调用，可配置成功/失败。
///
/// 用于「自动重登 / 保存服务器时先登录」两类场景的测试注入
/// （override `onboardingApiFactoryProvider` 后充当生产 [OnboardingServerApi]）。
class FakeOnboardingLoginApi implements OnboardingServerApi {
  int loginCalls = 0;
  String? lastPassword;
  ApiException? loginError;

  @override
  Future<HealthResponse> health() async => const HealthResponse(status: 'ok');

  @override
  Future<AuthStatusResponse> authStatus() async =>
      const AuthStatusResponse(authEnabled: true);

  @override
  Future<LoginResponse> login(String password) async {
    loginCalls++;
    lastPassword = password;
    final error = loginError;
    if (error != null) throw error;
    return const LoginResponse(ok: true);
  }
}