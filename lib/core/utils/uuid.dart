import 'dart:math';

final Random _uuidRandom = Random.secure();

/// 生成 v4 UUID 字符串（无外部依赖，替代 Swift 的 `UUID().uuidString`）。
///
/// 规格中所有「uuid 兜底」的 id 派生规则均使用本函数。
String uuidV4() {
  final bytes = List<int>.generate(16, (_) => _uuidRandom.nextInt(256));
  // 设置 v4 版本位与变体位。
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex =
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
