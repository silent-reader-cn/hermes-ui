import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/connections/connection_store.dart';
import 'package:hermes_ui/core/connections/server_connection.dart';

import '../../helpers/in_memory_secure_storage.dart';

void main() {
  ServerConnection buildConn(
    String id, {
    String? password,
    Map<String, String> headers = const {},
    String baseUrl = 'http://hermes.local:30002',
  }) {
    return ServerConnection(
      id: id,
      name: 'Home',
      baseUrl: baseUrl,
      password: password,
      customHeaders: headers,
      createdAt: DateTime.utc(2026, 1, 1),
    );
  }

  group('ConnectionStore 增删改查', () {
    test('save → loadAll 往返：密码单独 key，不进 connections blob', () async {
      final storage = InMemorySecureStorage();
      final store = ConnectionStore(storage: storage);
      await store.save(
        buildConn('c1', password: 'secret', headers: {
          'Authorization': 'Bearer xyz',
        }),
      );

      final all = await store.loadAll();
      expect(all, hasLength(1));
      final conn = all.single;
      expect(conn.id, 'c1');
      expect(conn.name, 'Home');
      expect(conn.baseUrl, 'http://hermes.local:30002');
      expect(conn.password, 'secret');
      expect(conn.customHeaders['Authorization'], 'Bearer xyz');

      // 安全：密码不进 connections blob（blob 整体在 secure storage 加密区，
      // 自定义头随 blob 存储合规）；密码在单独 key
      final raw = storage.data[ConnectionStore.connectionsKey];
      expect(raw, isNotNull);
      expect(raw, isNot(contains('secret')));
      expect(storage.data[ConnectionStore.passwordKey('c1')], 'secret');
    });

    test('save upsert：同 id 覆盖，未传新密码时保留原密码', () async {
      final store = ConnectionStore(storage: InMemorySecureStorage());
      await store.save(buildConn('c1', password: 'old'));
      await store.save(
        ServerConnection(
          id: 'c1',
          name: 'Renamed',
          baseUrl: 'http://other.local:8787',
          createdAt: DateTime.utc(2026, 2, 2),
        ),
      );

      final all = await store.loadAll();
      expect(all, hasLength(1));
      expect(all.single.name, 'Renamed');
      expect(all.single.baseUrl, 'http://other.local:8787');
      expect(all.single.password, 'old'); // 保留原密码
    });

    test('save 新密码覆盖旧密码', () async {
      final store = ConnectionStore(storage: InMemorySecureStorage());
      await store.save(buildConn('c1', password: 'old'));
      await store.save(
        buildConn('c1', password: 'new', baseUrl: 'http://x.local'),
      );
      expect((await store.loadAll()).single.password, 'new');
    });

    test('delete：移除连接 + 密码 + 清理 active 指向', () async {
      final storage = InMemorySecureStorage();
      final store = ConnectionStore(storage: storage);
      await store.save(buildConn('c1', password: 's'));
      await store.setActive('c1');
      await store.delete('c1');

      expect(await store.loadAll(), isEmpty);
      expect(await store.getActive(), isNull);
      expect(storage.data.containsKey(ConnectionStore.passwordKey('c1')), isFalse);
      expect(
        storage.data.containsKey(ConnectionStore.activeConnectionKey),
        isFalse,
      );
    });

    test('setActive / getActive：多服务器切换', () async {
      final store = ConnectionStore(storage: InMemorySecureStorage());
      await store.save(buildConn('a'));
      await store.save(buildConn('b'));

      expect(await store.getActive(), isNull);
      await store.setActive('b');
      expect((await store.getActive())?.id, 'b');
      await store.setActive('a');
      expect((await store.getActive())?.id, 'a');
    });

    test('setActive 未知 id → StateError', () async {
      final store = ConnectionStore(storage: InMemorySecureStorage());
      await expectLater(store.setActive('nope'), throwsStateError);
    });

    test('clearActive：清除标记但保留连接', () async {
      final store = ConnectionStore(storage: InMemorySecureStorage());
      await store.save(buildConn('a'));
      await store.setActive('a');
      await store.clearActive();
      expect(await store.getActive(), isNull);
      expect(await store.loadAll(), hasLength(1));
    });

    test('delete builtinId 或 kind==builtin → 抛出 StateError 防护', () async {
      final store = ConnectionStore(storage: InMemorySecureStorage());
      final builtin = ServerConnection(
        id: ServerConnection.builtinId,
        name: 'Builtin',
        baseUrl: 'http://127.0.0.1:8787',
        createdAt: DateTime.utc(2026, 1, 1),
        kind: ConnectionKind.builtin,
      );
      await store.save(builtin);

      await expectLater(
        () => store.delete(ServerConnection.builtinId),
        throwsStateError,
      );
      // 确认连接未被删除
      expect(await store.loadAll(), hasLength(1));
    });

    test('setActive 拒绝已停用的 builtin 连接', () async {
      final store = ConnectionStore(storage: InMemorySecureStorage());
      final disabledBuiltin = ServerConnection(
        id: ServerConnection.builtinId,
        name: 'Builtin',
        baseUrl: 'http://127.0.0.1:8787',
        createdAt: DateTime.utc(2026, 1, 1),
        kind: ConnectionKind.builtin,
        enabled: false,
      );
      await store.save(disabledBuiltin);

      await expectLater(
        () => store.setActive(ServerConnection.builtinId),
        throwsStateError,
      );
    });

    test('getActive 对已停用的 builtin 连接返回 null', () async {
      final storage = InMemorySecureStorage();
      final store = ConnectionStore(storage: storage);
      final disabledBuiltin = ServerConnection(
        id: ServerConnection.builtinId,
        name: 'Builtin',
        baseUrl: 'http://127.0.0.1:8787',
        createdAt: DateTime.utc(2026, 1, 1),
        kind: ConnectionKind.builtin,
        enabled: false,
      );
      await store.save(disabledBuiltin);
      // 直接写入 active 键模拟旧指向
      storage.data[ConnectionStore.activeConnectionKey] =
          ServerConnection.builtinId;

      expect(await store.getActive(), isNull);
    });

    test('save builtin 总是置首且幂等', () async {
      final store = ConnectionStore(storage: InMemorySecureStorage());
      await store.save(buildConn('r1', baseUrl: 'http://r1.local'));
      await store.save(buildConn('r2', baseUrl: 'http://r2.local'));

      final builtin = ServerConnection(
        id: ServerConnection.builtinId,
        name: 'Builtin',
        baseUrl: 'http://127.0.0.1:8787',
        createdAt: DateTime.utc(2026, 1, 1),
        kind: ConnectionKind.builtin,
      );
      await store.save(builtin);

      var all = await store.loadAll();
      expect(all.first.id, ServerConnection.builtinId);
      expect(all, hasLength(3));

      // 再次保存更新 builtin，依然在首位
      final updatedBuiltin = builtin.copyWith(name: 'Updated Builtin');
      await store.save(updatedBuiltin);

      all = await store.loadAll();
      expect(all.first.id, ServerConnection.builtinId);
      expect(all.first.name, 'Updated Builtin');
      expect(all, hasLength(3));
    });

    test('active 指向已删除连接 → getActive 返回 null', () async {
      final store = ConnectionStore(storage: InMemorySecureStorage());
      await store.save(buildConn('a'));
      await store.setActive('a');
      await store.delete('a');
      expect(await store.getActive(), isNull);
    });
  });

  group('ConnectionStore 容错持久化', () {
    test('connections 数据缺失 → 空表', () async {
      expect(
        await ConnectionStore(storage: InMemorySecureStorage()).loadAll(),
        isEmpty,
      );
    });

    test('connections 损坏 JSON → 空表不 crash', () async {
      final storage = InMemorySecureStorage();
      storage.data[ConnectionStore.connectionsKey] = 'not-json{{{';
      expect(await ConnectionStore(storage: storage).loadAll(), isEmpty);
    });

    test('畸形条目跳过，合法条目保留', () async {
      final storage = InMemorySecureStorage();
      storage.data[ConnectionStore.connectionsKey] = jsonEncode([
        42,
        'x',
        null,
        {'id': 'ok', 'name': 'N', 'base_url': 'http://x.local'},
      ]);
      final all = await ConnectionStore(storage: storage).loadAll();
      expect(all, hasLength(1));
      expect(all.single.id, 'ok');
    });
  });

  group('ServerConnection 模型', () {
    test('toJson 不含密码（安全）', () {
      final conn = buildConn('c1', password: 'secret');
      final json = conn.toJson();
      expect(json.containsKey('password'), isFalse);
      expect(json['id'], 'c1');
      expect(json['base_url'], 'http://hermes.local:30002');
      expect(json['created_at'], '2026-01-01T00:00:00.000Z');
    });

    test('fromJson 缺字段 → 安全默认值', () {
      final conn = ServerConnection.fromJson(const {});
      expect(conn.id, isNotEmpty);
      expect(conn.name, '');
      expect(conn.baseUrl, '');
      expect(conn.username, isNull);
      expect(conn.password, isNull);
      expect(conn.customHeaders, isEmpty);
      expect(
        conn.createdAt,
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );
    });

    test('fromJson 类型不符 → 容错默认值，绝不 crash', () {
      final conn = ServerConnection.fromJson({
        'id': 123, // 非 String → 走 uuid 兜底
        'name': null,
        'base_url': 42,
        'username': true,
        'custom_headers': 'not-a-map',
        'created_at': 'not-a-date',
      });
      expect(conn.id, isNotEmpty);
      expect(conn.name, '');
      expect(conn.baseUrl, '');
      expect(conn.username, isNull);
      expect(conn.customHeaders, isEmpty);
    });

    test('fromJson 完整字段 + 注入密码', () {
      final conn = ServerConnection.fromJson(
        {
          'id': 'c1',
          'name': 'Home',
          'base_url': 'http://hermes.local:30002',
          'username': 'admin',
          'custom_headers': {'Authorization': 'Bearer x'},
          'created_at': '2026-01-01T00:00:00Z',
        },
        password: 'secret',
      );
      expect(conn.id, 'c1');
      expect(conn.username, 'admin');
      expect(conn.password, 'secret');
      expect(conn.customHeaders['Authorization'], 'Bearer x');
      expect(conn.createdAt, DateTime.utc(2026, 1, 1));
    });

    test('fromJson 自定义头仅保留字符串键值对', () {
      final conn = ServerConnection.fromJson({
        'id': 'c1',
        'name': 'N',
        'base_url': 'http://x',
        'custom_headers': {
          'A': '1',
          42: 'bad-key',
          'B': 2, // 非 String 值跳过
        },
      });
      expect(conn.customHeaders, {'A': '1'});
    });

    test('builtinId 常量固定为 builtin-sidecar', () {
      expect(ServerConnection.builtinId, 'builtin-sidecar');
    });

    test('默认 kind 为 remote 且 enabled 为 true', () {
      final conn = ServerConnection(
        id: 'r1',
        name: 'Remote',
        baseUrl: 'http://remote.local:30002',
        createdAt: DateTime.utc(2026, 1, 1),
      );
      expect(conn.kind, ConnectionKind.remote);
      expect(conn.enabled, isTrue);
    });

    test('remote 类型恒为 enabled=true（即使传 enabled=false 也会被约束为 true）', () {
      final conn = ServerConnection(
        id: 'r2',
        name: 'Remote2',
        baseUrl: 'http://remote2.local:30002',
        createdAt: DateTime.utc(2026, 1, 1),
        kind: ConnectionKind.remote,
        enabled: false,
      );
      expect(conn.kind, ConnectionKind.remote);
      expect(conn.enabled, isTrue);
    });

    test('builtin 类型可指定 enabled 为 true 或 false', () {
      final connEnabled = ServerConnection(
        id: ServerConnection.builtinId,
        name: 'Builtin',
        baseUrl: 'http://127.0.0.1:8787',
        createdAt: DateTime.utc(2026, 1, 1),
        kind: ConnectionKind.builtin,
        enabled: true,
      );
      expect(connEnabled.kind, ConnectionKind.builtin);
      expect(connEnabled.enabled, isTrue);

      final connDisabled = ServerConnection(
        id: ServerConnection.builtinId,
        name: 'Builtin',
        baseUrl: 'http://127.0.0.1:8787',
        createdAt: DateTime.utc(2026, 1, 1),
        kind: ConnectionKind.builtin,
        enabled: false,
      );
      expect(connDisabled.kind, ConnectionKind.builtin);
      expect(connDisabled.enabled, isFalse);
    });

    test('kind 序列化 round-trip：builtin (enabled=true 与 enabled=false)', () {
      final builtinActive = ServerConnection(
        id: ServerConnection.builtinId,
        name: 'Builtin Active',
        baseUrl: 'http://127.0.0.1:8787',
        createdAt: DateTime.utc(2026, 9, 4),
        kind: ConnectionKind.builtin,
        enabled: true,
      );
      final jsonActive = builtinActive.toJson();
      expect(jsonActive['kind'], 'builtin');
      expect(jsonActive['enabled'], isTrue);

      final restoredActive = ServerConnection.fromJson(jsonActive);
      expect(restoredActive.kind, ConnectionKind.builtin);
      expect(restoredActive.enabled, isTrue);
      expect(restoredActive, builtinActive);

      final builtinDisabled = ServerConnection(
        id: ServerConnection.builtinId,
        name: 'Builtin Disabled',
        baseUrl: 'http://127.0.0.1:8787',
        createdAt: DateTime.utc(2026, 9, 4),
        kind: ConnectionKind.builtin,
        enabled: false,
      );
      final jsonDisabled = builtinDisabled.toJson();
      expect(jsonDisabled['kind'], 'builtin');
      expect(jsonDisabled['enabled'], isFalse);

      final restoredDisabled = ServerConnection.fromJson(jsonDisabled);
      expect(restoredDisabled.kind, ConnectionKind.builtin);
      expect(restoredDisabled.enabled, isFalse);
      expect(restoredDisabled, builtinDisabled);
    });

    test('kind 序列化 round-trip：remote', () {
      final remoteConn = ServerConnection(
        id: 'rem-1',
        name: 'My Remote Server',
        baseUrl: 'https://hermes.remote.example:30002',
        username: 'user1',
        customHeaders: const {'X-Header': 'val'},
        createdAt: DateTime.utc(2026, 9, 4),
        kind: ConnectionKind.remote,
      );
      final json = remoteConn.toJson();
      expect(json['kind'], 'remote');
      expect(json['enabled'], isTrue);
      expect(json.containsKey('password'), isFalse);

      final restored = ServerConnection.fromJson(json);
      expect(restored.kind, ConnectionKind.remote);
      expect(restored.enabled, isTrue);
      expect(restored, remoteConn);
    });

    test('无 kind 存量兼容：旧 JSON（无 kind 字段）反序列化为 remote 且 enabled=true', () {
      final legacyJson = <String, Object?>{
        'id': 'legacy-conn',
        'name': 'Legacy Server',
        'base_url': 'http://old.example.com:30002',
        'username': 'legacy_user',
        'custom_headers': {'Authorization': 'Bearer old-token'},
        'created_at': '2026-01-01T00:00:00.000Z',
      };

      final conn = ServerConnection.fromJson(legacyJson);
      expect(conn.id, 'legacy-conn');
      expect(conn.name, 'Legacy Server');
      expect(conn.baseUrl, 'http://old.example.com:30002');
      expect(conn.username, 'legacy_user');
      expect(conn.kind, ConnectionKind.remote);
      expect(conn.enabled, isTrue);
    });

    test('非法/未知 kind 字符串安全回退为 remote 且 enabled=true', () {
      final malformedJson = <String, Object?>{
        'id': 'unknown-kind-conn',
        'name': 'Unknown Kind Server',
        'base_url': 'http://unknown.example.com',
        'kind': 'future_or_invalid_kind',
        'enabled': false,
        'created_at': '2026-01-01T00:00:00.000Z',
      };

      final conn = ServerConnection.fromJson(malformedJson);
      expect(conn.kind, ConnectionKind.remote);
      expect(conn.enabled, isTrue);
    });

    test('copyWith 保留并可更新 kind 与 enabled', () {
      final original = ServerConnection(
        id: 'orig',
        name: 'Orig',
        baseUrl: 'http://orig.local',
        createdAt: DateTime.utc(2026, 1, 1),
        kind: ConnectionKind.remote,
      );

      final copiedNoChange = original.copyWith(name: 'New Name');
      expect(copiedNoChange.kind, ConnectionKind.remote);
      expect(copiedNoChange.enabled, isTrue);

      final switchedToBuiltin = original.copyWith(
        kind: ConnectionKind.builtin,
        enabled: false,
      );
      expect(switchedToBuiltin.kind, ConnectionKind.builtin);
      expect(switchedToBuiltin.enabled, isFalse);

      final switchedBackToRemote = switchedToBuiltin.copyWith(
        kind: ConnectionKind.remote,
      );
      expect(switchedBackToRemote.kind, ConnectionKind.remote);
      expect(switchedBackToRemote.enabled, isTrue);
    });

    test('存量升级端到端：旧 JSON 经 ConnectionStore.loadAll 后全部 remote、active 不变', () async {
      final storage = InMemorySecureStorage();
      storage.data[ConnectionStore.connectionsKey] = '''[
        {
          "id": "old-1",
          "name": "Server 1",
          "base_url": "http://srv1.local:30002",
          "created_at": "2026-01-01T00:00:00.000Z"
        },
        {
          "id": "old-2",
          "name": "Server 2",
          "base_url": "http://srv2.local:30002",
          "created_at": "2026-02-01T00:00:00.000Z"
        }
      ]''';
      storage.data[ConnectionStore.activeConnectionKey] = 'old-1';

      final store = ConnectionStore(storage: storage);
      final all = await store.loadAll();

      expect(all, hasLength(2));
      for (final conn in all) {
        expect(conn.kind, ConnectionKind.remote);
        expect(conn.enabled, isTrue);
      }

      final active = await store.getActive();
      expect(active, isNotNull);
      expect(active!.id, 'old-1');
      expect(active.kind, ConnectionKind.remote);
      expect(active.enabled, isTrue);
    });
  });
}
