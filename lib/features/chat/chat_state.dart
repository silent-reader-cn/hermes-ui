import '../../core/models/chat_message.dart';
import '../../core/models/context_window_snapshot.dart';
import '../../core/models/tool_call.dart';
import 'chat_models.dart';

/// 聊天主相位（chat_spec.md §2.1 九态）。
///
/// UI 主分支只 switch 本枚举；细粒度控制位在 [ChatStreamState] /
/// [ChatPendingActionState] 中保留（对齐 Hermex 的布尔标志）。
enum ChatPhase {
  /// 无流、无发送请求在途（可自由操作）。
  idle,

  /// POST /api/chat/start 在途（isStartingChat）；未拿到 stream_id。
  sending,

  /// activeStreamId != nil，SSE 连接存活，正常吐字/推理/工具。
  streaming,

  /// 子状态：POST /api/chat/steer 已 accepted，流继续，UI 显示 "steering"。
  steered,

  /// approvalPrompt != nil（流仍连）。
  approvalPending,

  /// clarificationPrompt != nil。
  clarifyPending,

  /// 传输断开后的恢复期（recovery=checking/reconnecting）。
  recovering,

  /// 收到 cancel 事件（瞬时，收尾后立即回 idle）。
  cancelled,

  /// 收到 error/apperror 或 transportError 且无法恢复（收尾后回 idle）。
  error,
}

/// 活跃流恢复阶段（chat_spec.md §2.1 映射表）。
enum ActiveStreamRecoveryState {
  /// 无恢复进行中。
  idle,

  /// 已挂起，正在检查 /api/chat/stream/status。
  checking,

  /// 正在重连（replay 或全量）。
  reconnecting,
}

/// 流式期间发送新消息的行为（chat_spec.md §4.2，默认 steer）。
enum StreamingSendBehavior {
  /// POST /api/chat/steer：提示而非消息，不追加 user 气泡。
  steer,

  /// 入队（队首）+ cancelActiveStream。
  interrupt,

  /// 仅入队 queuedSlashMessages，流结束后自动顺次发送。
  queue,
}

/// 流状态（chat_spec.md §2.1 映射表：activeStreamID / isCancelling /
/// hasCompletedResponse / isConnectionSuspended / recoveryState / lastEventID）。
class ChatStreamState {
  const ChatStreamState({
    this.activeStreamId,
    this.isSuspended = false,
    this.recovery = ActiveStreamRecoveryState.idle,
    this.lastEventId,
    this.hasCompletedResponse = false,
    this.isCancelling = false,
    this.streamingAssistantMessageId,
    this.toolCallAnchorMessageId,
    this.reasoningAnchorMessageId,
    this.liveTokensPerSecond,
    this.isReplayConnection = false,
    this.matchedPrefixLength = 0,
    this.matchedReasoningLength = 0,
    this.replayToolMatchIndex = 0,
  });

  /// activeStreamID != nil：流存在（streaming/steered/approvalPending/…）。
  final String? activeStreamId;

  /// 传输断开/挂起，等待恢复（isConnectionSuspended）。
  final bool isSuspended;

  /// 恢复阶段（recoveryState）。
  final ActiveStreamRecoveryState recovery;

  /// 最近一个 SSE 事件 `id:` 字段（重连续传用，非请求头 Last-Event-ID）。
  final String? lastEventId;

  /// done 已收尾（防 stream_end 重复收尾）。
  final bool hasCompletedResponse;

  /// 停止请求在途（isCancellingStream）。
  final bool isCancelling;

  /// 流式 assistant 消息 ID（token/reasoning/tool 全部锚定这一条）。
  final String? streamingAssistantMessageId;

  /// 本条回合第一个工具事件锚定的 assistant 消息 ID。
  final String? toolCallAnchorMessageId;

  /// reasoning 锚点（按 assistant turn 归档用）。
  final String? reasoningAnchorMessageId;

  /// 可展示 tps（metering 事件，session 匹配后）。
  final double? liveTokensPerSecond;

  /// replay 连接去重开关（首个非重复 token 或 resetRecoveryState 关闭）。
  final bool isReplayConnection;

