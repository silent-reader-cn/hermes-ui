import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/api/sse_client.dart';
import '../../core/cache/cache_providers.dart';
import '../../core/models/chat_message.dart';
import '../../core/models/context_window_snapshot.dart';
import '../../core/models/json_value.dart';
import '../../core/models/session.dart';
import '../../core/models/tool_call.dart';
import '../../core/utils/uuid.dart';
import '../../core/connections/connection_providers.dart';
import '../session_list/session_list_providers.dart';
import 'chat_diff_merge.dart';
import 'chat_models.dart';
import 'chat_providers.dart';
import 'chat_server_api.dart';
import 'chat_state.dart';

/// 聊天主控制器（chat_spec.md §1/§2：九态状态机 + 消息组装 + 断线恢复）。
///
/// 唯一写 `List<ChatMessage>` 的类；SSE 事件经 [_handleSseEvent] 同步串行
/// 处理；token 走「缓冲(16ms 合并) → 词级 reveal(48ms)」三段式；done 双重
/// 收尾；transportError 走「挂起 → status 检查 → 重连/replay/finalize」。
class ChatController extends FamilyNotifier<ChatState, String> {
  // -------------------------------------------------------------------------
  // 私有非状态（对齐 Swift @ObservationIgnored：Timer/游标不进 state）
  // -------------------------------------------------------------------------

  /// token 合并延迟（16ms）。
  static const mergeDelay = Duration(milliseconds: 16);

  /// 词级 reveal 间隔（48ms）。
  static const revealInterval = Duration(milliseconds: 48);

  /// 每 tick 最多 reveal 的词单元数。
  static const maxWordUnitsPerTick = 5;

  /// reveal 最大滞后（积压超过该时长一次性排空）。
  static const maxRevealLag = Duration(seconds: 1);

  ChatServerApi? _api;
  Timer? _mergeTimer;
  Timer? _revealTimer;
  Timer? _watchdogTimer;
  Timer? _transcriptRefreshTimer;

  /// 词级 reveal 队列（合并缓冲产出、逐 tick 消费）。
  final List<String> _revealQueue = [];

  /// reveal 队列开始积压的时刻（最大滞后判定）。
  DateTime? _revealQueueStart;

  /// 最近一次内容新增（看门狗 5s 阈值）。
  DateTime? _lastProgress;

  /// 最近一次传输活动（看门狗 12s/18s/25s 阈值）。
  DateTime? _lastTransportActivity;

  /// status 轮询冷却截止。
  DateTime? _statusCheckCooldownUntil;

  /// 异步操作代数守卫（防双 finalize / 覆盖新流）。
  int _generation = 0;

  bool _disposed = false;

  /// SSE 连接当前是否存活（409 恢复路径判断是否需要重连）。
  bool _streamConnected = false;

  /// loadYoloState 一次性守卫（页面每次 build 都会触发，仅首次真正拉取）。
  bool _yoloLoaded = false;

  /// P4：新会话创建后待通过 done/stream_end 二次刷新的会话 id 集合。
  ///
  /// 仅用于「首轮完成后才落库」的异步后端：startChat 阶段已做立即+600ms
  /// 双次补拉，若服务端仍未落库，则在 done/stream_end 成功收尾时再做一次
  /// 强制刷新，避免用户需手动下拉。
  final Set<String> _pendingNewSessionIds = {};

  DateTime _now() => ref.read(chatClockProvider)();

  ChatWatchdogConfig get _watchdogConfig =>
      ref.read(chatWatchdogConfigProvider);

  double _nowSeconds() => _now().millisecondsSinceEpoch / 1000;

  @override
  ChatState build(String sessionId) {
    _api = ref.read(chatApiProvider);
    _disposed = false;
    _streamConnected = false;
    _generation++;
    _lastProgress = null;
    _lastTransportActivity = null;
    _statusCheckCooldownUntil = null;
    _revealQueue.clear();
    _revealQueueStart = null;
    _startWatchdog();
    ref.onDispose(_dispose);
    if (sessionId.isNotEmpty) {
      // build 期间 state 未初始化，推迟到微任务再加载（读 state 安全）。
      scheduleMicrotask(() {
        if (_disposed) return;
        unawaited(loadMessages());
      });
    }
    return ChatState.initial(sessionId: sessionId);
  }

  void _dispose() {
    _disposed = true;
    _generation++;
    _mergeTimer?.cancel();
    _revealTimer?.cancel();
    _watchdogTimer?.cancel();
    _transcriptRefreshTimer?.cancel();
    _api?.stopStream();
  }

  // -------------------------------------------------------------------------
  // 用户动作
  // -------------------------------------------------------------------------

  /// 发送新消息；流式期间按 [behavior] 处理（默认 steer）。
  Future<bool> send(
    String text, {
    StreamingSendBehavior behavior = StreamingSendBehavior.steer,
  }) async {
    final current = state;
    if (current.isViewingCachedData) {
      _setSendError('Reconnect to the server to send a message.');
      return false;
    }
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;
    if (current.stream.activeStreamId != null) {
      return _submitStreamingMessage(trimmed, behavior);
    }
    return _sendMessage(trimmed);
  }

  /// 停止当前响应（保留已流出文本，不删除）。
  Future<bool> stop() async {
    final streamId = state.stream.activeStreamId;
    if (streamId == null) return false;
    state = state.copyWith(stream: state.stream.copyWith(isCancelling: true));
    final gen = _generation;
    try {
      final response = await _api!.cancelChat(streamId);
      if (_disposed || gen != _generation) return false;
      if (response.ok == true || response.cancelled == true) {
        _finishStream(endPhase: ChatPhase.cancelled);
        return true;
      }
      state = state.copyWith(
        stream: state.stream.copyWith(isCancelling: false),
        sendErrorMessage: response.error ?? '服务器未能停止当前响应。',
      );
      return false;
    } on ApiException catch (error) {
      if (_disposed || gen != _generation) return false;
      state = state.copyWith(
        stream: state.stream.copyWith(isCancelling: false),
        sendErrorMessage: error.message,
      );
      return false;
    }
  }

  /// 显式选择模型（发送时带 explicit_model_pick）。
  void selectModel(String? model, {String? modelProvider}) {
    state = state.copyWith(
      model: model,
      clearModel: model == null,
      modelProvider: modelProvider,
      clearModelProvider: modelProvider == null,
      explicitModelPick: model != null,
    );
  }

  /// 清除当前展示的错误。
  void dismissError() {
    state = state.copyWith(
      clearSendErrorMessage: true,
      clearErrorMessage: true,
    );
  }

  /// 关闭离线缓存横幅。
  void dismissOfflineCache() {
    state = state.copyWith(isShowingOfflineCache: false);
  }

  /// 重命名当前会话，并立即更新聊天页标题。
  Future<bool> renameSession(String title) async {
    final trimmed = title.trim();
    if (state.sessionId.isEmpty || state.isReadOnly || trimmed.isEmpty) {
      return false;
    }
    try {
      final response = await _api!.renameSession(
        sessionId: state.sessionId,
        title: trimmed,
      );
      if (response.ok == false) {
        _setSendError(response.error ?? '重命名会话失败。');
        return false;
      }
      state = state.copyWith(displayTitle: trimmed);
      return true;
    } on ApiException catch (error) {
      _setSendError(error.message);
      return false;
    }
  }

  /// 更新当前会话的置顶状态。
  Future<bool> setPinned(bool pinned) => _mutateSession(
    () => _api!.pinSession(sessionId: state.sessionId, pinned: pinned),
    failure: '置顶状态更新失败。',
  );

  /// 更新当前会话的归档状态。
  Future<bool> setArchived(bool archived) => _mutateSession(
    () => _api!.archiveSession(sessionId: state.sessionId, archived: archived),
    failure: '归档状态更新失败。',
  );

  Future<bool> _mutateSession(
    Future<SessionMutationResponse> Function() request, {
    required String failure,
  }) async {
    if (state.sessionId.isEmpty || state.isReadOnly) return false;
    try {
      final response = await request();
      if (response.ok == false) {
        _setSendError(response.error ?? failure);
        return false;
      }
      return true;
    } on ApiException catch (error) {
      _setSendError(error.message);
      return false;
    }
  }

  /// 删除当前会话。
  Future<bool> deleteSession() async {
    if (state.sessionId.isEmpty || state.isReadOnly) return false;
    try {
      final response = await _api!.deleteSession(state.sessionId);
      if (response.ok == false) {
        _setSendError(response.error ?? '删除会话失败。');
        return false;
      }
      return true;
    } on ApiException catch (error) {
      _setSendError(error.message);
      return false;
    }
  }

  /// 从当前会话创建分支，返回新会话 ID。
  ///
  /// [keepCount] 非空时仅复制前 N 条消息（消息级分支）。
  Future<String?> branchSession({int? keepCount}) async {
    if (state.sessionId.isEmpty || state.isReadOnly) return null;
    try {
      final response = await _api!.branchSession(
        state.sessionId,
        keepCount: keepCount,
      );
      if (response.sessionId == null) {
        _setSendError(response.error ?? '创建会话分支失败。');
      }
      return response.sessionId;
    } on ApiException catch (error) {
      _setSendError(error.message);
      return null;
    }
  }

  /// 从此处创建分支：保留 [messageIndex] 之前（含）的消息分支出新会话。
  Future<String?> branchAt(int messageIndex) async {
    final messages = state.messages;
    if (messageIndex < 0 || messageIndex >= messages.length) return null;
    return branchSession(keepCount: messageIndex + 1);
  }

  /// 压缩当前会话（可带聚焦主题）；成功后刷新消息列表并轻提示。
  Future<bool> compressSession({String? focusTopic}) async {
    if (state.sessionId.isEmpty || state.isReadOnly) return false;
    final trimmedTopic = focusTopic?.trim();
    try {
      final response = await _api!.compressSession(
        sessionId: state.sessionId,
        focusTopic: (trimmedTopic == null || trimmedTopic.isEmpty)
            ? null
            : trimmedTopic,
      );
      if (response.ok == false) {
        _setSendError(response.error ?? '压缩会话失败。');
        return false;
      }
      setNotice('会话已压缩');
      await loadMessages();
      // 对齐 Swift：用压缩摘要的 token 估算覆盖 snapshot 的 lastPromptTokens
      final estimate = response.summary?.compressedTokenEstimate;
      if (estimate != null && estimate > 0) {
        final prev = state.contextWindowSnapshot;
        if (prev != null) {
          state = state.copyWith(
            contextWindowSnapshot: prev.replacingTokensUsed(estimate),
          );
        } else {
          state = state.copyWith(
            contextWindowSnapshot: ContextWindowSnapshot(
              lastPromptTokens: estimate,
              contextLength: prev?.contextLength,
              thresholdTokens: prev?.thresholdTokens,
            ),
          );
        }
      }
      return true;
    } on ApiException catch (error) {
      _setSendError(error.message);
      return false;
    }
  }

