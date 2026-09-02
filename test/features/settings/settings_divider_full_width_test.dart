import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/api/api_exception.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/connections/connection_store.dart';
import 'package:hermes_ui/core/connections/server_connection.dart';
import 'package:hermes_ui/features/onboarding/onboarding_providers.dart';
import 'package:hermes_ui/features/settings/settings_page.dart';
import 'package:hermes_ui/features/settings/settings_providers.dart';
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

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  /// 组装容器：注入内存存储（预置连接）+ fake 设置 API + 占位 ApiClient。
  Future<ProviderContainer> makeContainer({
    required FakeSettingsApi api,
    List<ServerConnection> connections = const [],
    String? activeId,
  }) async {
    final storage = InMemorySecureStorage();
    final store = ConnectionStore(storage: storage);
    for (final connection in connections) {
      await store.save(connection);
    }
    if (activeId != null) {
      await store.setActive(activeId);
    }
    final client = ApiClient(baseUrl: 'http://test.local:30002');
    final container = ProviderContainer(
      overrides: [
        connectionStoreProvider.overrideWithValue(store),
        apiClientProvider.overrideWithValue(client),
        settingsApiFactoryProvider.overrideWithValue((_) => api),
        onboardingApiFactoryProvider.overrideWithValue(
          (baseUrl, headers) => FakeOnboardingLoginApi(),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  /// 挂载设置页（大视口让尽量多分组构建）+ 等异步加载完成。
  Future<void> pumpPage(
    WidgetTester tester,
    ProviderContainer container, {
    Size size = const Size(800, 2000),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MediaQuery(
          data: MediaQueryData(size: size),
          child: const CupertinoApp(
            theme: CupertinoThemeData(),
            home: SettingsPage(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  /// 断言页面上所有已构建 ListSection 的分割线起点置 0（全宽贯穿）。
  ///
  /// 根因（SDK 源码 list_section.dart）：短分割线
  /// `margin: EdgeInsetsDirectional.only(start: dividerMargin + additionalDividerMargin)`，
  /// base 构造默认 dividerMargin=20 且 hasLeading=true 时 additionalDividerMargin=44
  /// → 起点 64px；insetGrouped 默认 14(+42)。置 0 后从容器左缘起笔（#28 同款）。
  void expectAllSectionsFullWidth(WidgetTester tester, String stage) {
    final widgets = tester
        .widgetList<CupertinoListSection>(find.byType(CupertinoListSection))
        .toList();
    expect(widgets, isNotEmpty, reason: '$stage 应有 ListSection 已构建');
    for (final section in widgets) {
      expect(
        section.dividerMargin,
        equals(0.0),
        reason: '$stage 分割线应从容器左缘起笔（dividerMargin=0）',
      );
      expect(
        section.additionalDividerMargin,
        equals(0.0),
        reason: '$stage 分割线应从容器左缘起笔（additionalDividerMargin=0）',
      );
    }
  }

  testWidgets('设置页全宽分割线：所有已构建分组 dividerMargin 均置 0', (tester) async {
    final container = await makeContainer(
      api: FakeSettingsApi(),
      connections: [buildConn('c1', 'Home', 'http://hermes.local:30002')],
      activeId: 'c1',
    );
    await pumpPage(tester, container);

    // 首屏：外观 / 对话 / 服务器 / 模型 等分组
    expectAllSectionsFullWidth(tester, '首屏');

    // 滚动中段：定时会话 / 通知 / 二级入口组
    await tester.drag(
      find.byKey(const ValueKey('settings-scroll')),
      const Offset(0, -1500),
    );
    await tester.pumpAndSettle();
    expectAllSectionsFullWidth(tester, '中段');

    // 滚动到底：关于分组（惰性构建区）
    await tester.drag(
      find.byKey(const ValueKey('settings-scroll')),
      const Offset(0, -3000),
    );
    await tester.pumpAndSettle();
    expectAllSectionsFullWidth(tester, '底部');
  });

  testWidgets('设置页全宽分割线：加载态与错误态分组同样全宽', (tester) async {
    // 加载态：模型分组初始为 loading（settingsController 未解析完成）
    final loadingContainer = await makeContainer(api: FakeSettingsApi());
    await pumpPage(tester, loadingContainer);
    expectAllSectionsFullWidth(tester, '初始加载');

    // 错误态：models() 抛错 → 模型分组走 error 分支
    final failingApi = FakeSettingsApi()
      ..modelsError = HttpException(500, null, message: '加载失败');
    final failingContainer = await makeContainer(api: failingApi);
    await pumpPage(tester, failingContainer);
    await tester.pump(const Duration(milliseconds: 100));
    expectAllSectionsFullWidth(tester, '错误态');
  });
}
