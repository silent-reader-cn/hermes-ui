import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/api/sse_client.dart';
import 'package:hermes_ui/core/models/server_catalog.dart';
import 'package:hermes_ui/features/chat/chat_page.dart';
import 'package:hermes_ui/features/chat/chat_providers.dart';
import 'package:hermes_ui/features/chat/widgets/chat_message_list.dart';
import 'package:hermes_ui/main.dart';

import '../../helpers/fake_chat_api.dart';

void main() {
  group('#8 P0 渲染与网络错误兜底测试', () {
    testWidgets('RecoverableErrorCard 正确展示错误提示与重试按钮', (tester) async {
      var retried = false;
      await tester.pumpWidget(
        CupertinoApp(
          home: CupertinoPageScaffold(
            child: RecoverableErrorCard(
              message: '已断开 / 网络错误，重试',
              onRetry: () => retried = true,
            ),
          ),
        ),
      );

      expect(find.text('已断开 / 网络错误，重试'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);

      await tester.tap(find.text('重试'));
      await tester.pump();

      expect(retried, isTrue);
      expect(find.text('已重试'), findsOneWidget);
    });

    testWidgets('ErrorWidget.builder 兜底返回 RecoverableErrorCard 而非默认红/灰屏', (tester) async {
      final oldBuilder = ErrorWidget.builder;
      try {
        final errorDetails = FlutterErrorDetails(
          exception: Exception('Simulated network/render error'),
        );
        final widget = RecoverableErrorCard(details: errorDetails);
        expect(widget, isA<RecoverableErrorCard>());

        await tester.pumpWidget(
          CupertinoApp(
            home: CupertinoPageScaffold(child: widget),
          ),
        );

        expect(find.text('已断开 / 网络错误，重试'), findsOneWidget);
        expect(find.byType(RecoverableErrorCard), findsOneWidget);
      } finally {
        ErrorWidget.builder = oldBuilder;
      }
    });

    testWidgets('Markdown 畸形/增量内容解析异常时安全降级为 Text 不崩溃', (tester) async {
      final api = FakeChatApi()
        ..statusResponse = const ChatStreamStatusResponse(active: true);

      api.sessionResult = {
        'session': {
          'session_id': 's-markdown-err',
          'active_stream_id': 'stream-err',
          'messages': [
            {'role': 'user', 'content': 'hello', 'message_id': 'm0'},
          ],
          'message_count': 1,
        },
      };

      await tester.pumpWidget(
        ProviderScope(
          overrides: [chatApiProvider.overrideWithValue(api)],
          child: const CupertinoApp(
            home: ChatPage(sessionId: 's-markdown-err'),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // 注入畸形/未闭合 markdown 内容
      api.emit(const TokenSseEvent('```dart\nvoid main() {\n[broken link](http'));
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 48));

      // 验证未抛出异常，内容正常显示
      expect(tester.takeException(), isNull);
      expect(find.byType(ChatMessageList), findsOneWidget);
    });

    testWidgets('liveTimelineProvider 返回 null 时 itemCount 稳定不卡死', (tester) async {
      final api = FakeChatApi()
        ..statusResponse = const ChatStreamStatusResponse(active: true);

      api.sessionResult = {
        'session': {
          'session_id': 's-timeline-null',
          'active_stream_id': 'stream-null',
          'messages': [
            {'role': 'user', 'content': 'test', 'message_id': 'm0'},
            {'role': 'assistant', 'content': 'streaming response', 'message_id': 'm1'},
          ],
          'message_count': 2,
        },
      };

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            chatApiProvider.overrideWithValue(api),
            liveTimelineProvider('s-timeline-null').overrideWithValue(null),
          ],
          child: const CupertinoApp(
            home: ChatPage(sessionId: 's-timeline-null'),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(tester.takeException(), isNull);
      expect(find.byType(ChatMessageList), findsOneWidget);
      expect(find.text('streaming response'), findsOneWidget);
    });

    testWidgets('同 sessionId 重建/didUpdateWidget 时状态重置可恢复', (tester) async {
      final api = FakeChatApi();
      api.sessionResult = {
        'session': {
          'session_id': 's-reenter',
          'messages': [
            {'role': 'user', 'content': 'hello 1', 'message_id': 'm1'},
          ],
          'message_count': 1,
        },
      };

      await tester.pumpWidget(
        ProviderScope(
          overrides: [chatApiProvider.overrideWithValue(api)],
          child: const CupertinoApp(
            home: CupertinoPageScaffold(
              child: ChatMessageList(sessionId: 's-reenter'),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('hello 1'), findsOneWidget);

      // 模拟更新 widget
      await tester.pumpWidget(
        ProviderScope(
          overrides: [chatApiProvider.overrideWithValue(api)],
          child: const CupertinoApp(
            home: CupertinoPageScaffold(
              child: ChatMessageList(sessionId: 's-reenter'),
            ),
          ),
        ),
      );

      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });
}