  /// token 去重游标（已匹配进 existingContent 的字符数）。
  final int matchedPrefixLength;

  /// reasoning 去重游标。
  final int matchedReasoningLength;

  /// 无 stableID 工具事件重放去重的顺序游标。
  final int replayToolMatchIndex;

  /// 是否有活跃流（streaming/steered/approvalPending/clarifyPending/recovering）。
  bool get hasActiveStream => activeStreamId != null;

  ChatStreamState copyWith({
    String? activeStreamId,
    bool clearActiveStreamId = false,
    bool? isSuspended,
    ActiveStreamRecoveryState? recovery,
    String? lastEventId,
    bool clearLastEventId = false,
    bool? hasCompletedResponse,
    bool? isCancelling,
    String? streamingAssistantMessageId,
    bool clearStreamingAssistantMessageId = false,
    String? toolCallAnchorMessageId,
    bool clearToolCallAnchorMessageId = false,
    String? reasoningAnchorMessageId,
    bool clearReasoningAnchorMessageId = false,
    double? liveTokensPerSecond,
    bool clearLiveTokensPerSecond = false,
    bool? isReplayConnection,
    int? matchedPrefixLength,
    int? matchedReasoningLength,
    int? replayToolMatchIndex,
  }) {
    return ChatStreamState(
      activeStreamId: clearActiveStreamId ? null : (activeStreamId ?? this.activeStreamId),
      isSuspended: isSuspended ?? this.isSuspended,
      recovery: recovery ?? this.recovery,
      lastEventId: clearLastEventId ? null : (lastEventId ?? this.lastEventId),
      hasCompletedResponse: hasCompletedResponse ?? this.hasCompletedResponse,
      isCancelling: isCancelling ?? this.isCancelling,
      streamingAssistantMessageId: clearStreamingAssistantMessageId
          ? null
          : (streamingAssistantMessageId ?? this.streamingAssistantMessageId),
      toolCallAnchorMessageId: clearToolCallAnchorMessageId
          ? null
          : (toolCallAnchorMessageId ?? this.toolCallAnchorMessageId),
      reasoningAnchorMessageId: clearReasoningAnchorMessageId
          ? null
          : (reasoningAnchorMessageId ?? this.reasoningAnchorMessageId),
      liveTokensPerSecond: clearLiveTokensPerSecond
          ? null
          : (liveTokensPerSecond ?? this.liveTokensPerSecond),
      isReplayConnection: isReplayConnection ?? this.isReplayConnection,
      matchedPrefixLength: matchedPrefixLength ?? this.matchedPrefixLength,
      matchedReasoningLength:
          matchedReasoningLength ?? this.matchedReasoningLength,
      replayToolMatchIndex: replayToolMatchIndex ?? this.replayToolMatchIndex,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ChatStreamState &&
        other.activeStreamId == activeStreamId &&
        other.isSuspended == isSuspended &&
        other.recovery == recovery &&
        other.lastEventId == lastEventId &&
        other.hasCompletedResponse == hasCompletedResponse &&
        other.isCancelling == isCancelling &&
        other.streamingAssistantMessageId == streamingAssistantMessageId &&
        other.toolCallAnchorMessageId == toolCallAnchorMessageId &&
        other.reasoningAnchorMessageId == reasoningAnchorMessageId &&
        other.liveTokensPerSecond == liveTokensPerSecond &&
        other.isReplayConnection == isReplayConnection &&
        other.matchedPrefixLength == matchedPrefixLength &&
        other.matchedReasoningLength == matchedReasoningLength &&
        other.replayToolMatchIndex == replayToolMatchIndex;
  }

  @override
  int get hashCode {
    return Object.hash(
      activeStreamId,
      isSuspended,
      recovery,
      lastEventId,
      hasCompletedResponse,
      isCancelling,
      streamingAssistantMessageId,
      toolCallAnchorMessageId,
      reasoningAnchorMessageId,
      liveTokensPerSecond,
      isReplayConnection,
      matchedPrefixLength,
      matchedReasoningLength,
      replayToolMatchIndex,
    );
  }

  @override
  String toString() => 'ChatStreamState(activeStreamId: $activeStreamId, '
      'recovery: $recovery, hasCompletedResponse: $hasCompletedResponse)';
}

/// 审批/澄清卡片状态（chat_spec.md §2.1 映射表）。
class ChatPendingActionState {
  const ChatPendingActionState({this.approvalPrompt, this.clarificationPrompt});