  /// 从此处截断：保留 [messageIndex] 及其之前的全部消息，删除其后所有。
  ///
  /// 服务端 keep_count = index + 1（从开头保留条数）；越界或只读返回 false。
  Future<bool> truncateAt(int messageIndex) async {
    if (state.sessionId.isEmpty || state.isReadOnly) return false;
    final messages = state.messages;
    if (messageIndex < 0 || messageIndex >= messages.length) return false;
    final keepCount = messageIndex + 1;
    try {
      final response = await _api!.truncateSession(
        sessionId: state.sessionId,
        keepCount: keepCount,
      );
      if (response.session == null) {
        _setSendError('截断会话失败。');
        return false;
      }
      await loadMessages();
      return true;
    } on ApiException catch (error) {
      _setSendError(error.message);
      return false;
    }
  }

  /// 用 [text] 预填输入框（编辑/重试复用；不自动发送）。
  void prefillComposer(String text) {
    if (state.sessionId.isEmpty || state.isReadOnly) return;
    state = state.copyWith(composerPrefill: text);
  }

  /// 撤销上一轮（删除最后一轮用户消息及其后全部）；成功后刷新消息列表。
  Future<bool> undoLastTurn() async {
    if (state.sessionId.isEmpty || state.isReadOnly) return false;
    try {
      final response = await _api!.undoSession(state.sessionId);
      if (response.ok == false) {
        _setSendError(response.error ?? '撤销上一轮失败。');
        return false;
      }
      await loadMessages();
      return true;
    } on ApiException catch (error) {
      _setSendError(error.message);
      return false;
    }
  }

  /// 重试上一轮：服务端删除最后一轮并返回该轮用户消息原文。
  ///
  /// 成功时把文本写入 [ChatState.composerPrefill]（UI 回填输入框，不自动发送），
  /// 并刷新消息列表；返回该文本供调用方直接使用。
  Future<String?> retryLastTurn() async {
    if (state.sessionId.isEmpty || state.isReadOnly) return null;
    try {
      final response = await _api!.retrySession(state.sessionId);
      final lastText = response.lastUserText;
      if (response.ok == false || lastText == null || lastText.isEmpty) {
        _setSendError(response.error ?? '重试上一轮失败。');
        return null;
      }
      state = state.copyWith(composerPrefill: lastText);
      await loadMessages();
      return lastText;
    } on ApiException catch (error) {
      _setSendError(error.message);
      return null;
    }
  }

  /// 更新会话设置（workspace / model）；成功后乐观更新本地元数据并轻提示。
  ///
  /// 模型列表由 [chatAvailableModelsProvider] 注入、无服务端状态可刷新，
  /// 这里仅同步 state.model/modelProvider 供后续发送使用。
  Future<bool> updateSessionSettings({String? workspace, String? model}) async {
    if (state.sessionId.isEmpty || state.isReadOnly) return false;
    final trimmedWorkspace = workspace?.trim();
    final trimmedModel = model?.trim();
    try {
      final response = await _api!.updateSession(
        sessionId: state.sessionId,
        workspace: (trimmedWorkspace == null || trimmedWorkspace.isEmpty)
            ? null
            : trimmedWorkspace,
        model: (trimmedModel == null || trimmedModel.isEmpty)
            ? null
            : trimmedModel,
      );
      final updated = response.session;
      state = state.copyWith(
        workspace: updated?.workspace ?? trimmedWorkspace ?? state.workspace,
        model: updated?.model ?? trimmedModel ?? state.model,
        modelProvider: updated?.modelProvider ?? state.modelProvider,
      );
      setNotice('设置已保存');
      return true;
    } on ApiException catch (error) {
      _setSendError(error.message);
      return false;
    }
  }

  /// 切换 YOLO 模式；成功后乐观更新开关状态。
  Future<bool> toggleYolo(bool enabled) async {
    if (state.sessionId.isEmpty || state.isReadOnly) return false;
    try {
      final response = await _api!.setYolo(
        sessionId: state.sessionId,
        enabled: enabled,
      );
      if (response.ok == false) {
        _setSendError('YOLO 状态更新失败。');
        return false;
      }
      state = state.copyWith(
        yoloEnabled: response.yoloEnabled ?? enabled,
      );
      return true;
    } on ApiException catch (error) {
      _setSendError(error.message);
      return false;
    }
  }

  /// 拉取当前会话 YOLO 状态（页面初始化调用；一次性守卫，失败静默）。
  Future<void> loadYoloState() async {
    if (_yoloLoaded || state.sessionId.isEmpty) return;
    _yoloLoaded = true;
    final gen = _generation;
    try {
      final response = await _api!.getYolo(state.sessionId);
      if (_disposed || gen != _generation) return;
      if (response.yoloEnabled != null) {
        state = state.copyWith(yoloEnabled: response.yoloEnabled);
      }
    } on ApiException {
      // YOLO 状态拉取失败静默（保持关闭默认值）。
    }
  }

  /// 加载更早的消息（分页）。
  Future<void> loadOlderMessages() async {
    final offset = state.messagesOffset;
    if (offset <= 0) return;
    await loadMessages(messageBefore: offset);
  }

  /// 跨端/跨设备聊天记录同步补齐（diff patch 类 VDOM 思路）。
  ///
  /// 从服务器拉取最新消息并与本地 [state.messages] 进行 diff 合并，
  /// 补全缺失消息、原地更新已变化消息，静默容错不弹全局错误。
  Future<void> syncMissingMessages({int limit = 50}) async {
    final sessionId = state.sessionId;
    if (sessionId.isEmpty || _disposed) return;
    final api = _api;
    if (api == null) return;
    // 若当前正在发送或流式接收中，避免与实时消息状态竞争
    if (state.stream.activeStreamId != null ||
        state.phase == ChatPhase.streaming ||
        state.phase == ChatPhase.sending) {
      return;
    }
    final gen = _generation;
    try {
      final response = await api.session(
        sessionId: sessionId,
        includeMessages: true,
        messageLimit: limit,
        expandRenderable: true,
      );
      if (_disposed || gen != _generation) return;
      final detail = response.session;
      if (detail == null) return;
      final serverMessages = detail.messages ?? const <ChatMessage>[];
      final mergedMessages = diffMergeMessages(
        localMessages: state.messages,
        serverMessages: serverMessages,
      );
      _applySessionDetail(detail: detail, mergedMessages: mergedMessages);
    } on Object {
      // 同步失败静默容错（不弹全局错误）
    }
  }

  /// 加载会话 transcript（冷启动 / 重载 / 分页）。
  Future<void> loadMessages({int? messageBefore}) async {
    final sessionId = state.sessionId;
    if (sessionId.isEmpty) return;
    final api = _api;
    if (api == null) return;
    final gen = _generation;
    try {
      final response = await api.session(
        sessionId: sessionId,
        includeMessages: true,
        messageLimit: 50,
        messageBefore: messageBefore,
        expandRenderable: messageBefore == null,
      );
      if (_disposed || gen != _generation) return;
      final detail = response.session;
      if (detail == null) return;
      final loaded = detail.messages ?? const <ChatMessage>[];
      if (messageBefore != null) {
        final existingIds = state.messages
            .map((m) => m.messageId)
            .whereType<String>()
            .toSet();
        final existingFingerprints = state.messages
            .where((m) => m.messageId == null)
            .map((m) => '${m.role}:${m.timestamp}:${m.content}')
            .toSet();
        final fresh = loaded
            .where((m) {
              if (m.messageId != null) {
                return !existingIds.contains(m.messageId);
              }
              return !existingFingerprints
                  .contains('${m.role}:${m.timestamp}:${m.content}');
            })
            .toList();
        final allMessages = [...fresh, ...state.messages];
        final fallbackOffset = state.messagesOffset - loaded.length;
        final newOffset =
            detail.messagesOffset ?? (fallbackOffset < 0 ? 0 : fallbackOffset);
        final persistedToolCalls =
            detail.toolCalls ?? const <PersistedToolCall>[];
        final serverDerivedGroups = ToolCallGroup.groups(
          persistedToolCalls: persistedToolCalls,
          messages: allMessages,
          messageOffset: newOffset,
        );
        final nextToolGroups = ToolCallGroup.merging(
          primaryGroups: serverDerivedGroups,
          fallbackGroups: state.completedToolCallGroups,
        );
        final serverDerivedReasoning = ReasoningGroup.groups(
          messages: allMessages,
          messageOffset: newOffset,
        );
        final nextReasoningGroups = ReasoningGroup.merging(
          primaryGroups: serverDerivedReasoning,
          fallbackGroups: state.completedReasoningGroups,
        );
        state = state.copyWith(
          messages: allMessages,
          messagesOffset: newOffset,
          hasOlderMessages:
              detail.messageCount != null &&
              detail.messageCount! > state.messages.length + fresh.length,
          completedToolCallGroups: nextToolGroups,
          completedReasoningGroups: nextReasoningGroups,
        );
      } else {
        // 全量重载：diff-merge 调和本地与服务端消息
        // 若当前展示的是离线缓存回放数据，fresh 在线消息直接替换旧缓存
        final local =
            state.isViewingCachedData ? const <ChatMessage>[] : state.messages;
        final mergedMessages = diffMergeMessages(
          localMessages: local,
          serverMessages: loaded,
        );
        _applySessionDetail(detail: detail, mergedMessages: mergedMessages);
      }
    } on ApiException catch (error) {
      if (_disposed || gen != _generation) return;
      if (messageBefore == null && ApiException.shouldUseCache(error)) {
        List<Map<String, Object?>> cachedMaps = const [];
        try {
          cachedMaps =
              await ref.read(cacheServiceProvider).readMessages(sessionId);
        } catch (_) {
          // 缓存读取异常静默，继续维持无缓存错误态
        }
        if (cachedMaps.isNotEmpty) {
          final parsed = cachedMaps
              .map((map) => ChatMessage.fromJson(map))
              .toList(growable: true);
          final hasTimestamps = parsed.any(
            (m) => m.timestamp != null && m.timestamp! > 0,
          );
          final List<ChatMessage> cachedMessages;
          if (hasTimestamps) {
            parsed.sort((a, b) {
              final tsA = a.timestamp ?? 0;
              final tsB = b.timestamp ?? 0;
              return tsA.compareTo(tsB);
            });
            cachedMessages = parsed;
          } else {
            // readMessages 按 cachedAt 倒序返回，反转恢复时间正序
            cachedMessages = parsed.reversed.toList(growable: false);
          }
          final serverDerivedGroups = ToolCallGroup.groups(
            persistedToolCalls: const [],
            messages: cachedMessages,
            messageOffset: 0,
          );
          final serverDerivedReasoning = ReasoningGroup.groups(
            messages: cachedMessages,
            messageOffset: 0,
          );
          state = state.copyWith(
            messages: cachedMessages,
            completedToolCallGroups: serverDerivedGroups,
            completedReasoningGroups: serverDerivedReasoning,
            isViewingCachedData: true,
            isShowingOfflineCache: true,
            clearErrorMessage: true,
            clearSendErrorMessage: true,
          );
          return;
        }
      }
      // 无缓存或非网络类错误（401/业务错误）：保持现状错误态
      state = state.copyWith(
        errorMessage: error.message,
      );
    }
  }

