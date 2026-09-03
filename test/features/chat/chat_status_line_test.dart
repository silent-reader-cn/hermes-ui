import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/api/sse_client.dart';
import 'package:hermes_ui/core/models/chat_message.dart';
import 'package:hermes_ui/core/models/server_catalog.dart';
import 'package:hermes_ui/features/chat/chat_controller.dart';
import 'package:hermes_ui/features/chat/chat_providers.dart';
import 'package:hermes_ui/features/chat/chat_state.dart';
import 'package:hermes_ui/features/chat/widgets/chat_message_list.dart';
import 'package:hermes_ui/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_chat_api.dart';

/// #52 状态行测试：注入预设 ChatState，逐态断言列表尾部状态行渲染。
class _FakeChatController extends ChatController {
  _FakeChatController(this._initialState);

  final ChatState _initialState;

  @override
  ChatState build(String sessionId) => _initialState;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const sessionId = 's-status-line';
  const streamingId = 'msg-streaming-1';

  Future<void> pumpWithState(
    WidgetTester tester,
    ChatState state, {
    bool statusLineEnabled = true,
    DateTime Function()? clockOverride,
    Locale locale = const Locale('zh'),
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({
      kChatStatusLineKey: statusLineEnabled,
    });

    final api = FakeChatApi()
      ..statusResponse = const ChatStreamStatusResponse(active: true);
    api.sessionResult = {
      'session': {
        'session_id': sessionId,
        'title': 'status line',
        'messages': [
          {'role': 'user', 'content': 'hi', 'message_id': 'u1'},
        ],
        'message_count': 1,
      },
    };

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chatApiProvider.overrideWithValue(api),
          chatControllerProvider.overrideWith(() => _FakeChatController(state)),
          if (clockOverride != null)
            chatClockProvider.overrideWithValue(clockOverride),
        ],
        child: CupertinoApp(
          locale: locale,
          supportedLocales: const [Locale('zh'), Locale('en')],
          localizationsDelegates: const [
            AppLocalizationsDelegate(),
            DefaultCupertinoLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          home: const CupertinoPageScaffold(
            child: ChatMessageList(sessionId: sessionId),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  ChatState baseState({ChatPhase phase = ChatPhase.idle}) {
    return ChatState(
      sessionId: sessionId,
      phase: phase,
      messages: const [
        ChatMessage(
          role: 'assistant',
          content: 'hello',
          messageId: streamingId,
        ),
      ],
      stream: const ChatStreamState(streamingAssistantMessageId: streamingId),
    );
  }

  group('#52 聊天状态指示行渲染', () {
    testWidgets('sending 态 → 连接中 转圈', (tester) async {
      await pumpWithState(tester, baseState(phase: ChatPhase.sending));
      expect(find.text('连接中'), findsOneWidget);
    });

    testWidgets('prefill loading → 等待模型响应（含 tps 不显示）', (tester) async {
      await pumpWithState(
        tester,
        baseState(phase: ChatPhase.streaming).copyWith(
          prefillStatus: ContextPrefillStatus.loading,
          prefillLabel: 'Building context',
        ),
      );
      expect(find.text('等待模型响应'), findsOneWidget);
      expect(find.textContaining('tps'), findsNothing);
    });

    testWidgets('prefill not_configured → 等待模型响应', (tester) async {
      await pumpWithState(
        tester,
        baseState(phase: ChatPhase.streaming)
            .copyWith(prefillStatus: ContextPrefillStatus.notConfigured),
      );
      expect(find.text('等待模型响应'), findsOneWidget);
    });

    testWidgets('prefill error → 上下文不可用', (tester) async {
      await pumpWithState(
        tester,
        baseState(phase: ChatPhase.streaming).copyWith(
          prefillStatus: ContextPrefillStatus.error,
          prefillLabel: 'context failed',
        ),
      );
      expect(find.text('上下文不可用'), findsOneWidget);
    });

    testWidgets('streaming + metering tps → 生成中 ≈85 tps', (tester) async {
      await pumpWithState(
        tester,
        baseState(phase: ChatPhase.streaming).copyWith(
          stream: const ChatStreamState(
            streamingAssistantMessageId: streamingId,
            liveTokensPerSecond: 85,
          ),
        ),
      );
      expect(find.text('生成中 ≈85 tps'), findsOneWidget);
    });

    testWidgets('streaming 无 tps → 生成中', (tester) async {
      await pumpWithState(
        tester,
        baseState(phase: ChatPhase.streaming).copyWith(
          stream: const ChatStreamState(
            streamingAssistantMessageId: streamingId,
          ),
        ),
      );
      expect(find.text('生成中'), findsOneWidget);
    });

    testWidgets('recovery=checking → 连接异常，排查中', (tester) async {
      await pumpWithState(
        tester,
        baseState(phase: ChatPhase.recovering).copyWith(
          stream: const ChatStreamState(
            streamingAssistantMessageId: streamingId,
            recovery: ActiveStreamRecoveryState.checking,
          ),
        ),
      );
      expect(find.text('连接异常，排查中'), findsOneWidget);
    });

    testWidgets('recovery=reconnecting → 正在重新连接', (tester) async {
      await pumpWithState(
        tester,
        baseState(phase: ChatPhase.recovering).copyWith(
          stream: const ChatStreamState(
            streamingAssistantMessageId: streamingId,
            recovery: ActiveStreamRecoveryState.reconnecting,
          ),
        ),
      );
      expect(find.text('正在重新连接'), findsOneWidget);
    });

    testWidgets('空闲（无流无 sending 无 prefill）→ 状态行隐藏', (tester) async {
      await pumpWithState(
        tester,
        const ChatState(
          sessionId: sessionId,
          phase: ChatPhase.idle,
          messages: [
            ChatMessage(
              role: 'assistant',
              content: 'hello',
              messageId: streamingId,
            ),
          ],
        ),
      );
      expect(find.text('连接中'), findsNothing);
      expect(find.text('等待模型响应'), findsNothing);
      expect(find.text('生成中'), findsNothing);
    });

    testWidgets('开关关闭 → sending 态也完全隐藏', (tester) async {
      await pumpWithState(
        tester,
        baseState(phase: ChatPhase.sending),
        statusLineEnabled: false,
      );
      expect(find.text('连接中'), findsNothing);
      expect(find.text('等待模型响应'), findsNothing);
    });

    testWidgets('prefill loaded（就绪）→ 不显示等待/上下文错误', (tester) async {
      await pumpWithState(
        tester,
        baseState(phase: ChatPhase.streaming)
            .copyWith(prefillStatus: ContextPrefillStatus.loaded),
      );
      expect(find.text('等待模型响应'), findsNothing);
      expect(find.text('上下文不可用'), findsNothing);
      expect(find.text('生成中'), findsOneWidget);
    });

    testWidgets('意见1：发消息后只有一行状态，无「思考中…」指示器', (tester) async {
      await pumpWithState(
        tester,
        ChatState(
          sessionId: sessionId,
          phase: ChatPhase.streaming,
          messages: const [
            ChatMessage(
              role: 'user',
              content: 'Hello',
              messageId: 'u1',
            ),
          ],
          stream: const ChatStreamState(
            streamingAssistantMessageId: streamingId,
          ),
          prefillStatus: ContextPrefillStatus.loading,
          turnStartedMillis: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      // 仅有一行状态行（等待模型响应）
      expect(find.textContaining('等待模型响应'), findsOneWidget);
      // 无思考中文本残留
      expect(find.text('思考中…'), findsNothing);
      expect(find.textContaining('思考中'), findsNothing);
    });

    testWidgets('意见2：状态行 Row 靠左对齐 (MainAxisAlignment.start)', (tester) async {
      await pumpWithState(tester, baseState(phase: ChatPhase.sending));
      final rowFinder = find.byWidgetPredicate(
        (widget) =>
            widget is Row &&
            widget.mainAxisAlignment == MainAxisAlignment.start &&
            widget.children.any((child) => child is CupertinoActivityIndicator),
      );
      expect(rowFinder, findsOneWidget);
    });

    testWidgets('意见3：等待态含 MM:SS 耗时文本，随 pump(1s) 推进递增', (tester) async {
      var now = DateTime(2026, 9, 2, 12, 0, 0);
      final startMs = now.millisecondsSinceEpoch;
      await pumpWithState(
        tester,
        baseState(phase: ChatPhase.streaming).copyWith(
          prefillStatus: ContextPrefillStatus.loading,
          turnStartedMillis: startMs,
        ),
        clockOverride: () => now,
      );
      expect(find.text('等待模型响应 · 已工作 00:00'), findsOneWidget);

      // 推进 1 秒
      now = now.add(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('等待模型响应 · 已工作 00:01'), findsOneWidget);

      // 推进 64 秒 (累计 65 秒 -> 01:05)
      now = now.add(const Duration(seconds: 64));
      await tester.pump(const Duration(seconds: 64));
      expect(find.text('等待模型响应 · 已工作 01:05'), findsOneWidget);
    });

    testWidgets('意见3：生成态含 tps 与 MM:SS 耗时文本', (tester) async {
      var now = DateTime(2026, 9, 2, 12, 0, 0);
      final startMs = now.millisecondsSinceEpoch;
      await pumpWithState(
        tester,
        baseState(phase: ChatPhase.streaming).copyWith(
          turnStartedMillis: startMs,
          stream: const ChatStreamState(
            streamingAssistantMessageId: streamingId,
            liveTokensPerSecond: 85,
          ),
        ),
        clockOverride: () => now,
      );
      expect(find.text('生成中 ≈85 tps · 已工作 00:00'), findsOneWidget);

      now = now.add(const Duration(seconds: 23));
      await tester.pump(const Duration(seconds: 23));
      expect(find.text('生成中 ≈85 tps · 已工作 00:23'), findsOneWidget);
    });

    testWidgets('意见3：英文环境状态行耗时显示 Working for MM:SS', (tester) async {
      final now = DateTime(2026, 9, 2, 12, 0, 0);
      final startMs = now.millisecondsSinceEpoch;
      await pumpWithState(
        tester,
        baseState(phase: ChatPhase.streaming).copyWith(
          prefillStatus: ContextPrefillStatus.loading,
          turnStartedMillis: startMs,
        ),
        locale: const Locale('en'),
        clockOverride: () => now,
      );
      expect(find.textContaining('Working for 00:00'), findsOneWidget);
    });
  });
}