  /// approvalPrompt != nil → 有审批卡片。
  final Map<String, Object?>? approvalPrompt;

  /// clarificationPrompt != nil → 有澄清卡片。
  final Map<String, Object?>? clarificationPrompt;

  /// 有任一待处理提示（恢复看门狗在此时暂停）。
  bool get hasPendingPrompt =>
      approvalPrompt != null || clarificationPrompt != null;

  ChatPendingActionState copyWith({
    Map<String, Object?>? approvalPrompt,
    bool clearApproval = false,
    Map<String, Object?>? clarificationPrompt,
    bool clearClarification = false,
  }) {
    return ChatPendingActionState(
      approvalPrompt:
          clearApproval ? null : (approvalPrompt ?? this.approvalPrompt),
      clarificationPrompt: clearClarification
          ? null
          : (clarificationPrompt ?? this.clarificationPrompt),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ChatPendingActionState &&
        _mapEquals(other.approvalPrompt, approvalPrompt) &&
        _mapEquals(other.clarificationPrompt, clarificationPrompt);
  }

  @override
  int get hashCode => Object.hash(
        _mapHash(approvalPrompt),
        _mapHash(clarificationPrompt),
      );

  static bool _mapEquals(Map<String, Object?>? a, Map<String, Object?>? b) {
    if (a == null || b == null) return a == b;
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (!_valueEquals(entry.value, b[entry.key])) return false;
    }
    return true;
  }

  static bool _valueEquals(Object? a, Object? b) {
    if (a is Map && b is Map) {
      return _mapEquals(
        Map<String, Object?>.from(a),
        Map<String, Object?>.from(b),
      );
    }
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (!_valueEquals(a[i], b[i])) return false;
      }
      return true;
    }
    return a == b;
  }

  static int _mapHash(Map<String, Object?>? map) {
    if (map == null) return 0;
    return Object.hashAllUnordered(map.entries.map((e) => Object.hash(e.key, e.value)));
  }
}

/// 聊天全量状态（不可变；任何变更整列表替换，配 Notifier 通知）。
class ChatState {
  const ChatState({
    required this.sessionId,
    this.phase = ChatPhase.idle,
    this.messages = const [],
    this.messagesOffset = 0,
    this.hasOlderMessages = false,
    this.displayTitle = 'Untitled Session',
    this.workspace,
    this.model,
    this.modelProvider,
    this.profile,
    this.explicitModelPick = false,
    this.errorMessage,
    this.sendErrorMessage,
    this.noticeMessage,
    this.isViewingCachedData = false,
    this.isShowingOfflineCache = false,
    this.isReadOnly = false,
    this.hasPendingUserMessage = false,
    this.parentSessionId,
    this.yoloEnabled = false,
    this.composerPrefill,
    this.pendingAssistantTokenChunks = const [],
    this.pendingReasoningChunks = const [],
    this.liveReasoningText = '',
    this.liveToolCalls = const [],
    this.completedToolCallGroups = const [],
    this.completedReasoningGroups = const [],
    this.queuedSlashMessages = const [],
    this.pinnedLocalNotices = const [],
    this.lastSteerHint,
    this.stream = const ChatStreamState(),
    this.pendingAction = const ChatPendingActionState(),
    this.contextWindowSnapshot,
    this.responseCompletionNeedsTranscriptRefresh = false,
    this.streamingScrollTrigger = 0,
  });

  /// 初始状态（会话参数经 family key 传入）。
  factory ChatState.initial({required String sessionId}) {
    return ChatState(
      sessionId: sessionId,
      displayTitle: sessionId.isEmpty ? '新会话' : 'Untitled Session',
    );
  }

  /// 会话 id（空串 = 新会话）。
  final String sessionId;