  void _applySessionDetail({
    required SessionDetail detail,
    required List<ChatMessage> mergedMessages,
  }) {
    final persistedToolCalls =
        detail.toolCalls ?? const <PersistedToolCall>[];
    final newOffset = detail.messagesOffset ?? state.messagesOffset;
    final serverDerivedGroups = ToolCallGroup.groups(
      persistedToolCalls: persistedToolCalls,
      messages: mergedMessages,
      messageOffset: newOffset,
    );
    final serverDerivedReasoning = ReasoningGroup.groups(
      messages: mergedMessages,
      messageOffset: newOffset,
    );
    List<ToolCallGroup> nextCompletedGroups;
    List<ToolCall> nextLiveToolCalls = state.liveToolCalls;
    String nextLiveReasoning = state.liveReasoningText;
    final hasServerTools =
        persistedToolCalls.isNotEmpty || serverDerivedGroups.isNotEmpty;
    if (hasServerTools) {
      nextCompletedGroups = serverDerivedGroups;
      nextLiveToolCalls = const [];
    } else {
      if (state.liveToolCalls.isNotEmpty) {
        final anchor = state.stream.toolCallAnchorMessageId ??
            state.stream.streamingAssistantMessageId ??
            _lastAssistantMessageId(mergedMessages);
        final liveGroup = ToolCallGroup.live(
          anchorMessageID: anchor,
          toolCalls: List<ToolCall>.of(state.liveToolCalls),
        );
        nextCompletedGroups = ToolCallGroup.merging(
          primaryGroups: state.completedToolCallGroups,
          fallbackGroups: [liveGroup],
        );
        nextLiveToolCalls = const [];
      } else {
        nextCompletedGroups = state.completedToolCallGroups;
      }
    }

    final liveReasoningList = <ReasoningGroup>[];
    if (state.liveReasoningText.isNotEmpty) {
      final anchor = state.stream.reasoningAnchorMessageId ??
          state.stream.streamingAssistantMessageId ??
          _lastAssistantMessageId(mergedMessages);
      liveReasoningList.add(
        ReasoningGroup(
          anchorMessageId: anchor,
          text: state.liveReasoningText,
        ),
      );
      nextLiveReasoning = '';
    }
    final nextCompletedReasoning = ReasoningGroup.merging(
      primaryGroups: serverDerivedReasoning,
      fallbackGroups: [
        ...state.completedReasoningGroups,
        ...liveReasoningList,
      ],
    );
    state = state.copyWith(
      messages: mergedMessages,
      messagesOffset: detail.messagesOffset ?? state.messagesOffset,
      hasOlderMessages: detail.messageCount != null &&
          detail.messageCount! > mergedMessages.length,
      displayTitle: _resolveTitle(detail),
      workspace: detail.workspace ?? state.workspace,
      model: detail.model ?? state.model,
      modelProvider: detail.modelProvider ?? state.modelProvider,
      profile: detail.profile ?? state.profile,
      isReadOnly: detail.readOnly == true || detail.isReadOnly == true,
      hasPendingUserMessage:
          detail.pendingUserMessage?.trim().isNotEmpty == true ||
              detail.pendingAttachments?.isNotEmpty == true,
      parentSessionId: detail.parentSessionId,
      contextWindowSnapshot: ContextWindowSnapshot(
        contextLength: detail.contextLength,
        thresholdTokens: detail.thresholdTokens,
        lastPromptTokens: detail.lastPromptTokens,
        inputTokens: detail.inputTokens,
        outputTokens: detail.outputTokens,
        estimatedCost: detail.estimatedCost,
        tokensPerSecond: state.stream.liveTokensPerSecond ??
            state.contextWindowSnapshot?.tokensPerSecond,
      ),
      completedToolCallGroups: nextCompletedGroups,
      liveToolCalls: nextLiveToolCalls,
      completedReasoningGroups: nextCompletedReasoning,
      liveReasoningText: nextLiveReasoning,
      responseCompletionNeedsTranscriptRefresh: false,
      isViewingCachedData: false,
      isShowingOfflineCache: false,
    );
    unawaited(_writeCacheMessages(state.sessionId, mergedMessages));
    final activeStreamId = detail.activeStreamId;
    if (activeStreamId != null &&
        activeStreamId.isNotEmpty &&
        state.stream.activeStreamId == null) {
      state = state.copyWith(
        phase: ChatPhase.streaming,
        stream: state.stream.copyWith(activeStreamId: activeStreamId),
      );
      unawaited(_reconnectIfNeeded());
    }
  }

  /// done 后补拉 transcript：status → active==false → loadMessages。
  Future<void> refreshTranscriptIfCompleted(String streamId) async {
    // 已开启新流则跳过；无流（已完成）或仍是旧流则继续。
    if (state.stream.activeStreamId != null &&
        state.stream.activeStreamId != streamId) {
      return;
    }
    final gen = _generation;
    try {
      final status = await _api!.chatStreamStatus(streamId);
      if (_disposed || gen != _generation) return;
      if (status.active == true) return; // 仍在流中，稍后再试
      await loadMessages();
      if (_disposed || gen != _generation) return;
      state = state.copyWith(responseCompletionNeedsTranscriptRefresh: false);
    } on ApiException {
      // 状态检查失败：静默（下次会话加载会补上）。
    }
  }

  /// 审批卡片作答。
  Future<bool> respondToApproval(String choice) async {
    final sessionId = state.sessionId;
    if (sessionId.isEmpty) return false;
    final gen = _generation;
    try {
      await _api!.respondApproval(sessionId: sessionId, choice: choice);
      if (_disposed || gen != _generation) return false;
      _clearApprovalCard();
      return true;
    } on ApiException {
      if (_disposed || gen != _generation) return false;
      return false;
    }
  }

  /// 澄清卡片作答。
  Future<bool> respondToClarification(String response) async {
    final sessionId = state.sessionId;
    if (sessionId.isEmpty) return false;
    final gen = _generation;
    try {
      await _api!.respondClarification(
        sessionId: sessionId,
        response: response,
      );
      if (_disposed || gen != _generation) return false;
      _clearClarificationCard();
      return true;
    } on ApiException {
      if (_disposed || gen != _generation) return false;
      return false;
    }
  }

  // -------------------------------------------------------------------------
  // 发送内部实现
  // -------------------------------------------------------------------------

  Future<bool> _sendMessage(String text) async {
    final api = _api;
    if (api == null) return false;
    _archiveLiveReasoningIfNeeded();
    _archiveLiveToolCallsIfNeeded();
    final messageId = 'local-${uuidV4()}';
    final optimistic = ChatMessage(
      role: 'user',
      content: text,
      messageId: messageId,
      timestamp: _nowSeconds(),
    );
    state = state.copyWith(
      phase: ChatPhase.sending,
      messages: [...state.messages, optimistic],
      clearSendErrorMessage: true,
      clearErrorMessage: true,
    );
    final gen = ++_generation;
    try {
      final response = await api.startChat(
        sessionId: state.sessionId,
        message: text,
        workspace: state.workspace,
        model: state.model,
        modelProvider: state.modelProvider,
        profile: state.profile,
        explicitModelPick: state.explicitModelPick,
      );
      if (_disposed || gen != _generation) return false;
      final streamId = response.streamId;
      final sessionId = response.sessionId;
      if (streamId == null || streamId.isEmpty) {
        _rollbackOptimisticMessage(messageId);
        state = state.copyWith(
          phase: ChatPhase.idle,
          sendErrorMessage: response.error ?? '服务器未返回流 ID，发送失败。',
        );
        return false;
      }
      if (sessionId != null &&
          sessionId.isNotEmpty &&
          state.sessionId.isEmpty) {
        final newSessionId = sessionId;
        state = state.copyWith(sessionId: newSessionId);
        _onNewSessionCreated(newSessionId, text);
      }
      _beginStream(streamId);
      return true;
    } on ApiException catch (error) {
      if (_disposed || gen != _generation) return false;
      if (error is HttpException && error.indicatesActiveStream) {
        // 409 已有活动流：服务端未接受本条消息 → 回滚 → 接管已有流。
        _rollbackOptimisticMessage(messageId);
        await _recoverExistingStream(error.activeStreamId!);
        return false;
      }
      _rollbackOptimisticMessage(messageId);
      state = state.copyWith(
        phase: ChatPhase.idle,
        sendErrorMessage: error.message,
      );
      return false;
    }
  }

  /// 流式期间发送：steer / interrupt / queue 三行为（chat_spec.md §4.2）。
  Future<bool> _submitStreamingMessage(
    String text,
    StreamingSendBehavior behavior,
  ) async {
    switch (behavior) {
      case StreamingSendBehavior.steer:
        return _steer(text);
      case StreamingSendBehavior.interrupt:
        state = state.copyWith(
          queuedSlashMessages: [text, ...state.queuedSlashMessages],
        );
        final stopped = await stop();
        if (!stopped && state.stream.activeStreamId != null) {
          _pinNotice(
            'Could not stop the current response — your message is queued for the next turn.',
          );
        }
        return false;
      case StreamingSendBehavior.queue:
        state = state.copyWith(
          queuedSlashMessages: [...state.queuedSlashMessages, text],
        );
        _pinNotice(
          'Queued for next turn (#${state.queuedSlashMessages.length})',
        );
        return false;
    }
  }

  Future<bool> _steer(String text) async {
    final gen = _generation;
    try {
      final response = await _api!.steerChat(sessionId: state.sessionId, text: text);
      if (_disposed || gen != _generation) return false;
      if (response.accepted == true) {
        _markProgress();
        state = state.copyWith(phase: ChatPhase.steered, lastSteerHint: text);
        return true;
      }
      _queueSteerFailure(text);
      unawaited(cancelActiveStream());
      return false;
    } on ApiException {
      if (_disposed || gen != _generation) return false;
      _queueSteerFailure(text);
      unawaited(cancelActiveStream());
      return false;
    }
  }

  void _queueSteerFailure(String text) {
    state = state.copyWith(
      queuedSlashMessages: [...state.queuedSlashMessages, text],
      pinnedLocalNotices: [
        ...state.pinnedLocalNotices,
        'Steer was unavailable — your message has been queued for the next turn.',
      ],
    );
  }

  /// 停止当前流（steer 失败路径；finishStream 会顺次发送队列）。
  Future<void> cancelActiveStream() async {
    final streamId = state.stream.activeStreamId;
    if (streamId == null) return;
    await _api?.cancelChat(streamId);
    if (_disposed) return;
    _finishStream(endPhase: ChatPhase.cancelled);
  }

