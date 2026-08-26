import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/connections/connection_providers.dart';
import '../../../core/models/chat_message.dart';
import '../../../core/models/tool_call.dart';
import '../../../core/utils/selected_context.dart';
import '../../../l10n/app_localizations.dart';
import '../../chat/chat_models.dart';
import '../../chat/chat_providers.dart';
import '../../chat/chat_state.dart';
import 'chat_media_parser.dart';
import 'chat_media_view.dart';
import 'markdown_styles.dart';
import 'message_action_menu.dart';
import 'message_bubble.dart';
import 'reasoning_block.dart';
import 'message_highlight.dart';
import '../../settings/injected_notice_settings.dart';
import '../../settings/tool_group_settings.dart';
import 'selected_context_card.dart';
import 'steer_banner.dart';
import 'tool_call_card.dart';

/// 消息列表（ListView.builder + 稳定 renderId key + 自动滚动跟随）。
///
/// 流式消息由独立气泡层渲染（transcriptMessagesProvider 已隐藏它），
/// 工具卡片/reasoning 折叠块按 anchorMessageID 锚定到对应气泡。
/// 底部额外插入 steer 横幅（phase==steered 时）与排队横幅（queued 非空时）。
class ChatMessageList extends ConsumerStatefulWidget {
  const ChatMessageList({
    super.key,
    required this.sessionId,
    this.highlightQuery,
  });

  final String sessionId;

  /// 搜索结果定位关键词（匹配 content 的第一条消息滚动+高亮；null 关闭）。
  final String? highlightQuery;

  @override
  ConsumerState<ChatMessageList> createState() => _ChatMessageListState();
}

class _ChatMessageListState extends ConsumerState<ChatMessageList> {
  final ScrollController _controller = ScrollController();
  final GlobalKey<State<StatefulWidget>> _highlightKey =
      GlobalKey<State<StatefulWidget>>();
  final Set<String> _expandedNoticeIds = <String>{};
  bool _nearBottom = true;
  bool _loadingOlder = false;
  bool _olderLoadQueued = false;
  bool _initialPositioned = false;
  bool _initialPositioning = false;
  bool _restoringOlderPosition = false;
  bool _userHasScrolled = false;
  int _layoutGeneration = 0;
  bool _initialPositionScheduled = false;
  String? _highlightTargetRenderId;
  bool _highlightPositioned = false;
  bool _highlightSettled = false;