  /// 主相位（九态之一，任何时刻只有一个生效）。
  final ChatPhase phase;

  /// 消息列表（不可变；流式期间仅 flush 时变更）。
  final List<ChatMessage> messages;

  /// 分页偏移。
  final int messagesOffset;

  /// 是否还有更早的消息可加载。
  final bool hasOlderMessages;

  /// 会话标题（title 事件 / done 会话 / 加载更新；空 → "Untitled Session"）。
  final String displayTitle;

  /// 会话参数（startChat body 透传）。
  final String? workspace;
  final String? model;
  final String? modelProvider;
  final String? profile;

  /// 用户刚显式选模型（startChat 带 explicit_model_pick）。
  final bool explicitModelPick;

  /// 会话级错误（errorMessage）。
  final String? errorMessage;

  /// 发送错误（error/apperror 事件、send/stop 失败）。
  final String? sendErrorMessage;

  /// 轻提示（成功类会话操作；非错误，渲染为中性横幅）。
  final String? noticeMessage;

  /// 离线缓存兜底模式（send 拒绝）。
  final bool isViewingCachedData;

  /// 是否正在展示离线缓存（离线回放模式）。
  final bool isShowingOfflineCache;

  /// 只读会话（read_only / is_read_only 为 true；变更操作全部拒绝）。
  final bool isReadOnly;

  /// 会话有待处理消息（pending_user_message / pending_attachments 非空）。
  final bool hasPendingUserMessage;

  /// 父会话 ID（分支会话非空，用于展示「分支」标识与跳转）。
  final String? parentSessionId;

  /// YOLO 模式开关（服务端内存态，重启丢失）。
  final bool yoloEnabled;

  /// 重试上一轮后待回填输入框的文本（UI 消费后立即清除）。
  final String? composerPrefill;

  /// token 三段式缓冲：合并缓冲（16ms 后进入词级 reveal 队列）。
  final List<String> pendingAssistantTokenChunks;

  /// reasoning 缓冲（flush 时整块写入 liveReasoningText）。
  final List<String> pendingReasoningChunks;

  /// 已 flush 的实时推理文本（reasoning 不写进 ChatMessage.content）。
  final String liveReasoningText;

  /// 实时工具调用（流期间，未归档）。
  final List<ToolCall> liveToolCalls;

  /// 已归档工具调用组（done / transcript 重载后）。
  final List<ToolCallGroup> completedToolCallGroups;

  /// 已归档推理段（按 assistant turn 分组）。
  final List<ReasoningGroup> completedReasoningGroups;

  /// 排队待发送消息（queue 行为 / steer 失败入队 / pending_steer_leftover）。
  final List<String> queuedSlashMessages;

  /// 流进行中产生的本地 notice（流结束后 flush 进 transcript）。
  final List<String> pinnedLocalNotices;

  /// 最近一次 steer 提示文本（ephemeral，不进 transcript；流结束后自动清除）。
  final String? lastSteerHint;

  /// 流状态（activeStreamId 等）。
  final ChatStreamState stream;

  /// 审批/澄清卡片状态。
  final ChatPendingActionState pendingAction;

  /// 上下文窗口快照（done usage / 会话加载）。
  final ContextWindowSnapshot? contextWindowSnapshot;

  /// done 后需要补拉 transcript（视图据此刷新）。
  final bool responseCompletionNeedsTranscriptRefresh;

  /// 流式内容 flush 计数（视图滚动跟随触发）。
  final int streamingScrollTrigger;

  /// isStartingChat（sending 相位）。
  bool get isStartingChat => phase == ChatPhase.sending;

  /// 是否有活跃流。
  bool get hasActiveStream => stream.hasActiveStream;

