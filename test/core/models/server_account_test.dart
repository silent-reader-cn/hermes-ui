import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/models/server_account.dart';

class _InMemoryServerRegistryStorage implements ServerRegistryStorage {
  _InMemoryServerRegistryStorage({this.value});

  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String value) async {
    this.value = value;
  }
}

void main() {
  group('ServerAccount.fromJson', () {
    test('规格示例正常解析', () {
      final account = ServerAccount.fromJson({
        'id': 'http://192.168.1.5:30002',
        'url_string': 'http://192.168.1.5:30002',
        'display_name': 'Home',
        'initials': 'H',
        'header_logo_color_hex': '#4f46e5',
        'custom_headers_ref': 'http://192.168.1.5:30002',
        'created_at': '2026-08-01T08:00:00Z',
        'updated_at': '2026-08-15T12:00:00Z',
      });
      expect(account.id, 'http://192.168.1.5:30002');
      expect(account.urlString, 'http://192.168.1.5:30002');
      expect(account.displayName, 'Home');
      expect(account.initials, 'H');
      expect(account.headerLogoColorHex, '#4f46e5');
      expect(account.customHeadersRef, 'http://192.168.1.5:30002');
      expect(account.createdAt, DateTime.utc(2026, 8, 1, 8));
      expect(account.updatedAt, DateTime.utc(2026, 8, 15, 12));
    });

    test('id 缺失时用 url_string', () {
      final account = ServerAccount.fromJson({'url_string': 'http://x:1'});
      expect(account.id, 'http://x:1');
      expect(account.urlString, 'http://x:1');
    });

    test('字段缺失 → 安全默认值', () {
      final account = ServerAccount.fromJson({'id': 'http://x:1'});
      expect(account.displayName, '');
      expect(account.initials, '');
      expect(account.headerLogoColorHex, ServerAccount.defaultHeaderLogoColorHex);
      expect(account.customHeadersRef, isNull);
      expect(account.createdAt.millisecondsSinceEpoch, 0);
      expect(account.updatedAt, account.createdAt);
    });

    test('坏时间戳 → 回退 epoch 0', () {
      final account = ServerAccount.fromJson({
        'id': 'x',
        'created_at': 'not-a-date',
      });
      expect(account.createdAt.millisecondsSinceEpoch, 0);
    });

    test('唯一允许解码失败：id 与 url_string 都缺 → 抛 FormatException', () {
      expect(
        () => ServerAccount.fromJson(const {}),
        throwsFormatException,
      );
    });

    test('toJson 往返', () {
      final account = ServerAccount.fromJson({
        'id': 'http://x:1',
        'url_string': 'http://x:1',
        'display_name': 'H',
      });
      final decoded = ServerAccount.fromJson(account.toJson());
      expect(decoded, account);
    });
  });

  group('ServerRegistrySnapshot', () {
    test('fromJson / toJson / activeServer', () {
      final snapshot = ServerRegistrySnapshot.fromJson({
        'servers': [
          {'id': 'a', 'url_string': 'a'},
          {'id': 'b', 'url_string': 'b'},
          'bad-element',
        ],
        'active_server_id': 'a',
      });
      expect(snapshot.servers, hasLength(2));
      expect(snapshot.activeServerID, 'a');
      expect(snapshot.activeServer!.id, 'a');

      final roundTrip = ServerRegistrySnapshot.fromJson(snapshot.toJson());
      expect(roundTrip, snapshot);
      expect(const ServerRegistrySnapshot().activeServer, isNull);
    });
  });

  group('ServerRegistry', () {
    test('load 空存储 → 空快照', () async {
      final registry = ServerRegistry(storage: _InMemoryServerRegistryStorage());
      await registry.load();
      expect(registry.servers, isEmpty);
      expect(registry.activeServerID, isNull);
    });

    test('activate：新 URL 注册并激活 / 已注册只重新激活不重复', () async {
      final storage = _InMemoryServerRegistryStorage();
      final registry = ServerRegistry(storage: storage);
      await registry.load();

      final account = await registry.activate('http://srv:30002');
      expect(account.id, 'http://srv:30002');
      expect(registry.activeServerID, 'http://srv:30002');
      expect(registry.servers, hasLength(1));

      // 重复 activate：不重复插入
      await registry.activate('http://srv:30002');
      expect(registry.servers, hasLength(1));

      // 持久化后可恢复
      final reloaded = ServerRegistry(storage: storage);
      await reloaded.load();
      expect(reloaded.servers, hasLength(1));
      expect(reloaded.activeServerID, 'http://srv:30002');
    });

    test('setActive / remove（active 移除后自动选中下一个）', () async {
      final registry = ServerRegistry(storage: _InMemoryServerRegistryStorage());
      await registry.load();
      await registry.activate('a');
      await registry.activate('b'); // active = b

      final activated = await registry.setActive('a');
      expect(activated!.id, 'a');
      expect(registry.activeServerID, 'a');
      // 已是 active → null
      expect(await registry.setActive('a'), isNull);
      // 未注册 → null
      expect(await registry.setActive('zz'), isNull);

      // 移除 active → 自动选中下一个
      final after = await registry.remove('a');
      expect(after!.id, 'b');
      expect(registry.activeServerID, 'b');

      final last = await registry.remove('b');
      expect(last, isNull);
      expect(registry.servers, isEmpty);
    });

    test('update：替换身份并 bump updatedAt', () async {
      final registry = ServerRegistry(
        storage: _InMemoryServerRegistryStorage(),
        now: () => DateTime.utc(2026, 8, 16),
      );
      await registry.load();
      final original = await registry.activate('http://srv:1');
      await registry.update(ServerAccount(
        id: original.id,
        urlString: original.urlString,
        displayName: '改名',
      ));
      expect(registry.servers.single.displayName, '改名');
      expect(registry.servers.single.updatedAt, DateTime.utc(2026, 8, 16));
      // 未注册 id → no-op
      await registry.update(ServerAccount(id: 'nope', urlString: 'nope'));
      expect(registry.servers, hasLength(1));
    });

    test('forgetActiveServer：登出移除 active', () async {
      final registry = ServerRegistry(storage: _InMemoryServerRegistryStorage());
      await registry.load();
      await registry.activate('a');
      await registry.forgetActiveServer();
      expect(registry.servers, isEmpty);
      expect(registry.activeServerID, isNull);
    });

    test('坏 blob → 空快照不 crash', () async {
      final registry = ServerRegistry(
        storage: _InMemoryServerRegistryStorage(value: 'not-json{{'),
      );
      await registry.load();
      expect(registry.servers, isEmpty);
    });
  });

  test('== / hashCode / toString', () {
    final a = ServerAccount.fromJson({'id': 'x'});
    final b = ServerAccount.fromJson({'id': 'x'});
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a.toString(), contains('ServerAccount'));
  });
}
