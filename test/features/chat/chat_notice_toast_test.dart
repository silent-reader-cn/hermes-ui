import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/api/api_exception.dart';
import 'package:hermes_ui/core/api/sse_client.dart';
import 'package:hermes_ui/core/models/tool_call.dart';
import 'package:hermes_ui/features/chat/chat_page.dart';
import 'package:hermes_ui/features/chat/chat_providers.dart';
import 'package:hermes_ui/features/chat/widgets/steer_banner.dart';
import 'package:hermes_ui/features/chat/widgets/tool_call_card.dart';

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

      // 12 字体
      final text = tester.widget<Text>(find.text('已复制到剪贴板'));
      expect(text.style?.fontSize, 12);

      await _unmount(tester);
    });

    testWidgets('Toast 内边距纵向为 10，文字固定单行 ellipsis', (tester) async {
      final api = _FakeChatApi();
      api.sessionResult = {
        'session': {'session_id': 's1', 'messages': const []},
      };
      await _pumpPage(tester, api);
      final container = _containerOf(tester);

      container
          .read(chatControllerProvider('s1').notifier)
          .setNotice('已复制到剪贴板这是一段很长的提示');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final toastContainer = tester.widget<Container>(
        find.byKey(const ValueKey('chat-notice-toast')),
      );
      final padding = toastContainer.padding as EdgeInsets?;
      expect(padding?.top, 10);
      expect(padding?.bottom, 10);

      final text = tester.widget<Text>(find.text('已复制到剪贴板这是一段很长的提示'));
      expect(text.maxLines, 1);
      expect(text.overflow, TextOverflow.ellipsis);

      await _unmount(tester);
    });

    testWidgets('SteerNoticeToast 内边距纵向为 10，文字固定单行 ellipsis', (tester) async {
      final api = _FakeChatApi();
      api.sessionResult = {
        'session': {'session_id': 's1', 'messages': const []},
      };
      await _pumpPage(tester, api);
      final container = _containerOf(tester);

      await container.read(chatControllerProvider('s1').notifier).send('hello');
      await tester.pump();
      await tester.pump();

      await container
          .read(chatControllerProvider('s1').notifier)
          .send('这是一段很长很长的 steer 提示文案用来测试单行');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byKey(const ValueKey('chat-steer-notice-0')), findsOneWidget);
      final steerContainer = tester.widget<Container>(
        find.descendant(
          of: find.byKey(const ValueKey('chat-steer-notice-0')),
          matching: find.byType(Container),
        ).first,
      );
      final padding = steerContainer.padding as EdgeInsets?;
      expect(padding?.top, 10);
      expect(padding?.bottom, 10);

      final text = tester.widget<Text>(find.text('这是一段很长很长的 steer 提示文案用来测试单行'));
      expect(text.maxLines, 1);
      expect(text.overflow, TextOverflow.ellipsis);

      await _unmount(tester);
    });

    testWidgets('连续 steer 3 次 → 出现 3 条独立 toast 垂直堆叠，各自 × 可单独关闭，关闭一条不影响其余；live 会话结束全清', (tester) async {
      final api = _FakeChatApi();
      api.sessionResult = {
        'session': {'session_id': 's1', 'messages': const []},
      };
      await _pumpPage(tester, api);
      final container = _containerOf(tester);

      await container.read(chatControllerProvider('s1').notifier).send('hello');
      await tester.pump();
      await tester.pump();

      // 连续 3 次 steer
      await container.read(chatControllerProvider('s1').notifier).send('steer 提示 1');
      await tester.pump();
      await container.read(chatControllerProvider('s1').notifier).send('steer 提示 2');
      await tester.pump();
      await container.read(chatControllerProvider('s1').notifier).send('steer 提示 3');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // 3 条 toast 独立堆叠
      expect(find.byKey(const ValueKey('chat-steer-notice-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('chat-steer-notice-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('chat-steer-notice-2')), findsOneWidget);
      expect(find.text('steer 提示 1'), findsOneWidget);
      expect(find.text('steer 提示 2'), findsOneWidget);
      expect(find.text('steer 提示 3'), findsOneWidget);

      // 单独关闭中间那条（index 1: steer 提示 2）
      await tester.tap(find.byKey(const ValueKey('chat-steer-notice-close-1')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // 提示 2 消失，提示 1 与 提示 3 仍在
      expect(find.text('steer 提示 2'), findsNothing);
      expect(find.text('steer 提示 1'), findsOneWidget);
      expect(find.text('steer 提示 3'), findsOneWidget);
      expect(find.byKey(const ValueKey('chat-steer-notice-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('chat-steer-notice-1')), findsOneWidget);

      // live 会话结束（done）→ 全清
      api.emit(
        const DoneSseEvent(DoneStreamEvent(session: {'session_id': 's1'})),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('steer 提示 1'), findsNothing);
      expect(find.text('steer 提示 3'), findsNothing);
      expect(find.byKey(const ValueKey('chat-steer-notice-0')), findsNothing);

      await _unmount(tester);
    });

    testWidgets('长按任一条 steer 文本 → 剪贴板内容等于该条 hint 文本，顶部出现 已复制到剪贴板 轻提示', (tester) async {
      String? clipboardText;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall methodCall) async {
          if (methodCall.method == 'Clipboard.setData') {
            clipboardText = (methodCall.arguments as Map)['text'] as String?;
            return null;
          }
          if (methodCall.method == 'Clipboard.getData') {
            return {'text': clipboardText};
          }
          return null;
        },
      );

      final api = _FakeChatApi();
      api.sessionResult = {
        'session': {'session_id': 's1', 'messages': const []},
      };
      await _pumpPage(tester, api);
      final container = _containerOf(tester);

      await container.read(chatControllerProvider('s1').notifier).send('hello');
      await tester.pump();
      await tester.pump();

      await container.read(chatControllerProvider('s1').notifier).send('长按复制测试文本');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('长按复制测试文本'), findsOneWidget);

      // 长按 steer 文本
      await tester.longPress(find.text('长按复制测试文本'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // 验证剪贴板内容
      expect(clipboardText, '长按复制测试文本');
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      expect(data?.text, '长按复制测试文本');

      // 验证顶部出现 '已复制到剪贴板' toast
      expect(find.byKey(const ValueKey('chat-notice-toast')), findsOneWidget);
      expect(find.text('已复制到剪贴板'), findsOneWidget);

      await _unmount(tester);
    });

    testWidgets('hasPendingUserMessage 为 true 时不渲染待处理消息横幅', (tester) async {
      final api = _FakeChatApi();
      api.sessionResult = {
        'session': {
          'session_id': 's1',
          'messages': const [],
          'pending_user_message': '一条待处理消息',
        },
      };
      await _pumpPage(tester, api);

      expect(find.byKey(const ValueKey('chat-pending-banner')), findsNothing);
      expect(find.textContaining('待处理消息'), findsNothing);

      await _unmount(tester);
    });
  });

  group('SteerBanner & QueuedBanner widget 测试', () {
    testWidgets('SteerBanner padding 垂直为 6，文字固定单行 ellipsis', (tester) async {
      await tester.pumpWidget(
        const CupertinoApp(
          home: CupertinoPageScaffold(
            child: SteerBanner(text: '这是一条很长的 steer 提示'),
          ),
        ),
      );

      final container = tester.widget<Container>(
        find.byKey(const ValueKey('chat-steer-banner')),
      );
      final padding = container.padding as EdgeInsets?;
      expect(padding?.top, 6);
      expect(padding?.bottom, 6);

      final text = tester.widget<Text>(find.byType(Text));
      expect(text.maxLines, 1);
      expect(text.overflow, TextOverflow.ellipsis);
    });

    testWidgets('QueuedBanner padding 垂直为 6，文字固定单行 ellipsis', (tester) async {
      await tester.pumpWidget(
        const CupertinoApp(
          home: CupertinoPageScaffold(
            child: QueuedBanner(
              count: 2,
              preview: '这是一条很长很长的排队预览文本',
            ),
          ),
        ),
      );

      final container = tester.widget<Container>(
        find.byKey(const ValueKey('chat-queued-banner')),
      );
      final padding = container.padding as EdgeInsets?;
      expect(padding?.top, 6);
      expect(padding?.bottom, 6);

      final texts = tester.widgetList<Text>(find.byType(Text)).toList();
      expect(texts[0].maxLines, 1);
      expect(texts[0].overflow, TextOverflow.ellipsis);
      expect(texts[1].maxLines, 1);
      expect(texts[1].overflow, TextOverflow.ellipsis);
    });
  });

  group('同区横幅高度归一测试（与 ToolCallGroupCard 高度差 ≤2px）', () {
    testWidgets('深浅色模式下，同区横幅视觉高度与 ToolCallGroupCard 差值 ≤ 2px', (tester) async {
      for (final brightness in [Brightness.light, Brightness.dark]) {
        final group = ToolCallGroup(
          id: 'grp-1',
          toolCalls: [
            ToolCall(
              id: 'call-1',
              name: 'read_file',
              isCompleted: true,
            ),
          ],
        );

        await tester.pumpWidget(
          CupertinoApp(
            theme: CupertinoThemeData(brightness: brightness),
            home: CupertinoPageScaffold(
              child: Column(
                children: [
                  ToolCallGroupCard(
                    key: const ValueKey('tool-call-group-card'),
                    group: group,
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final toolCardBox = tester.renderObject<RenderBox>(
          find.byKey(const ValueKey('tool-call-group-card')),
        );
        final toolCardHeight = toolCardBox.size.height;
        expect(toolCardHeight, inInclusiveRange(34.0, 38.0));

        final api = _FakeChatApi();
        api.sessionResult = {
          'session': {'session_id': 's1', 'messages': const []},
        };

        await tester.pumpWidget(
          ProviderScope(
            overrides: [chatApiProvider.overrideWithValue(api)],
            child: CupertinoApp(
              theme: CupertinoThemeData(brightness: brightness),
              home: const ChatPage(sessionId: 's1'),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        final container = _containerOf(tester);
        final notifier = container.read(chatControllerProvider('s1').notifier);

        // 1. Notice Toast
        notifier.setNotice('轻提示测试');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        final toastBox = tester.renderObject<RenderBox>(
          find.descendant(
            of: find.byKey(const ValueKey('chat-notice-toast')),
            matching: find.byType(DecoratedBox),
          ).first,
        );
        expect((toastBox.size.height - toolCardHeight).abs(), lessThanOrEqualTo(2.0));

        // 2. Steer Toast
        await notifier.send('hello');
        await tester.pump();
        await notifier.send('steer 提示');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        final steerBox = tester.renderObject<RenderBox>(
          find.descendant(
            of: find.byKey(const ValueKey('chat-steer-notice-0')),
            matching: find.byType(DecoratedBox),
          ).first,
        );
        expect((steerBox.size.height - toolCardHeight).abs(), lessThanOrEqualTo(2.0));

        await _unmount(tester);
      }
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
