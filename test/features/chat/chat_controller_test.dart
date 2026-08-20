import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermex_flutter/core/api/api_exception.dart';
import 'package:hermex_flutter/core/api/sse_client.dart';
import 'package:hermex_flutter/features/chat/chat_controller.dart';
import 'package:hermex_flutter/features/chat/chat_providers.dart';
import 'package:hermex_flutter/features/chat/chat_state.dart';
import '../../helpers/fake_chat_api.dart';

void main() {
  group('ChatPhase 九态（chat_spec.md §2.1）', () {
    test('恰好 9 个状态', () {
      expect(ChatPhase.values, hasLength(9));
      expect(ChatPhase.values.toSet(), {
        ChatPhase.idle,
        ChatPhase.sending,
        ChatPhase.streaming,
        ChatPhase.steered,
        ChatPhase.approvalPending,
        ChatPhase.clarifyPending,
        ChatPhase.recovering,
        ChatPhase.cancelled,
        ChatPhase.error,
      });
    });
  });

  group('send → sending → streaming（§4.1）', () {
    test('乐观消息追加 + startChat 成功进入 streaming', () {
      fakeAsync((async) {
        final api = _FakeChatApi();
        final clock = _FakeClock();
        final container = _buildContainer(api, clock);
        final controller = container.read(chatControllerProvider('').notifier);

        unawaited(controller.send('你好'));
        expect(
          container.read(chatControllerProvider('')).phase,
          ChatPhase.sending,
        );
        // 乐观 user 消息已追加
        expect(
          container.read(chatControllerProvider('')).messages,
          hasLength(1),
        );
        expect(
          container.read(chatControllerProvider('')).messages.first.content,
          '你好',
        );
        expect(
          container.read(chatControllerProvider('')).messages.first.role,
          'user',
        );

        async.flushMicrotasks();
        final state = container.read(chatControllerProvider(''));
        expect(state.phase, ChatPhase.streaming);
        expect(state.stream.activeStreamId, 'stream-1');
        expect(api.startChatCalls, 1);
        expect(api.lastSentText, '你好');
        expect(api.streamIds, ['stream-1']);
        // 新会话：服务端返回的 session_id 接管
        expect(state.sessionId, 'sess-new');
      });
    });

    test('startChat 失败 → 回滚乐观消息 + sendErrorMessage + idle', () {
      fakeAsync((async) {
        final api = _FakeChatApi();
        api.startChatError = NetworkException(
          NetworkExceptionKind.cannotConnect,
        );
        final container = _buildContainer(api, _FakeClock());
        final controller = container.read(chatControllerProvider('').notifier);

        unawaited(controller.send('hi'));
        async.flushMicrotasks();
        final state = container.read(chatControllerProvider(''));
        expect(state.phase, ChatPhase.idle);
        expect(state.messages, isEmpty);
        expect(state.sendErrorMessage, isNotNull);
        expect(api.startStreamCalls, 0);
      });
    });

    test('409 已有活动流 → 回滚 + loadMessages + 接管已有流', () {
      fakeAsync((async) {
        final api = _FakeChatApi();
        api.startChatError = HttpException.fromBody(
          409,
          '{"error":"active","active_stream_id":"st-exist"}',
        );
        api.sessionResult = {
          'session': {
            'session_id': 's1',
            'messages': [
              {'role': 'user', 'content': 'old', 'message_id': 'u0'},
              {
                'role': 'assistant',
                'content': 'old answer',
                'message_id': 'a0',
              },
            ],
          },
        };
        final container = _buildContainer(api, _FakeClock());
        final controller = container.read(
          chatControllerProvider('s1').notifier,
        );

        unawaited(controller.send('hi'));
        async.flushMicrotasks();
        final state = container.read(chatControllerProvider('s1'));
        expect(state.phase, ChatPhase.streaming);
        expect(state.stream.activeStreamId, 'st-exist');
        // 乐观消息已回滚
        expect(state.messages.where((m) => m.content == 'hi'), isEmpty);
        expect(api.streamIds, ['st-exist']);
      });
    });
  });

  group('token 三段式缓冲（§3.1）', () {
    test('16ms 合并 + 48ms 词级 reveal，收尾全量 flush', () {
      fakeAsync((async) {
        final api = _FakeChatApi();
        final container = _buildContainer(api, _FakeClock());
        final controller = container.read(chatControllerProvider('').notifier);
        unawaited(controller.send('hi'));
        async.flushMicrotasks();

        // token 只入缓冲，不改 messages
        api.emit(const TokenSseEvent('Hello '));
        api.emit(const TokenSseEvent('world'));
        var state = container.read(chatControllerProvider(''));
        expect(state.pendingAssistantTokenChunks, ['Hello ', 'world']);
        // 流开始即锚定空流式气泡（思考中指示器）；内容在 flush 前为空
        expect(state.stream.streamingAssistantMessageId, isNotNull);
        final emptyStreaming = state.messages
            .where(
              (m) => m.messageId == state.stream.streamingAssistantMessageId,
            )
            .firstOrNull;
        expect(emptyStreaming!.content, '');

        // 16ms 合并 → reveal 队列（仍不改 messages）
        async.elapse(const Duration(milliseconds: 16));
        state = container.read(chatControllerProvider(''));
        expect(state.pendingAssistantTokenChunks, isEmpty);
        final stillEmpty = state.messages
            .where(
              (m) => m.messageId == state.stream.streamingAssistantMessageId,
            )
            .firstOrNull;
        expect(stillEmpty!.content, '');

        // 48ms reveal tick → 内容落地
        async.elapse(const Duration(milliseconds: 48));
        state = container.read(chatControllerProvider(''));
        final streaming = state.messages
            .where(
              (m) => m.messageId == state.stream.streamingAssistantMessageId,
            )
            .firstOrNull;
        expect(streaming, isNotNull);
        expect(streaming!.content, 'Hello world');

        // 完成路径全量 flush（stop → cancel ok → finishStream 先 flush）
        api.emit(const TokenSseEvent('!'));
        unawaited(controller.stop());
        async.flushMicrotasks();
        state = container.read(chatControllerProvider(''));
        expect(state.phase, ChatPhase.idle);
        expect(state.stream.streamingAssistantMessageId, isNull);
        // 文本保留在最后一条 assistant 消息
        final last = state.messages.last;
        expect(last.role, 'assistant');
        expect(last.content, 'Hello world!');
      });
    });

    test('reasoning 整块 flush（不走词级 pacing）', () {
      fakeAsync((async) {
        final api = _FakeChatApi();
        final container = _buildContainer(api, _FakeClock());
        final controller = container.read(chatControllerProvider('').notifier);
        unawaited(controller.send('hi'));
        async.flushMicrotasks();

        api.emit(const ReasoningSseEvent('think step 1'));
        var state = container.read(chatControllerProvider(''));
        expect(state.pendingReasoningChunks, ['think step 1']);
        expect(state.liveReasoningText, isEmpty);

        async.elapse(const Duration(milliseconds: 16));
        state = container.read(chatControllerProvider(''));
        expect(state.pendingReasoningChunks, isEmpty);
        expect(state.liveReasoningText, 'think step 1');
      });
    });
  });

  group('interim_assistant（§3.3）', () {
    test('already_streamed=true 或空文本 → 忽略', () {
      fakeAsync((async) {
        final api = _FakeChatApi();
        final container = _buildContainer(api, _FakeClock());
        final controller = container.read(chatControllerProvider('').notifier);
        unawaited(controller.send('hi'));
        async.flushMicrotasks();

        api.emit(
          const InterimAssistantSseEvent(text: 'dup', alreadyStreamed: true),
        );
        api.emit(
          const InterimAssistantSseEvent(text: '   ', alreadyStreamed: false),
        );
        expect(
          container.read(chatControllerProvider('')).messages,
          hasLength(2),
        );
      });
    });

    test('先 flush 积压 token 再追加，非 replay 用 \\n\\n 分隔', () {
      fakeAsync((async) {
        final api = _FakeChatApi();
        final container = _buildContainer(api, _FakeClock());
        final controller = container.read(chatControllerProvider('').notifier);
        unawaited(controller.send('hi'));
        async.flushMicrotasks();

        api.emit(const TokenSseEvent('partial '));
        api.emit(
          const InterimAssistantSseEvent(
            text: 'full paragraph',
            alreadyStreamed: false,
          ),
        );
        final state = container.read(chatControllerProvider(''));
        final streaming = state.messages
            .where(
              (m) => m.messageId == state.stream.streamingAssistantMessageId,
            )
            .firstOrNull;
        expect(streaming!.content, 'partial \n\nfull paragraph');
      });
    });
  });

  group('工具调用（§3.5）', () {
    test('tool 追加未完成 → tool_complete 按 stableID 补全', () {
      fakeAsync((async) {
        final api = _FakeChatApi();
        final container = _buildContainer(api, _FakeClock());
        final controller = container.read(chatControllerProvider('').notifier);
        unawaited(controller.send('hi'));
        async.flushMicrotasks();

        api.emit(
          const ToolStartedSseEvent(
            ToolStreamEvent(stableId: 't1', name: 'bash', args: {'cmd': 'ls'}),
          ),
        );
        var state = container.read(chatControllerProvider(''));
        expect(state.liveToolCalls, hasLength(1));
        expect(state.liveToolCalls.first.isCompleted, isFalse);
        expect(state.liveToolCalls.first.name, 'bash');
        expect(state.stream.toolCallAnchorMessageId, isNotNull);

        api.emit(
          const ToolCompletedSseEvent(
            ToolStreamEvent(
              stableId: 't1',
              name: 'bash',
              duration: 1.5,
              isError: false,
            ),
          ),
        );
        state = container.read(chatControllerProvider(''));
        expect(state.liveToolCalls.first.isCompleted, isTrue);
        expect(state.liveToolCalls.first.duration, 1.5);
      });
    });

    test('tool_complete 匹配不到 → 兜底 append 已完成项', () {
      fakeAsync((async) {
        final api = _FakeChatApi();
        final container = _buildContainer(api, _FakeClock());
        final controller = container.read(chatControllerProvider('').notifier);
        unawaited(controller.send('hi'));
        async.flushMicrotasks();

        api.emit(
          const ToolCompletedSseEvent(
            ToolStreamEvent(name: 'shell', preview: 'done', isError: false),
          ),
        );
        final state = container.read(chatControllerProvider(''));
        expect(state.liveToolCalls, hasLength(1));
        expect(state.liveToolCalls.first.isCompleted, isTrue);
        expect(state.liveToolCalls.first.displayName, 'shell');
      });
    });

    test('done 携带 session.toolCalls → 重建 completedToolCallGroups 并清 live', () {
      fakeAsync((async) {
        final api = _FakeChatApi();
        final container = _buildContainer(api, _FakeClock());
        final controller = container.read(chatControllerProvider('').notifier);
        unawaited(controller.send('hi'));
        async.flushMicrotasks();

        api.emit(
          const ToolStartedSseEvent(
            ToolStreamEvent(stableId: 't1', name: 'bash'),
          ),
        );
        api.emit(
          const DoneSseEvent(
            DoneStreamEvent(
              session: {
                'session_id': 's1',
                'messages': [
                  {'role': 'user', 'content': 'hi', 'message_id': 'u1'},
                  {
                    'role': 'assistant',
                    'content': 'answer',
                    'message_id': 'a1',
                  },
                ],
                'tool_calls': [
                  {
                    'name': 'bash',
                    'snippet': 'out',
                    'tid': 't1',
                    'assistant_msg_idx': 1,
                  },
                ],
              },
            ),
          ),
        );
        final state = container.read(chatControllerProvider(''));
        expect(state.phase, ChatPhase.idle);
        expect(state.liveToolCalls, isEmpty);
        expect(state.completedToolCallGroups, isNotEmpty);
        expect(state.completedToolCallGroups.first.toolCalls, hasLength(1));
        expect(
          state.completedToolCallGroups.first.toolCalls.first.isCompleted,
          isTrue,
        );
      });
    });
  });

  group('done 收尾（§3.7，易错点 #3）', () {
    test('done 带 transcript → 服务端替换 + 清流状态；stream_end 不重复收尾', () {
      fakeAsync((async) {
        final api = _FakeChatApi();
        final container = _buildContainer(api, _FakeClock());
        final controller = container.read(chatControllerProvider('').notifier);
        unawaited(controller.send('hi'));
        async.flushMicrotasks();
        api.emit(const TokenSseEvent('local '));
        async.elapse(const Duration(milliseconds: 64));

        api.emit(
          const DoneSseEvent(
            DoneStreamEvent(
              session: {
                'session_id': 's1',
                'messages': [
                  {'role': 'user', 'content': 'hi', 'message_id': 'u1'},
                  {
                    'role': 'assistant',
                    'content': 'server answer',
                    'message_id': 'a1',
                  },
                ],
              },
              usage: {'input_tokens': 10, 'output_tokens': 20, 'tps': 8.5},
            ),
          ),
        );
        var state = container.read(chatControllerProvider(''));
        expect(state.phase, ChatPhase.idle);
        expect(state.stream.activeStreamId, isNull);
        expect(state.stream.hasCompletedResponse, isTrue);
        expect(state.messages, hasLength(2));
        expect(state.messages.last.content, 'server answer');
        expect(state.contextWindowSnapshot, isNotNull);
        expect(state.messages.last.turnTps, 8.5);

        // stream_end 因 hasCompletedResponse 不重复收尾，但 finishStream 清理
        api.emit(const StreamEndSseEvent());
        state = container.read(chatControllerProvider(''));
        expect(state.phase, ChatPhase.idle);
        expect(state.messages, hasLength(2));
      });
    });

    test('done 无 transcript → needsTranscriptRefresh → status 轮询兜底', () {
      fakeAsync((async) {
        final api = _FakeChatApi();
        final container = _buildContainer(api, _FakeClock());
        final controller = container.read(chatControllerProvider('').notifier);
        unawaited(controller.send('hi'));
        async.flushMicrotasks();

        api.emit(
          const DoneSseEvent(DoneStreamEvent(session: {'session_id': 's1'})),
        );
        var state = container.read(chatControllerProvider(''));
        expect(state.phase, ChatPhase.idle);
        expect(state.responseCompletionNeedsTranscriptRefresh, isTrue);

        final sessionCallsBefore = api.sessionCalls;
        async.elapse(const Duration(milliseconds: 600));
        async.flushMicrotasks();
        expect(api.statusCalls, greaterThan(0));
        expect(api.sessionCalls, greaterThan(sessionCallsBefore));
        state = container.read(chatControllerProvider(''));
        expect(state.responseCompletionNeedsTranscriptRefresh, isFalse);
      });
    });

    test('error 事件 → sendErrorMessage + 回 idle；done 之后到达不显示', () {
      fakeAsync((async) {
        final api = _FakeChatApi();
        final container = _buildContainer(api, _FakeClock());
        final controller = container.read(chatControllerProvider('').notifier);
        unawaited(controller.send('hi'));
        async.flushMicrotasks();

        api.emit(const ErrorSseEvent('模型出错了'));
        var state = container.read(chatControllerProvider(''));
        expect(state.sendErrorMessage, '模型出错了');
        expect(state.phase, ChatPhase.idle);

        // 第二轮：done 收尾后 error 不显示
        unawaited(controller.send('again'));
        async.flushMicrotasks();
        api.emit(
          const DoneSseEvent(DoneStreamEvent(session: {'session_id': 's1'})),
        );
        api.emit(const ErrorSseEvent('晚了'));
        state = container.read(chatControllerProvider(''));
        expect(state.sendErrorMessage, isNot('晚了'));
        expect(state.phase, ChatPhase.idle);
      });
    });
  });

  group('stop / steer / queue（§4.2/§4.3）', () {
    test('stop → GET cancel → finishStream（cancelled 瞬时回 idle，文本保留）', () {
      fakeAsync((async) {
        final api = _FakeChatApi();
        final container = _buildContainer(api, _FakeClock());
        final controller = container.read(chatControllerProvider('').notifier);
        unawaited(controller.send('hi'));
        async.flushMicrotasks();
        api.emit(const TokenSseEvent('keep me '));
        async.elapse(const Duration(milliseconds: 64));

        unawaited(controller.stop());
        async.flushMicrotasks();
        expect(api.cancelCalls, 1);
        final state = container.read(chatControllerProvider(''));
        expect(state.phase, ChatPhase.idle);
        expect(state.stream.isCancelling, isFalse);
        expect(state.messages.last.content, 'keep me ');
      });
    });

    test('stop 失败（ok=false）→ 流继续 + sendErrorMessage', () {
      fakeAsync((async) {
        final api = _FakeChatApi();
        api.cancelOk = false;
        final container = _buildContainer(api, _FakeClock());
        final controller = container.read(chatControllerProvider('').notifier);
        unawaited(controller.send('hi'));
        async.flushMicrotasks();

        unawaited(controller.stop());
        async.flushMicrotasks();
        final state = container.read(chatControllerProvider(''));
        expect(state.stream.activeStreamId, isNotNull);
        expect(state.sendErrorMessage, isNotNull);
        expect(state.stream.isCancelling, isFalse);
      });
    });

    test('流式期间 send → steer accepted → steered；收到 token 回 streaming', () {
      fakeAsync((async) {
        final api = _FakeChatApi();
        final container = _buildContainer(api, _FakeClock());
        final controller = container.read(chatControllerProvider('').notifier);
        unawaited(controller.send('hi'));
        async.flushMicrotasks();

        unawaited(controller.send('更详细一点'));
        async.flushMicrotasks();
        expect(api.steerCalls, 1);
        var state = container.read(chatControllerProvider(''));
        expect(state.phase, ChatPhase.steered);
        // steer 不追加 user 气泡（仅乐观 user + 空流式气泡）
        expect(state.messages, hasLength(2));

        api.emit(const TokenSseEvent('ok '));
        async.elapse(const Duration(milliseconds: 64));
        state = container.read(chatControllerProvider(''));
        expect(state.phase, ChatPhase.streaming);
      });
    });

    test('steer 被拒 → 入队 + notice + cancelActiveStream → 队列顺次发送', () {
      fakeAsync((async) {
        final api = _FakeChatApi();
        api.steerAccepted = false;
        final container = _buildContainer(api, _FakeClock());
        final controller = container.read(chatControllerProvider('').notifier);
        unawaited(controller.send('hi'));
        async.flushMicrotasks();

        unawaited(controller.send('被拒的消息'));
        async.flushMicrotasks();
        expect(api.cancelCalls, 1);
        final state = container.read(chatControllerProvider(''));
        // cancel ok → finishStream → pinned notice flush 进 transcript
        expect(
          state.messages.where((m) => m.role == 'local_notice'),
          isNotEmpty,
        );
        expect(api.startChatCalls, 2);
        expect(api.lastSentText, '被拒的消息');
        expect(state.queuedSlashMessages, isEmpty);
        expect(state.phase, ChatPhase.streaming);
      });
    });

    test('queue 行为 → 仅入队；done+stream_end 后自动发送', () {
      fakeAsync((async) {
        final api = _FakeChatApi();
        final container = _buildContainer(api, _FakeClock());
        final controller = container.read(chatControllerProvider('').notifier);
        unawaited(controller.send('hi'));
        async.flushMicrotasks();

        unawaited(
          controller.send('排队消息', behavior: StreamingSendBehavior.queue),
        );
        async.flushMicrotasks();
        var state = container.read(chatControllerProvider(''));
        expect(state.queuedSlashMessages, ['排队消息']);
        expect(state.pinnedLocalNotices, isNotEmpty);
        expect(api.startChatCalls, 1);

        api.emit(
          const DoneSseEvent(DoneStreamEvent(session: {'session_id': 's1'})),
        );
        api.emit(const StreamEndSseEvent());
        async.flushMicrotasks();
        expect(api.startChatCalls, 2);
        expect(api.lastSentText, '排队消息');
        state = container.read(chatControllerProvider(''));
        expect(state.queuedSlashMessages, isEmpty);
      });
    });

    test('pending_steer_leftover → 入队 + notice', () {
      fakeAsync((async) {
        final api = _FakeChatApi();
        final container = _buildContainer(api, _FakeClock());
        final controller = container.read(chatControllerProvider('').notifier);
        unawaited(controller.send('hi'));
        async.flushMicrotasks();

        api.emit(const PendingSteerLeftoverSseEvent('剩余提示'));
        final state = container.read(chatControllerProvider(''));
        expect(state.queuedSlashMessages, ['剩余提示']);
        expect(state.pinnedLocalNotices, hasLength(1));
      });
    });
  });

  group('transportError 断线恢复（§5.3）', () {
    test('active==true → loadMessages 重载 → 全量重连', () {
      fakeAsync((async) {
        final api = _FakeChatApi();
        api.statusResult = {'active': true, 'replay_available': false};
        api.sessionResult = {
          'session': {
            'session_id': 's1',
            'messages': [
              {'role': 'user', 'content': 'hi', 'message_id': 'u1'},
              {
                'role': 'assistant',
                'content': 'partial answer',
                'message_id': 'a1',
              },
            ],
          },
        };
        final container = _buildContainer(api, _FakeClock());
        final controller = container.read(chatControllerProvider('').notifier);
        unawaited(controller.send('hi'));
        async.flushMicrotasks();

        api.emit(const TransportErrorSseEvent('连接断开'));
        async.flushMicrotasks();
        expect(api.statusCalls, greaterThan(0));
        expect(api.streamIds, hasLength(2));
        final state = container.read(chatControllerProvider(''));
        expect(state.phase, ChatPhase.streaming);
        expect(state.stream.isSuspended, isFalse);
        expect(state.stream.activeStreamId, 'stream-1');
        expect(state.messages, isNotEmpty);
      });
    });

    test('replayAvailable==true → replay=1&after_seq=N 重连', () {
      fakeAsync((async) {
        final api = _FakeChatApi();
        api.statusResult = {'active': false, 'replay_available': true};
        final container = _buildContainer(api, _FakeClock());
        final controller = container.read(chatControllerProvider('').notifier);
        unawaited(controller.send('hi'));
        async.flushMicrotasks();

        // 记录 SSE 事件 id（lastEventID 语义：事件 id: 字段）
        api.emitId('evt:42');
        api.emit(const TransportErrorSseEvent('断开'));
        async.flushMicrotasks();
        expect(api.streamIds, hasLength(2));
        expect(api.replaySeqs.last, 42);
        final state = container.read(chatControllerProvider(''));
        expect(state.phase, ChatPhase.streaming);
        expect(state.stream.recovery, ActiveStreamRecoveryState.idle);
      });
    });

    test('非 active 且无 replay → loadMessages 按 transcript finalize', () {
      fakeAsync((async) {
        final api = _FakeChatApi();
        api.statusResult = {'active': false, 'replay_available': false};
        api.sessionResult = {
          'session': {
            'session_id': 's1',
            'messages': [
              {'role': 'user', 'content': 'hi', 'message_id': 'u1'},
              {
                'role': 'assistant',
                'content': 'final answer',
                'message_id': 'a1',
              },
            ],
          },
        };
        final container = _buildContainer(api, _FakeClock());
        final controller = container.read(chatControllerProvider('').notifier);
        unawaited(controller.send('hi'));
        async.flushMicrotasks();

        api.emit(const TransportErrorSseEvent('断开'));
        async.flushMicrotasks();
        final state = container.read(chatControllerProvider(''));
        expect(state.phase, ChatPhase.idle);
        expect(state.stream.activeStreamId, isNull);
        expect(state.messages, hasLength(2));
      });
    });

    test('流已结束后的迟到 transportError → 无连接可恢复 → 错误收尾', () {
      fakeAsync((async) {
        final api = _FakeChatApi();
        final container = _buildContainer(api, _FakeClock());
        final controller = container.read(chatControllerProvider('').notifier);
        unawaited(controller.send('hi'));
        async.flushMicrotasks();

        // 流已结束（done + stream_end 后 activeStreamId 已清空）
        api.emit(
          const DoneSseEvent(DoneStreamEvent(session: {'session_id': 's1'})),
        );
        api.emit(const StreamEndSseEvent());
        // 迟到的 transportError → 无连接可恢复 → 错误收尾
        api.fail('迟到的断开');
        final state = container.read(chatControllerProvider(''));
        expect(state.sendErrorMessage, '迟到的断开');
        expect(state.phase, ChatPhase.idle);
      });
    });

    test('看门狗：5s 无进度 + 12s 无传输 → status 检查', () {
      fakeAsync((async) {
        final api = _FakeChatApi();
        api.statusResult = {'active': true, 'replay_available': false};
        api.sessionResult = {
          'session': {'session_id': 's1', 'messages': const []},
        };
        final clock = _FakeClock();
        final container = _buildContainer(api, clock);
        final controller = container.read(chatControllerProvider('').notifier);
        unawaited(controller.send('hi'));
        async.flushMicrotasks();

        clock.advance(const Duration(seconds: 13));
        async.elapse(const Duration(seconds: 13));
        async.flushMicrotasks();
        expect(api.statusCalls, greaterThan(0));
        final state = container.read(chatControllerProvider(''));
        expect(state.phase, ChatPhase.streaming);
      });
    });
  });

  group('title / metering（§3.6）', () {
    test('session_id 不匹配 → 忽略；匹配才生效', () {
      fakeAsync((async) {
        final api = _FakeChatApi();
        final container = _buildContainer(api, _FakeClock());
        final controller = container.read(
          chatControllerProvider('s1').notifier,
        );
        unawaited(controller.send('hi'));
        async.flushMicrotasks();

        api.emit(const TitleSseEvent(sessionId: 'other', title: '错标题'));
        expect(
          container.read(chatControllerProvider('s1')).displayTitle,
          'Untitled Session',
        );
        api.emit(const TitleSseEvent(sessionId: 's1', title: '  真标题  '));
        expect(
          container.read(chatControllerProvider('s1')).displayTitle,
          '真标题',
        );

        api.emit(
          const MeteringSseEvent(
            tps: 12.5,
            tpsAvailable: true,
            estimated: false,
            sessionId: 's1',
          ),
        );
        expect(
          container
              .read(chatControllerProvider('s1'))
              .stream
              .liveTokensPerSecond,
          12.5,
        );
        // tps<=0 不更新
        api.emit(
          const MeteringSseEvent(
            tps: -1,
            tpsAvailable: true,
            estimated: false,
            sessionId: 's1',
          ),
        );
        expect(
          container
              .read(chatControllerProvider('s1'))
              .stream
              .liveTokensPerSecond,
          12.5,
        );
      });
    });
  });

  group('approval / clarify（§2.3）', () {
    test('approval 事件 → approvalPending；作答后回 streaming', () {
      fakeAsync((async) {
        final api = _FakeChatApi();
        final container = _buildContainer(api, _FakeClock());
        final controller = container.read(chatControllerProvider('').notifier);
        unawaited(controller.send('hi'));
        async.flushMicrotasks();

        api.emit(
          const ApprovalPendingSseEvent({
            'pending': {
              'question': '允许执行?',
              'choices': ['允许', '拒绝'],
            },
          }),
        );
        var state = container.read(chatControllerProvider(''));
        expect(state.phase, ChatPhase.approvalPending);
        expect(state.pendingAction.hasPendingPrompt, isTrue);

        unawaited(controller.respondToApproval('允许'));
        async.flushMicrotasks();
        state = container.read(chatControllerProvider(''));
        expect(state.phase, ChatPhase.streaming);
        expect(state.pendingAction.approvalPrompt, isNull);
      });
    });

    test('clarify 事件 → clarifyPending', () {
      fakeAsync((async) {
        final api = _FakeChatApi();
        final container = _buildContainer(api, _FakeClock());
        final controller = container.read(chatControllerProvider('').notifier);
        unawaited(controller.send('hi'));
        async.flushMicrotasks();

        api.emit(
          const ClarificationPendingSseEvent({
            'pending': {
              'question': '哪个方案?',
              'choices_offered': ['A', 'B'],
            },
          }),
        );
        final state = container.read(chatControllerProvider(''));
        expect(state.phase, ChatPhase.clarifyPending);
        expect(state.pendingAction.clarificationPrompt, isNotNull);
      });
    });
  });

  group('replay 去重算法（§5.6，逐分支）', () {
    ({String remainder, int newCursor, bool stillReplay}) dedup(
      String token,
      String existing, {
      int cursor = 0,
    }) {
      return ChatController.deduplicatedReplayToken(
        token: token,
        existingContent: existing,
        matchedPrefixLength: cursor,
      );
    }

    test('existingContent 为空 → 原样返回 + 关闭 replay', () {
      final result = dedup('abc', '');
      expect(result.remainder, 'abc');
      expect(result.stillReplay, isFalse);
    });

    test('expectedRemainder.hasPrefix(token) → 纯重复，游标前进', () {
      final result = dedup('world', 'Hello world', cursor: 6);
      expect(result.remainder, '');
      // 游标 ≥ existingContent 长度后自动复位（§5.6 规则 3）
      expect(result.newCursor, 0);
      expect(result.stillReplay, isTrue);
    });

    test('token.hasPrefix(expectedRemainder) → 残余拼接', () {
      final result = dedup('world!', 'Hello world', cursor: 6);
      expect(result.remainder, '!');
      expect(result.newCursor, 0);
      expect(result.stillReplay, isTrue);
    });

    test('existingContent.hasPrefix(token) → 完全重复', () {
      final result = dedup('Hello', 'Hello world');
      expect(result.remainder, '');
      expect(result.stillReplay, isTrue);
    });

    test('existingContent.hasSuffix(token) → 完全重复', () {
      final result = dedup('world', 'Hello world');
      expect(result.remainder, '');
      expect(result.stillReplay, isTrue);
    });

    test('token.hasPrefix(existingContent) → 返回多出的部分', () {
      final result = dedup('Hello world!', 'Hello world');
      expect(result.remainder, '!');
      expect(result.stillReplay, isTrue);
    });

    test('最大重叠扫描（后缀 ∩ 前缀）', () {
      final result = dedup('world peace', 'Hello world');
      // existing 'Hello world' 后缀 'world' ∩ token 前缀 'world' → 重叠 5
      expect(result.remainder, ' peace');
      expect(result.stillReplay, isTrue);
    });

    test('皆不匹配 → 原样返回 + 关闭 replay', () {
      final result = dedup('xyz', 'Hello world');
      expect(result.remainder, 'xyz');
      expect(result.stillReplay, isFalse);
      expect(result.newCursor, 0);
    });

    test('游标 ≥ existingContent 长度后自动复位', () {
      final result = dedup('!', 'Hello', cursor: 5);
      expect(result.newCursor, 0);
    });
  });

  group('replay 连接内 token 去重集成（§6.4）', () {
    test('重连后重复 token 被吃掉，只追加新增部分', () {
      fakeAsync((async) {
        final api = _FakeChatApi();
        api.statusResult = {'active': false, 'replay_available': true};
        final container = _buildContainer(api, _FakeClock());
        final controller = container.read(chatControllerProvider('').notifier);
        unawaited(controller.send('hi'));
        async.flushMicrotasks();
        api.emit(const TokenSseEvent('Hello world'));
        async.elapse(const Duration(milliseconds: 64));

        // 断开重连（replay）
        api.emitId('evt:5');
        api.emit(const TransportErrorSseEvent('断开'));
        async.flushMicrotasks();
        expect(api.streamIds, hasLength(2));
        expect(
          container.read(chatControllerProvider('')).stream.isReplayConnection,
          isTrue,
        );

        // 重放：先 Hello（已有，吃掉）再 world（已有，吃掉）再 !（新增）
        api.emit(const TokenSseEvent('Hello'));
        async.elapse(const Duration(milliseconds: 64));
        api.emit(const TokenSseEvent(' world'));
        async.elapse(const Duration(milliseconds: 64));
        api.emit(const TokenSseEvent('!'));
        async.elapse(const Duration(milliseconds: 64));

        final state = container.read(chatControllerProvider(''));
        final streaming = state.messages
            .where(
              (m) => m.messageId == state.stream.streamingAssistantMessageId,
            )
            .firstOrNull;
        expect(streaming!.content, 'Hello world!');
      });
    });
  });

  group('词单元切分', () {
    test('英文按空白切分且拼接无损', () {
      expect(ChatController.splitIntoWordUnits('Hello world!'), [
        'Hello ',
        'world!',
      ]);
      expect(
        ChatController.splitIntoWordUnits('Hello world!').join(),
        'Hello world!',
      );
    });

    test('无空白 CJK 长串每 8 字符切一刀', () {
      final units = ChatController.splitIntoWordUnits('你好世界你好世界你好');
      expect(units, ['你好世界你好世界', '你好']);
      expect(units.join(), '你好世界你好世界你好');
    });
  });

  group('会话操作（第一阶段：聊天页会话菜单）', () {
    test('重命名成功 → 更新 displayTitle', () async {
      final api = _FakeChatApi();
      final container = _buildContainer(api, _FakeClock());
      final controller = container.read(chatControllerProvider('s1').notifier);

      final ok = await controller.renameSession('新标题');
      expect(ok, isTrue);
      expect(container.read(chatControllerProvider('s1')).displayTitle, '新标题');
      expect(api.renameCalls, 1);
      expect(api.lastRenameTitle, '新标题');
    });

    test('重命名空白标题 → 拒绝且不发请求', () async {
      final api = _FakeChatApi();
      final container = _buildContainer(api, _FakeClock());
      final controller = container.read(chatControllerProvider('s1').notifier);

      final ok = await controller.renameSession('   ');
      expect(ok, isFalse);
      expect(api.renameCalls, 0);
    });

    test('重命名服务端失败 → 返回 false 且设置错误', () async {
      final api = _FakeChatApi();
      api.mutationOk = false;
      api.mutationError = '标题已存在';
      final container = _buildContainer(api, _FakeClock());
      final controller = container.read(chatControllerProvider('s1').notifier);

      final ok = await controller.renameSession('新标题');
      expect(ok, isFalse);
      expect(
        container.read(chatControllerProvider('s1')).sendErrorMessage,
        '标题已存在',
      );
    });

    test('重命名网络异常 → 返回 false 且设置错误', () async {
      final api = _FakeChatApi();
      api.mutationThrows = NetworkException(NetworkExceptionKind.cannotConnect);
      final container = _buildContainer(api, _FakeClock());
      final controller = container.read(chatControllerProvider('s1').notifier);

      final ok = await controller.renameSession('新标题');
      expect(ok, isFalse);
      expect(
        container.read(chatControllerProvider('s1')).sendErrorMessage,
        startsWith('无法连接'),
      );
    });

    test('置顶/归档成功 → 返回 true', () async {
      final api = _FakeChatApi();
      final container = _buildContainer(api, _FakeClock());
      final controller = container.read(chatControllerProvider('s1').notifier);

      expect(await controller.setPinned(true), isTrue);
      expect(api.pinCalls, 1);
      expect(api.lastPinned, isTrue);
      expect(await controller.setArchived(true), isTrue);
      expect(api.archiveCalls, 1);
      expect(api.lastArchived, isTrue);
    });

    test('置顶保持状态 → 返回 true', () async {
      final api = _FakeChatApi();
      final container = _buildContainer(api, _FakeClock());
      final controller = container.read(chatControllerProvider('s1').notifier);

      expect(await controller.setPinned(false), isTrue);
      expect(api.lastPinned, isFalse);
      expect(await controller.setArchived(false), isTrue);
      expect(api.lastArchived, isFalse);
    });

    test('删除成功 → 返回 true', () async {
      final api = _FakeChatApi();
      final container = _buildContainer(api, _FakeClock());
      final controller = container.read(chatControllerProvider('s1').notifier);

      expect(await controller.deleteSession(), isTrue);
      expect(api.deleteCalls, 1);
    });

    test('分支成功 → 返回新会话 ID', () async {
      final api = _FakeChatApi();
      final container = _buildContainer(api, _FakeClock());
      final controller = container.read(chatControllerProvider('s1').notifier);

      final newId = await controller.branchSession();
      expect(newId, 'branch-s1');
      expect(api.branchCalls, 1);
    });

    test('消息级 branchAt：keep_count=index+1，越界拒绝', () async {
      final api = _FakeChatApi();
      api.sessionResult = {
        'session': {
          'session_id': 's1',
          'messages': [
            {'role': 'user', 'content': 'm0', 'message_id': 'u0'},
            {'role': 'assistant', 'content': 'm1', 'message_id': 'a0'},
            {'role': 'user', 'content': 'm2', 'message_id': 'u1'},
          ],
        },
      };
      final container = _buildContainer(api, _FakeClock());
      final controller = container.read(chatControllerProvider('s1').notifier);

      // 先加载 3 条消息
      await controller.loadMessages();
      expect(container.read(chatControllerProvider('s1')).messages.length, 3);

      // 从第 2 条（index=1）分支 → keep_count=2
      final newId = await controller.branchAt(1);
      expect(newId, 'branch-s1');
      expect(api.branchCalls, 1);
      expect(api.lastBranchKeepCount, 2);

      // 越界 → 拒绝
      expect(await controller.branchAt(3), isNull);
      expect(api.branchCalls, 1);
    });

    test('新会话（空 sessionId）操作全部拒绝', () async {
      final api = _FakeChatApi();
      final container = _buildContainer(api, _FakeClock());
      final controller = container.read(chatControllerProvider('').notifier);

      expect(await controller.renameSession('标题'), isFalse);
      expect(await controller.setPinned(true), isFalse);
      expect(await controller.setArchived(true), isFalse);
      expect(await controller.deleteSession(), isFalse);
      expect(await controller.branchSession(), isNull);
      expect(api.renameCalls, 0);
      expect(api.pinCalls, 0);
      expect(api.archiveCalls, 0);
      expect(api.deleteCalls, 0);
      expect(api.branchCalls, 0);
    });

    test('从此处截断成功 → keepCount = index+1 并刷新', () async {
      final api = _FakeChatApi();
      api.sessionResult = {
        'session': {
          'session_id': 's1',
          'messages': [
            {'role': 'user', 'content': 'a', 'message_id': 'm1'},
            {'role': 'assistant', 'content': 'b', 'message_id': 'm2'},
            {'role': 'user', 'content': 'c', 'message_id': 'm3'},
          ],
        },
      };
      final container = _buildContainer(api, _FakeClock());
      final controller = container.read(chatControllerProvider('s1').notifier);
      await controller.loadMessages();

      final ok = await controller.truncateAt(1);
      expect(ok, isTrue);
      expect(api.truncateCalls, 1);
      expect(api.truncateKeepCounts, [2]);
    });

    test('从此处截断：服务端失败 → false + 错误', () async {
      final api = _FakeChatApi();
      api.sessionResult = {
        'session': {
          'session_id': 's1',
          'messages': [
            {'role': 'user', 'content': 'a', 'message_id': 'm1'},
            {'role': 'assistant', 'content': 'b', 'message_id': 'm2'},
          ],
        },
      };
      api.mutationOk = false;
      api.mutationError = '截断被拒绝';
      final container = _buildContainer(api, _FakeClock());
      final controller = container.read(chatControllerProvider('s1').notifier);
      await controller.loadMessages();

      final ok = await controller.truncateAt(0);
      expect(ok, isFalse);
      expect(
        container.read(chatControllerProvider('s1')).sendErrorMessage,
        '截断被拒绝',
      );
      expect(api.truncateKeepCounts, [1]);
    });

    test('从此处截断：越界 → false 且不发请求', () async {
      final api = _FakeChatApi();
      api.sessionResult = {
        'session': {
          'session_id': 's1',
          'messages': [
            {'role': 'user', 'content': 'a', 'message_id': 'm1'},
          ],
        },
      };
      final container = _buildContainer(api, _FakeClock());
      final controller = container.read(chatControllerProvider('s1').notifier);
      await controller.loadMessages();

      expect(await controller.truncateAt(5), isFalse);
      expect(await controller.truncateAt(-1), isFalse);
      expect(api.truncateCalls, 0);
    });

    test('prefillComposer → 设置 composerPrefill', () async {
      final api = _FakeChatApi();
      final container = _buildContainer(api, _FakeClock());
      final controller = container.read(chatControllerProvider('s1').notifier);

      controller.prefillComposer('回填内容');
      expect(
        container.read(chatControllerProvider('s1')).composerPrefill,
        '回填内容',
      );
    });

    test('只读会话：truncate/prefill 拒绝', () async {
      final api = _FakeChatApi();
      api.sessionResult = {
        'session': {
          'session_id': 's1',
          'read_only': true,
          'messages': [
            {'role': 'user', 'content': 'a', 'message_id': 'm1'},
          ],
        },
      };
      final container = _buildContainer(api, _FakeClock());
      final controller = container.read(chatControllerProvider('s1').notifier);
      await controller.loadMessages();

      expect(await controller.truncateAt(0), isFalse);
      expect(api.truncateCalls, 0);
      controller.prefillComposer('x');
      expect(
        container.read(chatControllerProvider('s1')).composerPrefill,
        isNull,
      );
    });
  });
}

// ---------------------------------------------------------------------------
// 测试基础设施
// ---------------------------------------------------------------------------

class _FakeClock {
  DateTime now = DateTime(2026, 1, 1);

  DateTime call() => now;

  void advance(Duration duration) => now = now.add(duration);
}

typedef _FakeChatApi = FakeChatApi;

ProviderContainer _buildContainer(_FakeChatApi api, _FakeClock clock) {
  final container = ProviderContainer(
    overrides: [
      chatApiProvider.overrideWithValue(api),
      chatClockProvider.overrideWithValue(clock.call),
    ],
  );
  addTearDown(container.dispose);
  return container;
}