  ChatState copyWith({
    String? sessionId,
    ChatPhase? phase,
    List<ChatMessage>? messages,
    int? messagesOffset,
    bool? hasOlderMessages,
    String? displayTitle,
    String? workspace,
    String? model,
    String? modelProvider,
    String? profile,
    bool? explicitModelPick,
    String? errorMessage,
    bool clearErrorMessage = false,
    String? sendErrorMessage,
    bool clearSendErrorMessage = false,
    String? noticeMessage,
    bool clearNoticeMessage = false,
    bool? isViewingCachedData,
    bool? isShowingOfflineCache,
    bool? isReadOnly,
    bool? hasPendingUserMessage,
    String? parentSessionId,
    bool? yoloEnabled,
    String? composerPrefill,
    bool clearComposerPrefill = false,
    List<String>? pendingAssistantTokenChunks,
    List<String>? pendingReasoningChunks,
    String? liveReasoningText,
    List<ToolCall>? liveToolCalls,
    List<ToolCallGroup>? completedToolCallGroups,
    List<ReasoningGroup>? completedReasoningGroups,
    List<String>? queuedSlashMessages,
    List<String>? pinnedLocalNotices,
    String? lastSteerHint,
    bool clearLastSteerHint = false,
    ChatStreamState? stream,
    ChatPendingActionState? pendingAction,
    ContextWindowSnapshot? contextWindowSnapshot,
    bool clearContextWindowSnapshot = false,
    bool? responseCompletionNeedsTranscriptRefresh,
    int? streamingScrollTrigger,
  }) {
    return ChatState(
      sessionId: sessionId ?? this.sessionId,
      phase: phase ?? this.phase,
      messages: messages ?? this.messages,
      messagesOffset: messagesOffset ?? this.messagesOffset,
      hasOlderMessages: hasOlderMessages ?? this.hasOlderMessages,
      displayTitle: displayTitle ?? this.displayTitle,
      workspace: workspace ?? this.workspace,
      model: model ?? this.model,
      modelProvider: modelProvider ?? this.modelProvider,
      profile: profile ?? this.profile,
      explicitModelPick: explicitModelPick ?? this.explicitModelPick,
      errorMessage: clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
      sendErrorMessage:
          clearSendErrorMessage ? null : (sendErrorMessage ?? this.sendErrorMessage),
      noticeMessage: clearNoticeMessage ? null : (noticeMessage ?? this.noticeMessage),
      isViewingCachedData: isViewingCachedData ?? this.isViewingCachedData,
      isShowingOfflineCache:
          isShowingOfflineCache ?? this.isShowingOfflineCache,
      isReadOnly: isReadOnly ?? this.isReadOnly,
      hasPendingUserMessage: hasPendingUserMessage ?? this.hasPendingUserMessage,
      parentSessionId: parentSessionId ?? this.parentSessionId,
      yoloEnabled: yoloEnabled ?? this.yoloEnabled,
      composerPrefill: clearComposerPrefill
          ? null
          : (composerPrefill ?? this.composerPrefill),
      pendingAssistantTokenChunks:
          pendingAssistantTokenChunks ?? this.pendingAssistantTokenChunks,
      pendingReasoningChunks:
          pendingReasoningChunks ?? this.pendingReasoningChunks,
      liveReasoningText: liveReasoningText ?? this.liveReasoningText,
      liveToolCalls: liveToolCalls ?? this.liveToolCalls,
      completedToolCallGroups:
          completedToolCallGroups ?? this.completedToolCallGroups,
      completedReasoningGroups:
          completedReasoningGroups ?? this.completedReasoningGroups,
      queuedSlashMessages: queuedSlashMessages ?? this.queuedSlashMessages,
      pinnedLocalNotices: pinnedLocalNotices ?? this.pinnedLocalNotices,
      lastSteerHint: clearLastSteerHint ? null : (lastSteerHint ?? this.lastSteerHint),
      stream: stream ?? this.stream,
      pendingAction: pendingAction ?? this.pendingAction,
      contextWindowSnapshot: clearContextWindowSnapshot
          ? null
          : (contextWindowSnapshot ?? this.contextWindowSnapshot),
      responseCompletionNeedsTranscriptRefresh:
          responseCompletionNeedsTranscriptRefresh ??
              this.responseCompletionNeedsTranscriptRefresh,
      streamingScrollTrigger: streamingScrollTrigger ?? this.streamingScrollTrigger,
    );
  }

  @override
  String toString() =>
      'ChatState(phase: $phase, sessionId: $sessionId, messages: ${messages.length})';
}
