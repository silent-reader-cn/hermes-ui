import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/connections/connection_providers.dart';
import '../../core/models/chat_message.dart';
import '../../core/models/tool_call.dart';
import 'chat_controller.dart';
import 'chat_models.dart';
import 'chat_server_api.dart';
import 'chat_state.dart';

/// 看门狗阈值配置（chat_spec.md §5.3；测试可 override 缩短阈值）。
class ChatWatchdogConfig {
  const ChatWatchdogConfig({
    this.watchdogInterval = const Duration(seconds: 1),
    this.progressStaleThreshold = const Duration(seconds: 5),
    this.transportStaleThreshold = const Duration(seconds: 12),
    this.forceReconnectThreshold = const Duration(seconds: 18),
    this.forceReconnectWithRunningToolsThreshold = const Duration(seconds: 25),
    this.statusPollCooldown = const Duration(seconds: 4),
  });

  /// 前台看门狗心跳间隔。
  final Duration watchdogInterval;

  /// 距上次进度 ≥ 该值（且传输 ≥ [transportStaleThreshold]）→ checking。
  final Duration progressStaleThreshold;

  /// 距上次传输活动 ≥ 该值 → 触发 status 检查。
  final Duration transportStaleThreshold;

  /// 距上次传输活动 ≥ 该值（无运行中工具）→ 强制重连。
  final Duration forceReconnectThreshold;

  /// 距上次传输活动 ≥ 该值（有运行中工具）→ 强制重连。
  final Duration forceReconnectWithRunningToolsThreshold;

  /// status 轮询冷却。
  final Duration statusPollCooldown;
}

/// 看门狗配置 Provider（测试可 override）。
final chatWatchdogConfigProvider = Provider<ChatWatchdogConfig>(
  (ref) => const ChatWatchdogConfig(),
);

/// 时钟 Provider（看门狗/时间戳用；测试可 override 注入可控假时钟）。
final chatClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

/// 聊天服务器 API（生产 [ChatApiClient] 包 ApiClient；测试可 override 注入 fake）。
final chatApiProvider = Provider<ChatServerApi>((ref) {
  final client = ref.watch(apiClientProvider);
  return ChatApiClient(client);
});

/// 聊天控制器（family by sessionId；空串 = 新会话）。
final chatControllerProvider =
    NotifierProvider.family<ChatController, ChatState, String>(
  ChatController.new,
);

/// 当前相位（UI 主分支只 switch 它）。
final chatPhaseProvider = Provider.family<ChatPhase, String>((ref, sessionId) {
  return ref.watch(chatControllerProvider(sessionId)).phase;
});

/// 是否可发送（idle 且非缓存模式且无停止在途）。
final canSendProvider = Provider.family<bool, String>((ref, sessionId) {
  final state = ref.watch(chatControllerProvider(sessionId));
  return state.phase == ChatPhase.idle &&
      !state.isViewingCachedData &&
      !state.stream.isCancelling;
});

/// 展示层转录消息（过滤 tool 消息 / 纯工具结果消息 / 流式消息；renderId 稳定）。
final transcriptMessagesProvider =
    Provider.family<List<TranscriptMessage>, String>((ref, sessionId) {
  final state = ref.watch(chatControllerProvider(sessionId));
  final messages = state.messages;
  final offset = state.messagesOffset;
  final streamingId = state.stream.streamingAssistantMessageId;
  final result = <TranscriptMessage>[];
  for (var i = 0; i < messages.length; i++) {
    final message = messages[i];
    if (message.role == 'tool') continue;
    if (TranscriptTurnClassifier.isToolResultOnlyMessage(message)) continue;
    if (message.messageId != null && message.messageId == streamingId) continue;
    result.add(TranscriptMessage(
      loadedIndex: i,
      renderId: 'transcript:${offset + i}',
      anchorId:
          TranscriptTurnClassifier.anchorID(message, at: i, messageOffset: offset),
      message: message,
    ));
  }
  return result;
});

/// 当前流式 assistant 消息（独立流式气泡渲染层）。
final streamingMessageProvider = Provider.family<ChatMessage?, String>(
  (ref, sessionId) {
    final state = ref.watch(chatControllerProvider(sessionId));
    final id = state.stream.streamingAssistantMessageId;
    if (id == null) return null;
    for (final message in state.messages) {
      if (message.messageId == id) return message;
    }
    return null;
  },
);

/// 工具调用组（已归档 + 实时组合，按 assistant 回合分组）。
final toolGroupsProvider = Provider.family<List<ToolCallGroup>, String>(
  (ref, sessionId) {
    final state = ref.watch(chatControllerProvider(sessionId));
    final live = state.liveToolCalls.isEmpty
        ? const <ToolCallGroup>[]
        : [
            ToolCallGroup.live(
              anchorMessageID: state.stream.toolCallAnchorMessageId ??
                  state.stream.streamingAssistantMessageId,
              toolCalls: state.liveToolCalls,
            ),
          ];
    return [...state.completedToolCallGroups, ...live];
  },
);

/// 推理组（已归档 + 实时组合）。
final reasoningGroupsProvider = Provider.family<List<ReasoningGroup>, String>(
  (ref, sessionId) {
    final state = ref.watch(chatControllerProvider(sessionId));
    final live = state.liveReasoningText.isEmpty
        ? const <ReasoningGroup>[]
        : [
            ReasoningGroup(
              anchorMessageId: state.stream.reasoningAnchorMessageId ??
                  state.stream.streamingAssistantMessageId,
              text: state.liveReasoningText,
            ),
          ];
    return [...state.completedReasoningGroups, ...live];
  },
);

/// 排队待发送消息数。
final queuedCountProvider = Provider.family<int, String>((ref, sessionId) {
  return ref.watch(chatControllerProvider(sessionId)).queuedSlashMessages.length;
});

/// 模型选择器可选项（默认空 = 仅"跟随服务器默认"；测试可 override）。
final chatAvailableModelsProvider = Provider<List<String>>((ref) => const []);

