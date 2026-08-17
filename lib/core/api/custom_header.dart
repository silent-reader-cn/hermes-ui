import 'dart:convert';

import '../connections/connection_store.dart' show SecureStorage;

/// 用户为反向代理配置的单个自定义请求头。秘密值只进入安全存储。
class CustomHeader {
  const CustomHeader({required this.name, required this.value});

  final String name;
  final String value;
  String get sanitizedName => name.trim();
  String get sanitizedValue => value.trim();

  bool get isApplicable {
    final n = sanitizedName;
    if (n.isEmpty || !_tokenRegExp.hasMatch(n)) return false;
    return !value.contains('\n') && !value.contains('\r');
  }

  static final RegExp _tokenRegExp = RegExp(r"^[!#$%&'*+\-.^_`|~0-9A-Za-z]+$");

  Map<String, String> toJson() => {'name': sanitizedName, 'value': sanitizedValue};

  factory CustomHeader.fromJson(Map<String, Object?> json) => CustomHeader(
        name: json['name'] is String ? json['name'] as String : '',
        value: json['value'] is String ? json['value'] as String : '',
      );

  @override
  bool operator ==(Object other) =>
      other is CustomHeader && other.name == name && other.value == value;

  @override
  int get hashCode => Object.hash(name, value);
}

/// 进程级自定义头快照，支持 flutter_secure_storage 持久化。
class CustomHeaderStore {
  CustomHeaderStore([List<CustomHeader> headers = const []])
      : _headers = List.of(headers);

  static const storageKey = 'custom_headers_v1';
  List<CustomHeader> _headers;

  List<CustomHeader> snapshot() => List.unmodifiable(_headers);

  void replace(List<CustomHeader> headers) => _headers = List.of(headers);

  Future<void> persist(SecureStorage storage) async {
    final valid = _headers.where((header) => header.isApplicable);
    await storage.write(storageKey, jsonEncode(valid.map((h) => h.toJson()).toList()));
  }

  Future<void> restore(SecureStorage storage) async {
    try {
      final raw = await storage.read(storageKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      replace([
        for (final item in decoded)
          if (item is Map)
            CustomHeader.fromJson(Map<String, Object?>.from(item)),
      ]);
    } on FormatException {
      // 损坏的秘密数据静默忽略。
    }
  }
}

/// 用于 API 层请求头注入的安全 Map。
Map<String, String> applicableHeaders(Iterable<CustomHeader> headers) => {
      for (final header in headers)
        if (header.isApplicable) header.sanitizedName: header.sanitizedValue,
    };