  /// 流结束后顺次发送队列首条（发送失败回队首并停止连锁，防死循环）。
  Future<void> _drainQueuedSlashMessage() async {
    final queued = state.queuedSlashMessages;
    if (queued.isEmpty) return;
    if (state.stream.activeStreamId != null) return;
    final next = queued.first;
    state = state.copyWith(queuedSlashMessages: queued.sublist(1));
    final sent = await _sendMessage(next);
    if (!sent) {
      state = state.copyWith(
        queuedSlashMessages: [next, ...state.queuedSlashMessages],
      );
    }
  }

  void _beginStream(String streamId) {
    state = state.copyWith(
      phase: ChatPhase.streaming,
      clearSendErrorMessage: true,
      clearErrorMessage: true,
      stream: state.stream.copyWith(
        activeStreamId: streamId,
        isSuspended: false,
        recovery: ActiveStreamRecoveryState.idle,
        hasCompletedResponse: false,
        isCancelling: false,
        clearLastEventId: true,
        isReplayConnection: false,
        matchedPrefixLength: 0,
        matchedReasoningLength: 0,
        replayToolMatchIndex: 0,
      ),
      pendingAction: const ChatPendingActionState(),
      responseCompletionNeedsTranscriptRefresh: false,
    );
    // 空流式气泡立即锚定（思考中指示器依赖它）。
    _ensureStreamingAssistantMessage();
    _connectStream(streamId);
    _markProgress();
    _recordTransportActivity();
  }

  /// 建立 SSE 连接。replayAfterSeq → `?replay=1&after_seq=N`（保留 lastEventID）；
  /// [fullReconnect] → 不带 replay 参数但从 0 重放（靠 §6.4 去重）。
  void _connectStream(
    String streamId, {
    int? replayAfterSeq,
    bool fullReconnect = false,
  }) {
    final api = _api;
    if (api == null) return;
    final useReplay = replayAfterSeq != null || fullReconnect;
    final freshStart = replayAfterSeq == null && !fullReconnect;
    state = state.copyWith(
      stream: state.stream.copyWith(
        isReplayConnection: useReplay,
        matchedPrefixLength: 0,
        matchedReasoningLength: 0,
        replayToolMatchIndex: 0,
        lastEventId: freshStart ? null : state.stream.lastEventId,
        clearLastEventId: freshStart,
      ),
    );
    _streamConnected = true;
    unawaited(
      api.startStream(
        streamId,
        replayAfterSeq: replayAfterSeq,
        onEvent: _handleSseEvent,
        onEventId: (id) {
          if (_disposed) return;
          state = state.copyWith(
            stream: state.stream.copyWith(lastEventId: id),
          );
          _recordTransportActivity();
        },
        onTransportError: (message) {
          if (_disposed) return;
          _streamConnected = false;
          _handleTransportError(message);
        },
        onClosed: () {
          _streamConnected = false;
          _recordTransportActivity();
        },
      ),
    );
  }

  // -------------------------------------------------------------------------
  // SSE 事件分发（同步串行；先记录传输活动，有新增再 markProgress）
  // -------------------------------------------------------------------------

  void _handleSseEvent(SseEvent event) {
    if (_disposed) return;
    _recordTransportActivity();
    switch (event) {
      case TokenSseEvent(:final text):
        if (_appendAssistantToken(text)) _markProgress();
      case InterimAssistantSseEvent(:final text, :final alreadyStreamed):
        _handleInterimAssistant(text, alreadyStreamed);
      case ReasoningSseEvent(:final text):
        if (_appendReasoning(text)) _markProgress();
      case ToolStartedSseEvent(:final event):
        _appendToolCall(event);
      case ToolCompletedSseEvent(:final event):
        _completeToolCall(event);
      case TitleSseEvent(:final sessionId, :final title):
        _handleTitle(sessionId, title);
      case MeteringSseEvent(
        :final tps,
        :final tpsAvailable,
        :final estimated,
        :final sessionId,
      ):
        _handleMetering(
          tps: tps,
          tpsAvailable: tpsAvailable,
          estimated: estimated,
          sessionId: sessionId,
        );
      case DoneSseEvent(:final event):
        _applyDone(event);
      case ApprovalPendingSseEvent(:final payload):
        _applyApprovalUpdate(payload);
      case ClarificationPendingSseEvent(:final payload):
        _applyClarificationUpdate(payload);
      case PendingSteerLeftoverSseEvent(:final text):
        _handlePendingSteerLeftover(text);
      case StreamEndSseEvent():
        _handleStreamEnd();
      case CancelledSseEvent():
        _handleCancelled();
      case ErrorSseEvent(:final message):
        _handleErrorEvent(message);
      case TransportErrorSseEvent(:final message):
        _handleTransportError(message);
      case HeartbeatSseEvent():
        _handleHeartbeat();
      case IgnoredSseEvent():
        break;
    }
  }

  // -------------------------------------------------------------------------
  // token 三段式缓冲（合并 → 词级 reveal）
  // -------------------------------------------------------------------------

  /// 去重（replay 连接）→ 入 pendingAssistantTokenChunks → 调度 16ms 合并。
  /// 返回是否有真实新增（看门狗进度信号）。
  bool _appendAssistantToken(String text) {
    if (text.isEmpty) return false;
    var remainder = text;
    final stream = state.stream;
    if (stream.isReplayConnection) {
      final deduped = deduplicatedReplayToken(
        token: text,
        existingContent: _currentStreamingContent(),
        matchedPrefixLength: stream.matchedPrefixLength,
      );
      remainder = deduped.remainder;
      state = state.copyWith(
        stream: state.stream.copyWith(
          matchedPrefixLength: deduped.newCursor,
          isReplayConnection: deduped.stillReplay,
        ),
      );
      if (remainder.isEmpty) return false;
    }
    state = state.copyWith(
      pendingAssistantTokenChunks: [
        ...state.pendingAssistantTokenChunks,
        remainder,
      ],
    );
    _scheduleMerge();
    return true;
  }

  void _scheduleMerge() {
    _mergeTimer ??= Timer(mergeDelay, () {
      _mergeTimer = null;
      _mergePendingTokens();
    });
  }

  void _mergePendingTokens() {
    final chunks = state.pendingAssistantTokenChunks;
    if (chunks.isNotEmpty) {
      final text = chunks.join();
      state = state.copyWith(pendingAssistantTokenChunks: const []);
      if (_revealQueue.isEmpty) _revealQueueStart = _now();
      _revealQueue.addAll(splitIntoWordUnits(text));
      _startRevealTimerIfNeeded();
    }
    // 同一 tick 内 token 先、reasoning 后。
    _flushReasoningChunks();
  }

  void _startRevealTimerIfNeeded() {
    if (_revealTimer != null) return;
    _revealTimer = Timer.periodic(revealInterval, (_) => _drainReveal());
  }

  void _drainReveal() {
    if (_revealQueue.isEmpty) {
      _revealTimer?.cancel();
      _revealTimer = null;
      _revealQueueStart = null;
      return;
    }
    final count = _revealQueue.length < maxWordUnitsPerTick
        ? _revealQueue.length
        : maxWordUnitsPerTick;
    final units = _revealQueue.sublist(0, count);
    _revealQueue.removeRange(0, count);
    _appendToStreamingMessage(units.join());
    _markProgress();
    // 最大滞后 1s：积压超过时限一次性排空。
    final start = _revealQueueStart;
    if (_revealQueue.isNotEmpty &&
        start != null &&
        _now().difference(start) >= maxRevealLag) {
      final rest = _revealQueue.join();
      _revealQueue.clear();
      _revealQueueStart = null;
      _appendToStreamingMessage(rest);
      _markProgress();
    }
  }

  /// 完成路径全量 flush：取消待定 tick，把缓冲全部写入消息。
  void flushPendingStreamingContent() {
    _mergeTimer?.cancel();
    _mergeTimer = null;
    _revealTimer?.cancel();
    _revealTimer = null;
    final text = state.pendingAssistantTokenChunks.join() + _revealQueue.join();
    _revealQueue.clear();
    _revealQueueStart = null;
    if (text.isNotEmpty) {
      state = state.copyWith(pendingAssistantTokenChunks: const []);
      _appendToStreamingMessage(text);
    }
    _flushReasoningChunks();
  }

  void _flushReasoningChunks() {
    final chunks = state.pendingReasoningChunks;
    if (chunks.isEmpty) return;
    final text = chunks.join();
    state = state.copyWith(
      pendingReasoningChunks: const [],
      liveReasoningText: state.liveReasoningText + text,
    );
  }

  /// reasoning：去重 → 入 pendingReasoningChunks → 合并 tick 整块 flush。
  bool _appendReasoning(String text) {
    if (text.isEmpty) return false;
    var remainder = text;
    final stream = state.stream;
    if (stream.isReplayConnection) {
      final deduped = deduplicatedReplayText(
        text: text,
        existingContent: state.liveReasoningText,
        matchedLength: stream.matchedReasoningLength,
      );
      remainder = deduped.remainder;
      state = state.copyWith(
        stream: state.stream.copyWith(
          matchedReasoningLength: deduped.newCursor,
          isReplayConnection: deduped.stillReplay,
        ),
      );
      if (remainder.isEmpty) return false;
    }
    state = state.copyWith(
      pendingReasoningChunks: [...state.pendingReasoningChunks, remainder],
    );
    _scheduleMerge();
    return true;
  }

  // -------------------------------------------------------------------------
  // 消息组装
  // -------------------------------------------------------------------------

  /// 流式 assistant 消息锚定：不存在则创建并记住 ID。
  void _ensureStreamingAssistantMessage() {
    if (state.stream.streamingAssistantMessageId != null) return;
    final message = ChatMessage(
      role: 'assistant',
      content: '',
      messageId: 'stream-${uuidV4()}',
      timestamp: _nowSeconds(),
    );
    state = state.copyWith(
      messages: [...state.messages, message],
      stream: state.stream.copyWith(
        streamingAssistantMessageId: message.messageId,
      ),
    );
  }

  /// 以 messageId == streamingAssistantMessageId 定位，原地替换（content 追加）。
  void _appendToStreamingMessage(String text) {
    if (text.isEmpty) return;
    _ensureStreamingAssistantMessage();
    final id = state.stream.streamingAssistantMessageId!;
    final index = state.messages.indexWhere((m) => m.messageId == id);
    if (index == -1) return;
    final current = state.messages[index];
    final next = List<ChatMessage>.of(state.messages);
    next[index] = current.copyWith(content: '${current.content ?? ''}$text');
    state = state.copyWith(
      messages: next,
      streamingScrollTrigger: state.streamingScrollTrigger + 1,
    );
  }

  String _currentStreamingContent() {
    final id = state.stream.streamingAssistantMessageId;
    if (id == null) return '';
    for (final message in state.messages) {
      if (message.messageId == id) return message.content ?? '';
    }
    return '';
  }

