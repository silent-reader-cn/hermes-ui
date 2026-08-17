import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermex_flutter/app/theme/theme_provider.dart';
import 'package:hermex_flutter/core/api/api_client.dart';
import 'package:hermex_flutter/core/api/api_exception.dart';
import 'package:hermex_flutter/core/connections/connection_providers.dart';
import 'package:hermex_flutter/core/connections/connection_store.dart';
import 'package:hermex_flutter/core/connections/server_connection.dart';
import 'package:hermex_flutter/core/models/server_catalog.dart';
import 'package:hermex_flutter/features/onboarding/onboarding_providers.dart';
import 'package:hermex_flutter/features/settings/settings_page.dart';
import 'package:hermex_flutter/features/settings/settings_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_onboarding_login_api.dart';
import '../../helpers/fake_settings_api.dart';
import '../../helpers/in_memory_secure_storage.dart';

/// 构造服务器连接（测试用）。
ServerConnection buildConn(String id, String name, String url) {
  return ServerConnection(
    id: id,
    name: name,
    baseUrl: url,
    createdAt: DateTime.utc(2026, 1, 1),
  );
}

/// 两个 provider 分组 + 一个 extra model 的样例目录（与 controller 测试共用形状）。
const sampleGroups = <Map<String, Object?>>[
  {
    'provider_id': 'openai',
    'name': 'OpenAI',
    'models': [
      {'id': 'gpt-4o', 'name': 'GPT-4o'},
      {'id': 'gpt-4o-mini', 'name': 'GPT-4o mini'},
    ],
    'extra_models': [
      {'id': 'o3', 'name': 'o3'},
    ],
  },
  {
    'provider_id': 'anthropic',
    'name': 'Anthropic',
    'models': [
      {'id': 'claude-sonnet-4', 'name': 'Claude Sonnet 4'},
    ],
  },
];

