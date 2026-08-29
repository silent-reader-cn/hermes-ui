import 'dart:convert';

import 'package:flutter/widgets.dart' show EditableText, FocusManager, ValueKey;
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

  /// 点击底部「连接并保存」提交按钮，并推进异步检查/保存链路。
  ///
  /// 阶段一：health → authStatus；阶段二：login → upsert → 跳转。
  Future<void> tapConnect(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('onboarding-connect')));
    await tester.pump();
    await tester.pump();
    await tester.pump();
    await tester.pump();
  }

  testWidgets('输入 URL 后不点提交：不触发任何健康检查（无失焦隐式事件）', (tester) async {
    await pumpApp(tester);

    // 路由守卫：无连接 → onboarding 单页
    expect(find.text('连接你的 Hermes 服务器'), findsOneWidget);

    await fillUrl(tester);

    // 输入后仅失焦（模拟旧行为），不再触发检查
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(api.healthCalls, 0);
    expect(api.authCalls, 0);
    expect(find.byKey(const ValueKey('onboarding-password')), findsNothing);
  });

  testWidgets('提交：非法 URL → 弹窗提示格式错误 + 就地红字，不触发健康检查', (tester) async {
    await pumpApp(tester);

    await fillUrl(tester, 'not-a-url');
    await tapConnect(tester);

    // 弹窗（对齐 #19 确认框模式）：标题「连接失败」+ 格式错误内容
    expect(find.text('连接失败'), findsOneWidget);
    expect(
      find.text('请输入有效的服务器地址，例如 https://hermes.example.com:30002'),
      findsOneWidget,
    );
    // 就地红字并存
    expect(
      find.text('❌ 请输入有效的服务器地址，例如 https://hermes.example.com:30002'),
      findsOneWidget,
    );
    expect(api.healthCalls, 0);
    expect(find.byKey(const ValueKey('onboarding-password')), findsNothing);

    // 关闭弹窗后消失
    await tester.tap(find.text('好'));
    await tester.pump();
    await tester.pump();
    expect(find.text('连接失败'), findsNothing);
  });

  testWidgets('提交：网络异常 → 弹窗「无法连接到服务器」', (tester) async {
    api.throwNetworkError = true;
    await pumpApp(tester);

    await fillUrl(tester);
    await tapConnect(tester);

    expect(find.text('连接失败'), findsOneWidget);
    expect(find.text('无法连接到服务器'), findsOneWidget);
    expect(api.healthCalls, 1);
    expect(find.byKey(const ValueKey('onboarding-password')), findsNothing);
  });

  testWidgets('提交：health 非 ok（非 Hermes）→ 弹窗「服务器返回异常状态」', (tester) async {
    api.healthOk = false;
    await pumpApp(tester);

    await fillUrl(tester);
    await tapConnect(tester);

    expect(find.text('连接失败'), findsOneWidget);
    expect(find.text('服务器返回异常状态'), findsOneWidget);
    expect(api.healthCalls, 1);
    expect(api.authCalls, 0); // 健康检查失败不继续查 auth
    expect(find.byKey(const ValueKey('onboarding-password')), findsNothing);
  });

  testWidgets('提交：无需密码（auth_enabled=false）→ 检查通过后直接保存跳转，密码框不出现', (
    tester,
  ) async {
    api.authEnabled = false;
    await pumpApp(tester);

    await fillUrl(tester);
    await tapConnect(tester);
    await tester.pump(const Duration(milliseconds: 400));

    // health → authStatus 顺序保持，login 从不调用
    expect(api.healthCalls, 1);
    expect(api.authCalls, 1);
    expect(api.loginCalls, 0);
    expect(find.byKey(const ValueKey('onboarding-password')), findsNothing);

    // 跳转会话列表
    expect(find.text('暂无会话'), findsOneWidget);

    // 验证持久化：connections blob + active id，无密码 key
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
    expect(storage.data[ConnectionStore.activeConnectionKey], id);
  });

  testWidgets('提交阶段一：需密码 → 密码框就地出现并自动聚焦，不强校验', (tester) async {
    api.authEnabled = true;
    await pumpApp(tester);

    await fillUrl(tester);
    await tapConnect(tester);

    expect(api.healthCalls, 1);
    expect(api.authCalls, 1);
    expect(api.loginCalls, 0); // 阶段一不触发 login
    expect(find.text('该服务器需要密码认证，请登录'), findsOneWidget);

    // 密码框出现且自动聚焦
    final passwordField = find.byKey(const ValueKey('onboarding-password'));
    expect(passwordField, findsOneWidget);
    final editable = tester.widget<EditableText>(
      find.descendant(of: passwordField, matching: find.byType(EditableText)),
    );
    expect(editable.focusNode.hasFocus, isTrue);
  });

  testWidgets('提交阶段二：密码正确 → 保存连接（username null / 空 Headers）并跳转 /', (
    tester,
  ) async {
    api.authEnabled = true;
    await pumpApp(tester);

    await fillUrl(tester);
    await tapConnect(tester);

    // 阶段一完成后填写密码并再次提交（阶段二：login → 保存 → 跳转）
    await tester.enterText(
      find.byKey(const ValueKey('onboarding-password')),
      'pw123',
    );
    await tester.pump();
    await tapConnect(tester);
    await tester.pump(const Duration(milliseconds: 400));

    expect(api.loginCalls, 1);
    expect(api.lastPassword, 'pw123');
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

  testWidgets('提交阶段二：密码错误 → 弹窗 + 就地红字并存，不保存不跳转', (tester) async {
    api.authEnabled = true;
    api.loginOk = false;
    await pumpApp(tester);

    await fillUrl(tester);
    await tapConnect(tester);

    await tester.enterText(
      find.byKey(const ValueKey('onboarding-password')),
      'wrong',
    );
    await tester.pump();
    await tapConnect(tester);

    // 弹窗（标题「登录失败」）+ 就地红字并存
    expect(find.text('登录失败'), findsOneWidget);
    expect(find.text('登录失败：密码错误'), findsOneWidget); // 弹窗内容
    expect(find.text('❌ 登录失败：密码错误'), findsOneWidget); // 就地红字
    expect(api.loginCalls, 1);

    // 未保存、未跳转
    expect(storage.data[ConnectionStore.connectionsKey], isNull);
    expect(find.text('暂无会话'), findsNothing);
  });

  testWidgets('引导页不展示自定义 Headers 高级设置区块', (tester) async {
    await pumpApp(tester);

    expect(find.byKey(const ValueKey('onboarding-add-header')), findsNothing);
    expect(
      find.byKey(const ValueKey('onboarding-header-name-0')),
      findsNothing,
    );
    expect(find.text('自定义 Headers（可选）'), findsNothing);
  });
}

/// 纯 Dart 假 onboarding API（无网络，widget 测试 FakeAsync 下可靠完成）。
class _FakeOnboardingApi implements OnboardingServerApi {
  bool authEnabled = false;
  bool loginOk = true;
  bool healthOk = true;
  bool throwNetworkError = false;

  int healthCalls = 0;
  int authCalls = 0;
  int loginCalls = 0;
  String? lastPassword;

  @override
  Future<HealthResponse> health() async {
    healthCalls++;
    if (throwNetworkError) throw Exception('network down');
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
