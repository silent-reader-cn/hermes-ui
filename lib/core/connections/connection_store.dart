import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'server_connection.dart';

/// 极简安全存储接口（读写删除）。
///
/// 生产实现 [FlutterSecureStorageAdapter] 包 flutter_secure_storage；
/// 测试注入内存版 fake，彻底绕开 platform 解析/平台通道。
abstract interface class SecureStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// 生产实现：flutter_secure_storage（Windows DPAPI / 移动端 Keychain-Keystore）。
class FlutterSecureStorageAdapter implements SecureStorage {
  const FlutterSecureStorageAdapter();

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// 服务器连接持久化存储（app_shell_spec.md §5.2）。
///
/// 基于安全存储（[SecureStorage]）：
/// - `connections` → JSON 数组（每项为 [ServerConnection.toJson]，**不含密码**）
/// - `connection_password_<id>` → 密码（单独 key「单独加密」）
/// - `active_connection_id` → 当前激活连接 id
///
/// 多服务器支持：save 按 id upsert，delete 连带清理密码。
class ConnectionStore {
  ConnectionStore({SecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorageAdapter();

  final SecureStorage _storage;

  static const String connectionsKey = 'connections';
  static const String activeConnectionKey = 'active_connection_id';

  static String passwordKey(String id) => 'connection_password_$id';

  /// 读取全部连接（含各自密码）；数据缺失/损坏时容错返回空表，绝不 crash。
  Future<List<ServerConnection>> loadAll() async {
    final raw = await _storage.read(connectionsKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final result = <ServerConnection>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        final json = Map<String, Object?>.from(item);
        final id = json['id'] is String ? json['id'] as String : '';
        final password = id.isEmpty ? null : await _storage.read(passwordKey(id));
        result.add(ServerConnection.fromJson(json, password: password));
      }
      final builtinIdx =
          result.indexWhere((c) => c.kind == ConnectionKind.builtin);
      if (builtinIdx > 0) {
        final builtin = result.removeAt(builtinIdx);
        result.insert(0, builtin);
      }
      return result;
    } on FormatException {
      return const [];
    }
  }

  /// 按 id upsert 保存连接；密码非空时写入单独 key，为空时保留原密码。
  /// 内置连接（[ConnectionKind.builtin]）总是落在首位。
  Future<void> save(ServerConnection connection) async {
    final all = List<ServerConnection>.of(await loadAll());
    final index = all.indexWhere((c) => c.id == connection.id);
    if (connection.kind == ConnectionKind.builtin) {
      if (index >= 0) {
        all.removeAt(index);
      }
      all.insert(0, connection);
    } else if (index >= 0) {
      all[index] = connection;
    } else {
      all.add(connection);
    }
    await _storage.write(
      connectionsKey,
      jsonEncode([for (final c in all) c.toJson()]),
    );
    final password = connection.password;
    if (password != null && password.isNotEmpty) {
      await _storage.write(passwordKey(connection.id), password);
    }
    // 停用 builtin 语义：若该内置连接正处于激活状态，调用 clearActive（风险②裁定）
    if (connection.kind == ConnectionKind.builtin && !connection.enabled) {
      final active = await _storage.read(activeConnectionKey);
      if (active == connection.id) {
        await clearActive();
      }
    }
  }

  /// 删除连接（连带密码与 active 指向清理）。
  /// 对 kind==builtin 抛 [StateError] 防护（模型层兜底）。
  Future<void> delete(String id) async {
    if (id == ServerConnection.builtinId) {
      throw StateError('不能删除内置连接：$id');
    }
    final all = List<ServerConnection>.of(await loadAll());
    final target = all.cast<ServerConnection?>().firstWhere(
      (c) => c?.id == id,
      orElse: () => null,
    );
    if (target != null && target.kind == ConnectionKind.builtin) {
      throw StateError('不能删除内置连接：$id');
    }
    all.removeWhere((c) => c.id == id);
    await _storage.write(
      connectionsKey,
      jsonEncode([for (final c in all) c.toJson()]),
    );
    await _storage.delete(passwordKey(id));
    final active = await _storage.read(activeConnectionKey);
    if (active == id) {
      await _storage.delete(activeConnectionKey);
    }
  }

  /// 设置激活连接；id 不存在或为已停用的内置连接时抛 [StateError]。
  Future<void> setActive(String id) async {
    final all = await loadAll();
    final match = all.cast<ServerConnection?>().firstWhere(
      (c) => c?.id == id,
      orElse: () => null,
    );
    if (match == null) {
      throw StateError('连接不存在：$id');
    }
    if (match.kind == ConnectionKind.builtin && !match.enabled) {
      throw StateError('无法激活已停用的内置连接：$id');
    }
    await _storage.write(activeConnectionKey, id);
  }

  /// 读取激活连接（无 active、已被删除或为已停用的内置连接时返回 null）。
  Future<ServerConnection?> getActive() async {
    final id = await _storage.read(activeConnectionKey);
    if (id == null || id.isEmpty) return null;
    final all = await loadAll();
    for (final connection in all) {
      if (connection.id == id) {
        if (connection.kind == ConnectionKind.builtin && !connection.enabled) {
          return null;
        }
        return connection;
      }
    }
    return null;
  }

  /// 清除激活连接标记（不删除连接本身）。
  Future<void> clearActive() async {
    await _storage.delete(activeConnectionKey);
  }
}
