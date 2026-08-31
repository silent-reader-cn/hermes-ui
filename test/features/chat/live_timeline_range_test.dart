import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/api/sse_client.dart';
import 'package:hermes_ui/core/models/chat_message.dart';
import 'package:hermes_ui/core/models/server_catalog.dart';
import 'package:hermes_ui/core/models/tool_call.dart';
import 'package:hermes_ui/features/chat/chat_controller.dart';
import 'package:hermes_ui/features/chat/chat_models.dart';
import 'package:hermes_ui/features/chat/chat_page.dart';
import 'package:hermes_ui/features/chat/chat_providers.dart';
import 'package:hermes_ui/features/chat/chat_state.dart';
import 'package:hermes_ui/features/chat/widgets/chat_message_list.dart';
import 'package:hermes_ui/features/settings/tool_group_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_chat_api.dart';

class _FakeChatController extends ChatController {
  _FakeChatController(this._initialState);

  final ChatState _initialState;

  @override
  ChatState build(String sessionId) => _initialState;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('liveTimelineProvider RangeError 防御与切片边界加固测试', () {
    const sessionId = 'test-session';
    const streamingId = 'msg-streaming-1';

    test('边界用例 1: liveToolCalls=[] + toolStarts=[1] (不抛 RangeError 0:1)', () {
      final container = ProviderContainer(
        overrides: [
          chatControllerProvider.overrideWith(
            () => _FakeChatController(
              const ChatState(
                sessionId: sessionId,
                messages: [
                  ChatMessage(
                    role: 'assistant',
                    content: 'hello',
                    messageId: streamingId,
                  ),
                ],
                stream: ChatStreamState(
                  streamingAssistantMessageId: streamingId,
                ),
                liveToolCalls: [], // 空工具列表
                liveTimelinePoints: [
                  LiveTimelinePoint(
                    kind: LiveSegmentKind.tools,
                    start: 1, // 异常偏移 1 > length(0)
                    sequence: 1,
                  ),
                ],
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final timeline = container.read(liveTimelineProvider(sessionId));
      expect(timeline, isNotNull);
      // 验证未抛 RangeError，且无异常 entries
      expect(timeline, isA<List<LiveTimelineEntry>>());
    });

    test('边界用例 2: liveToolCalls=[] + toolStarts=[0, 1] 跨点切片不抛 RangeError', () {
      final container = ProviderContainer(
        overrides: [
          chatControllerProvider.overrideWith(
            () => _FakeChatController(
              const ChatState(
                sessionId: sessionId,
                messages: [
                  ChatMessage(
                    role: 'assistant',
                    content: 'text',
                    messageId: streamingId,
                  ),
                ],
                stream: ChatStreamState(
                  streamingAssistantMessageId: streamingId,
                ),
                liveToolCalls: [],
                liveTimelinePoints: [
                  LiveTimelinePoint(
                    kind: LiveSegmentKind.tools,
                    start: 0,
                    sequence: 1,
                  ),
                  LiveTimelinePoint(
                    kind: LiveSegmentKind.tools,
                    start: 1,
                    sequence: 2,
                  ),
                ],
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final timeline = container.read(liveTimelineProvider(sessionId));
      expect(timeline, isNotNull);
      expect(timeline, isA<List<LiveTimelineEntry>>());
    });

    test('边界用例 3: start > liveToolCalls.length 且 end > liveToolCalls.length', () {
      final container = ProviderContainer(
        overrides: [
          chatControllerProvider.overrideWith(
            () => _FakeChatController(
              ChatState(
                sessionId: sessionId,
                messages: const [
                  ChatMessage(
                    role: 'assistant',
                    content: 'content',
                    messageId: streamingId,
                  ),
                ],
                stream: const ChatStreamState(
                  streamingAssistantMessageId: streamingId,
                ),
                liveToolCalls: [
                  ToolCall(id: 't1', name: 'read_file'),
                ], // length = 1
                liveTimelinePoints: const [
                  LiveTimelinePoint(
                    kind: LiveSegmentKind.tools,
                    start: 5, // 5 > 1
                    sequence: 1,
                  ),
                  LiveTimelinePoint(
                    kind: LiveSegmentKind.tools,
                    start: 10, // 10 > 1
                    sequence: 2,
                  ),
                ],
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final timeline = container.read(liveTimelineProvider(sessionId));
      expect(timeline, isNotNull);
      expect(timeline, isA<List<LiveTimelineEntry>>());
    });

    test('边界用例 4: orphanToolCount 超界安全 clamp', () {
      final container = ProviderContainer(
        overrides: [
          chatControllerProvider.overrideWith(
            () => _FakeChatController(
              ChatState(
                sessionId: sessionId,
                messages: const [
                  ChatMessage(
                    role: 'assistant',
                    content: '',
                    messageId: streamingId,
                  ),
                ],
                stream: const ChatStreamState(
                  streamingAssistantMessageId: streamingId,
                ),
                liveToolCalls: [
                  ToolCall(id: 't1', name: 'read_file'),
                ], // length = 1
                liveTimelinePoints: const [
                  // 首个 tool point start = 5 > liveToolCalls.length(1)
                  LiveTimelinePoint(
                    kind: LiveSegmentKind.tools,
                    start: 5,
                    sequence: 1,
                  ),
                ],
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final timeline = container.read(liveTimelineProvider(sessionId));
      expect(timeline, isNotNull);
      expect(timeline!.length, 1);
      expect(timeline.first.kind, LiveSegmentKind.tools);
      expect(timeline.first.toolGroup?.toolCalls.length, 1);
    });

    test('边界用例 5: orphanText / orphanThink 偏移超界安全 clamp 且空文本保护', () {
      final container = ProviderContainer(
        overrides: [
          chatControllerProvider.overrideWith(
            () => _FakeChatController(
              const ChatState(
                sessionId: sessionId,
                messages: [
                  ChatMessage(
                    role: 'assistant',
                    content: 'abc', // length = 3
                    messageId: streamingId,
                  ),
                ],
                stream: ChatStreamState(
                  streamingAssistantMessageId: streamingId,
                ),
                liveReasoningText: 'think', // length = 5
                liveTimelinePoints: [
                  LiveTimelinePoint(
                    kind: LiveSegmentKind.text,
                    start: 100, // 100 > 3
                    sequence: 1,
                  ),
                  LiveTimelinePoint(
                    kind: LiveSegmentKind.thinking,
                    start: 100, // 100 > 5
                    sequence: 2,
                  ),
                ],
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final timeline = container.read(liveTimelineProvider(sessionId));
      expect(timeline, isNotNull);
      expect(timeline, isA<List<LiveTimelineEntry>>());
      final orphanTextEntry = timeline!.where((e) => e.renderKey == 'live:text:orphan');
      expect(orphanTextEntry.length, 1);
      expect(orphanTextEntry.first.textSlice, 'abc');
    });

    test('边界用例 6: points 与 segments 长度不同步 (points > segments) 校验保护', () {
      final container = ProviderContainer(
        overrides: [
          chatControllerProvider.overrideWith(
            () => _FakeChatController(
              const ChatState(
                sessionId: sessionId,
                messages: [
                  ChatMessage(
                    role: 'assistant',
                    content: '',
                    messageId: streamingId,
                  ),
                ],
                stream: ChatStreamState(
                  streamingAssistantMessageId: streamingId,
                ),
                liveReasoningText: '',
                liveToolCalls: [],
                liveTimelinePoints: [
                  LiveTimelinePoint(kind: LiveSegmentKind.text, start: 0, sequence: 1),
                  LiveTimelinePoint(kind: LiveSegmentKind.text, start: 5, sequence: 2),
                  LiveTimelinePoint(kind: LiveSegmentKind.thinking, start: 0, sequence: 3),
                  LiveTimelinePoint(kind: LiveSegmentKind.thinking, start: 10, sequence: 4),
                  LiveTimelinePoint(kind: LiveSegmentKind.tools, start: 0, sequence: 5),
                  LiveTimelinePoint(kind: LiveSegmentKind.tools, start: 2, sequence: 6),
                ],
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final timeline = container.read(liveTimelineProvider(sessionId));
      expect(timeline, isNotNull);
      expect(timeline, isEmpty);
    });

    test('边界用例 7: negative start values 安全 clamp 到 0', () {
      final container = ProviderContainer(
        overrides: [
          chatControllerProvider.overrideWith(
            () => _FakeChatController(
              ChatState(
                sessionId: sessionId,
                messages: const [
                  ChatMessage(
                    role: 'assistant',
                    content: 'hello',
                    messageId: streamingId,
                  ),
                ],
                stream: const ChatStreamState(
                  streamingAssistantMessageId: streamingId,
                ),
                liveToolCalls: [
                  ToolCall(id: 't1', name: 'bash'),
                ],
                liveTimelinePoints: const [
                  LiveTimelinePoint(
                    kind: LiveSegmentKind.tools,
                    start: -5,
                    sequence: 1,
                  ),
                  LiveTimelinePoint(
                    kind: LiveSegmentKind.text,
                    start: -10,
                    sequence: 2,
                  ),
                ],
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final timeline = container.read(liveTimelineProvider(sessionId));
      expect(timeline, isNotNull);
      expect(timeline, isA<List<LiveTimelineEntry>>());
    });
  });

  group('Widget 集成测试: 穿插流式与边界注入不崩溃', () {
    Future<FakeChatApi> pumpStreamingSession(
      WidgetTester tester, {
      bool coalesceTools = true,
      bool coalesceThink = true,
      bool hideReasoning = false,
      List<Map<String, Object?>> transcript = const [
        {'role': 'user', 'content': 'hi', 'message_id': 'u1'},
      ],
    }) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({
        kToolGroupCoalesceKey: coalesceTools,
        kThinkGroupCoalesceKey: coalesceThink,
        kHideReasoningKey: hideReasoning,
      });
      final api = FakeChatApi()
        ..statusResponse = const ChatStreamStatusResponse(active: true);
      api.sessionResult = {
        'session': {
          'session_id': 's-live-range',
          'title': 'live',
          'active_stream_id': 'stream-range',
          'messages': transcript,
          'message_count': transcript.length,
        },
      };
      await tester.pumpWidget(
        ProviderScope(
          overrides: [chatApiProvider.overrideWithValue(api)],
          child: const CupertinoApp(home: ChatPage(sessionId: 's-live-range')),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));
      return api;
    }

    testWidgets('流式中工具/思考/正文频繁穿插无 RangeError 报错', (tester) async {
      final api = await pumpStreamingSession(tester, coalesceTools: false);

      // 发射一系列交替事件
      api.emit(const ReasoningSseEvent('thinking 1...'));
      await tester.pump(const Duration(milliseconds: 16));

      api.emit(const ToolStartedSseEvent(
        ToolStreamEvent(stableId: 't1', name: 'glob', args: {'pattern': '*.dart'}),
      ));
      await tester.pump(const Duration(milliseconds: 16));

      api.emit(const ToolCompletedSseEvent(
        ToolStreamEvent(stableId: 't1', name: 'glob'),
      ));
      await tester.pump(const Duration(milliseconds: 16));

      api.emit(const TokenSseEvent('Here are the files:\n'));
      await tester.pump(const Duration(milliseconds: 16));

      api.emit(const ReasoningSseEvent('thinking 2...'));
      await tester.pump(const Duration(milliseconds: 16));

      api.emit(const ToolStartedSseEvent(
        ToolStreamEvent(stableId: 't2', name: 'read', args: {'file': 'a.dart'}),
      ));
      await tester.pump(const Duration(milliseconds: 16));

      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 48));
      }

      expect(tester.takeException(), isNull);
      expect(find.byType(ChatMessageList), findsOneWidget);
    });
  });
}
