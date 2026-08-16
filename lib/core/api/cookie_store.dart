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
}

/// 极简内存 Cookie 会话存储（dio_cookie_jar 的等价替代）。
///
/// - 登录成功后从响应 `Set-Cookie` 落库，之后每个同域请求自动携带。
/// - 按 host 作用域隔离：换服务器不串 cookie。
/// - TODO(merge)：需要持久化时接入 dio_cookie_jar / flutter_secure_storage
///   （CookieStore 接口保持不变，上层可整体替换）。
class CookieStore {
  final List<Cookie> _cookies = [];

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
  }

  /// 适用于 [uri] 的 `Cookie: name=value; …` 头（无匹配返回 null）。
  String? cookieHeaderFor(Uri uri) {
    final parts = _cookies
        .where((c) => c.matches(uri))
        .map((c) => '${c.name}=${c.value}');
    final joined = parts.join('; ');
    return joined.isEmpty ? null : joined;
  }

  void clear() => _cookies.clear();

  int get length => _cookies.length;
}
