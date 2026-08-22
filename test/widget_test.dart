import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermex_flutter/app/app.dart';
import 'package:hermex_flutter/core/connections/connection_providers.dart';
import 'package:hermex_flutter/core/connections/connection_store.dart';
import 'package:hermex_flutter/core/connections/server_connection.dart';
import 'package:hermex_flutter/features/session_list/session_list_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/fake_session_list_api.dart';
import 'package:hermex_flutter/features/session_list/session_auto_refresh.dart';
import 'helpers/in_memory_secure_storage.dart';

/// App 壳冒烟测试（替换模板 Counter 测试）。
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    enableSessionAutoRefresh = false;
  });
  tearDown(() {
    enableSessionAutoRefresh = true;
  });

  ServerConnection buildConn(String id) {
    return ServerConnection(
      id: id,
      name: 'Home',
      baseUrl: 'http://hermes.local:30002',
      createdAt: DateTime.utc(2026, 1, 1),
    );
  }

  testWidgets('无连接 → 路由守卫进入 onboarding 向导', (tester) async {
    final storage = InMemorySecureStorage();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          connectionStoreProvider.overrideWithValue(
            ConnectionStore(storage: storage),
          ),
        ],
        child: const HermexApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('连接你的 Hermex 服务器'), findsOneWidget);
    expect(find.text('暂无会话'), findsNothing);
  });

  testWidgets('有激活连接 → 异步加载后进入 SessionList 空态', (tester) async {
    final storage = InMemorySecureStorage();
    final store = ConnectionStore(storage: storage);
    final conn = buildConn('c1');
    await store.save(conn);
    await store.setActive(conn.id);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          connectionStoreProvider.overrideWithValue(store),
          // 会话列表页注入 fake（空列表），避免测试环境发起真实网络请求。
          sessionListApiFactoryProvider.overrideWithValue(
            (_) => FakeSessionListApi(),
          ),
        ],
        child: const HermexApp(),
      ),
    );
    // 连接/active 异步加载完成 → refreshListenable 触发守卫重定向 →
    // 两次页面过渡动画（onboarding 400ms + SessionList 400ms）
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    expect(find.text('暂无会话'), findsOneWidget);
    expect(find.text('连接你的 Hermex 服务器'), findsNothing);
  });

  testWidgets('默认主题浅色（跟随系统，测试环境为 light）', (tester) async {
    final storage = InMemorySecureStorage();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          connectionStoreProvider.overrideWithValue(
            ConnectionStore(storage: storage),
          ),
        ],
        child: const HermexApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final app = tester.widget<CupertinoApp>(find.byType(CupertinoApp));
    expect(app.theme?.brightness, Brightness.light);
    expect(app.theme?.primaryColor, const Color(0xFF007AFF));
  });
}