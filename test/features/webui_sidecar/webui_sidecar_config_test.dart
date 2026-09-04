import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/features/webui_sidecar/webui_sidecar_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeSecureStorage implements SidecarSecureStorage {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

void main() {
  group('SidecarConfig Model', () {
    test('默认值符合设计契约', () {
      const config = SidecarConfig();
      expect(config.enabled, isFalse);
      expect(config.host, '127.0.0.1');
      expect(config.port, 8787);
      expect(config.password, isEmpty);
    });

    test('copyWith 正确复制与覆盖指定字段', () {
      const initial = SidecarConfig();
      final updated = initial.copyWith(
        enabled: true,
        host: '0.0.0.0',
        port: 9000,
        password: 'secret_password',
      );

      expect(updated.enabled, isTrue);
      expect(updated.host, '0.0.0.0');
      expect(updated.port, 9000);
      expect(updated.password, 'secret_password');
    });

    test('相等性与 hashCode 正确', () {
      const a = SidecarConfig(
        enabled: true,
        host: '127.0.0.1',
        port: 8787,
        password: 'pass',
      );
      const b = SidecarConfig(
        enabled: true,
        host: '127.0.0.1',
        port: 8787,
        password: 'pass',
      );
      const c = SidecarConfig(
        enabled: false,
        host: '127.0.0.1',
        port: 8787,
        password: 'pass',
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });

    test('toString 必须打码密码，绝不泄漏明文', () {
      const config = SidecarConfig(password: 'super_secret_token_123');
      final stringRepresentation = config.toString();

      expect(stringRepresentation, isNot(contains('super_secret_token_123')));
      expect(stringRepresentation, contains('password: ***'));
    });

    test('toJson 绝不包含 password 字段', () {
      const config = SidecarConfig(
        enabled: true,
        host: '127.0.0.1',
        port: 8787,
        password: 'secret_value',
      );
      final json = config.toJson();

      expect(json.containsKey('password'), isFalse);
      expect(json['enabled'], isTrue);
      expect(json['host'], '127.0.0.1');
      expect(json['port'], 8787);
    });

    test('generateRandomPassword 生成 24 位高强度字母与数字随机密码', () {
      final pwd1 = SidecarConfig.generateRandomPassword();
      final pwd2 = SidecarConfig.generateRandomPassword();

      expect(pwd1.length, 24);
      expect(pwd2.length, 24);
      expect(pwd1, isNot(equals(pwd2)));
      expect(RegExp(r'^[a-zA-Z0-9]{24}$').hasMatch(pwd1), isTrue);
    });
  });

  group('WebuiSidecarConfigStorage 持久化', () {
    late _FakeSecureStorage fakeSecureStorage;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      fakeSecureStorage = _FakeSecureStorage();
    });

    test('首次 load 无值时自动生成 24 位随机密码并即刻落盘安全存储', () async {
      final storage = WebuiSidecarConfigStorage(
        prefs: SharedPreferences.getInstance(),
        secureStorage: fakeSecureStorage,
      );

      final config = await storage.load();

      expect(config.enabled, isFalse);
      expect(config.host, '127.0.0.1');
      expect(config.port, 8787);
      expect(config.password.length, 24);

      final storedPassword =
          await fakeSecureStorage.read(WebuiSidecarConfigStorage.keyPassword);
      expect(storedPassword, equals(config.password));
    });

    test('已有值时 load 正确读出各字段且不覆盖已有密码', () async {
      SharedPreferences.setMockInitialValues({
        WebuiSidecarConfigStorage.keyEnabled: true,
        WebuiSidecarConfigStorage.keyHost: '0.0.0.0',
        WebuiSidecarConfigStorage.keyPort: 9999,
      });
      await fakeSecureStorage.write(
        WebuiSidecarConfigStorage.keyPassword,
        'my_custom_secret',
      );

      final storage = WebuiSidecarConfigStorage(
        prefs: SharedPreferences.getInstance(),
        secureStorage: fakeSecureStorage,
      );

      final config = await storage.load();

      expect(config.enabled, isTrue);
      expect(config.host, '0.0.0.0');
      expect(config.port, 9999);
      expect(config.password, 'my_custom_secret');
    });

    test('save 完整 round-trip 验证且密码不进 shared_preferences', () async {
      final storage = WebuiSidecarConfigStorage(
        prefs: SharedPreferences.getInstance(),
        secureStorage: fakeSecureStorage,
      );

      const toSave = SidecarConfig(
        enabled: true,
        host: '192.168.1.5',
        port: 8080,
        password: 'secure_password_abc',
      );

      await storage.save(toSave);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(WebuiSidecarConfigStorage.keyEnabled), isTrue);
      expect(prefs.getString(WebuiSidecarConfigStorage.keyHost), '192.168.1.5');
      expect(prefs.getInt(WebuiSidecarConfigStorage.keyPort), 8080);
      expect(prefs.containsKey(WebuiSidecarConfigStorage.keyPassword), isFalse);

      final secureVal =
          await fakeSecureStorage.read(WebuiSidecarConfigStorage.keyPassword);
      expect(secureVal, 'secure_password_abc');

      final loaded = await storage.load();
      expect(loaded, equals(toSave));
    });

    test('单独 setEnabled / setHost / setPort / setPassword 正确落盘', () async {
      final storage = WebuiSidecarConfigStorage(
        prefs: SharedPreferences.getInstance(),
        secureStorage: fakeSecureStorage,
      );

      await storage.setEnabled(true);
      await storage.setHost('10.0.0.1');
      await storage.setPort(7777);
      await storage.setPassword('standalone_pwd');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(WebuiSidecarConfigStorage.keyEnabled), isTrue);
      expect(prefs.getString(WebuiSidecarConfigStorage.keyHost), '10.0.0.1');
      expect(prefs.getInt(WebuiSidecarConfigStorage.keyPort), 7777);
      expect(
        await fakeSecureStorage.read(WebuiSidecarConfigStorage.keyPassword),
        'standalone_pwd',
      );
    });
  });
}
