import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermex_flutter/core/api/api_exception.dart';
import 'package:hermex_flutter/core/api/sse_client.dart';
import 'package:hermex_flutter/features/chat/chat_page.dart';
import 'package:hermex_flutter/features/chat/chat_providers.dart';
import 'package:hermex_flutter/features/chat/chat_server_api.dart';

void main() {
  testWidgets('渲染已加载的会话消息列表', (tester) async {
    final api = _FakeChatApi();
    api.sessionResult = {
      'session': {
        'session_id': 's1',
        'title': '测试会话',
        'messages': [
          {'role': 'user', 'content': '你好', 'message_id': 'u1'},
          {'role': 'assistant', 'content': '**你好！** 有什么可以帮你？', 'message_id': 'a1'},
        ],
      },
    };
    await _pumpPage(tester, api);

    expect(find.text('你好'), findsOneWidget);
    // Markdown 渲染（粗体文本出现两次：源码 + 渲染后的富文本片段）
    expect(
      find.textContaining('有什么可以帮你', findRichText: true),
      findsWidgets,
    );
    expect(find.text('测试会话'), findsOneWidget); // 导航栏标题

    await _unmount(tester);
  });

  testWidgets('输入并发送 → 乐观 user 气泡 + 调用 startChat → streaming 停止按钮出现', (tester) async {
    final api = _FakeChatApi();
    api.sessionResult = {
      'session': {'session_id': 's1', 'messages': const []},
    };
    await _pumpPage(tester, api);

    // idle：有发送按钮，无停止按钮
    expect(find.byKey(const ValueKey('chat-send-button')), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-stop-button')), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey('chat-input-field')),
      '帮我写首诗',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('chat-send-button')));
    await tester.pump();
    await tester.pump();

    // startChat 已调用；乐观 user 气泡出现
    expect(api.startChatCalls, 1);
    expect(api.lastSentText, '帮我写首诗');
    expect(find.text('帮我写首诗'), findsOneWidget);

    // streaming：停止按钮出现，发送按钮消失
    await tester.pump();
    expect(find.byKey(const ValueKey('chat-stop-button')), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-send-button')), findsNothing);

    await _unmount(tester);
  });

  testWidgets('流式 token 渲染 + done 后停止按钮消失', (tester) async {
    final api = _FakeChatApi();
    api.sessionResult = {
      'session': {'session_id': 's1', 'messages': const []},
    };
    await _pumpPage(tester, api);

    await tester.enterText(
      find.byKey(const ValueKey('chat-input-field')),
      'hi',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('chat-send-button')));
    await tester.pump();
    await tester.pump();

    // 思考中指示器（空流式气泡）
    expect(find.text('思考中…'), findsOneWidget);

    // token 流式渲染（16ms 合并 + 48ms reveal）
    api.emit(const TokenSseEvent('流式'));
    api.emit(const TokenSseEvent('内容'));
    await tester.pump(const Duration(milliseconds: 80));
    expect(
      find.textContaining('流式内容', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('思考中…'), findsNothing);

    // done 收尾 → 停止按钮消失、发送按钮回归
    api.emit(const DoneSseEvent(DoneStreamEvent(
      session: {
        'session_id': 's1',
        'messages': [
          {'role': 'user', 'content': 'hi', 'message_id': 'u1'},
          {'role': 'assistant', 'content': '流式内容', 'message_id': 'a1'},
        ],
      },
    )));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('chat-stop-button')), findsNothing);
    expect(find.byKey(const ValueKey('chat-send-button')), findsOneWidget);
    expect(
      find.textContaining('流式内容', findRichText: true),
      findsOneWidget,
    );

    await _unmount(tester);
  });

  testWidgets('工具调用卡片渲染（tool 事件 → 卡片出现，完成后显示结果）', (tester) async {
    final api = _FakeChatApi();
    api.sessionResult = {
      'session': {'session_id': 's1', 'messages': const []},
    };
    await _pumpPage(tester, api);

    await tester.enterText(
      find.byKey(const ValueKey('chat-input-field')),
      'hi',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('chat-send-button')));
    await tester.pump();
    await tester.pump();

    api.emit(const ToolStartedSseEvent(ToolStreamEvent(
      stableId: 't1',
      name: 'bash',
      args: {'cmd': 'ls -la'},
    )));
    await tester.pump();
    expect(find.text('bash'), findsOneWidget);
    expect(find.textContaining('cmd: ls -la'), findsOneWidget);
    expect(find.text('运行中…'), findsOneWidget);

    api.emit(const ToolCompletedSseEvent(ToolStreamEvent(
      stableId: 't1',
      name: 'bash',
      preview: 'total 8',
      isError: false,
    )));
    await tester.pump();
    expect(find.text('运行中…'), findsNothing);
    expect(find.text('total 8'), findsOneWidget);

    await _unmount(tester);
  });

  testWidgets('模型选择器：选择后发送带 explicit_model_pick', (tester) async {
    final api = _FakeChatApi();
    api.sessionResult = {
      'session': {'session_id': 's1', 'messages': const []},
    };
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chatApiProvider.overrideWithValue(api),
          chatAvailableModelsProvider.overrideWithValue(const ['gpt-5', 'claude']),
        ],
        child: const CupertinoApp(home: ChatPage(sessionId: 's1')),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.byKey(const ValueKey('chat-model-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('gpt-5'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('chat-model-gpt-5')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.enterText(
      find.byKey(const ValueKey('chat-input-field')),
      '用模型回答',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('chat-send-button')));
    await tester.pump();
    await tester.pump();

    expect(api.startChatCalls, 1);
    expect(api.lastModel, 'gpt-5');
    expect(api.lastExplicitModelPick, isTrue);

    await _unmount(tester);
  });

  testWidgets('发送失败 → 错误横幅展示，可关闭', (tester) async {
    final api = _FakeChatApi();
    api.sessionResult = {
      'session': {'session_id': 's1', 'messages': const []},
    };
    api.startChatError = NetworkException(NetworkExceptionKind.cannotConnect);
    await _pumpPage(tester, api);

    await tester.enterText(
      find.byKey(const ValueKey('chat-input-field')),
      'hi',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('chat-send-button')));
    await tester.pump();
    await tester.pump();
    expect(api.startChatCalls, 1);
    // 错误横幅展示（NetworkException 被捕获 → sendErrorMessage）
    expect(find.textContaining('无法连接'), findsOneWidget);

    await _unmount(tester);
  });
}

