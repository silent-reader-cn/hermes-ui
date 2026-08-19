import 'package:flutter_test/flutter_test.dart';

import 'package:hermex_flutter/app/deep_link.dart';

void main() {
  group('resolveInitialRoute', () {
    test('空/默认值回退根路径', () {
      expect(resolveInitialRoute(''), '/');
      expect(resolveInitialRoute('/'), '/');
    });

    test('scheme 深链：hermex://chat/<id> → /chat/<id>', () {
      expect(resolveInitialRoute('hermex://chat/abc123'), '/chat/abc123');
    });

    test('scheme 深链带 host：hermex://chat/abc?q=1 → /chat/abc', () {
      expect(resolveInitialRoute('hermex://chat/abc?q=1'), '/chat/abc');
    });

    test('scheme 深链带 fragment', () {
      expect(resolveInitialRoute('hermex://workspace/ws1#top'), '/workspace/ws1');
    });

    test('无 scheme 直接路径（Android intent 形态）', () {
      expect(resolveInitialRoute('/chat/xyz'), '/chat/xyz');
      expect(resolveInitialRoute('chat/xyz'), '/chat/xyz');
    });

    test('已知路由保留', () {
      expect(resolveInitialRoute('hermex://settings'), '/settings');
      expect(resolveInitialRoute('hermex://git/sess-1'), '/git/sess-1');
      expect(resolveInitialRoute('hermex://chat'), '/chat');
      expect(resolveInitialRoute('hermex://'), '/');
    });

    test('未知路径/未知 scheme 回退根路径', () {
      expect(resolveInitialRoute('hermex://evil/path'), '/');
      expect(resolveInitialRoute('https://example.com/chat/1'), '/');
    });

    test('多余斜杠收敛', () {
      expect(resolveInitialRoute('hermex:////chat///abc'), '/chat/abc');
      expect(resolveInitialRoute('hermex://chat//double'), '/chat/double');
    });
  });
}