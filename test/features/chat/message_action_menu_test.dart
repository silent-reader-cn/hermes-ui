import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hermes_ui/app/widgets/adaptive_popover.dart';
import 'package:hermes_ui/core/models/chat_message.dart';
import 'package:hermes_ui/features/chat/chat_page.dart';
import 'package:hermes_ui/features/chat/chat_providers.dart';
import 'package:hermes_ui/features/chat/widgets/message_action_menu.dart';
import 'package:hermes_ui/features/chat/widgets/message_bubble.dart';

import '../../helpers/fake_chat_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    AdaptivePopover.debugReset();
  });

  Widget buildTestApp({
    required FakeChatApi api,
    required Size size,
    String sessionId = 's1',
  }) {
    final router = GoRouter(
      initialLocation: '/chat/$sessionId',
      routes: [
        GoRoute(
          path: '/chat/:id',
          builder: (context, state) => ChatPage(
            sessionId: state.pathParameters['id'] ?? sessionId,
          ),
        ),
      ],
    );
    return ProviderScope(
      overrides: [
        chatApiProvider.overrideWithValue(api),
      ],
      child: MediaQuery(
        data: MediaQueryData(size: size),
        child: CupertinoApp.router(
          routerConfig: router,
        ),
      ),
    );
  }

  Future<void> longPressBubble(WidgetTester tester, String text) async {
    final bubble = find
        .ancestor(of: find.text(text), matching: find.byType(ChatMessageBubble))
        .first;
    final rect = tester.getRect(bubble);
    await tester.longPressAt(rect.topLeft + const Offset(8, 8));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> secondaryTapBubble(WidgetTester tester, String text) async {
    final bubble = find
        .ancestor(of: find.text(text), matching: find.byType(ChatMessageBubble))
        .first;
    final rect = tester.getRect(bubble);
    await tester.tapAt(rect.topLeft + const Offset(8, 8), buttons: kSecondaryMouseButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  group('#78 宽屏悬浮面板 vs 窄屏 ActionSheet', () {
    testWidgets('宽屏（width >= 900）右键消息 → 弹出 CupertinoPopover 悬浮面板', (tester) async {
      final api = FakeChatApi();
      api.sessionResult = {
        'session': {
          'session_id': 's1',
          'messages': [
            {'role': 'user', 'content': '测试消息宽屏右键', 'message_id': 'm1'},
          ],
        },
      };

      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        buildTestApp(api: api, size: const Size(1200, 800)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      await secondaryTapBubble(tester, '测试消息宽屏右键');

      // 悬浮面板应当出现，且不弹出底部 ActionSheet
      expect(find.byType(CupertinoActionSheet), findsNothing);
      expect(AdaptivePopover.activeOverlayCount, 1);
      expect(find.byKey(const ValueKey('msg-action-copy')), findsOneWidget);
      expect(find.byKey(const ValueKey('msg-action-copy-md')), findsOneWidget);
      expect(find.byKey(const ValueKey('msg-action-edit')), findsOneWidget);
      expect(find.byKey(const ValueKey('msg-action-branch')), findsOneWidget);
      expect(find.byKey(const ValueKey('msg-action-truncate')), findsOneWidget);

      // 点击屏障外部关闭
      await tester.tapAt(const Offset(10, 10));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(AdaptivePopover.activeOverlayCount, 0);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('窄屏（width < 900）长按消息 → 弹出 CupertinoActionSheet 底部操作表', (tester) async {
      final api = FakeChatApi();
      api.sessionResult = {
        'session': {
          'session_id': 's1',
          'messages': [
            {'role': 'user', 'content': '测试消息窄屏长按', 'message_id': 'm1'},
          ],
        },
      };

      tester.view.physicalSize = const Size(600, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        buildTestApp(api: api, size: const Size(600, 800)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      await longPressBubble(tester, '测试消息窄屏长按');

      // 窄屏应弹出 CupertinoActionSheet
      expect(find.byType(CupertinoActionSheet), findsOneWidget);
      expect(AdaptivePopover.activeOverlayCount, 0);
      expect(find.byKey(const ValueKey('msg-action-cancel')), findsOneWidget);

      // 取消关闭
      await tester.tap(find.byKey(const ValueKey('msg-action-cancel')));
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoActionSheet), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('宽屏右键靠近右下屏缘 → 自动向上翻转且不溢出屏幕右缘', (tester) async {
      tester.view.physicalSize = const Size(1000, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      late BuildContext savedContext;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(1000, 600)),
          child: CupertinoApp(
            home: Builder(
              builder: (ctx) {
                savedContext = ctx;
                return const CupertinoPageScaffold(child: SizedBox.expand());
              },
            ),
          ),
        ),
      );
      await tester.pump();

      // 在靠近右下角（950, 550）处触发 showMessageActionMenu
      const testMsg = ChatMessage(
        messageId: 'test-1',
        role: 'user',
        content: '屏缘测试消息',
      );
      unawaited(
        showMessageActionMenu(
          savedContext,
          message: testMsg,
          position: const Offset(950, 550),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(AdaptivePopover.activeOverlayCount, 1);
      final copyItem = find.byKey(const ValueKey('msg-action-copy'));
      expect(copyItem, findsOneWidget);

      // 验证没有越界到右侧或底部之外（且翻转到 550 上方）
      final itemRect = tester.getRect(copyItem);
      expect(itemRect.right, lessThanOrEqualTo(1000.0));
      expect(itemRect.top, lessThan(550.0), reason: '底部空间不足应翻转至点击位置上方');

      // 点击关闭
      await tester.tapAt(const Offset(10, 10));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  });

  group('#79 截断与分支静默 no-op 修复（合成 ID 消息）', () {
    testWidgets('无 messageId（合成 id）消息通过直传索引成功截断', (tester) async {
      final api = FakeChatApi();
      // 模拟无 message_id 的消息（例如来自不同来源或合成 id）
      api.sessionResult = {
        'session': {
          'session_id': 's1',
          'messages': [
            {'role': 'user', 'content': '合成消息 1', 'message_id': null},
            {'role': 'assistant', 'content': '回复 1', 'message_id': null},
          ],
        },
      };

      tester.view.physicalSize = const Size(600, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        buildTestApp(api: api, size: const Size(600, 800)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // 长按第 1 条消息
      await longPressBubble(tester, '合成消息 1');

      // 点击截断
      await tester.tap(find.byKey(const ValueKey('msg-action-truncate')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // 确认对话框
      expect(find.byKey(const ValueKey('msg-truncate-confirm')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('msg-truncate-confirm')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // 验证 truncateSession 成功被调用且 keepCount=1（第0条保留）
      expect(api.truncateCalls, 1);
      expect(api.truncateKeepCounts, [1]);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('无 messageId（合成 id）消息通过直传索引成功创建分支', (tester) async {
      final api = FakeChatApi();
      api.sessionResult = {
        'session': {
          'session_id': 's1',
          'messages': [
            {'role': 'user', 'content': '合成消息 1', 'message_id': null},
            {'role': 'assistant', 'content': '回复 1', 'message_id': null},
          ],
        },
      };

      tester.view.physicalSize = const Size(600, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        buildTestApp(api: api, size: const Size(600, 800)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      await longPressBubble(tester, '合成消息 1');

      // 点击分支
      await tester.tap(find.byKey(const ValueKey('msg-action-branch')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // 验证 branchSession 成功被调用且 keepCount=1
      expect(api.branchCalls, 1);
      expect(api.lastBranchKeepCount, 1);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  });

  group('#80 编辑并重新发送截断语义（对齐 WebUI submitEdit）', () {
    testWidgets('编辑第 1 条消息（非首条）→ keepCount=1（不含该消息自身及其后全部）', (tester) async {
      final api = FakeChatApi();
      api.sessionResult = {
        'session': {
          'session_id': 's1',
          'messages': [
            {'role': 'user', 'content': '保留的第0条', 'message_id': 'm0'},
            {'role': 'assistant', 'content': '保留的助手回复', 'message_id': 'm1'},
            {'role': 'user', 'content': '将被编辑的第2条', 'message_id': 'm2'},
            {'role': 'assistant', 'content': '将被删除的后续回复', 'message_id': 'm3'},
          ],
        },
      };

      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        buildTestApp(api: api, size: const Size(1200, 800)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // 右键点击第三条消息（user, index=2）
      await secondaryTapBubble(tester, '将被编辑的第2条');

      // 点击编辑并重新发送
      await tester.tap(find.byKey(const ValueKey('msg-action-edit')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // 验证 truncateSession 调用的 keepCount=2（保留 index 0,1，删除 index 2 自身及其后）
      expect(api.truncateCalls, 1);
      expect(api.truncateKeepCounts, [2]);

      // 验证输入框已被预填
      final field = tester.widget<CupertinoTextField>(
        find.byKey(const ValueKey('chat-input-field')),
      );
      expect(field.controller!.text, '将被编辑的第2条');

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('宽屏悬浮面板中的 truncate 确认流程工作正常', (tester) async {
      final api = FakeChatApi();
      api.sessionResult = {
        'session': {
          'session_id': 's1',
          'messages': [
            {'role': 'user', 'content': '消息1', 'message_id': 'm1'},
            {'role': 'assistant', 'content': '回复1', 'message_id': 'm2'},
          ],
        },
      };

      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        buildTestApp(api: api, size: const Size(1200, 800)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // 宽屏右键第一条消息
      await secondaryTapBubble(tester, '消息1');

      // 点击截断
      await tester.tap(find.byKey(const ValueKey('msg-action-truncate')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // 确认对话框弹出
      expect(find.byKey(const ValueKey('msg-truncate-confirm')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('msg-truncate-confirm')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(api.truncateCalls, 1);
      expect(api.truncateKeepCounts, [1]);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  });
}
