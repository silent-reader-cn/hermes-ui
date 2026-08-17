import 'dart:async';
import 'dart:convert';

import '../connections/connection_store.dart' show SecureStorage;

/// 单个 Cookie（按 Domain/Path/Max-Age/Expires 做最小实现）。
class Cookie {
  Cookie({
    required this.name,
    required this.value,
    required this.domain,
    this.path = '/',
    this.expires,
  });

  final String name;
  final String value;
  final String domain;
  final String path;

  /// null = 会话级 cookie（不过期）。
  final DateTime? expires;

  bool get isExpired => expires != null && !expires!.isAfter(DateTime.now());

  /// 该 cookie 是否适用于 [uri]（host 精确或子域匹配 + path 前缀匹配 + 未过期）。
  bool matches(Uri uri) {
    final host = uri.host.toLowerCase();
    final d = domain.toLowerCase();
    if (host != d && !host.endsWith('.$d')) return false;
    if (path != '/' && !uri.path.startsWith(path)) return false;
    return !isExpired;
  }

  /// 解析一条 `Set-Cookie` 响应头（仅取首个 name=value 与常用属性）。
  static Cookie? parse(String header, Uri origin) {
    final parts = header.split(';');
    if (parts.isEmpty) return null;
    final nameValue = parts.first.trim();
    final eq = nameValue.indexOf('=');
    if (eq <= 0) return null;
    final name = nameValue.substring(0, eq).trim();
    final value = nameValue.substring(eq + 1).trim();
    if (name.isEmpty) return null;

    var domain = origin.host;
    var path = '/';
    DateTime? expires;
    for (final part in parts.skip(1)) {
      final p = part.trim();
      final i = p.indexOf('=');
      final key = (i == -1 ? p : p.substring(0, i)).trim().toLowerCase();
      final val = (i == -1 ? '' : p.substring(i + 1)).trim();
      switch (key) {
        case 'domain':
          var d = val.toLowerCase();
          if (d.startsWith('.')) d = d.substring(1);
          if (d.isNotEmpty) domain = d;
        case 'path':
          if (val.isNotEmpty) path = val;
        case 'expires':
          expires = DateTime.tryParse(val) ?? _parseHttpDate(val);
        case 'max-age':
          final seconds = int.tryParse(val);
          if (seconds != null) {
            expires = DateTime.now().add(Duration(seconds: seconds));
          }
      }
    }
    return Cookie(
      name: name,
      value: value,
      domain: domain,
      path: path,
      expires: expires,
    );
  }

  /// 容错解析 `Wed, 09 Jun 2021 10:18:14 GMT` 之类的 HTTP 日期。
  static DateTime? _parseHttpDate(String value) {
    try {
      final normalized = value.replaceAll('GMT', '').trim();
      return DateTime.parse(normalized);
    } catch (_) {
      return null;
    }
  }

  /// 持久化编码（expires 存 epoch 毫秒，无过期存 null）。
  Map<String, Object?> toJson() {
    return {
      'name': name,
      'value': value,
      'domain': domain,
      'path': path,
      if (expires != null) 'expires': expires!.millisecondsSinceEpoch,
    };
  }

  /// 容错解码：字段缺失/类型不符给安全默认值，绝不 crash。
  factory Cookie.fromJson(Map<String, Object?> json) {
    final name = json['name'] is String ? json['name'] as String : '';
    final value = json['value'] is String ? json['value'] as String : '';
    final domain = json['domain'] is String ? json['domain'] as String : '';
    final path = json['path'] is String ? json['path'] as String : '/';
    final expiresRaw = json['expires'];
    DateTime? expires;
    if (expiresRaw is num) {
      expires = DateTime.fromMillisecondsSinceEpoch(expiresRaw.toInt());
    }
    return Cookie(name: name, value: value, domain: domain, path: path, expires: expires);
  }
}

/// 极简内存 Cookie 会话存储（dio_cookie_jar 的等价替代）。
///
/// - 登录成功后从响应 `Set-Cookie` 落库，之后每个同域请求自动携带。
/// - 按 host 作用域隔离：换服务器不串 cookie。
/// - [shared] 为进程级共享实例：onboarding 临时 client 登录种下的 cookie，
///   后续 apiClientProvider 新建的 client 也能携带（修复「登录后 401」）。
/// - 可选持久化：注入 [SecureStorage] 后每次变更异步落盘（失败静默，不影响
///   内存态）；App 启动时调 [restore] 恢复，避免重启丢登录态。
/// - 测试可用 `CookieStore()` 构造独立实例隔离状态。
class CookieStore {
  CookieStore({this._storage});

  /// 进程级共享 cookie 存储（按 domain 隔离，多服务器不串）。
  ///
  /// 生产启动时整体替换为注入 secure storage 的实例
  /// （`CookieStore.shared = CookieStore(storage: …)`），此前引用均在
  /// runApp 之后创建，替换安全。
  static CookieStore shared = CookieStore();

  /// 持久化 key（存储全部 cookie 的 JSON 数组）。
  static const String storageKey = 'cookie_store_v1';

  final SecureStorage? _storage;

  final List<Cookie> _cookies = [];

  /// 启动恢复：从存储读回 cookie 填充内存（损坏数据静默忽略）。
  Future<void> restore() async {
    final storage = _storage;
    if (storage == null) return;
    try {
      final raw = await storage.read(storageKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      final restored = <Cookie>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        restored.add(Cookie.fromJson(Map<String, Object?>.from(item)));
      }
      _cookies
        ..clear()
        ..addAll(restored);
    } catch (_) {
      // 损坏数据：忽略，保持空存储。
    }
  }

  /// 从响应头解析并存入（同名同域同路径覆盖）。
  void setCookies(Uri origin, List<String>? setCookieHeaders) {
    if (setCookieHeaders == null) return;
    for (final header in setCookieHeaders) {
      final cookie = Cookie.parse(header, origin);
      if (cookie == null) continue;
      _cookies.removeWhere(
        (c) =>
            c.name == cookie.name &&
            c.domain == cookie.domain &&
            c.path == cookie.path,
      );
      _cookies.add(cookie);
    }
    unawaited(_persist());
  }

  /// 适用于 [uri] 的 `Cookie: name=value; …` 头（无匹配返回 null）。
  String? cookieHeaderFor(Uri uri) {
    final parts = _cookies
        .where((c) => c.matches(uri))
        .map((c) => '${c.name}=${c.value}');
    final joined = parts.join('; ');
    return joined.isEmpty ? null : joined;
  }

  void clear() {
    _cookies.clear();
    unawaited(_persist());
  }

  int get length => _cookies.length;

  /// 异步落盘（失败静默：cookie 持久化是优化项，不影响内存会话功能）。
  Future<void> _persist() async {
    final storage = _storage;
    if (storage == null) return;
    try {
      await storage.write(
        storageKey,
        jsonEncode([for (final c in _cookies) c.toJson()]),
      );
    } catch (_) {
      // 静默：存储失败不阻断登录/请求。
    }
  }
}
