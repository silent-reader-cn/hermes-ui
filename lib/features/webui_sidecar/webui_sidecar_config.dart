import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'webui_sidecar_models.dart';

export 'webui_sidecar_models.dart';

/// 安全存储接口抽象（用于单元测试注入 fake，解耦平台通道）。
abstract interface class SidecarSecureStorage {
  /// 读取指定键的值。
  Future<String?> read(String key);

  /// 写入指定键值对。
  Future<void> write(String key, String value);

  /// 删除指定键的值。
  Future<void> delete(String key);
}

/// 基于 [FlutterSecureStorage] 的生产安全存储实现。
class DefaultSidecarSecureStorage implements SidecarSecureStorage {
  /// 构造生产安全存储。
  const DefaultSidecarSecureStorage([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// WebUI Sidecar 配置持久化存储。
///
/// 存储分配规则：
/// - [SidecarConfig.enabled]、[SidecarConfig.host]、[SidecarConfig.port] 存储于 [SharedPreferences]。
/// - [SidecarConfig.password] 严格存储于 [SidecarSecureStorage]（Windows DPAPI / 加密密钥区），
///   绝不进入普通偏好文件，绝不进入日志。
class WebuiSidecarConfigStorage {
  /// 构造配置存储，允许注入 [SharedPreferences] 与 [SidecarSecureStorage] 便于测试。
  WebuiSidecarConfigStorage({
    FutureOr<SharedPreferences>? prefs,
    SidecarSecureStorage? secureStorage,
  })  : _prefsOrFuture = prefs,
        _secureStorage = secureStorage ?? const DefaultSidecarSecureStorage();

  final FutureOr<SharedPreferences>? _prefsOrFuture;
  final SidecarSecureStorage _secureStorage;

  /// SharedPreferences 持久化键：是否启用内置 WebUI。
  static const String keyEnabled = 'webui_sidecar_enabled';

  /// SharedPreferences 持久化键：WebUI 监听主机。
  static const String keyHost = 'webui_sidecar_host';

  /// SharedPreferences 持久化键：WebUI 监听端口。
  static const String keyPort = 'webui_sidecar_port';

  /// flutter_secure_storage 持久化键：WebUI 访问密码。
  static const String keyPassword = 'webui_sidecar_password';

  Future<SharedPreferences> _getPrefs() async {
    final prefs = _prefsOrFuture;
    if (prefs is SharedPreferences) return prefs;
    if (prefs is Future<SharedPreferences>) return await prefs;
    return await SharedPreferences.getInstance();
  }

  /// 异步读取已保存配置。若密码为空，则首次生成 24 位随机密码并即刻落盘。
  Future<SidecarConfig> load() async {
    final prefs = await _getPrefs();
    final enabled = prefs.getBool(keyEnabled) ?? false;
    final host = prefs.getString(keyHost) ?? SidecarConfig.defaultHost;
    final port = prefs.getInt(keyPort) ?? SidecarConfig.defaultPort;

    var password = await _secureStorage.read(keyPassword);
    if (password == null || password.trim().isEmpty) {
      password = SidecarConfig.generateRandomPassword();
      await _secureStorage.write(keyPassword, password);
    }

    return SidecarConfig(
      enabled: enabled,
      host: host,
      port: port,
      password: password,
    );
  }

  /// 保存完整配置。
  Future<void> save(SidecarConfig config) async {
    final prefs = await _getPrefs();
    await prefs.setBool(keyEnabled, config.enabled);
    await prefs.setString(keyHost, config.host);
    await prefs.setInt(keyPort, config.port);
    if (config.password.isNotEmpty) {
      await _secureStorage.write(keyPassword, config.password);
    }
  }

  /// 更新启用状态。
  Future<void> setEnabled(bool value) async {
    final prefs = await _getPrefs();
    await prefs.setBool(keyEnabled, value);
  }

  /// 更新监听主机。
  Future<void> setHost(String value) async {
    final prefs = await _getPrefs();
    await prefs.setString(keyHost, value);
  }

  /// 更新监听端口。
  Future<void> setPort(int value) async {
    final prefs = await _getPrefs();
    await prefs.setInt(keyPort, value);
  }

  /// 更新访问密码。
  Future<void> setPassword(String value) async {
    if (value.isNotEmpty) {
      await _secureStorage.write(keyPassword, value);
    }
  }
}
