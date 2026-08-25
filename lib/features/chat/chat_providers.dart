import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/connections/connection_providers.dart';
import '../../core/models/chat_message.dart';
import '../../core/models/tool_call.dart';
import '../settings/tool_group_settings.dart';
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
final chatClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

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

/// 回合完成回调（done / stream_end 成功收尾时由 [ChatController] 调用）。
///
/// 默认 no-op（测试不受影响）；生产由 main.dart 用
/// notifications 的 [turnNotificationHookProvider] override 注入，
/// 实现「后台发通知、前台不发」。
typedef ChatTurnCompletedCallback = void Function(
  String sessionId,
  String title,
  String preview,
);

/// 回合完成回调 Provider（notifications feature 注入点）。
final chatTurnCompletedCallbackProvider = Provider<ChatTurnCompletedCallback>(
  (ref) => (sessionId, title, preview) {},
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
      !state.isShowingOfflineCache &&
      !state.stream.isCancelling;
});

/// 展示层转录消息（过滤 tool 消息 / 纯工具结果消息 / 流式消息；renderId 稳定）。
final transcriptMessagesProvider =
    Provider.family<List<TranscriptMessage>, String>((ref, sessionId) {
      final state = ref.watch(chatControllerProvider(sessionId));
      final messages = state.messages;
      final offset = state.messagesOffset;
      final streamingId = state.stream.streamingAssistantMessageId;
      final completedToolGroups = state.completedToolCallGroups;
      final completedReasoningGroups = state.completedReasoningGroups;
      final result = <TranscriptMessage>[];
      for (var i = 0; i < messages.length; i++) {
        final message = messages[i];
        if (message.role == 'tool') continue;
        if (TranscriptTurnClassifier.isToolResultOnlyMessage(message)) continue;
        if (message.messageId != null && message.messageId == streamingId) {
          continue;
        }

        // Hermex parity: do not create a visible row for empty internal messages.
        // Attachment-only user messages remain visible; reasoning/tool groups are
        // rendered on their anchored assistant row even when its text is empty.
        final hasVisibleContent = message.content?.trim().isNotEmpty == true;
        final hasAttachments = message.attachments?.isNotEmpty == true;
        final anchorId = TranscriptTurnClassifier.anchorID(
          message,
          at: i,
          messageOffset: offset,
        );
        final hasToolGroups = completedToolGroups.any(
          (group) =>
              group.anchorMessageID == message.messageId ||
              group.anchorMessageID == anchorId,
        );
        final hasReasoningGroups = completedReasoningGroups.any(
          (group) =>
              group.anchorMessageId == message.messageId ||
              group.anchorMessageId == anchorId,
        );
        if (!hasVisibleContent &&
            !hasAttachments &&
            !hasToolGroups &&
            !hasReasoningGroups) {
          continue;
        }
        result.add(
          TranscriptMessage(
            loadedIndex: i,
            renderId: 'transcript:${offset + i}',
            anchorId: anchorId,
            message: message,
          ),
        );
      }
      return result;
    });

/// 当前流式 assistant 消息（独立流式气泡渲染层）。
final streamingMessageProvider = Provider.family<ChatMessage?, String>((
  ref,
  sessionId,
) {
  final state = ref.watch(chatControllerProvider(sessionId));
  final id = state.stream.streamingAssistantMessageId;
  if (id == null) return null;
  for (final message in state.messages) {
    if (message.messageId == id) return message;
  }
  return null;
});

/// 工具调用组（已归档 + 实时组合，按 assistant 回合分组或按消息穿插）。
final toolGroupsProvider = Provider.family<List<ToolCallGroup>, String>((
  ref,
  sessionId,
) {
  final state = ref.watch(chatControllerProvider(sessionId));
  final coalesce = ref.watch(toolGroupCoalesceProvider);
  final liveAnchor =
      state.stream.toolCallAnchorMessageId ??
      state.stream.streamingAssistantMessageId;
  // live 工具组遵循聚合设置：开启时累积为一张卡（整轮聚合）；
  // 关闭时按次拆分（每个工具调用一张卡），不再「总是按回合聚合」。
  final live = state.liveToolCalls.isEmpty
      ? const <ToolCallGroup>[]
      : coalesce
      ? [
          ToolCallGroup.live(
            anchorMessageID: liveAnchor,
            toolCalls: state.liveToolCalls,
          ),
        ]
      : [
          for (final call in state.liveToolCalls)
            ToolCallGroup.live(anchorMessageID: liveAnchor, toolCalls: [call]),
        ];
  final raw = [...state.completedToolCallGroups, ...live];
  if (raw.length <= 1) return raw;
  if (!coalesce) {
    // 关闭 ≠ 完全不聚合：仅相邻（无 text/think 打断）组合并，支持穿插呈现。
    // completed 已由 controller 按相邻语义生成；live 已逐卡拆分，直接返回。
    return raw;
  }
  return ToolCallGroup.coalescingByAssistantTurn(
    raw,
    messages: state.messages,
    messageOffset: state.messagesOffset,
  );
});

/// 推理组（已归档 + 实时组合；受「思考聚合 / 隐藏思考」设置控制）。
final reasoningGroupsProvider = Provider.family<List<ReasoningGroup>, String>((
  ref,
  sessionId,
) {
  final state = ref.watch(chatControllerProvider(sessionId));
  final hide = ref.watch(hideReasoningProvider);
  if (hide) return const [];
  final coalesce = ref.watch(thinkGroupCoalesceProvider);
  final live = state.liveReasoningText.isEmpty
      ? const <ReasoningGroup>[]
      : [
          ReasoningGroup(
            anchorMessageId:
                state.stream.reasoningAnchorMessageId ??
                state.stream.streamingAssistantMessageId,
            text: state.liveReasoningText,
          ),
        ];
  final raw = [...state.completedReasoningGroups, ...live];
  if (raw.length <= 1) return raw;
  // 去重兜底：同一锚点+同文本的推理段只保留一份（重连/重放时 completed 与
  // live 可能携带同一思考内容，合并前先去重，避免 double 思考卡）。
  final distinct = _distinctReasoning(raw);
  if (distinct.length <= 1) return distinct;
  if (!coalesce) {
    // 关闭 ≠ 完全不聚合：仅相邻（无 text/tool 打断）的思考段合并。
    return ReasoningGroup.coalescingAdjacent(
      distinct,
      messages: state.messages,
      messageOffset: state.messagesOffset,
    );
  }
  return ReasoningGroup.coalescingByTurn(
    distinct,
    messages: state.messages,
    messageOffset: state.messagesOffset,
  );
});

List<ReasoningGroup> _distinctReasoning(List<ReasoningGroup> groups) {
  final seen = <String>{};
  final out = <ReasoningGroup>[];
  for (final g in groups) {
    final key = '${g.anchorMessageId ?? ''}:${g.text.trim()}';
    if (seen.add(key)) out.add(g);
  }
  return out;
}

/// 排队待发送消息数。
final queuedCountProvider = Provider.family<int, String>((ref, sessionId) {
  return ref
      .watch(chatControllerProvider(sessionId))
      .queuedSlashMessages
      .length;
});

/// 模型选择器可选项（默认空 = 仅"跟随服务器默认"；测试可 override）。
final chatAvailableModelsProvider = Provider<List<String>>((ref) => const []);
