import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hermex_flutter/core/api/sse_client.dart';
import 'package:hermex_flutter/features/chat/chat_page.dart';
import 'package:hermex_flutter/features/chat/chat_providers.dart';
import 'package:hermex_flutter/features/chat/chat_server_api.dart';
import 'package:hermex_flutter/features/chat/widgets/message_highlight.dart';

/// 搜索结果定位（深链 /chat/:id?q=&match=）与分支关系展示。
void main() {
  group('搜索定位（深链）', () {
    testWidgets('match=content 命中 → 目标消息高亮出现且不抛错', (tester) async {
      final api = _FakeChatApi();
      api.sessionResult = {
        'session': {
          'session_id': 's1',
          'messages': [
            {'role': 'user', 'content': '第一句话不匹配', 'message_id': 'm1'},
            {'role': 'assistant', 'content': '这里提到了关键词喵', 'message_id': 'm2'},
            {'role': 'user', 'content': '最后一句话', 'message_id': 'm3'},
          ],
        },
      };
      final router = GoRouter(
        initialLocation: '/chat/s1?q=关键词&match=content',
        routes: [
          GoRoute(
            path: '/chat/:id',
            builder: (context, state) => ChatPage(
              sessionId: state.pathParameters['id']!,
              searchQuery: state.uri.queryParameters['q'],
              matchType: state.uri.queryParameters['match'],
            ),
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [chatApiProvider.overrideWithValue(api)],
          child: CupertinoApp.router(routerConfig: router),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 400));

      // 目标消息高亮包裹（FadeTransition 动画中）
      expect(find.byType(SearchMessageHighlight), findsWidgets);
      // 页面正常渲染
      expect(find.text('第一句话不匹配'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('match=content 无命中 → 静默，无异常无高亮', (tester) async {
      final api = _FakeChatApi();
      api.sessionResult = {
        'session': {
          'session_id': 's1',
          'messages': [
            {'role': 'user', 'content': '普通内容', 'message_id': 'm1'},
          ],
        },
      };
      final router = GoRouter(
        initialLocation: '/chat/s1?q=不存在的词&match=content',
        routes: [
          GoRoute(
            path: '/chat/:id',
            builder: (context, state) => ChatPage(
              sessionId: state.pathParameters['id']!,
              searchQuery: state.uri.queryParameters['q'],
              matchType: state.uri.queryParameters['match'],
            ),
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [chatApiProvider.overrideWithValue(api)],
          child: CupertinoApp.router(routerConfig: router),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.takeException(), isNull);
      expect(find.text('普通内容'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('match=title → 打开会话但不触发内容定位', (tester) async {
      final api = _FakeChatApi();
      api.sessionResult = {
        'session': {
          'session_id': 's1',
          'title': '标题命中会话',
          'messages': [
            {'role': 'user', 'content': '内容不相关', 'message_id': 'm1'},
          ],
        },
      };
      final router = GoRouter(
        initialLocation: '/chat/s1?q=标题命中&match=title',
        routes: [
          GoRoute(
            path: '/chat/:id',
            builder: (context, state) => ChatPage(
              sessionId: state.pathParameters['id']!,
              searchQuery: state.uri.queryParameters['q'],
              matchType: state.uri.queryParameters['match'],
            ),
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [chatApiProvider.overrideWithValue(api)],
          child: CupertinoApp.router(routerConfig: router),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // 无高亮包裹（title 命中不定位）
      final highlighted = tester
          .widgetList<SearchMessageHighlight>(find.byType(SearchMessageHighlight))
          .where((w) => w.highlight)
          .length;
      expect(highlighted, 0);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  });

  group('分支关系展示', () {
    testWidgets('parent_session_id 非空 → 分支 badge 显示；点击弹对话框；跳转父会话', (tester) async {
      final api = _FakeChatApi();
      api.sessionResult = {
        'session': {
          'session_id': 's1',
          'title': '分支会话标题',
          'parent_session_id': 'parent-1',
          'messages': [
            {'role': 'user', 'content': '内容', 'message_id': 'm1'},
          ],
        },
      };
      final router = GoRouter(
        initialLocation: '/chat/s1',
        routes: [
          GoRoute(
            path: '/chat/:id',
            builder: (context, state) => ChatPage(
              sessionId: state.pathParameters['id']!,
            ),
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [chatApiProvider.overrideWithValue(api)],
          child: CupertinoApp.router(routerConfig: router),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // badge 出现
      expect(find.byKey(const ValueKey('chat-branch-badge')), findsOneWidget);

      // 点击 → 对话框
      await tester.tap(find.byKey(const ValueKey('chat-branch-badge')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.byKey(const ValueKey('chat-branch-dialog')),
        findsOneWidget,
      );

      // 跳转父会话 → 路由变化
      await tester.tap(find.byKey(const ValueKey('chat-goto-parent')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        router.routeInformationProvider.value.uri.path,
        '/chat/parent-1',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('无 parent_session_id → 不显示分支 badge', (tester) async {
      final api = _FakeChatApi();
      api.sessionResult = {
        'session': {
          'session_id': 's1',
          'title': '普通会话',
          'messages': [
            {'role': 'user', 'content': '内容', 'message_id': 'm1'},
          ],
        },
      };
      await tester.pumpWidget(
        ProviderScope(
          overrides: [chatApiProvider.overrideWithValue(api)],
          child: const CupertinoApp(home: ChatPage(sessionId: 's1')),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byKey(const ValueKey('chat-branch-badge')), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  });
}

class _FakeChatApi implements ChatServerApi {
  Map<String, Object?>? sessionResult;

  @override
  Future<Object?> session({
    required String sessionId,
    bool includeMessages = true,
    int? messageLimit,
    int? messageBefore,
    bool expandRenderable = false,
  }) async {
    return sessionResult ??
        {
          'session': {'session_id': sessionId, 'messages': const []},
        };
  }

  @override
  Future<Object?> startChat({
    required String sessionId,
    required String message,
    String? workspace,
    String? model,
    String? modelProvider,
    String? profile,
    bool explicitModelPick = false,
    List<Map<String, Object?>>? attachments,
  }) async {
    return {'stream_id': 'st', 'session_id': sessionId};
  }

  @override
  Future<Object?> steerChat({
    required String sessionId,
    required String text,
  }) async {
    return {'accepted': true};
  }

  @override
  Future<Object?> cancelChat(String streamId) async {
    return {'ok': true};
  }

  @override
  Future<Object?> chatStreamStatus(String streamId) async {
    return {'active': false, 'replay_available': false};
  }

  @override
  Future<Object?> respondApproval({
    required String sessionId,
    required String choice,
    String? approvalId,
  }) async {
    return {'ok': true};
  }

  @override
  Future<Object?> respondClarification({
    required String sessionId,
    required String response,
    String? clarifyId,
  }) async {
    return {'ok': true};
  }

  @override
  Future<Object?> renameSession({
    required String sessionId,
    required String title,
  }) async {
    return {'ok': true};
  }

  @override
  Future<Object?> pinSession({
    required String sessionId,
    required bool pinned,
  }) async {
    return {'ok': true};
  }

  @override
  Future<Object?> archiveSession({
    required String sessionId,
    required bool archived,
  }) async {
    return {'ok': true};
  }

  @override
  Future<Object?> deleteSession(String sessionId) async {
    return {'ok': true};
  }

  @override
  Future<Object?> branchSession(String sessionId, {int? keepCount}) async {
    return {'ok': true, 'session_id': 'branch-$sessionId'};
  }

  @override
  Future<Object?> truncateSession({
    required String sessionId,
    required int keepCount,
  }) async {
    return {'ok': true};
  }

  @override
  Future<Object?> compressSession({
    required String sessionId,
    String? focusTopic,
  }) async {
    return {'ok': true};
  }

  @override
  Future<Object?> undoSession(String sessionId) async {
    return {'ok': true};
  }

  @override
  Future<Object?> retrySession(String sessionId) async {
    return {'ok': true, 'text': '回填'};
  }

  @override
  Future<Object?> updateSession({
    required String sessionId,
    String? workspace,
    String? model,
    String? modelProvider,
  }) async {
    return {'ok': true};
  }

  @override
  Future<Object?> getYolo(String sessionId) async {
    return {'ok': true, 'yolo_enabled': false};
  }

  @override
  Future<Object?> setYolo({
    required String sessionId,
    required bool enabled,
  }) async {
    return {'ok': true, 'yolo_enabled': enabled};
  }

  @override
  Future<void> startStream(
    String streamId, {
    int? replayAfterSeq,
    required void Function(SseEvent event) onEvent,
    void Function(String eventId)? onEventId,
    required void Function(String message) onTransportError,
    required void Function() onClosed,
  }) async {}

  @override
  void stopStream() {}
}