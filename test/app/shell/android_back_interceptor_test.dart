import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/app/shell/android_back_interceptor.dart';

void main() {
  setUp(() {
    AndroidBackInterceptorRegistry.debugReset();
  });

  group('AndroidBackInterceptorRegistry', () {
    test('无处理器时 handle 返回 false（放行）', () {
      expect(AndroidBackInterceptorRegistry.handle(), isFalse);
    });

    test('处理器返回 true 时消费本次返回', () {
      AndroidBackInterceptorRegistry.register(() => true);
      expect(AndroidBackInterceptorRegistry.handle(), isTrue);
    });

    test('处理器返回 false 时放行', () {
      AndroidBackInterceptorRegistry.register(() => false);
      expect(AndroidBackInterceptorRegistry.handle(), isFalse);
    });

    test('LIFO：后注册的处理器优先询问', () {
      final order = <String>[];
      AndroidBackInterceptorRegistry.register(() {
        order.add('first');
        return false;
      });
      AndroidBackInterceptorRegistry.register(() {
        order.add('second');
        return true;
      });
      expect(AndroidBackInterceptorRegistry.handle(), isTrue);
      expect(order, ['second']);
    });

    test('前面处理器返回 false 时继续询问下一个', () {
      final order = <String>[];
      AndroidBackInterceptorRegistry.register(() {
        order.add('first');
        return true;
      });
      AndroidBackInterceptorRegistry.register(() {
        order.add('second');
        return false;
      });
      expect(AndroidBackInterceptorRegistry.handle(), isTrue);
      expect(order, ['second', 'first']);
    });

    test('unregister 移除处理器（未注册时静默忽略）', () {
      bool consume() => true;
      AndroidBackInterceptorRegistry.register(consume);
      AndroidBackInterceptorRegistry.unregister(consume);
      AndroidBackInterceptorRegistry.unregister(consume); // 重复注销不抛
      expect(AndroidBackInterceptorRegistry.handle(), isFalse);
    });

    test('dispose 期间遍历安全：处理器内注销自身不影响遍历', () {
      bool selfRemoving() {
        AndroidBackInterceptorRegistry.unregister(selfRemoving);
        return true;
      }

      AndroidBackInterceptorRegistry.register(selfRemoving);
      expect(AndroidBackInterceptorRegistry.handle(), isTrue);
      expect(AndroidBackInterceptorRegistry.handle(), isFalse);
    });
  });
}
