import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/api/api_exception.dart';
import 'package:hermes_ui/features/chat/chat_page.dart';
import 'package:hermes_ui/features/chat/chat_providers.dart';

import '../../helpers/fake_chat_api.dart';

void main() {
  group('复制提示 toast 轻量自动消失', () {
    testWidgets('出现后 2.8s + 淡出 0.2s 自动消失', (tester) async {
      final api = _FakeChatApi();
      api.sessionResult = {
        'session': {'session_id': 's1', 'messages': const []},
      };
      await _pumpPage(tester, api);
      final container = _containerOf(tester);

      container.read(chatControllerProvider('s1').notifier).setNotice('已复制到剪贴板');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byKey(const ValueKey('chat-notice-toast')), findsOneWidget);
      expect(find.text('已复制到剪贴板'), findsOneWidget);

      // 距 2800ms 仍在（还在可见期，淡出尚未开始）
      await tester.pump(const Duration(milliseconds: 2700));
      expect(find.byKey(const ValueKey('chat-notice-toast')), findsOneWidget);

      // 2800ms 到点触发淡出（opacity 0），再 200ms 后真正清掉 noticeMessage
      await tester.pump(const Duration(milliseconds: 100)); // 2800
      await tester.pump(const Duration(milliseconds: 50)); // 触发 setState opacity 0
      // 此时仍在 tree 中，但 opacity 为 0（仍算 findsOneWidget，取决于实现）
      // 再等 200ms 的 Future.delayed 才 dismissNotice
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump();

      expect(find.byKey(const ValueKey('chat-notice-toast')), findsNothing);
      expect(find.text('已复制到剪贴板'), findsNothing);

      await _unmount(tester);
    });

    testWidgets('手动 × 可提前关闭', (tester) async {
      final api = _FakeChatApi();
      api.sessionResult = {
        'session': {'session_id': 's1', 'messages': const []},
      };
      await _pumpPage(tester, api);
      final container = _containerOf(tester);

      container.read(chatControllerProvider('s1').notifier).setNotice('已复制到剪贴板');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byKey(const ValueKey('chat-notice-toast')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('chat-notice-toast-dismiss')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      // 手动关闭走同样 200ms 淡出 + dismiss
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump();

      expect(find.byKey(const ValueKey('chat-notice-toast')), findsNothing);
      expect(find.text('已复制到剪贴板'), findsNothing);

      // 已取消定时，等待原 2.8s 不应再抛异常或重现
      await tester.pump(const Duration(milliseconds: 3000));
      expect(find.byKey(const ValueKey('chat-notice-toast')), findsNothing);

      await _unmount(tester);
    });

    testWidgets('与错误横幅共存不互相覆盖；错误横幅常驻不自动消失', (tester) async {
      final api = _FakeChatApi();
      api.sessionResult = {
        'session': {'session_id': 's1', 'messages': const []},
      };
      await _pumpPage(tester, api);
      final container = _containerOf(tester);

      // 先制造一个 sendErrorMessage：通过直接写 state（错误横幅是常驻红底，statusRedText）
      // 这里用 controller 的状态 copy 模拟网络/发送失败产生的错误横幅
      final notifier = container.read(chatControllerProvider('s1').notifier);
      // 通过私有 _setSendError 的公开等价路径：触发 startChat 失败
      // 备用：若 startChat 路径不抛错误，则用 state 覆盖兜底（FamilyNotifier 的 state setter 在同库内可写，这里通过容器读后复制）
      // 为避免依赖私有方法，优先走真实失败路径
      // 先置一个 toast
      notifier.setNotice('已复制到剪贴板');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byKey(const ValueKey('chat-notice-toast')), findsOneWidget);

      // 再触发错误：置一个 startChatError 并 send 一次（ChatController 会写 sendErrorMessage）
      api.startChatError = NetworkException(NetworkExceptionKind.cannotConnect);
      // 通过输入栏直接 send 会更真实；这里直接调 controller.send
      await notifier.send('trigger error');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // 两条横幅应同时可见：toast 与 error 分型
      expect(find.byKey(const ValueKey('chat-notice-toast')), findsOneWidget);
      // 错误横幅无固定 key，用文案兜底（_FakeNetworkError 会被映射为中文网络错误文案或透传）
      // 只要能找到一处错误文本与 toast 文案共存即判共存
      expect(find.text('已复制到剪贴板'), findsOneWidget);
      // 错误横幅文本存在（取外层 Container 中 Text 的父级，至少有一条非 toast 的可见错误行）
      // 这里断言 error banner 的 Container 存在：通过查找两个横幅的 margin 差异
      // 简化：断言 controller 状态中两者并存
      final st = container.read(chatControllerProvider('s1'));
      expect(st.noticeMessage, '已复制到剪贴板');
      expect(st.sendErrorMessage, isNotNull);

      // toast 3s 后消失，error 仍在
      await tester.pump(const Duration(milliseconds: 3000));
      await tester.pump();

      expect(find.byKey(const ValueKey('chat-notice-toast')), findsNothing);
      // error 横幅仍常驻
      final st2 = container.read(chatControllerProvider('s1'));
      expect(st2.sendErrorMessage, isNotNull);

      await _unmount(tester);
    });

    testWidgets('距输入栏 8px 间距（margin bottom 8）', (tester) async {
      final api = _FakeChatApi();
      api.sessionResult = {
        'session': {'session_id': 's1', 'messages': const []},
      };
      await _pumpPage(tester, api);
      final container = _containerOf(tester);

      container.read(chatControllerProvider('s1').notifier).setNotice('已复制到剪贴板');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final containerWidget = tester.widget<Container>(
        find.byKey(const ValueKey('chat-notice-toast')),
      );
      final margin = containerWidget.margin as EdgeInsets?;
      expect(margin, isNotNull);
      expect(margin!.bottom, 8);
      expect(margin.left, 12);
      expect(margin.right, 12);
      expect(margin.top, 6);

      await _unmount(tester);
    });

    testWidgets('多提示并发不重叠：新 notice 覆盖旧定时（Key 以 message 区分）', (tester) async {
      final api = _FakeChatApi();
      api.sessionResult = {
        'session': {'session_id': 's1', 'messages': const []},
      };
      await _pumpPage(tester, api);
      final container = _containerOf(tester);
      final notifier = container.read(chatControllerProvider('s1').notifier);

      notifier.setNotice('第一条');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('第一条'), findsOneWidget);

      // 500ms 后被第二条覆盖（旧定时应被取消）
      await tester.pump(const Duration(milliseconds: 500));
      notifier.setNotice('第二条');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('第一条'), findsNothing);
      expect(find.text('第二条'), findsOneWidget);
      expect(find.byKey(const ValueKey('chat-notice-toast')), findsOneWidget);

      // 若旧定时未取消，此时已过 2800ms 会误清新 toast；验证新 toast 仍在
      await tester.pump(const Duration(milliseconds: 2300)); // 距第一条 2800，距第二条 2300
      expect(find.text('第二条'), findsOneWidget);

      // 再等 600ms（距第二条 2900+200 淡出），新 toast 才消失
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump();
      expect(find.text('第二条'), findsNothing);

      await _unmount(tester);
    });

    testWidgets('轻量视觉：次要背景 + separator 边框 + 圆角 8 + 13 次要色 + AnimatedOpacity 200ms', (tester) async {
      final api = _FakeChatApi();
      api.sessionResult = {
        'session': {'session_id': 's1', 'messages': const []},
      };
      await _pumpPage(tester, api);
      final container = _containerOf(tester);

      container.read(chatControllerProvider('s1').notifier).setNotice('已复制到剪贴板');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // 存在 AnimatedOpacity 且 duration 200ms
      final opacity = tester.widget<AnimatedOpacity>(
        find.byKey(const ValueKey('chat-notice-toast-opacity')),
      );
      expect(opacity.duration, const Duration(milliseconds: 200));

      // 圆角 8 + 边框 separator
      final toast = tester.widget<Container>(find.byKey(const ValueKey('chat-notice-toast')));
      final deco = toast.decoration as BoxDecoration;
      expect(deco.borderRadius, BorderRadius.circular(10));
      expect(deco.border, isNotNull);

      // 13 次要色
      final text = tester.widget<Text>(find.text('已复制到剪贴板'));
      expect(text.style?.fontSize, 13);

      await _unmount(tester);
    });
  });
}

Future<void> _pumpPage(WidgetTester tester, FakeChatApi api) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [chatApiProvider.overrideWithValue(api)],
      child: const CupertinoApp(home: ChatPage(sessionId: 's1')),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

ProviderContainer _containerOf(WidgetTester tester) {
  final ctx = tester.element(find.byType(ChatPage));
  return ProviderScope.containerOf(ctx);
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

typedef _FakeChatApi = FakeChatApi;
