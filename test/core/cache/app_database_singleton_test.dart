import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/cache/app_database.dart';
import 'package:hermes_ui/core/cache/cache_providers.dart';

void main() {
  group('appDatabaseProvider 单例', () {
    test('同一容器多次 watch 同一实例', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      expect(identical(c.read(appDatabaseProvider), c.read(appDatabaseProvider)), isTrue);
    });

    test('overrideWithValue 单例保持', () async {
      final db = AppDatabase.memory();
      addTearDown(() async => db.close());
      final c = ProviderContainer(overrides: [appDatabaseProvider.overrideWithValue(db)]);
      addTearDown(c.dispose);
      expect(identical(c.read(appDatabaseProvider), db), isTrue);
    });

    test('persistent alias 同实例', () async {
      final db = AppDatabase.memory();
      addTearDown(() async => db.close());
      final c = ProviderContainer(overrides: [appDatabaseProvider.overrideWithValue(db)]);
      addTearDown(c.dispose);
      expect(identical(c.read(appDatabaseProvider), c.read(persistentAppDatabaseProvider)), isTrue);
    });
  });
}
