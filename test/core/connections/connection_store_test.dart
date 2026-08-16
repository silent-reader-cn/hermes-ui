import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermex_flutter/core/connections/connection_store.dart';
import 'package:hermex_flutter/core/connections/server_connection.dart';

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
  });
}
