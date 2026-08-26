import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/models/model_favorite.dart';

void main() {
  group('ModelFavoriteKey', () {
    test('fromJson / toJson / == / hashCode', () {
      const key = ModelFavoriteKey(modelID: 'gpt-4o', providerID: 'openai');
      final decoded = ModelFavoriteKey.fromJson(key.toJson());
      expect(decoded, key);
      expect(decoded.hashCode, key.hashCode);
      expect(
        ModelFavoriteKey.fromJson({'model_id': 'gpt-4o'}).providerID,
        isNull,
      );
    });
  });

  group('ModelFavoritesStore', () {
    test('toggleFavorite / isFavorite / removeFavorite / 去重', () async {
      final store = ModelFavoritesStore(storage: InMemoryModelKeyStorage());
      const key = ModelFavoriteKey(modelID: 'gpt-4o', providerID: 'openai');
      expect(await store.isFavorite(key), false);

      var keys = await store.toggleFavorite(key);
      expect(keys, [key]);
      expect(await store.isFavorite(key), true);

      // 再次 toggle → 移除
      keys = await store.toggleFavorite(key);
      expect(keys, isEmpty);
      expect(await store.isFavorite(key), false);

      await store.toggleFavorite(key);
      await store.toggleFavorite(const ModelFavoriteKey(modelID: 'claude', providerID: null));
      // save 去重
      await store.save([key, key, const ModelFavoriteKey(modelID: 'x')]);
      keys = await store.favoriteKeys;
      expect(keys, hasLength(2));
    });

    test('坏 blob → 空列表', () async {
      final store = ModelFavoritesStore(
        storage: InMemoryModelKeyStorage(value: 'not-json'),
      );
      expect(await store.favoriteKeys, isEmpty);
    });
  });

  group('ModelRecentsStore', () {
    test('recordRecent 置顶 + limit 截断 + 去重', () async {
      final store = ModelRecentsStore(
        storage: InMemoryModelKeyStorage(),
        limit: 3,
      );
      const a = ModelFavoriteKey(modelID: 'a');
      const b = ModelFavoriteKey(modelID: 'b');
      const c = ModelFavoriteKey(modelID: 'c');
      const d = ModelFavoriteKey(modelID: 'd');

      expect(await store.recordRecent(a), [a]);
      expect(await store.recordRecent(b), [b, a]);
      expect(await store.recordRecent(c), [c, b, a]);
      // 超限截断
      expect(await store.recordRecent(d), [d, c, b]);
      // 已存在的置顶
      expect(await store.recordRecent(b), [b, d, c]);

      expect(await store.removeRecent(b), [d, c]);
    });
  });
}