  /// interim_assistant：already_streamed 过滤 + 先 flush 再追加 + 分隔符规则。
  bool _handleInterimAssistant(String text, bool alreadyStreamed) {
    if (alreadyStreamed) return false;
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;
    flushPendingStreamingContent();
    final stream = state.stream;
    if (stream.streamingAssistantMessageId == null) {
      return _appendAssistantToken(text);
    }
    final currentContent = _currentStreamingContent();
    String append;
    if (stream.isReplayConnection) {
      final deduped = deduplicatedReplayText(
        text: text,
        existingContent: currentContent,
        matchedLength: 0,
      );
      append = deduped.remainder;
      if (append.isEmpty) return false;
      // replay 直连：直接拼接不加分隔符。
    } else {
      append = currentContent.isEmpty ? text : '\n\n$text';
    }
    _appendToStreamingMessage(append);
    _markProgress();
    return true;
  }

  // -------------------------------------------------------------------------
  // 工具调用
  // -------------------------------------------------------------------------

  void _appendToolCall(ToolStreamEvent evt) {
    final stream = state.stream;
    if (stream.isReplayConnection) {
      final stableId = evt.stableId;
      if (stableId != null) {
        if (state.liveToolCalls.any((t) => t.id == stableId)) return;
      } else {
        var idx = stream.replayToolMatchIndex;
        while (idx < state.liveToolCalls.length) {
          if (_sameToolSignature(state.liveToolCalls[idx], evt)) {
            state = state.copyWith(
              stream: state.stream.copyWith(replayToolMatchIndex: idx + 1),
            );
            return;
          }
          idx++;
        }
      }
    }
    _ensureStreamingAssistantMessage();
    final tool = ToolCall(
      id: evt.stableId,
      name: evt.name,
      preview: evt.preview,
      args: evt.jsonArgs ?? _argsToJsonValue(evt.args),
      isCompleted: false,
    );
    final anchor =
        state.stream.toolCallAnchorMessageId ??
        state.stream.streamingAssistantMessageId;
    state = state.copyWith(
      liveToolCalls: [...state.liveToolCalls, tool],
      stream: state.stream.copyWith(toolCallAnchorMessageId: anchor),
    );
    _markProgress();
  }

  void _completeToolCall(ToolStreamEvent evt) {
    final stableId = evt.stableId;
    final calls = state.liveToolCalls;
    var index = -1;
    if (stableId != null) {
      index = calls.indexWhere((t) => t.id == stableId);
    }
    if (index == -1 && evt.name != null) {
      // 匹配 name 相同的最后一个未完成项。
      for (var i = calls.length - 1; i >= 0; i--) {
        if (calls[i].name == evt.name && !calls[i].isCompleted) {
          index = i;
          break;
        }
      }
    }
    if (index != -1) {
      final existing = calls[index];
      if (state.stream.isReplayConnection && existing.isCompleted) return;
      final next = List<ToolCall>.of(calls);
      next[index] = ToolCall(
        id: existing.id,
        name: evt.name ?? existing.name,
        preview: evt.preview ?? existing.preview,
        args: evt.jsonArgs ?? (evt.args != null ? _argsToJsonValue(evt.args) : existing.args),
        duration: evt.duration,
        isError: evt.isError,
        isCompleted: true,
        startedAt: existing.startedAt,
      );
      state = state.copyWith(liveToolCalls: next);
    } else {
      // 匹配不到 → append 已完成项（服务器只发了完成事件）。
      state = state.copyWith(
        liveToolCalls: [
          ...calls,
          ToolCall(
            id: evt.stableId,
            name: evt.name,
            preview: evt.preview,
            args: evt.jsonArgs ?? _argsToJsonValue(evt.args),
            duration: evt.duration,
            isError: evt.isError,
            isCompleted: true,
          ),
        ],
      );
    }
    _markProgress();
  }

  Map<String, JsonValue>? _argsToJsonValue(Map<String, Object?>? args) {
    if (args == null || args.isEmpty) return null;
    return args.map((k, v) => MapEntry(k, JsonValue.fromJson(v)));
  }

  bool _sameToolSignature(ToolCall call, ToolStreamEvent evt) {
    if (call.name != evt.name) return false;
    if (call.preview != evt.preview) return false;
    final argsA = call.args == null
        ? '{}'
        : jsonEncode(call.args!.map((k, v) => MapEntry(k, v.toJson())));
    final argsB = evt.args == null ? '{}' : jsonEncode(evt.args);
    return argsA == argsB;
  }

  // -------------------------------------------------------------------------
  // title / metering / approval / clarify / steer leftover
  // -------------------------------------------------------------------------

  void _handleTitle(String? sessionId, String? title) {
    if (sessionId == null || sessionId.isEmpty || title == null) return;
    if (state.sessionId.isNotEmpty && sessionId != state.sessionId) return;
    final trimmed = title.trim();
    if (trimmed.isEmpty) return;
    state = state.copyWith(displayTitle: trimmed);
  }

  void _handleMetering({
    double? tps,
    required bool tpsAvailable,
    required bool estimated,
    String? sessionId,
  }) {
    if (sessionId != null &&
        sessionId.isNotEmpty &&
        state.sessionId.isNotEmpty &&
        sessionId != state.sessionId) {
      return;
    }
    if (tpsAvailable && !estimated && tps != null && tps.isFinite && tps > 0) {
      state = state.copyWith(
        stream: state.stream.copyWith(liveTokensPerSecond: tps),
      );
      // 同步更新 snapshot 的 tps，确保 popover 阈值色与 indicator 一致
      // 且即使仅有 metering 也能实时更新 cost/tps 相关行。
      final prev = state.contextWindowSnapshot;
      if (prev != null) {
        state = state.copyWith(
          contextWindowSnapshot: prev.replacingTokensPerSecond(tps),
        );
      } else {
        // 无历史 snapshot 时，用 tps 创建空壳（至少保留 tps 可展示）
        state = state.copyWith(
          contextWindowSnapshot: ContextWindowSnapshot(tokensPerSecond: tps),
        );
      }
    }
  }

  void _applyApprovalUpdate(Map<String, Object?> payload) {
    final pending = payload['pending'];
    if (pending is Map) {
      state = state.copyWith(
        phase: ChatPhase.approvalPending,
        pendingAction: state.pendingAction.copyWith(
          approvalPrompt: Map<String, Object?>.from(pending),
        ),
      );
    } else {
      _clearApprovalCard();
    }
    _markProgress();
  }

  void _applyClarificationUpdate(Map<String, Object?> payload) {
    final pending = payload['pending'];
    if (pending is Map) {
      state = state.copyWith(
        phase: ChatPhase.clarifyPending,
        pendingAction: state.pendingAction.copyWith(
          clarificationPrompt: Map<String, Object?>.from(pending),
        ),
      );
    } else {
      _clearClarificationCard();
    }
    _markProgress();
  }

  void _clearApprovalCard() {
    state = state.copyWith(
      phase: state.stream.hasActiveStream
          ? ChatPhase.streaming
          : ChatPhase.idle,
      pendingAction: state.pendingAction.copyWith(clearApproval: true),
    );
  }

  void _clearClarificationCard() {
    state = state.copyWith(
      phase: state.stream.hasActiveStream
          ? ChatPhase.streaming
          : ChatPhase.idle,
      pendingAction: state.pendingAction.copyWith(clearClarification: true),
    );
  }

  void _handlePendingSteerLeftover(String text) {
    if (text.trim().isEmpty) return;
    state = state.copyWith(
      queuedSlashMessages: [...state.queuedSlashMessages, text],
      pinnedLocalNotices: [
        ...state.pinnedLocalNotices,
        'Steering hint was not consumed — it has been queued for the next message.',
      ],
    );
    _markProgress();
  }

  // -------------------------------------------------------------------------
  // done / stream_end / cancel / error 收尾
  // -------------------------------------------------------------------------

  void _applyDone(DoneStreamEvent event) {
    flushPendingStreamingContent();
    final completedStreamId = state.stream.activeStreamId;
    final currentStreamingId = state.stream.streamingAssistantMessageId;
    final rawSession = event.session;
    final hasCompletedTranscript =
        rawSession != null &&
        rawSession['messages'] is List &&
        (rawSession['messages'] as List).isNotEmpty;
    if (hasCompletedTranscript) {
      _applyCompletedStreamSession(rawSession, currentStreamingId);
    }
    final rawUsage = event.usage;
    ContextWindowSnapshot? snapshot = event.usageSnapshot ??
        (rawUsage != null ? ContextWindowSnapshot.fromJson(rawUsage) : null);
    // 若 usage 缺失关键字段，尝试从 session detail 或历史 snapshot 回退补齐
    if (snapshot != null) {
      final prev = state.contextWindowSnapshot;
      final detailFallback = hasCompletedTranscript
          ? SessionDetail.fromJson(rawSession!) // ignore: unnecessary_non_null_assertion
          : null;
      // 回退 contextLength / threshold / tokens
      final merged = ContextWindowSnapshot(
        contextLength: snapshot.contextLength ??
            detailFallback?.contextLength ??
            prev?.contextLength,
        thresholdTokens: snapshot.thresholdTokens ??
            detailFallback?.thresholdTokens ??
            prev?.thresholdTokens,
        lastPromptTokens: snapshot.lastPromptTokens ??
            detailFallback?.lastPromptTokens ??
            prev?.lastPromptTokens,
        inputTokens: snapshot.inputTokens ??
            detailFallback?.inputTokens ??
            prev?.inputTokens,
        outputTokens: snapshot.outputTokens ??
            detailFallback?.outputTokens ??
            prev?.outputTokens,
        estimatedCost: snapshot.estimatedCost ??
            detailFallback?.estimatedCost ??
            prev?.estimatedCost,
        tokensPerSecond: snapshot.tokensPerSecond ?? prev?.tokensPerSecond,
      );
      // 若回退后仍有有效百分比，则使用合并后；否则保留原始
      snapshot = merged;
    } else if (hasCompletedTranscript) {
      // usage 缺失但有完整 transcript：直接从 session detail 构建
      // ignore: unnecessary_non_null_assertion
      final detail = SessionDetail.fromJson(rawSession!);
      snapshot = ContextWindowSnapshot(
        contextLength: detail.contextLength,
        thresholdTokens: detail.thresholdTokens,
        lastPromptTokens: detail.lastPromptTokens,
        inputTokens: detail.inputTokens,
        outputTokens: detail.outputTokens,
        estimatedCost: detail.estimatedCost,
        tokensPerSecond: state.contextWindowSnapshot?.tokensPerSecond,
      );
      // 若回退的 tps 存在，同步到 snapshot
      final prevTps = state.stream.liveTokensPerSecond ??
          state.contextWindowSnapshot?.tokensPerSecond;
      if (prevTps != null && snapshot.tokensPerSecond == null) {
        snapshot = snapshot.replacingTokensPerSecond(prevTps);
      }
    }
    if (snapshot != null &&
        (snapshot.contextLength != null ||
            snapshot.inputTokens != null ||
            snapshot.lastPromptTokens != null ||
            snapshot.tokensPerSecond != null)) {
      state = state.copyWith(contextWindowSnapshot: snapshot);
      final tps = snapshot.tokensPerSecond;
      if (tps != null && tps.isFinite && tps > 0) {
        _applyTurnTps(currentStreamingId, tps);
      }
    }
    _completeCurrentResponse(
      needsTranscriptRefresh: !hasCompletedTranscript,
      completedStreamId: completedStreamId,
    );
    // 回合完成（done）：通知 hook（仅后台发通知，见 notifications feature）。
    _notifyTurnCompleted();
    _triggerSessionListRefreshForCompleted(state.sessionId);
    unawaited(_writeCacheMessages(state.sessionId, state.messages));
  }

