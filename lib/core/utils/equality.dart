/// 深度相等比较（List / Map 递归逐项比较，其余走 `==`）。
///
/// 用于模型手写 `==` 时对集合字段（如 `List<JsonValue>`、`Map<String, JsonValue>`）
/// 做值比较，等价于 Swift 的 `Equatable` 合成语义。
bool deepEquals(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!deepEquals(a[i], b[i])) return false;
    }
    return true;
  }
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key)) return false;
      if (!deepEquals(a[key], b[key])) return false;
    }
    return true;
  }
  return a == b;
}

/// 深度哈希：List / Map 递归散列，与 [deepEquals] 保持一致。
int deepHash(Object? value) {
  if (value is List) {
    return Object.hashAll(value.map(deepHash));
  }
  if (value is Map) {
    return Object.hashAllUnordered(
      value.entries.expand((e) => [deepHash(e.key), deepHash(e.value)]),
    );
  }
  return value?.hashCode ?? 0;
}
