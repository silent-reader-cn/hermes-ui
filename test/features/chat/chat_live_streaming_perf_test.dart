import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/api/sse_client.dart';
import 'package:hermes_ui/core/cache/app_database.dart';
import 'package:hermes_ui/core/cache/cache_providers.dart';
import 'package:hermes_ui/core/cache/cache_service.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/connections/connection_store.dart';
import 'package:hermes_ui/core/models/server_catalog.dart';
import 'package:hermes_ui/features/chat/chat_page.dart';
import 'package:hermes_ui/features/chat/chat_providers.dart';

import '../../helpers/fake_chat_api.dart';
import '../../helpers/in_memory_secure_storage.dart';

class _NoopCacheService extends CacheService {
  _NoopCacheService(super.db);
  @override
  Future<void> writeMessages({
    required String sessionId,
    required List<Map<String, Object?>> messages,
  }) async {}

  @override
  Future<List<Map<String, Object?>>> readMessages(String sessionId) async =>
      const [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Phase B: 流式增量渲染与整表去重建测试', () {
    testWidgets(
      '流式 tick 期间不构建 MarkdownBody（走轻量 Text），done 后转正构建 MarkdownBody',
      (tester) async {
        final api = FakeChatApi()
          ..statusResponse = const ChatStreamStatusResponse(active: true);

        api.sessionResult = {
          'session': {
            'session_id': 's-perf-stream',
            'active_stream_id': 'stream-perf-1',
            'messages': [
              {
                'role': 'user',
                'content': 'Hello, tell me a formatted story.',
                'message_id': 'u1',
              },
            ],
            'message_count': 1,
          },
        };

        await tester.pumpWidget(
          ProviderScope(
            overrides: [chatApiProvider.overrideWithValue(api)],
            child: const CupertinoApp(
              home: ChatPage(sessionId: 's-perf-stream'),
            ),
          ),
        );

        await tester.pumpAndSettle();

        // 历史 user 消息渲染完成
        expect(find.text('Hello, tell me a formatted story.'), findsOneWidget);

        // 推送带有 Markdown 格式的 token
        api.emit(const TokenSseEvent('**Bold Story** with `code snippet`\n'));
        await tester.pump(const Duration(milliseconds: 16));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump();

        // 验证：在流式过程中，流式气泡走轻量文本渲染，不构建 MarkdownBody
        expect(find.byType(MarkdownBody), findsNothing);
        expect(
          find.textContaining('**Bold Story** with `code snippet`'),
          findsOneWidget,
        );

        // 继续推送更多 token
        api.emit(const TokenSseEvent('Second line of the story.\n'));
        await tester.pump(const Duration(milliseconds: 16));
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump();

        expect(find.byType(MarkdownBody), findsNothing);
        expect(
          find.textContaining('Second line of the story.'),
          findsOneWidget,
        );

        // 发送 done 事件，结束流
        api.emit(
          const DoneSseEvent(
            DoneStreamEvent(
              session: {
                'session_id': 's-perf-stream',
                'messages': [
                  {
                    'role': 'user',
                    'content': 'Hello, tell me a formatted story.',
                    'message_id': 'u1',
                  },
                  {
                    'role': 'assistant',
                    'content': '**Bold Story** with `code snippet`\nSecond line of the story.\n',
                    'message_id': 'a1',
                  },
                ],
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 验证：done 收尾后转入 transcript，完整构建 MarkdownBody 呈现富文本
        expect(find.byType(MarkdownBody), findsOneWidget);
      },
    );

    test('流式 token reveal 期间 transcriptMessagesProvider 保持列表实例引用不变', () {
      fakeAsync((async) {
        final api = FakeChatApi();
        final db = AppDatabase.memory();
        final container = ProviderContainer(
          overrides: [
            chatApiProvider.overrideWithValue(api),
            appDatabaseProvider.overrideWithValue(db),
            cacheServiceProvider.overrideWithValue(_NoopCacheService(db)),
            connectionStoreProvider.overrideWithValue(
              ConnectionStore(storage: InMemorySecureStorage()),
            ),
          ],
        );
        addTearDown(() {
          container.dispose();
          unawaited(db.close());
        });

        final controller = container.read(
          chatControllerProvider('s-cache').notifier,
        );
        unawaited(controller.send('Hello'));
        async.flushMicrotasks();

        // 第一次读取 transcript
        final initialTranscript = container.read(
          transcriptMessagesProvider('s-cache'),
        );
        expect(initialTranscript.length, 1); // user 消息

        // 连续收到 10 个 token
        for (var i = 0; i < 10; i++) {
          api.emit(TokenSseEvent('token$i '));
          async.elapse(const Duration(milliseconds: 16));
          async.elapse(const Duration(milliseconds: 48));

          final currentTranscript = container.read(
            transcriptMessagesProvider('s-cache'),
          );
          expect(
            identical(initialTranscript, currentTranscript),
            isTrue,
            reason: 'token $i: transcript 列表实例必须保持恒等，避免整表重建',
          );
        }
      });
    });
  });
}
