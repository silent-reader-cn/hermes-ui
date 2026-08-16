import 'dart:convert';

import '../utils/lossy_json.dart';

/// 模型收藏键（Swift: ModelFavoriteKey）。
class ModelFavoriteKey {
  const ModelFavoriteKey({required this.modelID, this.providerID});

  factory ModelFavoriteKey.fromJson(Map<String, Object?> json) {
    return ModelFavoriteKey(
      modelID: lossyString(json, 'model_id') ?? '',
      providerID: lossyString(json, 'provider_id'),
    );
  }

  final String modelID;
  final String? providerID;

  Map<String, Object?> toJson() {
    return {
      'model_id': modelID,
      if (providerID != null) 'provider_id': providerID,
    };
  }

  @override
  bool operator ==(Object other) {
    return other is ModelFavoriteKey &&
        other.modelID == modelID &&
        other.providerID == providerID;
  }

  @override
  int get hashCode => Object.hash(modelID, providerID);

  @override
  String toString() =>
      'ModelFavoriteKey(modelID: $modelID, providerID: $providerID)';
}

/// 本地键值存储抽象（测试注入内存实现）。
abstract interface class ModelKeyStorage {
  Future<String?> read();

  Future<void> write(String value);
}

/// 内存实现（测试用）。
class InMemoryModelKeyStorage implements ModelKeyStorage {
  InMemoryModelKeyStorage({this.value});

  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String value) async {
    this.value = value;
  }
}

/// 模型收藏存储（Swift `ModelFavoritesStore`）。去重逻辑照抄。
class ModelFavoritesStore {
  ModelFavoritesStore({required this.storage});

  static const String defaultStorageKey = 'hermes.mobile.favoriteModels';

  final ModelKeyStorage storage;

  Future<List<ModelFavoriteKey>> get favoriteKeys async {
    final raw = await storage.read();
    if (raw == null) return const [];
    return _deduplicated(_decodeKeys(raw));
  }

  Future<bool> isFavorite(ModelFavoriteKey key) async {
    final keys = await favoriteKeys;
    return keys.contains(key);
  }

  Future<List<ModelFavoriteKey>> toggleFavorite(ModelFavoriteKey key) async {
    final keys = await favoriteKeys;
    final List<ModelFavoriteKey> updated;
    if (keys.contains(key)) {
      updated = keys.where((k) => k != key).toList();
    } else {
      updated = [...keys, key];
    }
    await save(updated);
    return updated;
  }

  Future<List<ModelFavoriteKey>> removeFavorite(ModelFavoriteKey key) async {
    final keys = await favoriteKeys;
    final updated = keys.where((k) => k != key).toList();
    await save(updated);
    return updated;
  }

  Future<void> save(List<ModelFavoriteKey> keys) async {
    final deduplicated = _deduplicated(keys);
    await storage.write(jsonEncode(deduplicated.map((k) => k.toJson()).toList()));
  }

  static List<ModelFavoriteKey> _deduplicated(List<ModelFavoriteKey> keys) {
    final seen = <ModelFavoriteKey>{};
    final result = <ModelFavoriteKey>[];
    for (final key in keys) {
      if (seen.add(key)) result.add(key);
    }
    return result;
  }
}

/// 最近使用模型存储（Swift `ModelRecentsStore`）。limit 5。
class ModelRecentsStore {
  ModelRecentsStore({required this.storage, this.limit = 5});

  static const String defaultStorageKey = 'hermes.mobile.recentModels';

  final ModelKeyStorage storage;
  final int limit;

  Future<List<ModelFavoriteKey>> get recentKeys async {
    final raw = await storage.read();
    if (raw == null) return const [];
    return _limitedDeduplicated(_decodeKeys(raw), limit: limit);
  }

  Future<List<ModelFavoriteKey>> recordRecent(ModelFavoriteKey key) async {
    final current = await recentKeys;
    final updated = _limitedDeduplicated([key, ...current], limit: limit);
    await save(updated);
    return updated;
  }

  Future<List<ModelFavoriteKey>> removeRecent(ModelFavoriteKey key) async {
    final keys = await recentKeys;
    final updated = keys.where((k) => k != key).toList();
    await save(updated);
    return updated;
  }

  Future<void> save(List<ModelFavoriteKey> keys) async {
    final deduplicated = _limitedDeduplicated(keys, limit: limit);
    await storage.write(jsonEncode(deduplicated.map((k) => k.toJson()).toList()));
  }

  static List<ModelFavoriteKey> _limitedDeduplicated(
    List<ModelFavoriteKey> keys, {
    required int limit,
  }) {
    final seen = <ModelFavoriteKey>{};
    final result = <ModelFavoriteKey>[];
    for (final key in keys) {
      if (seen.add(key)) {
        result.add(key);
        if (result.length == limit) break;
      }
    }
    return result;
  }
}

List<ModelFavoriteKey> _decodeKeys(String raw) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    final result = <ModelFavoriteKey>[];
    for (final element in decoded) {
      if (element is Map) {
        result.add(ModelFavoriteKey.fromJson(Map<String, Object?>.from(element)));
      }
    }
    return result;
  } catch (_) {
    return const [];
  }
}
