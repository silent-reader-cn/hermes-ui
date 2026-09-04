import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/app/theme/theme_provider.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/connections/connection_store.dart';
import 'package:hermes_ui/core/connections/server_connection.dart';
import 'package:hermes_ui/core/models/server_info.dart';
import 'package:hermes_ui/features/onboarding/onboarding_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/in_memory_secure_storage.dart';

/// 记录 login 的 onboarding fake（测试 autoReauth 是否用保存密码重登）。
class _FakeOnboardingApi implements OnboardingServerApi {
  int loginCalls = 0;
  String? lastPassword;

  @override
  Future<HealthResponse> health() async => const HealthResponse();

  @override
  Future<AuthStatusResponse> authStatus() async =>
      const AuthStatusResponse();

  @override
  Future<LoginResponse> login(String password) async {
    loginCalls++;
    lastPassword = password;
    return const LoginResponse(ok: true);
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  ServerConnection buildConn(String id, String baseUrl) {
    return ServerConnection(
      id: id,
      name: 'S$id',
      baseUrl: baseUrl,
      createdAt: DateTime.utc(2026, 1, 1),
    );
  }

  /// 建容器并挂 listener 保证 provider 存活（异步 _load 可靠完成）。
  ProviderContainer buildContainer() {
    final container = ProviderContainer(
      overrides: [
        connectionStoreProvider.overrideWithValue(
          ConnectionStore(storage: InMemorySecureStorage()),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.listen(activeConnectionProvider, (_, _) {});
    container.listen(connectionsProvider, (_, _) {});
    return container;
  }

  group('connectionsProvider', () {
    test('upsert 新增 + 更新，remove 删除并清 active', () async {
      final container = buildContainer();

      final controller = container.read(connectionsProvider.notifier);
      await controller.upsert(buildConn('a', 'http://a.local'));
      await controller.upsert(buildConn('b', 'http://b.local'));
      expect(container.read(connectionsProvider), hasLength(2));

      await controller.upsert(buildConn('a', 'http://a-new.local'));
      expect(container.read(connectionsProvider), hasLength(2));
      expect(
        container.read(connectionsProvider).first.baseUrl,
        'http://a-new.local',
      );

      await container.read(activeConnectionProvider.notifier).setActive('a');
      expect(container.read(activeConnectionProvider)?.id, 'a');

      await controller.remove('a');
      expect(container.read(connectionsProvider), hasLength(1));
      // 删除的是 active → active 经 watch 自动重算为 null
      expect(container.read(activeConnectionProvider), isNull);
    });

    test('upsertBuiltin 幂等置首', () async {
      final container = buildContainer();
      final controller = container.read(connectionsProvider.notifier);

      await controller.upsert(buildConn('r1', 'http://r1.local'));
      await controller.upsert(buildConn('r2', 'http://r2.local'));
      expect(container.read(connectionsProvider), hasLength(2));

      final builtin = ServerConnection(
        id: ServerConnection.builtinId,
        name: 'Builtin Sidecar',
        baseUrl: 'http://127.0.0.1:8787',
        createdAt: DateTime.utc(2026, 9, 4),
        kind: ConnectionKind.builtin,
      );
      await controller.upsertBuiltin(builtin);

      var list = container.read(connectionsProvider);
      expect(list, hasLength(3));
      expect(list.first.id, ServerConnection.builtinId);
      expect(list.first.kind, ConnectionKind.builtin);

      // 再次 upsertBuiltin（更新属性），依然位于首位且不重复
      final updated = builtin.copyWith(baseUrl: 'http://127.0.0.1:9000');
      await controller.upsertBuiltin(updated);

      list = container.read(connectionsProvider);
      expect(list, hasLength(3));
      expect(list.first.id, ServerConnection.builtinId);
      expect(list.first.baseUrl, 'http://127.0.0.1:9000');
    });

    test('delete(builtin) 与 remove(builtin) 抛错防护', () async {
      final container = buildContainer();
      final controller = container.read(connectionsProvider.notifier);

      final builtin = ServerConnection(
        id: ServerConnection.builtinId,
        name: 'Builtin Sidecar',
        baseUrl: 'http://127.0.0.1:8787',
        createdAt: DateTime.utc(2026, 9, 4),
        kind: ConnectionKind.builtin,
      );
      await controller.upsertBuiltin(builtin);

      await expectLater(
        () => controller.remove(ServerConnection.builtinId),
        throwsStateError,
      );
      await expectLater(
        () => controller.delete(ServerConnection.builtinId),
        throwsStateError,
      );
      expect(container.read(connectionsProvider), hasLength(1));
    });

    test('setBuiltinEnabled 切换状态，停用 active builtin → clearActive', () async {
      final container = buildContainer();
      final controller = container.read(connectionsProvider.notifier);
      final activeController = container.read(activeConnectionProvider.notifier);

      final builtin = ServerConnection(
        id: ServerConnection.builtinId,
        name: 'Builtin Sidecar',
        baseUrl: 'http://127.0.0.1:8787',
        createdAt: DateTime.utc(2026, 9, 4),
        kind: ConnectionKind.builtin,
        enabled: true,
      );
      await controller.upsertBuiltin(builtin);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await activeController.setActive(ServerConnection.builtinId);
      expect(container.read(activeConnectionProvider)?.id, ServerConnection.builtinId);

      // 停用 active builtin → 触发 clearActive，active 变为 null
      await controller.setBuiltinEnabled(false);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(container.read(connectionsProvider).first.enabled, isFalse);
      expect(container.read(activeConnectionProvider), isNull);

      // 等待事件循环，确认不会被 watch 重建逻辑复活
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(container.read(activeConnectionProvider), isNull);

      // 重新启用，active 仍为 null（不自动激活）
      await controller.setBuiltinEnabled(true);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(container.read(connectionsProvider).first.enabled, isTrue);
      expect(container.read(activeConnectionProvider), isNull);
    });

    test('switchableConnectionsProvider 排除已停用的 builtin', () async {
      final container = buildContainer();
      final controller = container.read(connectionsProvider.notifier);

      await controller.upsert(buildConn('r1', 'http://r1.local'));
      final builtin = ServerConnection(
        id: ServerConnection.builtinId,
        name: 'Builtin',
        baseUrl: 'http://127.0.0.1:8787',
        createdAt: DateTime.utc(2026, 9, 4),
        kind: ConnectionKind.builtin,
        enabled: true,
      );
      await controller.upsertBuiltin(builtin);

      // enabled 时包含在 switchable 列表
      expect(container.read(switchableConnectionsProvider), hasLength(2));

      // 停用后不出现在可切换集合
      await controller.setBuiltinEnabled(false);
      final switchable = container.read(switchableConnectionsProvider);
      expect(switchable, hasLength(1));
      expect(switchable.single.id, 'r1');
    });
  });

  group('activeConnectionProvider', () {
    test('从持久化加载激活连接', () async {
      // 先经 store 预置连接 + active，模拟重启场景
      final storage = InMemorySecureStorage();
      final store = ConnectionStore(storage: storage);
      await store.save(buildConn('c1', 'http://c1.local'));
      await store.setActive('c1');

      final container = ProviderContainer(
        overrides: [
          connectionStoreProvider.overrideWithValue(store),
        ],
      );
      addTearDown(container.dispose);
      container.listen(activeConnectionProvider, (_, _) {});

      // build 触发异步 _load；给足事件循环轮次等待加载完成
      container.read(activeConnectionProvider);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(container.read(activeConnectionProvider)?.id, 'c1');
    });

    test('setActive 切换后 apiClientProvider 重建（新 baseUrl/头）', () async {
      final container = buildContainer();

      final connA = buildConn('a', 'http://a.local');
      final connB = ServerConnection(
        id: 'b',
        name: 'B',
        baseUrl: 'http://b.local',
        customHeaders: const {'Authorization': 'Bearer tok'},
        createdAt: DateTime.utc(2026, 1, 1),
      );
      await container.read(connectionsProvider.notifier).upsert(connA);
      await container.read(connectionsProvider.notifier).upsert(connB);

      await container.read(activeConnectionProvider.notifier).setActive('a');
      final clientA = container.read(apiClientProvider);
      expect(clientA.baseUrl, 'http://a.local');

      await container.read(activeConnectionProvider.notifier).setActive('b');
      final clientB = container.read(apiClientProvider);
      expect(clientB.baseUrl, 'http://b.local');
      expect(identical(clientA, clientB), isFalse, reason: '切换连接必须重建 ApiClient');
      expect(clientB.headerStore.snapshot().single.name, 'Authorization');
      expect(
        clientB.headerStore.snapshot().single.value,
        'Bearer tok',
      );
    });

    test('apiClientProvider 无激活连接 → StateError', () {
      final container = buildContainer();
      expect(
        () => container.read(apiClientProvider),
        throwsStateError,
      );
    });

    test('apiClientProvider.autoReauth 用保存密码重登', () async {
      final loginApi = _FakeOnboardingApi();
      final storage = InMemorySecureStorage();
      final store = ConnectionStore(storage: storage);
      await store.save(ServerConnection(
        id: 'c1',
        name: 'C1',
        baseUrl: 'http://c1.local',
        password: 'secret-pw',
        createdAt: DateTime.utc(2026, 1, 1),
      ));
      await store.setActive('c1');

      final container = ProviderContainer(
        overrides: [
          connectionStoreProvider.overrideWithValue(store),
          onboardingApiFactoryProvider.overrideWithValue(
            (baseUrl, headers) => loginApi,
          ),
        ],
      );
      addTearDown(container.dispose);
      container.listen(activeConnectionProvider, (_, _) {});
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final client = container.read(apiClientProvider);
      expect(client.autoReauthEnabled, isTrue);
      final reauth = client.autoReauth;
      expect(reauth, isNotNull);
      final ok = await reauth!();
      expect(ok, isTrue);
      expect(loginApi.loginCalls, 1);
      expect(loginApi.lastPassword, 'secret-pw');
    });

    test('apiClientProvider.autoReauth 无保存密码 → 返回 false（不重登）', () async {
      final loginApi = _FakeOnboardingApi();
      final storage = InMemorySecureStorage();
      final store = ConnectionStore(storage: storage);
      await store.save(ServerConnection(
        id: 'c2',
        name: 'C2',
        baseUrl: 'http://c2.local',
        // 无 password
        createdAt: DateTime.utc(2026, 1, 1),
      ));
      await store.setActive('c2');

      final container = ProviderContainer(
        overrides: [
          connectionStoreProvider.overrideWithValue(store),
          onboardingApiFactoryProvider.overrideWithValue(
            (baseUrl, headers) => loginApi,
          ),
        ],
      );
      addTearDown(container.dispose);
      container.listen(activeConnectionProvider, (_, _) {});
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final client = container.read(apiClientProvider);
      final ok = await client.autoReauth!();
      expect(ok, isFalse);
      expect(loginApi.loginCalls, 0);
    });

    test('setActive 拒绝已停用的 builtin 连接', () async {
      final container = buildContainer();
      final controller = container.read(connectionsProvider.notifier);
      final activeController = container.read(activeConnectionProvider.notifier);

      final builtin = ServerConnection(
        id: ServerConnection.builtinId,
        name: 'Builtin Sidecar',
        baseUrl: 'http://127.0.0.1:8787',
        createdAt: DateTime.utc(2026, 9, 4),
        kind: ConnectionKind.builtin,
        enabled: false,
      );
      await controller.upsertBuiltin(builtin);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      await expectLater(
        () => activeController.setActive(ServerConnection.builtinId),
        throwsStateError,
      );
      expect(container.read(activeConnectionProvider), isNull);
    });
  });

  group('themeModeProvider', () {
    test('三态切换 + shared_preferences 持久化', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(themeModeProvider), AppThemeMode.system);

      await container.read(themeModeProvider.notifier).setMode(AppThemeMode.dark);
      expect(container.read(themeModeProvider), AppThemeMode.dark);
      expect(AppThemeMode.dark.flutterThemeMode, ThemeMode.dark);

      // 新容器（模拟重启）应读到持久化值
      final container2 = ProviderContainer();
      addTearDown(container2.dispose);
      container2.read(themeModeProvider);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(container2.read(themeModeProvider), AppThemeMode.dark);
    });
  });
}