  late ProviderSubscription<int> _scrollTriggerSub;
  late ProviderSubscription<ChatPhase> _phaseSub;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
    _scrollTriggerSub = ref.listenManual<int>(
      chatControllerProvider(widget.sessionId)
          .select((s) => s.streamingScrollTrigger),
      (_, _) {
        if (!mounted) return;
        if (_nearBottom) _scrollToBottom();
      },
    );
    _phaseSub = ref.listenManual<ChatPhase>(
      chatPhaseProvider(widget.sessionId),
      (previous, next) {
        if (!mounted) return;
        if (next == ChatPhase.sending || next == ChatPhase.streaming) {
          _scrollToBottom();
        }
      },
    );
    // 初次 highlight 解析（transcript 尚未加载时会返回 false，下次 build 重试）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _maybeResolveHighlightAndScroll();
    });
  }

  @override
  void didUpdateWidget(ChatMessageList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sessionId != widget.sessionId) {
      _scrollTriggerSub.close();
      _phaseSub.close();
      _initialPositioned = false;
      _initialPositioning = false;
      _initialPositionScheduled = false;
      _restoringOlderPosition = false;
      _userHasScrolled = false;
      _highlightTargetRenderId = null;
      _highlightSettled = false;
      _highlightPositioned = false;
      _expandedNoticeIds.clear();
      _nearBottom = true;
      _layoutGeneration++;
      _scrollTriggerSub = ref.listenManual<int>(
        chatControllerProvider(widget.sessionId)
            .select((s) => s.streamingScrollTrigger),
        (_, _) {
          if (!mounted) return;
          if (_nearBottom) _scrollToBottom();
        },
      );
      _phaseSub = ref.listenManual<ChatPhase>(
        chatPhaseProvider(widget.sessionId),
        (previous, next) {
          if (!mounted) return;
          if (next == ChatPhase.sending || next == ChatPhase.streaming) {
            _scrollToBottom();
          }
        },
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _maybeResolveHighlightAndScroll();
      });
    } else if (oldWidget.highlightQuery != widget.highlightQuery) {
      _highlightTargetRenderId = null;
      _highlightSettled = false;
      _highlightPositioned = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _maybeResolveHighlightAndScroll();
      });
    }
  }

  @override
  void dispose() {
    _scrollTriggerSub.close();
    _phaseSub.close();
    _controller.dispose();
    super.dispose();
  }

  void _maybeResolveHighlightAndScroll() {
    if (!mounted) return;
    if (_resolveHighlightTarget() && !_highlightPositioned) {
      _highlightPositioned = true;
      _scrollToHighlight();
    }
  }

  void _onScroll() {
    if (!_controller.hasClients) return;
    final position = _controller.position;
    final nearBottom = position.maxScrollExtent - position.pixels < 120;
    // 用户在初始定位收敛完成前的一切位置变化（含 jumpTo 自身触发）都不
    // 算用户滚动，避免估算偏差把「初始定位未到底」误判为「用户已上滚」。
    if (!_restoringOlderPosition &&
        _initialPositioned &&
        !_initialPositioning) {
      if (!nearBottom) _userHasScrolled = true;
      if (nearBottom != _nearBottom) {
        if (mounted) setState(() => _nearBottom = nearBottom);
      }
    }
    if (position.pixels <= 80 &&
        _initialPositioned &&
        !_restoringOlderPosition) {
      unawaited(_loadOlderMessages());
    }
  }

  Future<void> _loadOlderMessages() async {
    if (_loadingOlder || _olderLoadQueued || !mounted) return;
    final state = ref.read(chatControllerProvider(widget.sessionId));
    if (!state.hasOlderMessages || state.messagesOffset <= 0) return;
    _olderLoadQueued = true;
    _loadingOlder = true;
    final beforePixels = _controller.hasClients
        ? _controller.position.pixels
        : 0.0;
    final beforeExtent = _controller.hasClients
        ? _controller.position.maxScrollExtent
        : 0.0;
    _restoringOlderPosition = true;
    try {
      await ref
          .read(chatControllerProvider(widget.sessionId).notifier)
          .loadOlderMessages();
      if (!mounted) return;
      _restoreOlderScrollPosition(
        beforePixels: beforePixels,
        beforeExtent: beforeExtent,
        frame: 0,
      );
    } finally {
      _olderLoadQueued = false;
      _loadingOlder = false;
      // The post-frame callback owns the final reset. This fallback covers
      // request failures and unmounted controllers.
      if (!mounted) _restoringOlderPosition = false;
    }
  }

  void _restoreOlderScrollPosition({
    required double beforePixels,
    required double beforeExtent,
    required int frame,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients) {
        _restoringOlderPosition = false;
        return;
      }
      if (frame < 2) {
        _restoreOlderScrollPosition(
          beforePixels: beforePixels,
          beforeExtent: beforeExtent,
          frame: frame + 1,
        );
        return;
      }
      final delta = _controller.position.maxScrollExtent - beforeExtent;
      final target = (beforePixels + delta).clamp(
        0.0,
        _controller.position.maxScrollExtent,
      );
      if (!mounted || !_controller.hasClients) {
        _restoringOlderPosition = false;
        return;
      }
      _controller.jumpTo(target);
      _restoringOlderPosition = false;
      _nearBottom =
          _controller.position.maxScrollExtent - _controller.position.pixels <
          120;
    });
  }

  /// 初始定位是否在途（调度中或收敛循环执行中）。
  bool get _positioningActive =>
      _initialPositionScheduled || _initialPositioning;

  /// 初始定位滚到底部：lazy `ListView.builder` 首帧的 `maxScrollExtent` 是
  /// 估算值（未构建条目按平均高度折算），单次 jumpTo 会停在估算位置——
  /// 长会话下表现为「随机停在中间」。改为逐帧复核、收敛到真实底部。
  void _positionInitialView({required bool hasContent}) {
    if (!mounted ||
        !hasContent ||
        _userHasScrolled ||
        _initialPositionScheduled ||
        _initialPositioned) {
      return;
    }
    _initialPositionScheduled = true;
    final generation = ++_layoutGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initialPositionScheduled = false;
      if (!mounted || _userHasScrolled || generation != _layoutGeneration) {
        return;
      }
      // ListView 尚未挂载 controller：等待下一次 build 重试。
      if (!_controller.hasClients) return;
      _settleToBottom(generation: generation, attempts: 0);
    });
  }

  /// 收敛循环：跳到底部 → 下一帧复核 `maxScrollExtent` 是否仍在增长
  /// （新增条目改变了真实 extent）→ 增长则再跳；连续两帧稳定则一次精准
  /// jumpTo(最终 max) 收官（收官值 == max，不会越界 clamp）。
  ///
  /// 相对旧实现的改进：① 以「extent 连续稳定」为收敛条件（而非与跳转前
  /// 目标值比较），杜绝 overshoot 后像素被 ClampingScrollPhysics 拉回的
  /// 「撞击反弹」；② 超限时也做最后一次精准跳转收场（不再停在半途）。
  void _settleToBottom({
    required int generation,
    required int attempts,
    double? lastExtent,
  }) {
    if (!mounted || _userHasScrolled || generation != _layoutGeneration) {
      _initialPositioning = false;
      return;
    }
    if (attempts >= 24 || !_controller.hasClients) {
      // 尽力而为收场：以当前（最新估算/真实）extent 精准跳一次，避免停在半途。
      if (mounted &&
          _controller.hasClients &&
          !_userHasScrolled &&
          generation == _layoutGeneration) {
        final target = _controller.position.maxScrollExtent;
        if (target > 0) _controller.jumpTo(target);
      }
      _initialPositioning = false;
      _initialPositioned = true;
      _nearBottom =
          _controller.hasClients &&
          _controller.position.maxScrollExtent - _controller.position.pixels <
              120;
      return;
    }
    final target = _controller.position.maxScrollExtent;
    if (target <= 0 && _controller.position.viewportDimension <= 0) {
      // 视口尚未布局：下一帧再试，避免空转。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _settleToBottom(
          generation: generation,
          attempts: attempts + 1,
          lastExtent: lastExtent,
        );
      });
      return;
    }
    // extent 已连续两帧不变 → 真实底部已确定，最终精准跳一次收场。
    if (lastExtent != null && (target - lastExtent).abs() <= 0.5) {
      _finishSettleWithTarget(generation);
      return;
    }
    _initialPositioning = true;
    if (!mounted || !_controller.hasClients) {
      _initialPositioning = false;
      return;
    }
    if (target > 0) _controller.jumpTo(target);
    // 下一帧复核真实 extent 是否与跳转目标仍有出入。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _userHasScrolled || generation != _layoutGeneration) {
        _initialPositioning = false;
        return;
      }
      if (!_controller.hasClients) {
        _initialPositioning = false;
        return;
      }
      _settleToBottom(
        generation: generation,
        attempts: attempts + 1,
        lastExtent: _controller.position.maxScrollExtent,
      );
    });
  }

  /// 收敛收官：以当前真实 maxScrollExtent 精准跳一次并标记定位完成。
  /// （收官值恒等于 extent 本身，无越界 clamp，无回弹。）
  void _finishSettleWithTarget(int generation) {
    if (mounted && _controller.hasClients && generation == _layoutGeneration) {
      final target = _controller.position.maxScrollExtent;
      if (target > 0) _controller.jumpTo(target);
    }
    _initialPositioning = false;
    _initialPositioned = true;
    _nearBottom = true;
  }

  void _scrollToBottom({bool animated = true}) {
    if (!mounted || !_controller.hasClients) return;
    // 初始定位在途期间的滚动由 _settleToBottom 收敛循环负责（jumpTo 链）；
    // 若此时允许 animateTo，会与 jumpTo 竞争，并在估算 extent 上越界
    // 后被 ClampingScrollPhysics 拉回 → 视觉「撞击反弹」。
    // 初始定位在途期间的滚动由 _settleToBottom 收敛循环负责（jumpTo 链）；
    // 若此时允许 animateTo，会与 jumpTo 竞争，并在估算 extent 上越界
    // 后被 ClampingScrollPhysics 拉回 → 视觉「撞击反弹」。
    if (_positioningActive) return;
    final target = _controller.position.maxScrollExtent;
    if (target <= 0) return;
    if (animated) {
      _controller.animateTo(
        target,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    } else {
      _controller.jumpTo(target);
    }
  }

  /// 解析搜索定位目标（幂等）：在 transcript 里找第一条含关键词的消息，用 renderId。
  ///
  /// transcript 尚未加载完成时返回 false，由下一次重试；已加载但无匹配 → 置 settled 不再尝试。
  bool _resolveHighlightTarget() {
    if (_highlightSettled) return true;
    final query = widget.highlightQuery;
    if (query == null || query.isEmpty) {
      _highlightSettled = true;
      _highlightTargetRenderId = null;
      return true;
    }
    final transcript = ref.read(transcriptMessagesProvider(widget.sessionId));
    if (transcript.isEmpty) {
      final raw = ref.read(chatControllerProvider(widget.sessionId));
      if (raw.messages.isEmpty) return false;
      // transcript 为空但 raw 非空（被过滤为 tool-only），视为无匹配。
      _highlightSettled = true;
      return true;
    }
    final lower = query.toLowerCase();
    for (final entry in transcript) {
      final text = entry.message.content ?? '';
      if (text.toLowerCase().contains(lower)) {
        _highlightTargetRenderId = entry.renderId;
        break;
      }
    }
    _highlightSettled = true;
    return true;
  }

  /// 定位到高亮消息：优先 GlobalKey.ensureVisible；未构建（列表懒加载）
  /// 时先按索引比例粗跳，下一帧再 ensureVisible。
  void _scrollToHighlight() {
    if (_highlightTargetRenderId == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients) return;
      final ctx = _highlightKey.currentContext;
      if (ctx != null) {
        final renderObject = ctx.findRenderObject();
        if (renderObject == null || !renderObject.attached) {
          // detached → 尝试 fallback 粗跳。
        } else {
          if (ctx is Element && !ctx.mounted) return;
          Scrollable.ensureVisible(
            ctx,
            duration: const Duration(milliseconds: 350),
            alignment: 0.25,
          );
          return;
        }
      }
      // 目标未构建或 detached：按「目标序次 / 消息总数」比例粗跳到附近。
      final transcript = ref.read(transcriptMessagesProvider(widget.sessionId));
      final index = transcript.indexWhere(
        (e) => e.renderId == _highlightTargetRenderId,
      );
      if (index < 0 || transcript.isEmpty) return;
      if (!mounted || !_controller.hasClients) return;
      final ratio = index / transcript.length;
      final target = _controller.position.maxScrollExtent * ratio;
      if (!mounted || !_controller.hasClients) return;
      _controller.jumpTo(target);
      // 下一帧再精确对准（此时目标多半已入视口构建）。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_controller.hasClients) return;
        final retryCtx = _highlightKey.currentContext;
        if (retryCtx == null) return;
        final renderObject = retryCtx.findRenderObject();
        if (renderObject == null || !renderObject.attached) return;
        if (retryCtx is Element && !retryCtx.mounted) return;
        Scrollable.ensureVisible(
          retryCtx,
          duration: const Duration(milliseconds: 250),
          alignment: 0.25,
        );
      });
    });
  }

  /// 长按/右键消息弹操作菜单并执行动作。
  Future<void> _showMessageActions(ChatMessage message) async {
    final action = await showMessageActionMenu(context, message: message);
    if (action == null || !mounted) return;
    final controller = ref.read(
      chatControllerProvider(widget.sessionId).notifier,
    );
    switch (action) {
      case MessageAction.copy:
      case MessageAction.copyMd:
        // 先提示，再异步写剪贴板（立即反馈，不阻塞菜单关闭）。
        unawaited(copyMessageText(message));
        if (mounted) {
          controller.setNotice(
            AppLocalizations.of(context).copiedToClipboardNotice,
          );
        }
      case MessageAction.edit:
        final text = message.content;
        if (text != null && text.isNotEmpty) {
          controller.prefillComposer(text);
        }
      case MessageAction.branch:
        final branchIndex = ref
            .read(chatControllerProvider(widget.sessionId))
            .messages
            .indexWhere((m) => m.id == message.id);
        if (branchIndex >= 0) {
          final newId = await controller.branchAt(branchIndex);
          if (newId != null && mounted) {
            context.go('/chat/$newId');
          }
        }
      case MessageAction.truncate:
        final index = ref
            .read(chatControllerProvider(widget.sessionId))
            .messages
            .indexWhere((m) => m.id == message.id);
        if (index >= 0) await controller.truncateAt(index);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sessionId = widget.sessionId;
    final collapseEnabled = ref.watch(
      injectedNoticeSettingsProvider.select((s) => s.collapseInjectedNotices),
    );
    final coalesce = ref.watch(toolGroupCoalesceProvider);
    final transcript = ref.watch(transcriptMessagesProvider(sessionId));
    final streaming = ref.watch(streamingMessageProvider(sessionId));
    final liveTimeline = ref.watch(liveTimelineProvider(sessionId));
    final toolGroups = ref.watch(toolGroupsProvider(sessionId));
    final reasoningGroups = ref.watch(reasoningGroupsProvider(sessionId));
    final phase = ref.watch(chatPhaseProvider(sessionId));
    final queuedMessages = ref.watch(
      chatControllerProvider(sessionId).select((s) => s.queuedSlashMessages),
    );

    final entryToolGroups = <String, List<ToolCallGroup>>{};
    final mountedGroupIds = <String>{};
    for (final entry in transcript) {
      final msgId = entry.message.messageId;
      final anchorId = entry.anchorId;
      final matched = <ToolCallGroup>[];
      for (final g in toolGroups) {
        if (!coalesce && mountedGroupIds.contains(g.id)) {
          continue;
        }
        final isMatch =
            (msgId != null && msgId.isNotEmpty && g.anchorMessageID == msgId) ||
            (g.anchorMessageID != null && g.anchorMessageID == anchorId);
        if (isMatch) {
          matched.add(g);
          if (!coalesce) {
            mountedGroupIds.add(g.id);
          }
        }
      }
      entryToolGroups[entry.renderId] = matched;
    }

    // 初始定位与搜索定位均以 postFrame 调度，避免 build 期间同步 markNeedsBuild
    // 或在 dependents 未就绪时触发 listen 副作用。
    _positionInitialView(
      hasContent: transcript.isNotEmpty || streaming != null,
    );
    if (!_highlightSettled ||
        (_highlightTargetRenderId != null && !_highlightPositioned)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_resolveHighlightTarget() && !_highlightPositioned) {
          _highlightPositioned = true;
          _scrollToHighlight();
        }
      });
    }

    // live 时间线模式：streaming 且 provider 非 null（null = 重连归档等
    // 无法还原段落边界的场景，回退旧分组式流式气泡）。
    final timelineActive = streaming != null && liveTimeline != null;
    final streamingTools = streaming == null || liveTimeline != null
        ? const <ToolCallGroup>[]
        : toolGroups
              .where((g) => g.anchorMessageID == streaming.messageId)
              .toList();
    final streamingReasoning = streaming == null || liveTimeline != null
        ? const <ReasoningGroup>[]
        : reasoningGroups
              .where((g) => g.anchorMessageId == streaming.messageId)
              .toList();

    final showQueuedBanner = queuedMessages.isNotEmpty;
    // 落地兜底：仅在 coalesce==true 或 transcript 为空且无可挂载 anchor 时才渲染聚合视图
    final needFallback =
        coalesce &&
        transcript.isEmpty &&
        streaming == null &&
        phase != ChatPhase.sending &&
        (toolGroups.isNotEmpty || reasoningGroups.isNotEmpty);

    // live 段落条目数：时间线模式 = 段数（空段列表 = 思考中指示器 1 条）；
    // legacy 模式 = 单个流式气泡。
    final liveItemCount = streaming == null
        ? 0
        : liveTimeline == null
        ? 1
        : (liveTimeline.isEmpty ? 1 : liveTimeline.length);

    var itemCount = transcript.length + liveItemCount;
    if (phase == ChatPhase.sending) itemCount++;
    if (showQueuedBanner) itemCount++;
    if (needFallback) itemCount++;

    return ListView.builder(
      controller: _controller,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        // 统一尾部顺序：transcript | queued | steer | streaming | sending | fallback
        if (index < transcript.length) {
          final entry = transcript[index];
          final groups =
              entryToolGroups[entry.renderId] ?? const <ToolCallGroup>[];
          final reasoning = reasoningGroups
              .where(
                (g) =>
                    g.anchorMessageId == entry.message.messageId ||
                    (g.anchorMessageId != null &&
                        g.anchorMessageId == entry.anchorId),
              )
              .toList();
          final noticeId = entry.message.id;
          final expanded = _expandedNoticeIds.contains(noticeId);
          final isHighlightTarget =
              _highlightTargetRenderId != null &&
              entry.renderId == _highlightTargetRenderId;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onLongPress: () => _showMessageActions(entry.message),
            onSecondaryTapDown: (_) => _showMessageActions(entry.message),
            child: KeyedSubtree(
              key: isHighlightTarget ? _highlightKey : null,
              child: SearchMessageHighlight(
                highlight: isHighlightTarget,
                child: ChatMessageBubble(
                  key: ValueKey(entry.renderId),
                  message: entry.message,
                  toolGroups: groups,
                  reasoningGroups: reasoning,
                  collapseInjectedEnabled: collapseEnabled,
                  injectedExpanded: expanded,
                  onToggleInjected: () {
                    if (!mounted) return;
                    setState(() {
                      if (_expandedNoticeIds.contains(noticeId)) {
                        _expandedNoticeIds.remove(noticeId);
                      } else {
                        _expandedNoticeIds.add(noticeId);
                      }
                    });
                  },
                ),
              ),
            ),
          );
        }
        var tail = index - transcript.length;
        if (showQueuedBanner) {
          if (tail == 0) {
            return QueuedBanner(
              count: queuedMessages.length,
              preview: queuedMessages.first,
            );
          }
          tail--;
        }
        if (streaming != null && !timelineActive) {
          // legacy：旧分组式流式气泡（重连归档等无法还原段落边界的场景）。
          if (tail == 0) {
            return _StreamingBubble(
              message: streaming,
              toolGroups: streamingTools,
              reasoningGroups: streamingReasoning,
            );
          }
          tail--;
        }
        if (streaming != null && timelineActive) {
          if (liveTimeline.isEmpty) {
            if (tail == 0) return const _StreamingThinkingIndicator();
            tail--;
          } else {
            if (tail < liveTimeline.length) {
              return _LiveTimelineItem(
                entry: liveTimeline[tail],
                streamingMessage: streaming,
              );
            }
            tail -= liveTimeline.length;
          }
        }
        if (phase == ChatPhase.sending) {
          if (tail == 0) return const _SendingIndicator();
          tail--;
        }
        if (needFallback) {
          if (tail == 0) {
            return _FallbackToolReasoningCards(
              toolGroups: toolGroups,
              reasoningGroups: reasoningGroups,
            );
          }
          tail--;
        }
        return const SizedBox.shrink();
      },
    );
  }
}