  void _applyCompletedStreamSession(
    Map<String, Object?> rawSession,
    String? currentStreamingId,
  ) {
    final detail = SessionDetail.fromJson(rawSession);
    final loaded = detail.messages ?? const <ChatMessage>[];
    final merged = _mergingLoadedMessages(
      loaded,
      state.messages,
      currentStreamingId,
    );
    final persisted = detail.toolCalls ?? const <PersistedToolCall>[];
    final persistedGroups = ToolCallGroup.groups(
      persistedToolCalls: persisted,
      messages: merged,
      messageOffset: state.messagesOffset,
    );
    final liveGroups = _archiveLiveToolCallsToGroups();
    final groups = ToolCallGroup.merging(
      primaryGroups: persistedGroups,
      fallbackGroups: liveGroups,
    );
    final serverDerivedReasoning = ReasoningGroup.groups(
      messages: merged,
      messageOffset: state.messagesOffset,
    );
    final liveReasoning = _archiveLiveReasoningToGroups();
    final reasoningGroups = ReasoningGroup.merging(
      primaryGroups: serverDerivedReasoning,
      fallbackGroups: liveReasoning,
    );
    final title = detail.title?.trim();
    // 同步上下文快照（对齐 Swift applyCompletedStreamSession）
    final snapshotFromDetail = ContextWindowSnapshot(
      contextLength: detail.contextLength,
      thresholdTokens: detail.thresholdTokens,
      lastPromptTokens: detail.lastPromptTokens,
      inputTokens: detail.inputTokens,
      outputTokens: detail.outputTokens,
      estimatedCost: detail.estimatedCost,
      tokensPerSecond: state.stream.liveTokensPerSecond ??
          state.contextWindowSnapshot?.tokensPerSecond,
    );
    final hasSnapshotValues = snapshotFromDetail.contextLength != null ||
        snapshotFromDetail.thresholdTokens != null ||
        snapshotFromDetail.lastPromptTokens != null ||
        snapshotFromDetail.inputTokens != null;
    state = state.copyWith(
      messages: merged,
      messagesOffset: detail.messagesOffset ?? state.messagesOffset,
      hasOlderMessages:
          detail.messageCount != null && detail.messageCount! > merged.length,
      displayTitle: (title == null || title.isEmpty)
          ? state.displayTitle
          : title,
      workspace: detail.workspace ?? state.workspace,
      model: detail.model ?? state.model,
      modelProvider: detail.modelProvider ?? state.modelProvider,
      profile: detail.profile ?? state.profile,
      completedToolCallGroups: groups,
      completedReasoningGroups: reasoningGroups,
      liveToolCalls: const [],
      liveReasoningText: '',
      stream: state.stream.copyWith(
        clearStreamingAssistantMessageId: true,
        clearToolCallAnchorMessageId: true,
        clearReasoningAnchorMessageId: true,
      ),
    );
    if (hasSnapshotValues) {
      state = state.copyWith(contextWindowSnapshot: snapshotFromDetail);
    }
  }

  /// 服务端 transcript 与本地合并：local- 乐观消息保留插回；本地流式内容
  /// 与服务端取「更长/更新的」，前缀包含去重（chat_spec.md §5.5 最低档）。
  List<ChatMessage> _mergingLoadedMessages(
    List<ChatMessage> loaded,
    List<ChatMessage> current,
    String? streamingMessageId,
  ) {
    if (loaded.isEmpty) return List<ChatMessage>.from(current);
    if (current.isEmpty) return loaded;
    final result = List<ChatMessage>.from(loaded);
    if (streamingMessageId != null) {
      ChatMessage? localStreaming;
      for (final message in current) {
        if (message.messageId == streamingMessageId) {
          localStreaming = message;
          break;
        }
      }
      if (localStreaming != null) {
        final localContent = localStreaming.content ?? '';
        var lastAssistantIndex = -1;
        for (var i = result.length - 1; i >= 0; i--) {
          if (result[i].role == 'assistant') {
            lastAssistantIndex = i;
            break;
          }
        }
        if (lastAssistantIndex != -1) {
          final serverContent = result[lastAssistantIndex].content ?? '';
          if (localContent.isNotEmpty &&
              serverContent.startsWith(localContent)) {
            // 服务端已含本地全部内容 → 丢弃本地流式消息。
          } else if (localContent.isNotEmpty &&
              (serverContent.isEmpty ||
                  localContent.startsWith(serverContent))) {
            result[lastAssistantIndex] = result[lastAssistantIndex].copyWith(
              content: localContent,
            );
          }
        } else if (localContent.isNotEmpty) {
          result.add(localStreaming);
        }
      }
    }
    final loadedIds = result
        .map((m) => m.messageId)
        .whereType<String>()
        .toSet();
    final localToInsert = current
        .where(
          (m) =>
              (m.messageId ?? '').startsWith('local-') &&
              !loadedIds.contains(m.messageId) &&
              !_duplicatesLoadedUserMessage(m, result),
        )
        .toList();
    if (localToInsert.isNotEmpty) {
      var insertAt = result.length;
      for (var i = result.length - 1; i >= 0; i--) {
        if (result[i].role == 'user' &&
            TranscriptTurnClassifier.isUserTurnBoundary(result[i])) {
          insertAt = i + 1;
          break;
        }
      }
      result.insertAll(insertAt, localToInsert);
    }
    return result;
  }

  /// local- 乐观 user 消息与加载 transcript 的最后一条 user 消息内容相同
  /// （服务端已确认该消息）→ 视为重复，不再保留。
  bool _duplicatesLoadedUserMessage(
    ChatMessage local,
    List<ChatMessage> loaded,
  ) {
    if (local.role != 'user') return false;
    final localContent = local.content?.trim();
    if (localContent == null || localContent.isEmpty) return false;
    for (var i = loaded.length - 1; i >= 0; i--) {
      final message = loaded[i];
      if (message.role == 'user' &&
          (message.content ?? '').trim() == localContent) {
        return true;
      }
    }
    return false;
  }

  void _applyTurnTps(String? currentStreamingId, double tps) {
    var index = -1;
    if (currentStreamingId != null) {
      index = state.messages.indexWhere(
        (m) => m.messageId == currentStreamingId,
      );
    }
    if (index == -1) {
      for (var i = state.messages.length - 1; i >= 0; i--) {
        if (state.messages[i].role == 'assistant') {
          index = i;
          break;
        }
      }
    }
    if (index == -1) return;
    final next = List<ChatMessage>.of(state.messages);
    next[index] = next[index].copyWith(turnTps: tps);
    state = state.copyWith(messages: next);
  }

  /// completeCurrentResponse：结束流（activeStreamId=null、hasCompletedResponse=true）。
  void _completeCurrentResponse({
    required bool needsTranscriptRefresh,
    String? completedStreamId,
  }) {
    _api?.stopStream();
    state = state.copyWith(
      phase: ChatPhase.idle,
      clearLastSteerHint: true,
      stream: state.stream.copyWith(
        clearActiveStreamId: true,
        clearLastEventId: true,
        clearStreamingAssistantMessageId: true,
        clearToolCallAnchorMessageId: true,
        clearReasoningAnchorMessageId: true,
        clearLiveTokensPerSecond: true,
        hasCompletedResponse: true,
        isSuspended: false,
        recovery: ActiveStreamRecoveryState.idle,
        isReplayConnection: false,
        matchedPrefixLength: 0,
        matchedReasoningLength: 0,
        replayToolMatchIndex: 0,
      ),
      pendingAction: const ChatPendingActionState(),
      responseCompletionNeedsTranscriptRefresh: needsTranscriptRefresh,
    );
    if (needsTranscriptRefresh && completedStreamId != null) {
      _scheduleTranscriptRefresh(completedStreamId);
    }
    _markProgress();
  }

  void _scheduleTranscriptRefresh(String streamId) {
    _transcriptRefreshTimer?.cancel();
    _transcriptRefreshTimer = Timer(const Duration(milliseconds: 500), () {
      _transcriptRefreshTimer = null;
      unawaited(refreshTranscriptIfCompleted(streamId));
    });
  }

  /// 回合完成 → 通知 hook（仅 done / stream_end 成功收尾触发；
  /// cancel / error / transportError 路径不调用）。
  ///
  /// sessionId 为空（新会话尚未确定）时跳过：通知点击需要可跳转的会话。
  void _notifyTurnCompleted() {
    if (_disposed) return;
    final current = state;
    final sessionId = current.sessionId;
    if (sessionId.isEmpty) return;
    final title = current.displayTitle;
    final preview = _lastAssistantContent(current);
    ref.read(chatTurnCompletedCallbackProvider)(sessionId, title, preview);
  }

  /// 最近一条非空 assistant 消息内容（通知预览用）；无则空串。
  String _lastAssistantContent(ChatState state) {
    for (final message in state.messages.reversed) {
      final content = message.content ?? '';
      if (message.role == 'assistant' && content.trim().isNotEmpty) {
        return content;
      }
    }
    return '';
  }

  void _handleStreamEnd() {
    final wasCompleted = state.stream.hasCompletedResponse;
    if (!wasCompleted) {
      _completeCurrentResponse(
        needsTranscriptRefresh: false,
        completedStreamId: state.stream.activeStreamId,
      );
      // 回合完成（stream_end，done 未先到）：通知 hook。
      // done 已收尾时 wasCompleted 为 true，不会重复通知。
      _notifyTurnCompleted();
      _triggerSessionListRefreshForCompleted(state.sessionId);
    }
    _finishStream();
    unawaited(_writeCacheMessages(state.sessionId, state.messages));
  }

  void _handleCancelled() {
    if (!state.stream.hasCompletedResponse) {
      _completeCurrentResponse(
        needsTranscriptRefresh: false,
        completedStreamId: state.stream.activeStreamId,
      );
    }
    _finishStream(endPhase: ChatPhase.cancelled);
  }

  void _handleErrorEvent(String message) {
    if (!state.stream.hasCompletedResponse) {
      state = state.copyWith(sendErrorMessage: message);
      _completeCurrentResponse(
        needsTranscriptRefresh: false,
        completedStreamId: state.stream.activeStreamId,
      );
      _finishStream(endPhase: ChatPhase.error);
    } else {
      // done 已收尾：不显示错误，仅清理残留。
      _finishStream();
    }
  }

