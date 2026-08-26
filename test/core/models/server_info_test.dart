import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/models/server_info.dart';

void main() {
  group('HealthResponse', () {
    test('正常解析（附录 A.5）', () {
      final response = HealthResponse.fromJson({
        'status': 'ok',
        'sessions': 3,
        'active_streams': 1,
        'uptime_seconds': 86400.0,
      });
      expect(response.status, 'ok');
      expect(response.sessions, 3);
      expect(response.activeStreams, 1);
      expect(response.uptimeSeconds, 86400.0);
    });

    test('畸形输入：缺失/错型 → null 容错', () {
      final response = HealthResponse.fromJson({
        'status': 1,
        'sessions': 'many',
        'uptime_seconds': 'long',
      });
      expect(response.status, '1');
      expect(response.sessions, isNull);
      expect(response.uptimeSeconds, isNull);
      expect(HealthResponse.fromJson(const {}).status, isNull);
    });
  });

  group('AuthStatusResponse', () {
    test('正常解析（附录 A.5）', () {
      final response = AuthStatusResponse.fromJson({
        'auth_enabled': true,
        'logged_in': true,
        'password_auth_enabled': true,
        'passkeys_enabled': false,
        'passwordless_enabled': false,
      });
      expect(response.authEnabled, true);
      expect(response.loggedIn, true);
      expect(response.passwordAuthEnabled, true);
      expect(response.passkeysEnabled, false);
      expect(response.passwordlessEnabled, false);
    });

    test('畸形输入：错型 → null，缺失保持可空', () {
      final response = AuthStatusResponse.fromJson({
        'auth_enabled': 'yes',
        'logged_in': 'nope',
      });
      expect(response.authEnabled, true);
      expect(response.loggedIn, isNull);
      expect(response.passwordAuthEnabled, isNull);
      final empty = AuthStatusResponse.fromJson(const {});
      expect(empty.authEnabled, isNull);
      expect(empty.passwordlessEnabled, isNull);
    });
  });

  group('LoginResponse', () {
    test('正常解析（附录 A.5）', () {
      final response = LoginResponse.fromJson(
        {'ok': true, 'message': '登录成功', 'error': null},
      );
      expect(response.ok, true);
      expect(response.message, '登录成功');
      expect(response.error, isNull);
    });

    test('畸形输入：缺失/错型 → null 容错', () {
      final response = LoginResponse.fromJson({
        'ok': 'maybe',
        'message': 42,
      });
      expect(response.ok, isNull);
      expect(response.message, '42');
    });
  });

  test('== / hashCode', () {
    final a = HealthResponse.fromJson({'status': 'ok'});
    final b = HealthResponse.fromJson({'status': 'ok'});
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });
}