/// 组装 ChatPage（override chatApiProvider 注入 fake）。
Future<void> _pumpPage(WidgetTester tester, _FakeChatApi api) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        chatApiProvider.overrideWithValue(api),
      ],
      child: const CupertinoApp(home: ChatPage(sessionId: 's1')),
    ),
  );
  // 初始 loadMessages + 页面动画
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

/// 卸载 ProviderScope（dispose 容器 → 取消看门狗等周期定时器，避免 pending timer）。
Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

class _FakeChatApi implements ChatServerApi {
  Map<String, Object?>? sessionResult;
  Object? startChatError;
  int startChatCalls = 0;
  String? lastSentText;
  String? lastModel;
  bool? lastExplicitModelPick;

  void Function(SseEvent event)? _onEvent;

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
    startChatCalls++;
    lastSentText = message;
    lastModel = model;
    lastExplicitModelPick = explicitModelPick;
    if (startChatError != null) throw startChatError!;
    return {'stream_id': 'stream-1', 'session_id': sessionId};
  }

  @override
  Future<Object?> steerChat({
    required String sessionId,
    required String text,
  }) async {
    return {'accepted': true};
  }

  @override
  Future<Object?> cancelChat(String streamId) async => {'ok': true};

  @override
  Future<Object?> chatStreamStatus(String streamId) async =>
      {'active': false, 'replay_available': false};

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
  Future<void> startStream(
    String streamId, {
    int? replayAfterSeq,
    required void Function(SseEvent event) onEvent,
    void Function(String eventId)? onEventId,
    required void Function(String message) onTransportError,
    required void Function() onClosed,
  }) async {
    _onEvent = onEvent;
  }

  @override
  void stopStream() {}

  void emit(SseEvent event) => _onEvent?.call(event);
}
