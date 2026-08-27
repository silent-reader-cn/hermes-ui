import 'dart:convert';

import 'package:flutter/widgets.dart' show FocusManager, ValueKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/app/app.dart';
import 'package:hermes_ui/core/api/api_exception.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/connections/connection_store.dart';
import 'package:hermes_ui/core/models/server_info.dart';
import 'package:hermes_ui/features/onboarding/onboarding_providers.dart';
import 'package:hermes_ui/features/session_list/session_list_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_session_list_api.dart';
import '../../helpers/in_memory_secure_storage.dart';

void main() {
  late InMemorySecureStorage storage;
  late _FakeOnboardingApi api;

  setUp(() {
    storage = InMemorySecureStorage();
    api = _FakeOnboardingApi();
    SharedPreferences.setMockInitialValues({});
  });

  /// 组装完整 App（真实 router + 守卫），override 存储与 onboarding API。
  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          connectionStoreProvider.overrideWithValue(
            ConnectionStore(storage: storage),
          ),
          onboardingApiFactoryProvider.overrideWithValue(
            (baseUrl, headers) => api,
          ),
          // 会话列表页注入 fake（空列表），避免测试环境发起真实网络请求。
          sessionListApiFactoryProvider.overrideWithValue(
            (_) => FakeSessionListApi(),
          ),
        ],
        child: const HermesApp(),
      ),
    );
    // 初始路由（守卫重定向到 onboarding）+ 页面过渡动画
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// 填入服务器地址。
  Future<void> fillUrl(
    WidgetTester tester, [
    String url = 'http://hermes.local:30002',
  ]) async {
    await tester.enterText(find.byKey(const ValueKey('onboarding-url')), url);
    await tester.pump();
  }

  /// 让当前聚焦的输入框失焦。
  ///
  /// FocusNode listener 触发对应即时校验（URL → 健康检查；密码 → 试探登录），
  /// 两次异步段各 pump 一次以完成 setState。
  Future<void> unfocus(WidgetTester tester) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.pump();
    await tester.pump();
  }

  testWidgets('单页连接：合法 URL 失焦 → 健康检查成功显示通过提示', (tester) async {
    await pumpApp(tester);

    // 路由守卫：无连接 → onboarding 单页
    expect(find.text('连接你的 Hermes 服务器'), findsOneWidget);

    await fillUrl(tester);
    await unfocus(tester);

    // 健康检查成功：绿色通过提示 + auth 未启用文案（fake 默认），无密码框
    expect(find.text('✅ 连接成功'), findsOneWidget);
    expect(find.text('该服务器未启用密码认证，可直接继续'), findsOneWidget);
    expect(api.healthCalls, 1);
    expect(api.authCalls, 1);
  });

  testWidgets('非法 URL 失焦 → 即时显示格式错误，不触发健康检查', (tester) async {
    await pumpApp(tester);

    await fillUrl(tester, 'not-a-url');
    await unfocus(tester);

    expect(
      find.text('❌ 请输入有效的服务器地址，例如 https://hermes.example.com:30002'),
      findsOneWidget,
    );
    expect(api.healthCalls, 0);
    expect(find.byKey(const ValueKey('onboarding-password')), findsNothing);
  });

  testWidgets('auth 启用时显示密码框，密码失焦验证成功显示通过提示', (tester) async {
    api.authEnabled = true;
    await pumpApp(tester);

    await fillUrl(tester);
    await unfocus(tester);
    expect(find.text('该服务器需要密码认证，请登录'), findsOneWidget);

    // 密码框出现后才能填写
    final passwordField = find.byKey(const ValueKey('onboarding-password'));
    expect(passwordField, findsOneWidget);
    await tester.enterText(passwordField, 'pw123');
    await tester.pump();

    await unfocus(tester);

    expect(find.text('✅ 密码正确'), findsOneWidget);
    expect(api.loginCalls, 1);
    expect(api.lastPassword, 'pw123');
  });

  testWidgets('密码失焦验证失败 → 就地显示错误文案', (tester) async {
    api.authEnabled = true;
    api.loginOk = false;
    await pumpApp(tester);

    await fillUrl(tester);
    await unfocus(tester);

    await tester.enterText(
      find.byKey(const ValueKey('onboarding-password')),
      'wrong',
    );
    await tester.pump();
    await unfocus(tester);

    expect(find.textContaining('登录失败'), findsOneWidget);
    expect(api.loginCalls, 1);
  });

  testWidgets('auth 未启用时不显示密码框', (tester) async {
    api.authEnabled = false;
    await pumpApp(tester);

    await fillUrl(tester);
    await unfocus(tester);

    expect(find.text('该服务器未启用密码认证，可直接继续'), findsOneWidget);
    expect(find.byKey(const ValueKey('onboarding-password')), findsNothing);
  });

  testWidgets('完整流程：URL + 密码 → 连接保存（username 为 null，customHeaders 为空）并跳转 /', (
    tester,
  ) async {
    api.authEnabled = true;
    await pumpApp(tester);

    await fillUrl(tester);
    await unfocus(tester);

    // 填写密码（不失焦验证也可直接保存）
    await tester.enterText(
      find.byKey(const ValueKey('onboarding-password')),
      'pw123',
    );
    await tester.pump();

    // 连接 → 保存连接 + setActive + 跳转 /
    await tester.tap(find.byKey(const ValueKey('onboarding-connect')));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('暂无会话'), findsOneWidget);

    // 验证持久化：connections blob + 密码单独 key + active id
    final raw = storage.data[ConnectionStore.connectionsKey];
    expect(raw, isNotNull);
    final list = jsonDecode(raw!) as List;
    expect(list, hasLength(1));
    final saved = list.single as Map<String, Object?>;
    expect(saved['base_url'], 'http://hermes.local:30002');
    expect(saved['name'], 'hermes.local');
    expect(saved.containsKey('username'), isFalse); // 无用户名概念，恒为 null
    expect((saved['custom_headers'] as Map), isEmpty);
    final id = saved['id'] as String;
    expect(storage.data[ConnectionStore.passwordKey(id)], 'pw123');
    expect(storage.data[ConnectionStore.activeConnectionKey], id);
  });

  testWidgets('引导页不展示自定义 Headers 高级设置区块', (tester) async {
    await pumpApp(tester);

    expect(find.byKey(const ValueKey('onboarding-add-header')), findsNothing);
    expect(find.byKey(const ValueKey('onboarding-header-name-0')), findsNothing);
    expect(find.text('自定义 Headers（可选）'), findsNothing);
  });
}

/// 纯 Dart 假 onboarding API（无网络，widget 测试 FakeAsync 下可靠完成）。
class _FakeOnboardingApi implements OnboardingServerApi {
  bool authEnabled = false;
  bool loginOk = true;
  bool healthOk = true;

  int healthCalls = 0;
  int authCalls = 0;
  int loginCalls = 0;
  String? lastPassword;

  @override
  Future<HealthResponse> health() async {
    healthCalls++;
    return HealthResponse(status: healthOk ? 'ok' : 'degraded');
  }

  @override
  Future<AuthStatusResponse> authStatus() async {
    authCalls++;
    return AuthStatusResponse(authEnabled: authEnabled);
  }

  @override
  Future<LoginResponse> login(String password) async {
    loginCalls++;
    lastPassword = password;
    if (!loginOk) {
      throw const UnauthorizedException('密码错误');
    }
    return const LoginResponse(ok: true);
  }
}
