import 'package:flutter_test/flutter_test.dart';
import 'package:hermex_flutter/core/api/cookie_store.dart';

import '../../helpers/in_memory_secure_storage.dart';

void main() {
  group('Cookie 解析与匹配', () {
    test('Set-Cookie 解析：name/value + 属性', () {
      final cookie = Cookie.parse(
        'hermes_session=abc123; HttpOnly; Max-Age=2592000; Path=/; SameSite=Lax',
        Uri.parse('http://127.0.0.1:30002/'),
      );
      expect(cookie, isNotNull);
      expect(cookie!.name, 'hermes_session');
      expect(cookie.value, 'abc123');
      expect(cookie.domain, '127.0.0.1');
      expect(cookie.path, '/');
      expect(cookie.expires, isNotNull);
    });

    test('matches：同 host 匹配，跨 host / 路径不匹配', () {
      final cookie = Cookie(name: 's', value: 'v', domain: 'example.com');
      expect(cookie.matches(Uri.parse('http://example.com/x')), isTrue);
      expect(cookie.matches(Uri.parse('http://sub.example.com/x')), isTrue);
      expect(cookie.matches(Uri.parse('http://other.com/x')), isFalse);
    });

    test('expires 过期的 cookie 不匹配', () {
      final expired = Cookie(
        name: 's',
        value: 'v',
        domain: 'example.com',
        expires: DateTime.now().subtract(const Duration(seconds: 1)),
      );
      expect(expired.matches(Uri.parse('http://example.com/')), isFalse);
    });
  });

  group('CookieStore 持久化', () {
    test('注入 storage：setCookies 异步落盘，restore 恢复（重启不丢登录态）', () async {
      final storage = InMemorySecureStorage();
      final store = CookieStore(storage: storage);
      final origin = Uri.parse('http://127.0.0.1:30002/');

      store.setCookies(origin, [
        'hermes_session=token123; Path=/; Max-Age=2592000',
      ]);
      // 等待异步落盘完成
      await Future<void>.delayed(Duration.zero);
      expect(storage.data.containsKey(CookieStore.storageKey), isTrue);

      // 模拟重启：新实例（同 storage）restore 后 cookie 可用
      final restored = CookieStore(storage: storage);
      expect(restored.cookieHeaderFor(origin), isNull);
      await restored.restore();
      expect(restored.cookieHeaderFor(origin), 'hermes_session=token123');
    });

    test('clear 后 storage 同步清空', () async {
      final storage = InMemorySecureStorage();
      final store = CookieStore(storage: storage);
      store.setCookies(Uri.parse('http://x.local/'), [
        'a=1; Path=/',
      ]);
      await Future<void>.delayed(Duration.zero);
      store.clear();
      await Future<void>.delayed(Duration.zero);
      expect(store.length, 0);
    });

    test('损坏数据 restore 不 crash，保持空存储', () async {
      final storage = InMemorySecureStorage();
      await storage.write(CookieStore.storageKey, 'not-json{{{');
      final store = CookieStore(storage: storage);
      await store.restore();
      expect(store.length, 0);
    });

    test('无 storage：setCookies / restore 静默可用（纯内存模式）', () async {
      final store = CookieStore(); // 无 storage
      store.setCookies(Uri.parse('http://x.local/'), ['a=1; Path=/']);
      expect(store.cookieHeaderFor(Uri.parse('http://x.local/')), 'a=1');
      await store.restore(); // 不抛
      expect(store.length, 1);
    });

    test('含过期时间的 cookie 持久化往返：expires 保留且过期后不匹配', () async {
      final storage = InMemorySecureStorage();
      final store = CookieStore(storage: storage);
      store.setCookies(Uri.parse('http://x.local/'), [
        'a=1; Path=/; Max-Age=-1', // 立即可过期的 Max-Age
      ]);
      await Future<void>.delayed(Duration.zero);
      // 过期 → 内存中即不匹配
      expect(store.cookieHeaderFor(Uri.parse('http://x.local/')), isNull);
      final restored = CookieStore(storage: storage);
      await restored.restore();
      expect(restored.length, 1); // 数据仍在（过期由 matches 判断）
      expect(restored.cookieHeaderFor(Uri.parse('http://x.local/')), isNull);
    });
  });
}