import '../utils/lossy_json.dart';

/// 健康检查响应（Swift: HealthResponse）。
class HealthResponse {
  const HealthResponse({
    this.status,
    this.sessions,
    this.activeStreams,
    this.uptimeSeconds,
  });

  factory HealthResponse.fromJson(Map<String, Object?> json) {
    return HealthResponse(
      status: lossyString(json, 'status'),
      sessions: lossyInt(json, 'sessions'),
      activeStreams: lossyInt(json, 'active_streams'),
      uptimeSeconds: lossyDouble(json, 'uptime_seconds'),
    );
  }

  final String? status;
  final int? sessions;
  final int? activeStreams;
  final double? uptimeSeconds;

  @override
  bool operator ==(Object other) {
    return other is HealthResponse &&
        other.status == status &&
        other.sessions == sessions &&
        other.activeStreams == activeStreams &&
        other.uptimeSeconds == uptimeSeconds;
  }

  @override
  int get hashCode =>
      Object.hash(status, sessions, activeStreams, uptimeSeconds);

  @override
  String toString() => 'HealthResponse(status: $status)';
}

/// 认证状态响应（Swift: AuthStatusResponse）。
class AuthStatusResponse {
  const AuthStatusResponse({
    this.authEnabled,
    this.loggedIn,
    this.passwordAuthEnabled,
    this.passkeysEnabled,
    this.passwordlessEnabled,
  });

  factory AuthStatusResponse.fromJson(Map<String, Object?> json) {
    return AuthStatusResponse(
      authEnabled: lossyBool(json, 'auth_enabled'),
      loggedIn: lossyBool(json, 'logged_in'),
      passwordAuthEnabled: lossyBool(json, 'password_auth_enabled'),
      passkeysEnabled: lossyBool(json, 'passkeys_enabled'),
      passwordlessEnabled: lossyBool(json, 'passwordless_enabled'),
    );
  }

  final bool? authEnabled;
  final bool? loggedIn;
  final bool? passwordAuthEnabled;
  final bool? passkeysEnabled;
  final bool? passwordlessEnabled;

  @override
  bool operator ==(Object other) {
    return other is AuthStatusResponse &&
        other.authEnabled == authEnabled &&
        other.loggedIn == loggedIn &&
        other.passwordAuthEnabled == passwordAuthEnabled &&
        other.passkeysEnabled == passkeysEnabled &&
        other.passwordlessEnabled == passwordlessEnabled;
  }

  @override
  int get hashCode => Object.hash(
        authEnabled,
        loggedIn,
        passwordAuthEnabled,
        passkeysEnabled,
        passwordlessEnabled,
      );

  @override
  String toString() => 'AuthStatusResponse(authEnabled: $authEnabled)';
}

/// 登录响应（Swift: LoginResponse）。
class LoginResponse {
  const LoginResponse({this.ok, this.message, this.error});

  factory LoginResponse.fromJson(Map<String, Object?> json) {
    return LoginResponse(
      ok: lossyBool(json, 'ok'),
      message: lossyString(json, 'message'),
      error: lossyString(json, 'error'),
    );
  }

  final bool? ok;
  final String? message;
  final String? error;

  @override
  bool operator ==(Object other) {
    return other is LoginResponse &&
        other.ok == ok &&
        other.message == message &&
        other.error == error;
  }

  @override
  int get hashCode => Object.hash(ok, message, error);

  @override
  String toString() => 'LoginResponse(ok: $ok)';
}
