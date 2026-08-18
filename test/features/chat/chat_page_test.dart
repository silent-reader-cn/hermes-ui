import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hermex_flutter/core/api/api_exception.dart';
import 'package:hermex_flutter/core/api/sse_client.dart';
import 'package:hermex_flutter/features/chat/chat_page.dart';
import 'package:hermex_flutter/features/chat/chat_providers.dart';
import 'package:hermex_flutter/features/chat/chat_server_api.dart';
import 'package:hermex_flutter/features/chat/widgets/message_bubble.dart';

void main() {
  testWidgets('渲染已加载的会话消息列表', (tester) async {
    final api = _FakeChatApi();
    api.sessionResult = {
      'session': {
        'session_id': 's1',
        'title': '测试会话',
        'messages': [
          {'role': 'user', 'content': '你好', 'message_id': 'u1'},
          {
            'role': 'assistant',
            'content': '**你好！** 有什么可以帮你？',
            'message_id': 'a1',
          },
        ],
      },
    };
    await _pumpPage(tester, api);

    expect(find.text('你好'), findsOneWidget);
    // Markdown 渲染（粗体文本出现两次：源码 + 渲染后的富文本片段）
    expect(find.textContaining('有什么可以帮你', findRichText: true), findsWidgets);
    expect(find.text('测试会话'), findsOneWidget); // 导航栏标题

    await _unmount(tester);
  });

  testWidgets('输入并发送 → 乐观 user 气泡 + 调用 startChat → streaming 停止按钮出现', (
    tester,
  ) async {
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
    expect(find.textContaining('流式内容', findRichText: true), findsOneWidget);
    expect(find.text('思考中…'), findsNothing);

    // done 收尾 → 停止按钮消失、发送按钮回归
    api.emit(
      const DoneSseEvent(
        DoneStreamEvent(
          session: {
            'session_id': 's1',
            'messages': [
              {'role': 'user', 'content': 'hi', 'message_id': 'u1'},
              {'role': 'assistant', 'content': '流式内容', 'message_id': 'a1'},
            ],
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('chat-stop-button')), findsNothing);
    expect(find.byKey(const ValueKey('chat-send-button')), findsOneWidget);
    expect(find.textContaining('流式内容', findRichText: true), findsOneWidget);

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

    api.emit(
      const ToolStartedSseEvent(
        ToolStreamEvent(stableId: 't1', name: 'bash', args: {'cmd': 'ls -la'}),
      ),
    );
    await tester.pump();
    expect(find.text('bash'), findsOneWidget);
    expect(find.textContaining('cmd: ls -la'), findsOneWidget);
    expect(find.text('运行中…'), findsOneWidget);

    api.emit(
      const ToolCompletedSseEvent(
        ToolStreamEvent(
          stableId: 't1',
          name: 'bash',
          preview: 'total 8',
          isError: false,
        ),
      ),
    );
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
          chatAvailableModelsProvider.overrideWithValue(const [
            'gpt-5',
            'claude',
          ]),
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

  group('第一阶段：聊天页会话菜单', () {
    testWidgets('导航栏菜单按钮打开操作菜单，展示全部操作项', (tester) async {
      final api = _FakeChatApi();
      api.sessionResult = {
        'session': {'session_id': 's1', 'title': '测试会话', 'messages': const []},
      };
      await _pumpRouted(tester, api);

      await tester.tap(find.byKey(const ValueKey('chat-session-actions')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byKey(const ValueKey('chat-action-rename')), findsOneWidget);
      expect(find.byKey(const ValueKey('chat-action-pin')), findsOneWidget);
      expect(find.byKey(const ValueKey('chat-action-archive')), findsOneWidget);
      expect(find.byKey(const ValueKey('chat-action-branch')), findsOneWidget);
      expect(find.byKey(const ValueKey('chat-action-export')), findsOneWidget);
      expect(find.byKey(const ValueKey('chat-action-delete')), findsOneWidget);

      // 关闭菜单
      await tester.tap(find.byKey(const ValueKey('chat-action-cancel')));
      await tester.pump(const Duration(milliseconds: 300));
      await _unmount(tester);
    });

    testWidgets('重命名：输入新标题保存 → 标题更新且请求发出', (tester) async {
      final api = _FakeChatApi();
      api.sessionResult = {
        'session': {'session_id': 's1', 'title': '旧标题', 'messages': const []},
      };
      await _pumpRouted(tester, api);
      expect(find.text('旧标题'), findsWidgets);

      await tester.tap(find.byKey(const ValueKey('chat-session-actions')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const ValueKey('chat-action-rename')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // 对话框内有输入框（预填当前标题）
      final input = find.byType(CupertinoTextField).last;
      await tester.enterText(input, '新标题');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('chat-rename-save')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(api.renameCalls, 1);
      expect(api.lastRenameTitle, '新标题');
      expect(find.text('新标题'), findsWidgets); // 导航栏标题已更新

      await _unmount(tester);
    });

    testWidgets('置顶：选择置顶 → setPinned(true)', (tester) async {
      final api = _FakeChatApi();
      api.sessionResult = {
        'session': {'session_id': 's1', 'title': '会话', 'messages': const []},
      };
      await _pumpRouted(tester, api);

      await tester.tap(find.byKey(const ValueKey('chat-session-actions')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const ValueKey('chat-action-pin')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(api.pinCalls, 1);
      expect(api.lastPinned, isTrue);
      await _unmount(tester);
    });

    testWidgets('删除：确认后删除并返回列表；取消则不删除', (tester) async {
      final api = _FakeChatApi();
      api.sessionResult = {
        'session': {'session_id': 's1', 'title': '会话', 'messages': const []},
      };
      await _pumpRouted(tester, api);

      // 取消路径：不删除
      await tester.tap(find.byKey(const ValueKey('chat-session-actions')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const ValueKey('chat-action-delete')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('此操作不可撤销'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('chat-delete-cancel')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(api.deleteCalls, 0);

      // 确认路径：删除并返回列表页
      await tester.tap(find.byKey(const ValueKey('chat-session-actions')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const ValueKey('chat-action-delete')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const ValueKey('chat-delete-confirm')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(api.deleteCalls, 1);
      expect(find.text('列表页'), findsOneWidget); // 已回到会话列表路由

      await _unmount(tester);
    });

    testWidgets('分支：创建分支后跳转到分支会话', (tester) async {
      final api = _FakeChatApi();
      api.sessionResult = {
        'session': {'session_id': 's1', 'title': '会话', 'messages': const []},
      };
      final router = await _pumpRouted(tester, api);
      expect(router.routeInformationProvider.value.uri.path, '/chat/s1');

      await tester.tap(find.byKey(const ValueKey('chat-session-actions')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const ValueKey('chat-action-branch')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(api.branchCalls, 1);
      // 已跳转到新分支会话路由
      expect(router.routeInformationProvider.value.uri.path, '/chat/branch-s1');

      await _unmount(tester);
    });
  });

  group('消息级操作（长按菜单）', () {
    testWidgets('长按用户消息 → 弹出操作菜单（复制/编辑/截断）', (tester) async {
      final api = _FakeChatApi();
      api.sessionResult = {
        'session': {
          'session_id': 's1',
          'messages': [
            {'role': 'user', 'content': '第一条用户消息', 'message_id': 'm1'},
            {'role': 'assistant', 'content': '回复内容', 'message_id': 'm2'},
          ],
        },
      };
      await _pumpPage(tester, api);

      await _longPressBubble(tester, '第一条用户消息');
      expect(find.byKey(const ValueKey('msg-action-copy')), findsOneWidget);
      expect(find.byKey(const ValueKey('msg-action-copy-md')), findsOneWidget);
      expect(find.byKey(const ValueKey('msg-action-edit')), findsOneWidget);
      expect(find.byKey(const ValueKey('msg-action-truncate')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('msg-action-cancel')));
      await tester.pump(const Duration(milliseconds: 300));
      await _unmount(tester);
    });

    testWidgets('截断：菜单 → 确认对话框 → 确认后调用 truncate(keepCount)', (tester) async {
      final api = _FakeChatApi();
      api.sessionResult = {
        'session': {
          'session_id': 's1',
          'messages': [
            {'role': 'user', 'content': '第一条用户消息', 'message_id': 'm1'},
            {'role': 'assistant', 'content': '回复内容', 'message_id': 'm2'},
          ],
        },
      };
      await _pumpPage(tester, api);

      await _longPressBubble(tester, '第一条用户消息');
      await tester.tap(find.byKey(const ValueKey('msg-action-truncate')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // 确认对话框
      expect(
        find.byKey(const ValueKey('msg-truncate-confirm')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('msg-truncate-confirm')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(api.truncateCalls, 1);
      // 第一条消息 index=0 → keepCount=1
      expect(api.truncateKeepCounts, [1]);

      await _unmount(tester);
    });

    testWidgets('截断：取消确认 → 不调用 truncate', (tester) async {
      final api = _FakeChatApi();
      api.sessionResult = {
        'session': {
          'session_id': 's1',
          'messages': [
            {'role': 'user', 'content': '第一条用户消息', 'message_id': 'm1'},
            {'role': 'assistant', 'content': '回复内容', 'message_id': 'm2'},
          ],
        },
      };
      await _pumpPage(tester, api);

      await _longPressBubble(tester, '第一条用户消息');
      await tester.tap(find.byKey(const ValueKey('msg-action-truncate')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byKey(const ValueKey('msg-truncate-cancel')));
      await tester.pump(const Duration(milliseconds: 300));

      expect(api.truncateCalls, 0);

      await _unmount(tester);
    });

    testWidgets('从此处分支：长按 → 分支 → keepCount=index+1 并跳转新会话', (tester) async {
      final api = _FakeChatApi();
      api.sessionResult = {
        'session': {
          'session_id': 's1',
          'messages': [
            {'role': 'user', 'content': '第一条用户消息', 'message_id': 'm1'},
            {'role': 'assistant', 'content': '回复内容', 'message_id': 'm2'},
          ],
        },
      };
      final router = await _pumpRouted(tester, api);

      await _longPressBubble(tester, '回复内容');
      expect(find.byKey(const ValueKey('msg-action-branch')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('msg-action-branch')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // 第二条消息（index=1）→ keep_count=2 → 跳转 /chat/branch-s1
      expect(api.branchCalls, 1);
      expect(api.lastBranchKeepCount, 2);
      expect(router.state.uri.path, '/chat/branch-s1');

      await _unmount(tester);
    });

    testWidgets('复制：长按 → 复制 → 提示已复制', (tester) async {
      final api = _FakeChatApi();
      api.sessionResult = {
        'session': {
          'session_id': 's1',
          'messages': [
            {'role': 'user', 'content': '第一条用户消息', 'message_id': 'm1'},
          ],
        },
      };
      await _pumpPage(tester, api);

      await _longPressBubble(tester, '第一条用户消息');
      await tester.tap(find.byKey(const ValueKey('msg-action-copy')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      // Clipboard 平台通道异步完成
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // 复制完成 → controller 轻提示就位（横幅渲染机制已有独立用例）
      final ctx = tester.element(find.byType(ChatPage));
      final container = ProviderScope.containerOf(ctx);
      final notice = container.read(chatControllerProvider('s1')).noticeMessage;
      expect(notice, contains('已复制'));

      await _unmount(tester);
    });

    testWidgets('assistant 消息菜单无「编辑」项', (tester) async {
      final api = _FakeChatApi();
      api.sessionResult = {
        'session': {
          'session_id': 's1',
          'messages': [
            {'role': 'assistant', 'content': '只有助手消息', 'message_id': 'm1'},
          ],
        },
      };
      await _pumpPage(tester, api);

      await _longPressBubble(tester, '只有助手消息');
      expect(find.byKey(const ValueKey('msg-action-edit')), findsNothing);
      expect(find.byKey(const ValueKey('msg-action-truncate')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('msg-action-cancel')));
      await tester.pump(const Duration(milliseconds: 300));
      await _unmount(tester);
    });
  });
}

/// 组装 ChatPage（override chatApiProvider 注入 fake）。
Future<void> _pumpPage(WidgetTester tester, _FakeChatApi api) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [chatApiProvider.overrideWithValue(api)],
      child: const CupertinoApp(home: ChatPage(sessionId: 's1')),
    ),
  );
  // 初始 loadMessages + 页面动画
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

/// 组装带 GoRouter 的 ChatPage（会话菜单的导航跳转走真实路由）。
///
/// 菜单项已超过 10 个（压缩/撤销/重试/设置/YOLO 等），默认 600px 高视口
/// 会裁剪底部项导致 tap miss——统一放大视口高度。
Future<GoRouter> _pumpRouted(WidgetTester tester, _FakeChatApi api) async {
  tester.view.physicalSize = const Size(800, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: '/chat/s1',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) =>
            const CupertinoPageScaffold(child: Center(child: Text('列表页'))),
      ),
      GoRoute(
        path: '/chat/:id',
        builder: (context, state) =>
            ChatPage(sessionId: state.pathParameters['id']!),
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
  await tester.pump(const Duration(milliseconds: 50));
  return router;
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

  // 会话操作计数（第一阶段：聊天页会话菜单）
  int renameCalls = 0;
  int pinCalls = 0;
  int archiveCalls = 0;
  int deleteCalls = 0;
  int branchCalls = 0;

  /// 最近一次分支请求携带的 keep_count（消息级分支断言用）。
  int? lastBranchKeepCount;
  int truncateCalls = 0;
  final List<int> truncateKeepCounts = [];
  int compressCalls = 0;
  int undoCalls = 0;
  int retryCalls = 0;
  int updateSessionCalls = 0;
  int getYoloCalls = 0;
  int setYoloCalls = 0;
  String? lastRenameTitle;
  bool? lastPinned;
  String? lastFocusTopic;
  String? lastUpdatedWorkspace;
  String? lastUpdatedModel;
  bool? lastYoloEnabled;
  Map<String, Object?>? yoloResult;
  Map<String, Object?>? retryResult;

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
  Future<Object?> chatStreamStatus(String streamId) async => {
    'active': false,
    'replay_available': false,
  };

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
  Future<Object?> renameSession({
    required String sessionId,
    required String title,
  }) async {
    renameCalls++;
    lastRenameTitle = title;
    return {
      'ok': true,
      'session': {'session_id': sessionId, 'title': title},
    };
  }

  @override
  Future<Object?> pinSession({
    required String sessionId,
    required bool pinned,
  }) async {
    pinCalls++;
    lastPinned = pinned;
    return {'ok': true};
  }

  @override
  Future<Object?> archiveSession({
    required String sessionId,
    required bool archived,
  }) async {
    archiveCalls++;
    return {'ok': true};
  }

  @override
  Future<Object?> deleteSession(String sessionId) async {
    deleteCalls++;
    return {'ok': true};
  }

  @override
  Future<Object?> branchSession(String sessionId, {int? keepCount}) async {
    branchCalls++;
    lastBranchKeepCount = keepCount;
    return {'session_id': 'branch-$sessionId', 'parent_session_id': sessionId};
  }

  @override
  Future<Object?> truncateSession({
    required String sessionId,
    required int keepCount,
  }) async {
    truncateCalls++;
    truncateKeepCounts.add(keepCount);
    return {'ok': true};
  }

  @override
  Future<Object?> compressSession({
    required String sessionId,
    String? focusTopic,
  }) async {
    compressCalls++;
    lastFocusTopic = focusTopic;
    return {'ok': true};
  }

  @override
  Future<Object?> undoSession(String sessionId) async {
    undoCalls++;
    return {'ok': true};
  }

  @override
  Future<Object?> retrySession(String sessionId) async {
    retryCalls++;
    if (retryResult != null) return retryResult;
    return {'ok': true, 'last_user_text': '你好'};
  }

  @override
  Future<Object?> updateSession({
    required String sessionId,
    String? workspace,
    String? model,
    String? modelProvider,
  }) async {
    updateSessionCalls++;
    lastUpdatedWorkspace = workspace;
    lastUpdatedModel = model;
    return {
      'ok': true,
      'session': {
        'session_id': sessionId,
        'workspace': workspace,
        'model': model,
      },
    };
  }

  @override
  Future<Object?> getYolo(String sessionId) async {
    getYoloCalls++;
    return yoloResult ?? {'ok': true, 'yolo_enabled': false};
  }

  @override
  Future<Object?> setYolo({
    required String sessionId,
    required bool enabled,
  }) async {
    setYoloCalls++;
    lastYoloEnabled = enabled;
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
  }) async {
    _onEvent = onEvent;
  }

  @override
  void stopStream() {}

  void emit(SseEvent event) => _onEvent?.call(event);
}

/// 消息级操作：长按气泡空白区（文本区被 selectable 抢占，模拟真实交互）。
Future<void> _longPressBubble(WidgetTester tester, String text) async {
  final bubble = find
      .ancestor(of: find.text(text), matching: find.byType(ChatMessageBubble))
      .first;
  final rect = tester.getRect(bubble);
  // 气泡左上角内侧 padding 区域（避开文本）
  await tester.longPressAt(rect.topLeft + const Offset(8, 8));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}
