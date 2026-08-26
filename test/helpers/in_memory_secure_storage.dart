import 'package:hermes_ui/core/connections/connection_store.dart';

/// 测试用内存版 [SecureStorage]（Map 实现，无平台通道）。
class InMemorySecureStorage implements SecureStorage {
  final Map<String, String> data = {};

  @override
  Future<String?> read(String key) async => data[key];

  @override
  Future<void> write(String key, String value) async {
    data[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    data.remove(key);
  }
}