  /// finishStream：清残留（flush、卡片、pinned notices、队列顺次发送），
  /// 相位经瞬态 endPhase 后立即回 idle。
  void _finishStream({ChatPhase endPhase = ChatPhase.idle}) {
    flushPendingStreamingContent();
    var messages = state.messages;
    if (state.pinnedLocalNotices.isNotEmpty) {
      final notices = state.pinnedLocalNotices
          .map(
            (text) => ChatMessage(
              role: 'local_notice',
              content: text,
              messageId: 'local-notice-${uuidV4()}',
              timestamp: _nowSeconds(),
            ),
          )
          .toList();
      messages = [...messages, ...notices];
    }
    state = state.copyWith(
      phase: endPhase,
      messages: messages,
      pinnedLocalNotices: const [],
      clearLastSteerHint: true,
      pendingAction: const ChatPendingActionState(),
      stream: state.stream.copyWith(
        clearActiveStreamId: true,
        clearLastEventId: true,
        clearStreamingAssistantMessageId: true,
        clearToolCallAnchorMessageId: true,
        clearReasoningAnchorMessageId: true,
        isSuspended: false,
        recovery: ActiveStreamRecoveryState.idle,
        isCancelling: false,
        isReplayConnection: false,
        matchedPrefixLength: 0,
        matchedReasoningLength: 0,
        replayToolMatchIndex: 0,
      ),
    );
    _api?.stopStream();
    _cancelStreamTimers();
    _markProgress();
    // 瞬态相位：收尾完成后立即回 idle。
    if (endPhase != ChatPhase.idle) {
      state = state.copyWith(phase: ChatPhase.idle);
    }
    // done 后未收到 title → 补拉一次标题。
    if (state.stream.hasCompletedResponse &&
        state.displayTitle == 'Untitled Session') {
      unawaited(_refreshCompletedResponseTitleIfNeeded());
    }
    // 队列顺次发送。
    if (state.queuedSlashMessages.isNotEmpty) {
      unawaited(_drainQueuedSlashMessage());
    }
  }

  void _cancelStreamTimers() {
    _mergeTimer?.cancel();
    _mergeTimer = null;
    _revealTimer?.cancel();
    _revealTimer = null;
    _revealQueue.clear();
    _revealQueueStart = null;
  }

  Future<void> _refreshCompletedResponseTitleIfNeeded() async {
    final sessionId = state.sessionId;
    if (sessionId.isEmpty) return;
    final gen = _generation;
    try {
      final response = await _api!.session(
        sessionId: sessionId,
        includeMessages: false,
      );
      if (_disposed || gen != _generation) return;
      final title = response.session?.title?.trim();
      if (title != null && title.isNotEmpty) {
        state = state.copyWith(displayTitle: title);
      }
    } on ApiException {
      // 标题补拉失败静默。
    }
  }

  void _onNewSessionCreated(String newSessionId, String hint) {
    _pendingNewSessionIds.add(newSessionId);
    // Guard: no active connection in tests/offline -> skip list refresh (avoid "尚未配置服务器连接" throw).
    try {
      final active = ref.read(activeConnectionProvider);
      if (active == null) return;
    } catch (_) {
      return;
    }
    try {
      final notifier = ref.read(sessionListControllerProvider.notifier);
      unawaited(
        notifier
            .handleNewChatSession(newSessionId, titleHint: hint)
            .catchError((_) {}),
      );
    } catch (_) {
      // Provider 未就绪（如无激活连接）时静默，列表会在下次进入时拉取。
    }
  }

  void _triggerSessionListRefreshForCompleted(String sessionId) {
    if (sessionId.isEmpty) return;
    if (!_pendingNewSessionIds.contains(sessionId)) return;
    _pendingNewSessionIds.remove(sessionId);
    try {
      final active = ref.read(activeConnectionProvider);
      if (active == null) return;
    } catch (_) {
      return;
    }
    try {
      final notifier = ref.read(sessionListControllerProvider.notifier);
      unawaited(notifier.refreshIfStale(force: true).catchError((_) {}));
    } catch (_) {}
  }

  // -------------------------------------------------------------------------
  // transportError 断线恢复（chat_spec.md §5.3）
  // -------------------------------------------------------------------------

  void _handleTransportError(String message) {
    final stream = state.stream;
    if (stream.activeStreamId == null || stream.hasCompletedResponse) {
      // 无连接可恢复：显示错误 + finishStream。
      state = state.copyWith(sendErrorMessage: message);
      _finishStream(endPhase: ChatPhase.error);
      return;
    }
    // 挂起：lastEventID 已由 onEventId 记录；快照即当前 state。
    state = state.copyWith(
      phase: ChatPhase.recovering,
      stream: stream.copyWith(
        isSuspended: true,
        recovery: ActiveStreamRecoveryState.checking,
      ),
    );
    _api?.stopStream();
    unawaited(_reconnectIfNeeded());
  }

  Future<void> _reconnectIfNeeded() async {
    final streamId = state.stream.activeStreamId;
    if (streamId == null) return;
    final gen = _generation;
    try {
      final status = await _api!.chatStreamStatus(streamId);
      if (_disposed || gen != _generation) return;
      if (status.active == true) {
        // 全量重连：loadMessages 后恢复（带 replay 若快照有 lastEventID）。
        await _loadMessagesAndResume(streamId);
        return;
      }
      if (status.replayAvailable == true) {
        final afterSeq = _replayAfterSeq(state.stream.lastEventId);
        state = state.copyWith(
          stream: state.stream.copyWith(
            isSuspended: false,
            recovery: ActiveStreamRecoveryState.reconnecting,
          ),
        );
        _connectStream(
          streamId,
          replayAfterSeq: afterSeq == 0 ? null : afterSeq,
        );
        state = state.copyWith(
          stream: state.stream.copyWith(
            isSuspended: false,
            recovery: ActiveStreamRecoveryState.idle,
          ),
          phase: ChatPhase.streaming,
        );
        _markProgress();
        return;
      }
      // 非 active 且无 replay：loadMessages → 有 assistant 响应按 transcript
      // complete，否则 finalize 为失败。
      await _finalizeAfterRecovery(streamId);
    } on ApiException {
      if (_disposed || gen != _generation) return;
      // status 失败 → 强制尝试 replay。
      _forceReconnect(streamId);
    }
  }

  Future<void> _loadMessagesAndResume(String streamId) async {
    await loadMessages();
    if (_disposed) return;
    if (state.stream.activeStreamId != streamId) return;
    // 重锚定：加载的 transcript 里当前回合最后一条 assistant 消息。
    final currentAnchor = state.stream.streamingAssistantMessageId;
    if (currentAnchor == null ||
        !state.messages.any((m) => m.messageId == currentAnchor)) {
      String? anchorId;
      for (var i = state.messages.length - 1; i >= 0; i--) {
        final message = state.messages[i];
        if (message.role == 'assistant' && message.messageId != null) {
          anchorId = message.messageId;
          break;
        }
      }
      if (anchorId != null) {
        state = state.copyWith(
          stream: state.stream.copyWith(streamingAssistantMessageId: anchorId),
        );
      }
    }
    final afterSeq = _replayAfterSeq(state.stream.lastEventId);
    if (afterSeq > 0) {
      _connectStream(streamId, replayAfterSeq: afterSeq);
    } else {
      _connectStream(streamId, fullReconnect: true);
    }
    state = state.copyWith(
      stream: state.stream.copyWith(
        isSuspended: false,
        recovery: ActiveStreamRecoveryState.idle,
      ),
      phase: ChatPhase.streaming,
    );
    _markProgress();
  }

  Future<void> _finalizeAfterRecovery(String streamId) async {
    await loadMessages();
    if (_disposed) return;
    if (state.stream.activeStreamId != streamId) return;
    final hasAssistantResponse = state.messages.any(
      (m) => m.role == 'assistant',
    );
    if (hasAssistantResponse) {
      _completeCurrentResponse(
        needsTranscriptRefresh: false,
        completedStreamId: streamId,
      );
      _finishStream();
    } else {
      state = state.copyWith(sendErrorMessage: '连接已断开，未能恢复流。');
      _finishStream(endPhase: ChatPhase.error);
    }
  }

  /// 强制重连（status 失败 / 看门狗超时；带 replay 若可用）。
  void _forceReconnect(String streamId) {
    final afterSeq = _replayAfterSeq(state.stream.lastEventId);
    state = state.copyWith(
      stream: state.stream.copyWith(
        isSuspended: true,
        recovery: ActiveStreamRecoveryState.reconnecting,
      ),
    );
    _api?.stopStream();
    if (afterSeq > 0) {
      _connectStream(streamId, replayAfterSeq: afterSeq);
    } else {
      _connectStream(streamId, fullReconnect: true);
    }
    state = state.copyWith(
      stream: state.stream.copyWith(
        isSuspended: false,
        recovery: ActiveStreamRecoveryState.idle,
      ),
      phase: ChatPhase.streaming,
    );
    _markProgress();
  }

  /// lastEventID 冒号后序号解析（§5.4）；解析失败 → 0。
  int _replayAfterSeq(String? lastEventId) {
    if (lastEventId == null) return 0;
    final idx = lastEventId.lastIndexOf(':');
    final part = idx == -1 ? lastEventId : lastEventId.substring(idx + 1);
    return int.tryParse(part.trim()) ?? 0;
  }

  // -------------------------------------------------------------------------
  // 看门狗（前台 1s 心跳；5s/12s/18s/25s 阈值；冷却 ≥4s）
  // -------------------------------------------------------------------------

  void _startWatchdog() {
    _watchdogTimer?.cancel();
    _watchdogTimer = Timer.periodic(_watchdogConfig.watchdogInterval, (_) {
      _recoverStaleStreamIfNeeded();
    });
  }

  void _recoverStaleStreamIfNeeded() {
    if (_disposed) return;
    if (state.stream.activeStreamId == null) return;
    if (state.stream.hasCompletedResponse) return;
    if (state.pendingAction.hasPendingPrompt) return; // 卡片期间暂停
    final now = _now();
    final config = _watchdogConfig;
    final lastProgress = _lastProgress;
    final lastTransport = _lastTransportActivity;
    if (lastProgress != null &&
        now.difference(lastProgress) >= config.progressStaleThreshold &&
        lastTransport != null &&
        now.difference(lastTransport) >= config.transportStaleThreshold) {
      final cooldown = _statusCheckCooldownUntil;
      if (cooldown == null || now.isAfter(cooldown)) {
        _statusCheckCooldownUntil = now.add(config.statusPollCooldown);
        state = state.copyWith(
          stream: state.stream.copyWith(
            recovery: ActiveStreamRecoveryState.checking,
          ),
        );
        unawaited(_checkStatusAndReconnect());
      }
    }
    final forceThreshold = _hasRunningTools
        ? config.forceReconnectWithRunningToolsThreshold
        : config.forceReconnectThreshold;
    if (lastTransport != null &&
        now.difference(lastTransport) >= forceThreshold) {
      _forceReconnect(state.stream.activeStreamId!);
    }
  }

