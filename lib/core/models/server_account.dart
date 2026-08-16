import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../utils/equality.dart';

/// 服务器账户（Swift: ServerAccount）。本地 Keychain 持久化 JSON blob。
///
/// **唯一允许解码失败的模型**：`id` 与 `url_string` 都缺失时抛
/// [FormatException]（由上层捕获——对齐 Swift 的 dataCorruptedError）。
class ServerAccount {
  ServerAccount({
    required this.id,
    required this.urlString,
    this.displayName = '',
    this.initials = '',
    this.headerLogoColorHex = defaultHeaderLogoColorHex,
    this.customHeadersRef,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt =
            (createdAt ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true))
                .toUtc(),
        updatedAt = (updatedAt ?? createdAt ??
                DateTime.fromMillisecondsSinceEpoch(0, isUtc: true))
            .toUtc();

  /// HeaderLogoColor.defaultHex（蓝本常量）。
  static const String defaultHeaderLogoColorHex = '#FFD700';

  /// 从 JSON blob 解码；`id` 缺失时用 `url_string`；两者都缺 → 抛 FormatException。
  factory ServerAccount.fromJson(Map<String, Object?> json) {
    final String? id = json['id'] is String ? json['id'] as String : null;
    final String? url =
        json['url_string'] is String ? json['url_string'] as String : null;
    final resolved = id ?? url;
    if (resolved == null) {
      throw const FormatException('ServerAccount requires an id or urlString');
    }

    final displayName =
        json['display_name'] is String ? json['display_name'] as String : '';
    final initials = json['initials'] is String ? json['initials'] as String : '';
    final colorHex = json['header_logo_color_hex'] is String
        ? json['header_logo_color_hex'] as String
        : defaultHeaderLogoColorHex;
    final customHeadersRef = json['custom_headers_ref'] is String
        ? json['custom_headers_ref'] as String
        : null;
    final createdAt = (_parseDate(json['created_at']) ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true))
        .toUtc();
    final updatedAt = (_parseDate(json['updated_at']) ?? createdAt).toUtc();

    return ServerAccount(
      id: id ?? resolved,
      urlString: url ?? resolved,
      displayName: displayName,
      initials: initials,
      headerLogoColorHex: colorHex,
      customHeadersRef: customHeadersRef,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  final String id;
  final String urlString;
  final String displayName;
  final String initials;
  final String headerLogoColorHex;
  final String? customHeadersRef;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// 时间戳：ISO8601 字符串解析失败回退 null（由调用方决定默认值）。
  static DateTime? _parseDate(Object? value) {
    if (value is! String) return null;
    return DateTime.tryParse(value);
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'url_string': urlString,
      'display_name': displayName,
      'initials': initials,
      'header_logo_color_hex': headerLogoColorHex,
      if (customHeadersRef != null) 'custom_headers_ref': customHeadersRef,
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
    };
  }

  @override
  bool operator ==(Object other) {
    return other is ServerAccount &&
        other.id == id &&
        other.urlString == urlString &&
        other.displayName == displayName &&
        other.initials == initials &&
        other.headerLogoColorHex == headerLogoColorHex &&
        other.customHeadersRef == customHeadersRef &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt;
  }

  @override
  int get hashCode => Object.hash(
        id,
        urlString,
        displayName,
        initials,
        headerLogoColorHex,
        customHeadersRef,
        createdAt,
        updatedAt,
      );

  @override
  String toString() => 'ServerAccount(id: $id, displayName: $displayName)';
}

/// 服务器注册表快照（Swift `ServerRegistry.Snapshot`）：servers + activeServerID。
class ServerRegistrySnapshot {
  const ServerRegistrySnapshot({this.servers = const [], this.activeServerID});

  factory ServerRegistrySnapshot.fromJson(Map<String, Object?> json) {
    final rawServers = json['servers'];
    final servers = <ServerAccount>[];
    if (rawServers is List) {
      for (final element in rawServers) {
        if (element is! Map) continue;
        try {
          servers.add(ServerAccount.fromJson(Map<String, Object?>.from(element)));
        } on FormatException {
          continue;
        }
      }
    }
    final active = json['active_server_id'];
    return ServerRegistrySnapshot(
      servers: servers,
      activeServerID: active is String ? active : null,
    );
  }

  final List<ServerAccount> servers;
  final String? activeServerID;

  ServerAccount? get activeServer {
    final id = activeServerID;
    if (id == null) return null;
    for (final server in servers) {
      if (server.id == id) return server;
    }
    return null;
  }

  Map<String, Object?> toJson() {
    return {
      'servers': servers.map((s) => s.toJson()).toList(),
      if (activeServerID != null) 'active_server_id': activeServerID,
    };
  }

  @override
  bool operator ==(Object other) {
    return other is ServerRegistrySnapshot &&
        deepEquals(other.servers, servers) &&
        other.activeServerID == activeServerID;
  }

  @override
  int get hashCode => Object.hash(deepHash(servers), activeServerID);

  @override
  String toString() =>
      'ServerRegistrySnapshot(servers: ${servers.length}, active: $activeServerID)';
}

/// 注册表持久化后端（默认 [SecureServerRegistryStorage] 走 flutter_secure_storage；
/// 测试注入内存后端）。
abstract interface class ServerRegistryStorage {
  Future<String?> read();

  Future<void> write(String value);
}

/// 基于 flutter_secure_storage 的默认持久化后端。
class SecureServerRegistryStorage implements ServerRegistryStorage {
  SecureServerRegistryStorage({
    this.storageKey = 'hermes.mobile.servers',
    FlutterSecureStorage? storage,
  }) : _storage = storage ?? const FlutterSecureStorage();

  final String storageKey;
  final FlutterSecureStorage _storage;