/// 流式气泡（独立渲染层：思考中指示器 + 流式文本 + 实时工具卡片）。
class _StreamingBubble extends StatelessWidget {
  const _StreamingBubble({
    required this.message,
    required this.toolGroups,
    required this.reasoningGroups,
  });

  final ChatMessage message;
  final List<ToolCallGroup> toolGroups;
  final List<ReasoningGroup> reasoningGroups;

  @override
  Widget build(BuildContext context) {
    final hasContent = (message.content ?? '').isNotEmpty;
    final isEmpty =
        !hasContent && toolGroups.isEmpty && reasoningGroups.isEmpty;
    if (!isEmpty) {
      return ChatMessageBubble(
        message: message,
        toolGroups: toolGroups,
        reasoningGroups: reasoningGroups,
      );
    }
    // 空流式气泡 → 思考中指示器。
    return const _StreamingThinkingIndicator();
  }
}

/// 思考中指示器（空流式气泡 / live 时间线空态共用）。
class _StreamingThinkingIndicator extends StatelessWidget {
  const _StreamingThinkingIndicator();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(
              children: [
                const CupertinoActivityIndicator(radius: 8),
                const SizedBox(width: 8),
                Text(
                  l10n.thinkingIndicator,
                  style: TextStyle(
                    fontSize: 14,
                    color: CupertinoColors.secondaryLabel.resolveFrom(context),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// live 时间线条目渲染（think/text/tools 按事件先后穿插的独立列表项）。
class _LiveTimelineItem extends StatelessWidget {
  const _LiveTimelineItem({
    required this.entry,
    required this.streamingMessage,
  });

  final LiveTimelineEntry entry;
  final ChatMessage streamingMessage;

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: ValueKey(entry.renderKey),
      child: switch (entry.kind) {
        LiveSegmentKind.thinking => Padding(
          // 与 text / tools 段同款外边距（12px 左右），对齐卡片左右对齐线。
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          child: ReasoningBlock(
            group: ReasoningGroup(
              anchorMessageId: streamingMessage.messageId,
              text: entry.reasoningText,
            ),
          ),
        ),
        LiveSegmentKind.text => _LiveTextBlock(
          slice: entry.textSlice,
          streamingMessage: streamingMessage,
        ),
        LiveSegmentKind.tools => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          child: ToolCallGroupCard(group: entry.toolGroup!),
        ),
      },
    );
  }
}

/// 流式文本段（Markdown 渲染，镜像历史 assistant 气泡的 content 处理管线）。
class _LiveTextBlock extends StatelessWidget {
  const _LiveTextBlock({required this.slice, required this.streamingMessage});

  final String slice;
  final ChatMessage streamingMessage;

  @override
  Widget build(BuildContext context) {
    final selected = SelectedContextParser.parse(slice);
    final blocks = selected.blocks;
    final cleanText = selected.cleanText;
    final hasMediaMarker =
        cleanText.contains('MEDIA:') || cleanText.contains('file://');
    final parsedContent = hasMediaMarker
        ? ChatMediaParser.parseMediaMarkers(cleanText)
        : cleanText;
    final sections = <Widget>[];
    if (blocks.isNotEmpty) {
      sections.add(SelectedContextCardGroup(blocks: blocks));
    }
    if (parsedContent.isNotEmpty) {
      sections.add(
        MarkdownBody(
          data: parsedContent,
          selectable: true,
          styleSheet: buildAssistantMarkdownStyleSheet(context),
          builders: createAssistantMarkdownBuilders(context),
          // ignore: deprecated_member_use
          imageBuilder: (uri, title, alt) {
            return ChatInlineMediaWidget(
              rawUri: uri.toString(),
              title: title,
              alt: alt,
              baseUrl: _resolveBaseUrl(context),
            );
          },
        ),
      );
    }
    if (sections.isEmpty) return const SizedBox.shrink();
    final children = <Widget>[];
    for (var i = 0; i < sections.length; i++) {
      if (i > 0) children.add(const SizedBox(height: kMessageSectionGap));
      children.add(sections[i]);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  String? _resolveBaseUrl(BuildContext context) {
    try {
      final container = ProviderScope.containerOf(context, listen: false);
      return container.read(activeConnectionProvider)?.baseUrl;
    } catch (_) {
      return null;
    }
  }
}

/// 发送中指示器（sending 相位，未拿到 stream_id）。
class _SendingIndicator extends StatelessWidget {
  const _SendingIndicator();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(
              children: [
                const CupertinoActivityIndicator(radius: 8),
                const SizedBox(width: 8),
                Text(
                  l10n.sendingIndicator,
                  style: TextStyle(
                    fontSize: 14,
                    color: CupertinoColors.secondaryLabel.resolveFrom(context),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 落地兜底：transcript 为空但已归档的工具/思考组非空时，末尾独立渲染入口
class _FallbackToolReasoningCards extends StatelessWidget {
  const _FallbackToolReasoningCards({
    required this.toolGroups,
    required this.reasoningGroups,
  });

  final List<ToolCallGroup> toolGroups;
  final List<ReasoningGroup> reasoningGroups;

  @override
  Widget build(BuildContext context) {
    // 复用与 assistant 气泡相同的 horizontal 12 外边距；区块间统一固定间距
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final group in reasoningGroups) ...[
            ReasoningBlock(group: group),
            if (group != reasoningGroups.last) const SizedBox(height: 8),
          ],
          if (reasoningGroups.isNotEmpty && toolGroups.isNotEmpty)
            const SizedBox(height: 8),
          for (final group in toolGroups) ...[
            ToolCallGroupCard(group: group),
            if (group != toolGroups.last) const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}
