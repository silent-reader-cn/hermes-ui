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

/// 回合完成 → 会话列表刷新的节流状态。
///
/// 挂在 Provider 上：同一 ProviderContainer 内所有 ChatController 实例
/// （不同会话并发完成）共享节流窗口，合并为一次列表刷新；跨容器
/// （测试）天然隔离，避免模块级状态泄漏。
class SessionListRefreshThrottleState {
  /// 最近一次回合完成触发的会话列表刷新时间。
  DateTime? lastRefreshAt;
}

/// #30：回合完成 → 会话列表刷新节流状态 Provider。
final sessionListRefreshThrottleProvider =
    Provider<SessionListRefreshThrottleState>(
      (ref) => SessionListRefreshThrottleState(),
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

/// 澄清请求回调（clarify 事件触发时由 [ChatController] 调用）。
typedef ChatClarificationNeededCallback = void Function(
  String sessionId,
  String question,
);

/// 澄清请求回调 Provider（notifications feature 注入点）。
final chatClarificationNeededCallbackProvider =
    Provider<ChatClarificationNeededCallback>(
  (ref) => (sessionId, question) {},
);

/// 会话异常回调（cancel / error / 重连失败时由 [ChatController] 调用）。
typedef ChatSessionErrorCallback = void Function(
  String sessionId,
  String title,
  String preview,
);

/// 会话异常回调 Provider（notifications feature 注入点）。
final chatSessionErrorCallbackProvider = Provider<ChatSessionErrorCallback>(
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

/// live 时间线（流式回合内 think/text/tools 按事件先后穿插的展示条目）。
///
/// 返回语义：
/// - `null`：非时间线模式（重连归档等无法还原段落边界的场景）→ 渲染层回退
///   旧的「分组式」流式气泡（思考卡 → 正文 → 工具卡），保证不丢内容；
/// - 空列表：流式存在但尚无任何可见内容 → 思考中指示器；
/// - 非空：按事件顺序排列的段落条目，渲染层逐条渲染。
///
/// 聚合开关语义与历史一致：coalesce=true 时同类型段落合并为一卡（挂在
/// 首现位置）；coalesce=false 时每段独立一卡（相邻工具段自然即「相邻合并」）。
final liveTimelineProvider = Provider.family<List<LiveTimelineEntry>?, String>((
  ref,
  sessionId,
) {
  final state = ref.watch(chatControllerProvider(sessionId));
  final id = state.stream.streamingAssistantMessageId;
  if (id == null) return null;
  ChatMessage? streamingMessage;
  for (final message in state.messages) {
    if (message.messageId == id) {
      streamingMessage = message;
      break;
    }
  }
  if (streamingMessage == null) return null;

  final content = streamingMessage.content ?? '';
  final reasoningText = state.liveReasoningText;
  final points = state.liveTimelinePoints;
  final hideReasoning = ref.watch(hideReasoningProvider);
  final toolCoalesce = ref.watch(toolGroupCoalesceProvider);

  // 断点为空但有锚定本流式消息的归档内容（重连/恢复路径）→ 无法还原段落
  // 边界，回退旧分组式气泡（内容与卡片由 legacy streamingTools 过滤承载）。
  if (points.isEmpty) {
    final hasAnchoredArchive =
        state.completedToolCallGroups.any((g) => g.anchorMessageID == id) ||
        state.completedReasoningGroups.any((g) => g.anchorMessageId == id);
    if (hasAnchoredArchive) return null;
    if (content.trim().isEmpty &&
        reasoningText.trim().isEmpty &&
        state.liveToolCalls.isEmpty) {
      return const <LiveTimelineEntry>[]; // 思考中指示器
    }
    // 防御兜底：内容非空但断点缺失 → 按「思考 → 正文 → 工具」单段呈现。
    return _fallbackSingleSegments(
      streamingId: id,
      content: content,
      reasoningText: reasoningText,
      liveToolCalls: state.liveToolCalls,
      hideReasoning: hideReasoning,
      toolCoalesce: toolCoalesce,
    );
  }

  // 按 kind 分组切片边界。
  final textStarts = <int>[];
  final thinkStarts = <int>[];
  final toolStarts = <int>[];
  for (final point in points) {
    switch (point.kind) {
      case LiveSegmentKind.text:
        textStarts.add(point.start);
      case LiveSegmentKind.thinking:
        thinkStarts.add(point.start);
      case LiveSegmentKind.tools:
        toolStarts.add(point.start);
    }
  }

  final textSegments = <({int start, int end})>[];
  for (var i = 0; i < textStarts.length; i++) {
    // 断点含 pending 缓冲长度，中间态可能超过已 flush 的 content 长度，
    // 两侧 clamp 保证切片安全（内容随后续 reveal 增长补齐）。
    final rawEnd = i + 1 < textStarts.length
        ? textStarts[i + 1]
        : content.length;
    final start = textStarts[i].clamp(0, content.length);
    final end = rawEnd.clamp(start, content.length);
    if (end > start) textSegments.add((start: start, end: end));
  }
  final thinkSegments = <String>[];
  for (var i = 0; i < thinkStarts.length; i++) {
    final rawEnd = i + 1 < thinkStarts.length
        ? thinkStarts[i + 1]
        : reasoningText.length;
    final start = thinkStarts[i].clamp(0, reasoningText.length);
    final end = rawEnd.clamp(start, reasoningText.length);
    if (end <= start) continue;
    final segment = reasoningText.substring(start, end).trim();
    if (segment.isNotEmpty) thinkSegments.add(segment);
  }
  final toolSegments = <List<ToolCall>>[];
  for (var i = 0; i < toolStarts.length; i++) {
    final start = toolStarts[i];
    final end = i + 1 < toolStarts.length
        ? toolStarts[i + 1]
        : state.liveToolCalls.length;
    if (end > start) {
      toolSegments.add(state.liveToolCalls.sublist(start, end));
    }
  }

  final entries = <LiveTimelineEntry>[];
  // 混合行缓冲：思考子卡行与工具行按断点序统一累积，flush 时合并为一
  // 张工具卡（思考为卡内子行，行序即事件时间线）。toolCoalesce=true
  // 整回合一张（仅末尾 flush）；false 按 text 区段拆分（text 断点 flush）。
  final pendingCallBlock = <({int seq, ToolCall call})>[];
  // 重连/重锚定场景：首个断点前的内容无断点覆盖（如恢复时锚定到一条
  // 已有内容的 assistant 消息），作为「孤儿段」前置，保证旧内容不丢失。
  final orphanText = textStarts.isNotEmpty && textStarts.first > 0
      ? content.substring(0, textStarts.first.clamp(0, content.length))
      : null;
  final orphanThink = thinkStarts.isNotEmpty && thinkStarts.first > 0
      ? reasoningText
            .substring(0, thinkStarts.first.clamp(0, reasoningText.length))
            .trim()
      : null;
  final orphanToolCount = toolStarts.isNotEmpty && toolStarts.first > 0
      ? toolStarts.first
      : 0;
  if (orphanText != null && orphanText.trim().isNotEmpty) {
    entries.add(
      LiveTimelineEntry(
        kind: LiveSegmentKind.text,
        renderKey: 'live:text:orphan',
        textSlice: orphanText,
      ),
    );
  }
  if (orphanThink != null && orphanThink.isNotEmpty && !hideReasoning) {
    pendingCallBlock.add((seq: -1, call: ToolCall.thinking(orphanThink)));
  }
  if (orphanToolCount > 0) {
    for (final call in state.liveToolCalls.sublist(0, orphanToolCount)) {
      pendingCallBlock.add((seq: -1, call: call));
    }
  }

  var textIndex = 0;
  var thinkIndex = 0;
  var toolIndex = 0;

  void flushBlock() {
    if (pendingCallBlock.isEmpty) return;
    final firstSeq = pendingCallBlock.first.seq;
    final renderKey = firstSeq < 0
        ? 'live:tools:orphan'
        : (toolCoalesce ? 'live:tools:merged' : 'live:tools:$firstSeq');
    entries.add(
      LiveTimelineEntry(
        kind: LiveSegmentKind.tools,
        renderKey: renderKey,
        toolGroup: ToolCallGroup(
          id: 'live-timeline-tools-${firstSeq < 0 ? 'orphan' : '$firstSeq'}',
          anchorMessageID: id,
          toolCalls: [for (final e in pendingCallBlock) e.call],
        ),
      ),
    );
    pendingCallBlock.clear();
  }

  for (final point in points) {
    switch (point.kind) {
      case LiveSegmentKind.text:
        // 关闭聚合：text 断点分区块（思考行/工具行随区段合并）。
        if (!toolCoalesce) flushBlock();
        if (textIndex < textSegments.length) {
          final segment = textSegments[textIndex];
          entries.add(
            LiveTimelineEntry(
              kind: LiveSegmentKind.text,
              renderKey: 'live:text:${point.sequence}',
              textSlice: content.substring(segment.start, segment.end),
            ),
          );
        }
        textIndex++;
      case LiveSegmentKind.thinking:
        // 思考降级为工具卡子卡行：并入混合块（时间线与工具行混排）。
        if (!hideReasoning && thinkIndex < thinkSegments.length) {
          pendingCallBlock.add((
            seq: point.sequence,
            call: ToolCall.thinking(thinkSegments[thinkIndex]),
          ));
        }
        thinkIndex++;
      case LiveSegmentKind.tools:
        if (toolIndex < toolSegments.length) {
          for (final call in toolSegments[toolIndex]) {
            pendingCallBlock.add((seq: point.sequence, call: call));
          }
        }
        toolIndex++;
    }
  }
  flushBlock();
  return entries;
});

/// 断点缺失时的单段兜底（防御路径，理论不可达）。
List<LiveTimelineEntry> _fallbackSingleSegments({
  required String streamingId,
  required String content,
  required String reasoningText,
  required List<ToolCall> liveToolCalls,
  required bool hideReasoning,
  required bool toolCoalesce,
}) {
  final entries = <LiveTimelineEntry>[];
  // 思考子卡行并入工具条目（think 行前置，时间线一致）。
  final calls = <ToolCall>[
    if (!hideReasoning && reasoningText.trim().isNotEmpty)
      ToolCall.thinking(reasoningText.trim()),
    ...liveToolCalls,
  ];
  if (calls.isNotEmpty) {
    entries.add(
      LiveTimelineEntry(
        kind: LiveSegmentKind.tools,
        renderKey: 'live:tools:fallback',
        toolGroup: ToolCallGroup(
          id: 'live-timeline-tools-fallback',
          anchorMessageID: streamingId,
          toolCalls: toolCoalesce ? calls : [for (final call in calls) call],
        ),
      ),
    );
  }
  if (content.trim().isNotEmpty) {
    entries.add(
      LiveTimelineEntry(
        kind: LiveSegmentKind.text,
        renderKey: 'live:text:fallback',
        textSlice: content,
      ),
    );
  }
  return entries;
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