  bool get _hasRunningTools => state.liveToolCalls.any((t) => !t.isCompleted);

  Future<void> _checkStatusAndReconnect() async {
    final streamId = state.stream.activeStreamId;
    if (streamId == null) return;
    final gen = _generation;
    try {
      final status = await _api!.chatStreamStatus(streamId);
      if (_disposed || gen != _generation) return;
      if (status.active == true) {
        await _loadMessagesAndResume(streamId);
      } else if (status.replayAvailable == true) {
        final afterSeq = _replayAfterSeq(state.stream.lastEventId);
        state = state.copyWith(
          stream: state.stream.copyWith(
            recovery: ActiveStreamRecoveryState.reconnecting,
          ),
        );
        _connectStream(
          streamId,
          replayAfterSeq: afterSeq == 0 ? null : afterSeq,
        );
        state = state.copyWith(
          stream: state.stream.copyWith(
            recovery: ActiveStreamRecoveryState.idle,
          ),
          phase: ChatPhase.streaming,
        );
        _markProgress();
      } else {
        await _finalizeAfterRecovery(streamId);
      }
    } on ApiException {
      if (_disposed || gen != _generation) return;
      _forceReconnect(streamId);
    }
  }

  void _handleHeartbeat() {
    // 心跳证明传输存活：checking → idle；绝不 demote reconnecting。
    if (state.stream.recovery == ActiveStreamRecoveryState.checking) {
      state = state.copyWith(
        stream: state.stream.copyWith(recovery: ActiveStreamRecoveryState.idle),
      );
    }
  }

  // -------------------------------------------------------------------------
  // 归档 / 辅助
  // -------------------------------------------------------------------------

  void _archiveLiveReasoningIfNeeded() {
    if (state.liveReasoningText.isEmpty) return;
    final groups = _archiveLiveReasoningToGroups();
    state = state.copyWith(
      liveReasoningText: '',
      completedReasoningGroups: groups,
    );
  }

  List<ReasoningGroup> _archiveLiveReasoningToGroups() {
    if (state.liveReasoningText.isEmpty) return state.completedReasoningGroups;
    final anchor =
        state.stream.reasoningAnchorMessageId ??
        state.stream.streamingAssistantMessageId;
    final group = ReasoningGroup(anchorMessageId: anchor, text: state.liveReasoningText);
    return ReasoningGroup.merging(
      primaryGroups: state.completedReasoningGroups,
      fallbackGroups: [group],
    );
  }

  void _archiveLiveToolCallsIfNeeded() {
    if (state.liveToolCalls.isEmpty) return;
    final groups = _archiveLiveToolCallsToGroups();
    state = state.copyWith(
      liveToolCalls: const [],
      completedToolCallGroups: groups,
    );
  }

  List<ToolCallGroup> _archiveLiveToolCallsToGroups() {
    if (state.liveToolCalls.isEmpty) return state.completedToolCallGroups;
    final anchor =
        state.stream.toolCallAnchorMessageId ??
        state.stream.streamingAssistantMessageId;
    final group = ToolCallGroup.live(
      anchorMessageID: anchor,
      toolCalls: List<ToolCall>.of(state.liveToolCalls),
    );
    return ToolCallGroup.merging(
      primaryGroups: state.completedToolCallGroups,
      fallbackGroups: [group],
    );
  }

  void _rollbackOptimisticMessage(String messageId) {
    state = state.copyWith(
      messages: state.messages.where((m) => m.messageId != messageId).toList(),
    );
  }

  void _pinNotice(String text) {
    state = state.copyWith(
      pinnedLocalNotices: [...state.pinnedLocalNotices, text],
    );
  }

  void _setSendError(String message) {
    state = state.copyWith(sendErrorMessage: message);
  }

  /// 轻提示（成功类会话操作结果）。
  void setNotice(String message) {
    state = state.copyWith(noticeMessage: message);
  }

  /// 清除轻提示。
  void dismissNotice() {
    state = state.copyWith(clearNoticeMessage: true);
  }

  /// 清除重试回填预填值（输入栏已消费后调用）。
  void clearComposerPrefill() {
    state = state.copyWith(clearComposerPrefill: true);
  }

  void _markProgress() {
    _lastProgress = _now();
    // steered 是子相位：收到任意 progress 事件回到 streaming。
    if (state.phase == ChatPhase.steered) {
      state = state.copyWith(phase: ChatPhase.streaming);
    }
    if (state.stream.recovery == ActiveStreamRecoveryState.checking) {
      state = state.copyWith(
        stream: state.stream.copyWith(recovery: ActiveStreamRecoveryState.idle),
      );
    }
  }

  void _recordTransportActivity() {
    _lastTransportActivity = _now();
  }

  Future<void> _recoverExistingStream(String activeStreamId) async {
    await loadMessages();
    if (_disposed) return;
    if (state.stream.activeStreamId == null) {
      state = state.copyWith(
        stream: state.stream.copyWith(activeStreamId: activeStreamId),
      );
    }
    if (state.stream.activeStreamId == activeStreamId && !_streamConnected) {
      _connectStream(activeStreamId, fullReconnect: true);
    }
    state = state.copyWith(
      phase: ChatPhase.streaming,
      stream: state.stream.copyWith(
        hasCompletedResponse: false,
        isSuspended: false,
      ),
    );
    _markProgress();
  }

  String? _lastAssistantMessageId(List<ChatMessage> messages) {
    for (var i = messages.length - 1; i >= 0; i--) {
      final m = messages[i];
      if (m.role == 'assistant' && m.messageId != null) return m.messageId;
    }
    return null;
  }

  String _resolveTitle(SessionDetail detail) {
    final title = detail.title?.trim();
    if (title == null || title.isEmpty) return 'Untitled Session';
    return title;
  }

  // -------------------------------------------------------------------------
  // replay 去重（chat_spec.md §5.6；token 粒度 + reasoning 同构）
  // -------------------------------------------------------------------------

  /// token 粒度去重。返回剩余文本 + 新游标 + 是否仍处于 replay 匹配。
  @visibleForTesting
  static ({String remainder, int newCursor, bool stillReplay})
  deduplicatedReplayToken({
    required String token,
    required String existingContent,
    required int matchedPrefixLength,
  }) {
    if (existingContent.isEmpty) {
      return (remainder: token, newCursor: 0, stillReplay: false);
    }
    var cursor = matchedPrefixLength;
    if (cursor < 0) cursor = 0;
    if (cursor > existingContent.length) cursor = existingContent.length;
    final expectedRemainder = existingContent.substring(cursor);

    if (expectedRemainder.isNotEmpty && expectedRemainder.startsWith(token)) {
      // 纯重复：游标前进。
      final newCursor = cursor + token.length;
      return (
        remainder: '',
        newCursor: newCursor >= existingContent.length ? 0 : newCursor,
        stillReplay: true,
      );
    }
    if (expectedRemainder.isNotEmpty && token.startsWith(expectedRemainder)) {
      // 残余拼接。
      return (
        remainder: token.substring(expectedRemainder.length),
        newCursor: 0,
        stillReplay: true,
      );
    }
    if (existingContent.endsWith(token) || existingContent.startsWith(token)) {
      // 完全重复。
      return (remainder: '', newCursor: 0, stillReplay: true);
    }
    if (token.startsWith(existingContent)) {
      return (
        remainder: token.substring(existingContent.length),
        newCursor: 0,
        stillReplay: true,
      );
    }
    // 最大重叠扫描（existingContent 后缀 ∩ token 前缀，从大到小）。
    final maxLen = existingContent.length < token.length
        ? existingContent.length
        : token.length;
    var overlap = 0;
    for (var len = maxLen; len > 0; len--) {
      if (existingContent.endsWith(token.substring(0, len))) {
        overlap = len;
        break;
      }
    }
    if (overlap > 0) {
      return (
        remainder: token.substring(overlap),
        newCursor: 0,
        stillReplay: true,
      );
    }
    // 皆不匹配 → 原样返回，关闭 replay。
    return (remainder: token, newCursor: 0, stillReplay: false);
  }

  /// reasoning 粒度去重（同构，游标基于已 flush 的 liveReasoningText）。
  @visibleForTesting
  static ({String remainder, int newCursor, bool stillReplay})
  deduplicatedReplayText({
    required String text,
    required String existingContent,
    required int matchedLength,
  }) {
    return deduplicatedReplayToken(
      token: text,
      existingContent: existingContent,
      matchedPrefixLength: matchedLength,
    );
  }

  /// 词单元切分：空白携带在单元尾部；无空白的 CJK 长串每 8 字符切一刀。
  /// 拼接（join）与原始文本完全一致。
  @visibleForTesting
  static List<String> splitIntoWordUnits(String text) {
    if (text.isEmpty) return const [];
    final units = <String>[];
    final buffer = StringBuffer();
    for (final rune in text.runes) {
      final ch = String.fromCharCode(rune);
      buffer.write(ch);
      final isWhitespace = RegExp(r'\s').hasMatch(ch);
      if (isWhitespace || (isCjkRune(rune) && buffer.length >= 8)) {
        units.add(buffer.toString());
        buffer.clear();
      }
    }
    if (buffer.isNotEmpty) units.add(buffer.toString());
    return units;
  }

  /// CJK 统一表意文字 / 假名 / 谚文范围判定。
  static bool isCjkRune(int rune) {
    return (rune >= 0x4E00 && rune <= 0x9FFF) ||
        (rune >= 0x3400 && rune <= 0x4DBF) ||
        (rune >= 0xF900 && rune <= 0xFAFF) ||
        (rune >= 0x3040 && rune <= 0x30FF) ||
        (rune >= 0xAC00 && rune <= 0xD7AF);
  }

  /// 缓存写入：写入最近至多 50 条消息（错误时不影响聊天主流程）。
  Future<void> _writeCacheMessages(
    String sessionId,
    List<ChatMessage> messages,
  ) async {
    if (sessionId.isEmpty || messages.isEmpty) return;
    try {
      final cacheService = ref.read(cacheServiceProvider);
      final authoritative = messages.where((m) {
        final id = m.messageId ?? m.id;
        if (id.startsWith('local-') || id.startsWith('stream-')) {
          return false;
        }
        return true;
      }).toList();
      if (authoritative.isEmpty) return;
      final takeCount = authoritative.length > 50 ? 50 : authoritative.length;
      final recentMessages =
          authoritative.sublist(authoritative.length - takeCount);
      final maps = recentMessages.map(_messageToCacheJson).toList();
      await cacheService.writeMessages(
        sessionId: sessionId,
        messages: maps,
      );
    } catch (_) {
      // 写缓存失败不得影响聊天主流程（缓存旁路设计，不吞异常原则下此处属旁路容错）。
    }
  }

  static Map<String, Object?> _messageToCacheJson(ChatMessage message) {
    final json = message.toJson();
    final id = message.messageId ?? message.id;
    json['id'] = id;
    json['message_id'] ??= id;
    return json;
  }
}