/// 带模型目录 + 推理能力的默认 fake 配置。
FakeSettingsApi buildApi() {
  final api = FakeSettingsApi();
  api.modelsResponse = ModelsResponse.fromJson({
    'default_model': 'gpt-4o',
    'active_provider': 'openai',
    'groups': sampleGroups,
  });
  api.reasoningResponse = const ReasoningStatusResponse(
    ok: true,
    reasoningEffort: 'medium',
    supportedEfforts: ['low', 'medium', 'high'],
    supportsReasoningEffort: true,
  );
  return api;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  /// 组装容器：注入内存存储（预置连接）+ fake 设置 API + 占位 ApiClient。
  Future<ProviderContainer> makeContainer({
    required FakeSettingsApi api,
    List<ServerConnection> connections = const [],
    String? activeId,
    FakeOnboardingLoginApi? loginApi,
  }) async {
    final storage = InMemorySecureStorage();
    final store = ConnectionStore(storage: storage);
    for (final connection in connections) {
      await store.save(connection);
    }
    if (activeId != null) {
      await store.setActive(activeId);
    }
    final container = ProviderContainer(
      overrides: [
        connectionStoreProvider.overrideWithValue(store),
        apiClientProvider.overrideWithValue(
          ApiClient(baseUrl: 'http://test.local:30002'),
        ),
        settingsApiFactoryProvider.overrideWithValue((_) => api),
        onboardingApiFactoryProvider.overrideWithValue(
          (baseUrl, headers) => loginApi ?? FakeOnboardingLoginApi(),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  /// 挂载设置页（CupertinoApp 提供 Directionality / 主题）并等异步加载完成。
  Future<void> pumpPage(
    WidgetTester tester,
    ProviderContainer container,
  ) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const CupertinoApp(home: SettingsPage()),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  group('分组渲染', () {
    testWidgets('四组标题 + 当前服务器 + 默认模型 + 推理强度 + 版本号', (tester) async {
      final container = await makeContainer(
        api: buildApi(),
        connections: [buildConn('c1', 'Home', 'http://hermes.local:30002')],
        activeId: 'c1',
      );
      await pumpPage(tester, container);

      // 分组标题
      expect(find.text('外观'), findsOneWidget);
      expect(find.text('服务器'), findsOneWidget);
      expect(find.text('模型'), findsOneWidget);
      expect(find.text('关于'), findsOneWidget);

      // 列表行渲染 name + url（激活标识在行内勾选图标）
      final rowC1 = find.byKey(const ValueKey('server-row-c1'));
      expect(
        find.descendant(of: rowC1, matching: find.text('Home')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: rowC1,
          matching: find.text('http://hermes.local:30002'),
        ),
        findsOneWidget,
      );

      // 模型：默认模型显示名 + 推理强度
      expect(find.text('默认模型'), findsOneWidget);
      expect(find.text('GPT-4o'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('settings-reasoning')));
      expect(find.text('推理强度'), findsOneWidget);
      expect(find.text('medium'), findsOneWidget);

      // 关于：版本号
      await tester.ensureVisible(find.text('版本'));
      expect(find.text('版本'), findsOneWidget);
      expect(find.text('1.0.0+1'), findsOneWidget);
    });

    testWidgets('无激活连接 → 显示未连接', (tester) async {
      final container = await makeContainer(
        api: buildApi(),
        connections: [buildConn('c1', 'Home', 'http://hermes.local:30002')],
      );
      await pumpPage(tester, container);

      // header 提示未连接；列表行无勾选图标
      expect(find.text('服务器（未连接）'), findsOneWidget);
      final activeIcon = find.descendant(
        of: find.byKey(const ValueKey('server-row-c1')),
        matching: find.byIcon(CupertinoIcons.checkmark_circle_fill),
      );
      expect(activeIcon, findsNothing);
    });

    testWidgets('模型加载失败 → 错误态 + 重试成功', (tester) async {
      final api = buildApi();
      api.modelsError = NetworkException(NetworkExceptionKind.cannotConnect);
      final container = await makeContainer(
        api: api,
        connections: [buildConn('c1', 'Home', 'http://hermes.local:30002')],
        activeId: 'c1',
      );
      await pumpPage(tester, container);

      expect(find.text('模型加载失败'), findsOneWidget);

      api.modelsError = null;
      await tester.tap(find.byKey(const ValueKey('settings-models-retry')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('模型加载失败'), findsNothing);
      expect(find.text('默认模型'), findsOneWidget);
      expect(find.text('GPT-4o'), findsOneWidget);
    });

    testWidgets('服务器不支持推理强度 → 不显示推理行', (tester) async {
      final api = buildApi();
      api.reasoningResponse = const ReasoningStatusResponse(
        ok: true,
        supportsReasoningEffort: false,
      );
      final container = await makeContainer(
        api: api,
        connections: [buildConn('c1', 'Home', 'http://hermes.local:30002')],
        activeId: 'c1',
      );
      await pumpPage(tester, container);

      expect(find.text('默认模型'), findsOneWidget);
      expect(find.byKey(const ValueKey('settings-reasoning')), findsNothing);
    });
  });

  group('主题切换', () {
    testWidgets('三态分段控件：点深色 / 浅色 更新 themeModeProvider', (tester) async {
      final container = await makeContainer(api: buildApi());
      await pumpPage(tester, container);

      expect(container.read(themeModeProvider), AppThemeMode.system);

      await tester.tap(find.text('深色'));
      await tester.pump();
      expect(container.read(themeModeProvider), AppThemeMode.dark);

      await tester.tap(find.text('浅色'));
      await tester.pump();
      expect(container.read(themeModeProvider), AppThemeMode.light);

      await tester.tap(find.text('跟随系统'));
      await tester.pump();
      expect(container.read(themeModeProvider), AppThemeMode.system);
    });
  });

  group('服务器操作', () {
    testWidgets('列表渲染：激活行有勾选，非激活行可点切换', (tester) async {
      final container = await makeContainer(
        api: buildApi(),
        connections: [
          buildConn('c1', 'Home', 'http://hermes.local:30002'),
          buildConn('c2', 'Office', 'http://office.example.com:30002'),
        ],
        activeId: 'c1',
      );
      await pumpPage(tester, container);

      expect(find.text('Office'), findsOneWidget);
      // c1 激活：仅列表行显示 c1（无独立 active 行），行内勾选图标
      expect(find.text('Home'), findsOneWidget);
      final activeIcon = find.descendant(
        of: find.byKey(const ValueKey('server-row-c1')),
        matching: find.byIcon(CupertinoIcons.checkmark_circle_fill),
      );
      expect(activeIcon, findsOneWidget);
      final inactiveIcon = find.descendant(
        of: find.byKey(const ValueKey('server-row-c2')),
        matching: find.byIcon(CupertinoIcons.checkmark_circle_fill),
      );
      expect(inactiveIcon, findsNothing);

      // 切换激活
      await tester.tap(find.byKey(const ValueKey('server-row-c2')));
      await tester.pump();
      await tester.pump();
      expect(container.read(activeConnectionProvider)?.id, 'c2');
      expect(container.read(activeConnectionProvider)?.name, 'Office');
    });

    testWidgets('添加服务器：空 URL 校验失败 → 填写保存入列表', (tester) async {
      final container = await makeContainer(
        api: buildApi(),
        connections: [buildConn('c1', 'Home', 'http://hermes.local:30002')],
        activeId: 'c1',
      );
      await pumpPage(tester, container);

      await tester.tap(find.byKey(const ValueKey('server-add')));
      await tester.pumpAndSettle();

      // 空 URL 直接保存 → 校验错误
      await tester.tap(find.byKey(const ValueKey('server-editor-save')));
      await tester.pump();
      expect(find.text('请输入服务器地址'), findsOneWidget);

      // 填名称 + URL → 保存成功并返回
      await tester.enterText(
        find.byKey(const ValueKey('server-editor-name')),
        'Lab',
      );
      await tester.enterText(
        find.byKey(const ValueKey('server-editor-url')),
        'http://lab.example.com:30002',
      );
      await tester.tap(find.byKey(const ValueKey('server-editor-save')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('server-editor-url')), findsNothing);
      final connections = container.read(connectionsProvider);
      expect(connections, hasLength(2));
      expect(connections.last.name, 'Lab');
      expect(connections.last.baseUrl, 'http://lab.example.com:30002');
      // 列表中出现新行
      expect(find.text('Lab'), findsOneWidget);
    });

    testWidgets('编辑服务器：表单预填 + 改名保存', (tester) async {
      final container = await makeContainer(
        api: buildApi(),
        connections: [buildConn('c2', 'Office', 'http://office.example.com:30002')],
        activeId: 'c2',
      );
      await pumpPage(tester, container);

      await tester.tap(find.byKey(const ValueKey('server-edit-c2')));
      await tester.pumpAndSettle();

      // 预填原值
      final urlField = tester.widget<CupertinoTextField>(
        find.byKey(const ValueKey('server-editor-url')),
      );
      expect(urlField.controller!.text, 'http://office.example.com:30002');

      // 改名保存
      await tester.enterText(
        find.byKey(const ValueKey('server-editor-name')),
        'Main Office',
      );
      await tester.tap(find.byKey(const ValueKey('server-editor-save')));
      await tester.pumpAndSettle();

      final connections = container.read(connectionsProvider);
      expect(connections, hasLength(1));
      expect(connections.single.id, 'c2'); // id 不变（编辑）
      expect(connections.single.name, 'Main Office');
      expect(connections.single.baseUrl, 'http://office.example.com:30002');
      // 列表行显示新名称（active 信息行也可能显示同名，用行内查询）
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('server-row-c2')),
          matching: find.text('Main Office'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('添加服务器带密码：先登录成功再保存入列表', (tester) async {
      final loginApi = FakeOnboardingLoginApi();
      final container = await makeContainer(
        api: buildApi(),
        connections: [buildConn('c1', 'Home', 'http://hermes.local:30002')],
        activeId: 'c1',
        loginApi: loginApi,
      );
      await pumpPage(tester, container);

      await tester.tap(find.byKey(const ValueKey('server-add')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('server-editor-name')),
        'Main',
      );
      await tester.enterText(
        find.byKey(const ValueKey('server-editor-url')),
        'http://main.example.com:30002',
      );
      await tester.enterText(
        find.byKey(const ValueKey('server-editor-password')),
        'secret',
      );
      await tester.tap(find.byKey(const ValueKey('server-editor-save')));
      await tester.pumpAndSettle();

      // 保存前先登录（种 cookie），成功后才落库
      expect(loginApi.loginCalls, 1);
      expect(loginApi.lastPassword, 'secret');
      final connections = container.read(connectionsProvider);
      expect(connections, hasLength(2));
      expect(connections.last.password, 'secret');
      expect(find.byKey(const ValueKey('server-editor-url')), findsNothing);
    });

    testWidgets('密码错误：登录失败 → 报错且不保存', (tester) async {
      final loginApi = FakeOnboardingLoginApi()
        ..loginError = const UnauthorizedException();
      final container = await makeContainer(
        api: buildApi(),
        connections: [buildConn('c1', 'Home', 'http://hermes.local:30002')],
        activeId: 'c1',
        loginApi: loginApi,
      );
      await pumpPage(tester, container);

      await tester.tap(find.byKey(const ValueKey('server-add')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('server-editor-url')),
        'http://main.example.com:30002',
      );
      await tester.enterText(
        find.byKey(const ValueKey('server-editor-password')),
        'wrong',
      );
      await tester.tap(find.byKey(const ValueKey('server-editor-save')));
      await tester.pumpAndSettle();

      // 错误提示 + 表单停留 + 未落库
      expect(
        find.text('登录失败：密码被拒绝。请检查服务器密码后重试。'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('server-editor-url')), findsOneWidget);
      expect(container.read(connectionsProvider), hasLength(1));
    });

    testWidgets('删除服务器：确认弹窗 → 移除且激活不受影响', (tester) async {
      final container = await makeContainer(
        api: buildApi(),
        connections: [
          buildConn('c1', 'Home', 'http://hermes.local:30002'),
          buildConn('c2', 'Office', 'http://office.example.com:30002'),
        ],
        activeId: 'c1',
      );
      await pumpPage(tester, container);

      await tester.tap(find.byKey(const ValueKey('server-delete-c2')));
      await tester.pumpAndSettle();
      expect(find.text('删除服务器'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('server-delete-confirm')));
      await tester.pumpAndSettle();

      final connections = container.read(connectionsProvider);
      expect(connections.map((c) => c.id).toList(), ['c1']);
      expect(container.read(activeConnectionProvider)?.id, 'c1');
      expect(find.text('Office'), findsNothing);
    });
  });

  group('模型操作', () {
    testWidgets('默认模型选择器：进入选择页 → 选 o3 → 调 API 并更新显示', (tester) async {
      final api = buildApi();
      final container = await makeContainer(
        api: api,
        connections: [buildConn('c1', 'Home', 'http://hermes.local:30002')],
        activeId: 'c1',
      );
      await pumpPage(tester, container);

      await tester.ensureVisible(
        find.byKey(const ValueKey('settings-default-model')),
      );
      await tester.tap(find.byKey(const ValueKey('settings-default-model')));
      await tester.pumpAndSettle();

      // 选择页：分组 + 选项渲染
      expect(find.text('OpenAI'), findsOneWidget);
      expect(find.text('Anthropic'), findsOneWidget);
      expect(find.byKey(const ValueKey('model-option-o3')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('model-option-o3')));
      await tester.pumpAndSettle();

      expect(api.defaultModelCalls, ['o3']);
      // 返回设置页后默认模型显示更新（id 不在目录 → 回退显示 id）
      expect(find.byKey(const ValueKey('model-option-o3')), findsNothing);
      expect(find.text('o3'), findsOneWidget);
    });

    testWidgets('推理强度：action sheet 选择 high → 调 API', (tester) async {
      final api = buildApi();
      final container = await makeContainer(
        api: api,
        connections: [buildConn('c1', 'Home', 'http://hermes.local:30002')],
        activeId: 'c1',
      );
      await pumpPage(tester, container);

      await tester.ensureVisible(find.byKey(const ValueKey('settings-reasoning')));
      await tester.tap(find.byKey(const ValueKey('settings-reasoning')));
      await tester.pumpAndSettle();

      expect(find.text('推理强度'), findsWidgets); // 标题行 + action sheet 标题
      await tester.tap(find.byKey(const ValueKey('reasoning-high')));
      await tester.pumpAndSettle();

      expect(api.reasoningEffortCalls, ['high']);
    });
  });
}
