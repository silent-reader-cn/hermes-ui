import 'package:flutter_test/flutter_test.dart';

import 'package:hermes_ui/app/deep_link.dart';

void main() {
  group('resolveInitialRoute', () {
    test('空/默认值回退根路径', () {
      expect(resolveInitialRoute(''), '/');
      expect(resolveInitialRoute('/'), '/');
    });

    test('scheme 深链：hermes://chat/<id> → /chat/<id>', () {
      expect(resolveInitialRoute('hermes://chat/abc123'), '/chat/abc123');
    });

    test('scheme 深链带 host：hermes://chat/abc?q=1 → /chat/abc', () {
      expect(resolveInitialRoute('hermes://chat/abc?q=1'), '/chat/abc');
    });

    test('scheme 深链带 fragment', () {
      expect(resolveInitialRoute('hermes://workspace/ws1#top'), '/workspace/ws1');
    });

    test('无 scheme 直接路径（Android intent 形态）', () {
      expect(resolveInitialRoute('/chat/xyz'), '/chat/xyz');
      expect(resolveInitialRoute('chat/xyz'), '/chat/xyz');
    });

    test('已知路由保留', () {
      expect(resolveInitialRoute('hermes://settings'), '/settings');
      expect(resolveInitialRoute('hermes://git/sess-1'), '/git/sess-1');
      expect(resolveInitialRoute('hermes://chat'), '/chat');
      expect(resolveInitialRoute('hermes://'), '/');
    });

    test('未知路径/未知 scheme 回退根路径', () {
      expect(resolveInitialRoute('hermes://evil/path'), '/');
      expect(resolveInitialRoute('https://example.com/chat/1'), '/');
    });

    test('多余斜杠收敛', () {
      expect(resolveInitialRoute('hermes:////chat///abc'), '/chat/abc');
      expect(resolveInitialRoute('hermes://chat//double'), '/chat/double');
    });
  });
}