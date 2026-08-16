/// 用户为反向代理（Authentik 等）配置的单个自定义请求头。
///
/// 名字/值可含秘密（如 `Authorization: Bearer …`），因此持久化走
/// flutter_secure_storage（TODO(merge)：由上层接入），禁止硬编码、禁止进日志。
class CustomHeader {
  const CustomHeader({required this.name, required this.value});

  final String name;
  final String value;

  /// 首尾空白/换行去掉；内部空格（如 `Bearer <token>`）保留。
  String get sanitizedName => name.trim();
  String get sanitizedValue => value.trim();

  /// RFC 7230 token 字符（`!#$%&'*+-.^_`|~` + 字母数字），且值不含换行
  /// （防止 HTTP 头注入）。空行/半输入行直接跳过（CustomHeader.swift）。
  bool get isApplicable {
    final name = sanitizedName;
    if (name.isEmpty) return false;
    if (!_tokenRegExp.hasMatch(name)) return false;
    return !value.contains('\n') && !value.contains('\r');
  }

  static final RegExp _tokenRegExp = RegExp(r"^[!#$%&'*+\-.^_`|~0-9A-Za-z]+$");

  @override
  bool operator ==(Object other) =>
      other is CustomHeader && other.name == name && other.value == value;

  @override
  int get hashCode => Object.hash(name, value);
}

/// 进程级自定义头内存快照。
///
/// 每次构建请求时读取（请求时点生效，改 header 不用重建 client，对齐
/// CustomHeaderStore.swift）。持久化由上层（AuthManager 等价物）负责。
class CustomHeaderStore {
  CustomHeaderStore([List<CustomHeader> headers = const []])
    : _headers = List.of(headers);

  List<CustomHeader> _headers;

  List<CustomHeader> snapshot() => List.unmodifiable(_headers);

  void replace(List<CustomHeader> headers) => _headers = List.of(headers);
}
