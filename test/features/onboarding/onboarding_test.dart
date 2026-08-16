import 'dart:convert';

import 'package:flutter/widgets.dart' show ValueKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermex_flutter/app/app.dart';
import 'package:hermex_flutter/core/api/api_exception.dart';
import 'package:hermex_flutter/core/connections/connection_providers.dart';
import 'package:hermex_flutter/core/connections/connection_store.dart';
import 'package:hermex_flutter/features/onboarding/onboarding_providers.dart';
import 'package:hermex_flutter/features/session_list/session_list_providers.dart';
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
        child: const HermexApp(),
      ),
    );
    // 初始路由（守卫重定向到 onboarding）+ 页面过渡动画
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// 进入步骤 1 并填好服务器地址。
  Future<void> fillUrl(WidgetTester tester) async {
    await tester.enterText(
      find.byKey(const ValueKey('onboarding-url')),
      'http://hermes.local:30002',
    );
    await tester.pump();
  }

  /// 走完步骤 1/2 到达步骤 3（auth 未启用，跳过认证）。
  Future<void> goToStep3(WidgetTester tester) async {
    await fillUrl(tester);
    await tester.tap(find.byKey(const ValueKey('onboarding-footer-next')));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('onboarding-footer-next')));
    await tester.pump();
  }

  testWidgets('三步向导：健康检查 → 跳过认证 → 自定义头 → 完成保存并跳转 /', (tester) async {
    await pumpApp(tester);

    // 路由守卫：无连接 → onboarding
    expect(find.text('连接你的 Hermex 服务器'), findsOneWidget);

    // 步骤 1：填 URL + 健康检查成功
    await fillUrl(tester);
    await tester.tap(find.byKey(const ValueKey('onboarding-health-check')));
    await tester.pump();
    await tester.pump();
    expect(find.text('✅ 连接成功'), findsOneWidget);
    expect(api.healthCalls, 1);

    // 下一步 → 步骤 2：服务器未启用认证，显示可跳过
    await tester.tap(find.byKey(const ValueKey('onboarding-footer-next')));
    await tester.pump();
    await tester.pump();
    expect(find.text('该服务器未启用密码认证，可直接继续'), findsOneWidget);

    // 继续 → 步骤 3：自定义 Headers
    await tester.tap(find.byKey(const ValueKey('onboarding-footer-next')));
    await tester.pump();
    expect(find.text('自定义 Headers（可选）'), findsOneWidget);

    // 添加一行 header 并填写
    await tester.tap(find.byKey(const ValueKey('onboarding-add-header')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('onboarding-header-name-0')),
      'Authorization',
    );
    await tester.enterText(
      find.byKey(const ValueKey('onboarding-header-value-0')),
      'Bearer abc',
    );
    await tester.pump();

    // 完成 → 保存连接 + setActive + 跳转 /
    await tester.tap(find.byKey(const ValueKey('onboarding-footer-finish')));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('暂无会话'), findsOneWidget);

    // 验证持久化：connections blob + active id
    final raw = storage.data[ConnectionStore.connectionsKey];
    expect(raw, isNotNull);
    final list = jsonDecode(raw!) as List;
    expect(list, hasLength(1));
    final saved = list.single as Map<String, Object?>;
    expect(saved['base_url'], 'http://hermes.local:30002');
    expect(saved['name'], 'hermes.local');
    expect(
      (saved['custom_headers'] as Map)['Authorization'],
      'Bearer abc',
    );
    expect(storage.data[ConnectionStore.activeConnectionKey], saved['id']);
  });

  testWidgets('密码登录路径：auth 启用 → 登录成功进入步骤 3', (tester) async {
    api.authEnabled = true;
    await pumpApp(tester);
    await fillUrl(tester);

    await tester.tap(find.byKey(const ValueKey('onboarding-footer-next')));
    await tester.pump();
    await tester.pump();
    expect(find.text('该服务器需要密码认证，请登录'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('onboarding-password')),
      'pw123',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('onboarding-footer-next')));
    await tester.pump();
    await tester.pump();

    expect(find.text('自定义 Headers（可选）'), findsOneWidget);
    expect(api.loginCalls, 1);
    expect(api.lastPassword, 'pw123');
  });

  testWidgets('登录失败 → CupertinoAlertDialog 提示，停留在步骤 2', (tester) async {
    api.authEnabled = true;
    api.loginOk = false;
    await pumpApp(tester);
    await fillUrl(tester);

    await tester.tap(find.byKey(const ValueKey('onboarding-footer-next')));
    await tester.pump();
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('onboarding-password')),
      'wrong',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('onboarding-footer-next')));
    await tester.pump();
    await tester.pump();

    expect(find.text('登录失败'), findsOneWidget);
    expect(api.loginCalls, 1);

    // 关闭弹窗后仍在步骤 2
    await tester.tap(find.text('好'));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('onboarding-password')), findsOneWidget);
    expect(find.text('自定义 Headers（可选）'), findsNothing);
  });

  testWidgets('非法 Header（名含空格）→ 完成时报错，不保存连接', (tester) async {
    await pumpApp(tester);
    await goToStep3(tester);

    await tester.enterText(
      find.byKey(const ValueKey('onboarding-header-name-0')),
      'Bad Name', // 空格不是 RFC 7230 token
    );
    await tester.enterText(
      find.byKey(const ValueKey('onboarding-header-value-0')),
      'x',
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('onboarding-footer-finish')));
    await tester.pump();
    expect(find.text('Header 名必须是合法 token，值不能包含换行'), findsOneWidget);

    expect(storage.data[ConnectionStore.connectionsKey], isNull); // 未保存
  });

  testWidgets('跳过向导入口：直接进入步骤 3', (tester) async {
    await pumpApp(tester);
    await fillUrl(tester);

    await tester.tap(find.byKey(const ValueKey('onboarding-skip-wizard')));
    await tester.pump();
    expect(find.text('自定义 Headers（可选）'), findsOneWidget);
  });

  testWidgets('健康检查失败（服务器返回异常状态）显示错误', (tester) async {
    api.healthOk = false;
    await pumpApp(tester);
    await fillUrl(tester);

    await tester.tap(find.byKey(const ValueKey('onboarding-health-check')));
    await tester.pump();
    await tester.pump();
    expect(find.text('❌ 服务器返回异常状态'), findsOneWidget);
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
  Future<Object?> health() async {
    healthCalls++;
    return {'status': healthOk ? 'ok' : 'degraded'};
  }

  @override
  Future<Object?> authStatus() async {
    authCalls++;
    return {'auth_enabled': authEnabled};
  }

  @override
  Future<Object?> login(String password) async {
    loginCalls++;
    lastPassword = password;
    if (!loginOk) {
      throw const UnauthorizedException('密码错误');
    }
    return {'ok': true};
  }
}