  @override
  Future<String?> read() => _storage.read(key: storageKey);

  @override
  Future<void> write(String value) =>
      _storage.write(key: storageKey, value: value);
}

/// 服务器注册表（Swift `ServerRegistry`）：flutter_secure_storage 持久化，
/// `activate/setActive/remove/update/forgetActiveServer` 方法照抄。
class ServerRegistry {
  ServerRegistry({
    ServerRegistryStorage? storage,
    DateTime Function()? now,
  })  : _storage = storage ?? SecureServerRegistryStorage(),
        _now = now ?? DateTime.now;

  final ServerRegistryStorage _storage;
  final DateTime Function() _now;
  ServerRegistrySnapshot? _snapshot;

  /// 当前快照；未 load 时为空快照。
  ServerRegistrySnapshot get snapshot => _snapshot ?? const ServerRegistrySnapshot();

  List<ServerAccount> get servers => snapshot.servers;

  String? get activeServerID => snapshot.activeServerID;

  ServerAccount? get activeServer => snapshot.activeServer;

  /// 从持久化层加载快照（启动时调用一次）。
  Future<void> load() async {
    final raw = await _storage.read();
    if (raw == null) {
      _snapshot = const ServerRegistrySnapshot();
      return;
    }
    _snapshot = _decodeSnapshot(raw);
  }

  /// 确保 `url` 已注册并标记为 active，返回 active 条目。
  /// 已注册的 URL 只重新激活，不重复插入，身份不动。
  Future<ServerAccount> activate(String url) async {
    var snapshot = this.snapshot;
    final existing = _firstById(snapshot.servers, url);
    if (existing != null) {
      if (snapshot.activeServerID != url) {
        snapshot = ServerRegistrySnapshot(
          servers: snapshot.servers,
          activeServerID: url,
        );
        await _persist(snapshot);
      }
      return existing;
    }

    final account = _makeSeededAccount(url);
    snapshot = ServerRegistrySnapshot(
      servers: [...snapshot.servers, account],
      activeServerID: url,
    );
    await _persist(snapshot);
    return account;
  }

  /// 标记已注册服务器为 active；未注册或已是 active → 返回 null。
  Future<ServerAccount?> setActive(String id) async {
    final snapshot = this.snapshot;
    if (snapshot.activeServerID == id) return null;
    final account = _firstById(snapshot.servers, id);
    if (account == null) return null;

    final updated = ServerRegistrySnapshot(
      servers: snapshot.servers,
      activeServerID: id,
    );
    await _persist(updated);
    return account;
  }

  /// 移除服务器；若是 active 则自动选中下一个剩余服务器。
  /// 返回移除后的 active（无剩余 → null）。未注册 id → no-op。
  Future<ServerAccount?> remove(String id) async {
    final snapshot = this.snapshot;
    if (_firstById(snapshot.servers, id) == null) return snapshot.activeServer;

    final remaining = snapshot.servers
        .where((s) => s.id != id)
        .toList(growable: false);
    final wasActive = snapshot.activeServerID == id;
    final updated = ServerRegistrySnapshot(
      servers: remaining,
      activeServerID: wasActive
          ? (remaining.isEmpty ? null : remaining.first.id)
          : snapshot.activeServerID,
    );
    await _persist(updated);
    return updated.activeServer;
  }

  /// 替换 `account.id` 的存储条目（身份编辑），bump updatedAt。
  Future<void> update(ServerAccount account) async {
    final snapshot = this.snapshot;
    final index = snapshot.servers.indexWhere((s) => s.id == account.id);
    if (index == -1) return;

    final updatedServers = List<ServerAccount>.from(snapshot.servers);
    updatedServers[index] = ServerAccount(
      id: account.id,
      urlString: account.urlString,
      displayName: account.displayName,
      initials: account.initials,
      headerLogoColorHex: account.headerLogoColorHex,
      customHeadersRef: account.customHeadersRef,
      createdAt: account.createdAt,
      updatedAt: _now(),
    );
    await _persist(ServerRegistrySnapshot(
      servers: updatedServers,
      activeServerID: snapshot.activeServerID,
    ));
  }

  /// 完全忘记 active 服务器（登出）。
  Future<void> forgetActiveServer() async {
    final snapshot = this.snapshot;
    final id = snapshot.activeServerID;
    if (id == null) return;
    final updated = ServerRegistrySnapshot(
      servers: snapshot.servers.where((s) => s.id != id).toList(growable: false),
      activeServerID: null,
    );
    await _persist(updated);
  }

  ServerAccount _makeSeededAccount(String id) {
    final timestamp = _now();
    return ServerAccount(
      id: id,
      urlString: id,
      displayName: id,
      initials: _deriveInitials(id),
      headerLogoColorHex: ServerAccount.defaultHeaderLogoColorHex,
      customHeadersRef: id,
      createdAt: timestamp,
      updatedAt: timestamp,
    );
  }

  static String _deriveInitials(String url) {
    final host = url.split('//').last.split('/').first;
    if (host.isEmpty) return '';
    return host.substring(0, 1).toUpperCase();
  }

  static ServerAccount? _firstById(List<ServerAccount> servers, String id) {
    for (final server in servers) {
      if (server.id == id) return server;
    }
    return null;
  }

  static ServerRegistrySnapshot _decodeSnapshot(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return ServerRegistrySnapshot.fromJson(
          Map<String, Object?>.from(decoded),
        );
      }
      return const ServerRegistrySnapshot();
    } catch (_) {
      return const ServerRegistrySnapshot();
    }
  }

  Future<void> _persist(ServerRegistrySnapshot snapshot) async {
    _snapshot = snapshot;
    await _storage.write(jsonEncode(snapshot.toJson()));
  }
}
