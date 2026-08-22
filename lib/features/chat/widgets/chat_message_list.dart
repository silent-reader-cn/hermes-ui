import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:go_router/go_router.dart';

import '../../../core/models/chat_message.dart';
import '../../../core/models/tool_call.dart';
import '../../../l10n/app_localizations.dart';
import '../../chat/chat_models.dart';
import '../../chat/chat_providers.dart';
import '../../chat/chat_state.dart';
import 'message_action_menu.dart';
import 'message_bubble.dart';
import '../../settings/injected_notice_settings.dart';
import 'message_highlight.dart';

/// 消息列表（ListView.builder + 稳定 renderId key + 自动滚动跟随）。
///
/// 流式消息由独立气泡层渲染（transcriptMessagesProvider 已隐藏它），
/// 工具卡片/reasoning 折叠块按 anchorMessageID 锚定到对应气泡。
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
  final GlobalKey _highlightKey = GlobalKey();
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
  String? _highlightTargetId;
  bool _highlightPositioned = false;
  bool _highlightSettled = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
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
        setState(() => _nearBottom = nearBottom);
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
      _controller.jumpTo(target);
      _restoringOlderPosition = false;
      _nearBottom =
          _controller.position.maxScrollExtent - _controller.position.pixels <
          120;
    });
  }

  /// 初始定位滚到底部：lazy `ListView.builder` 首帧的 `maxScrollExtent` 是
  /// 估算值（未构建条目按估算高度折算），单次 jumpTo 会停在估算位置——
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
  /// （新增条目改变了真实 extent）→ 增长则再跳；稳定或超限则完成。
  void _settleToBottom({required int generation, required int attempts}) {
    if (!mounted || _userHasScrolled || generation != _layoutGeneration) {
      _initialPositioning = false;
      return;
    }
    if (attempts >= 12 || !_controller.hasClients) {
      _initialPositioning = false;
      _initialPositioned = true; // 尽力而为：以当前 extent 收场。
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
        _settleToBottom(generation: generation, attempts: attempts + 1);
      });
      return;
    }
    _initialPositioning = true;
    _controller.jumpTo(target);
    // 下一帧复核真实 extent 是否与跳转目标仍有出入。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _userHasScrolled || generation != _layoutGeneration) {
        _initialPositioning = false;
        return;
      }
      final now = _controller.position.maxScrollExtent;
      if ((now - target).abs() > 1.0) {
        _settleToBottom(generation: generation, attempts: attempts + 1);
      } else {
        _initialPositioning = false;
        _initialPositioned = true;
        _nearBottom = true;
      }
    });
  }

  void _scrollToBottom({bool animated = true}) {
    if (!_controller.hasClients) return;
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

  /// 解析搜索定位目标（幂等）：在 messages 里找第一条含关键词的消息。
  ///
  /// messages 尚未加载完成时返回 false，由下一次 build 重试；
  /// 已加载但无匹配 → 置 settled 不再尝试。
  bool _resolveHighlightTarget() {
    if (_highlightSettled) return true;
    final query = widget.highlightQuery;
    if (query == null || query.isEmpty) {
      _highlightSettled = true;
      return true;
    }
    final state = ref.read(chatControllerProvider(widget.sessionId));
    if (state.messages.isEmpty) return false;
    final lower = query.toLowerCase();
    for (final message in state.messages) {
      final text = message.content ?? '';
      if (text.toLowerCase().contains(lower)) {
        _highlightTargetId = message.id;
        break;
      }
    }
    _highlightSettled = true;
    return true;
  }

  /// 定位到高亮消息：优先 GlobalKey.ensureVisible；未构建（列表懒加载）
  /// 时先按索引比例粗跳，下一帧再 ensureVisible。
  void _scrollToHighlight() {
    if (_highlightTargetId == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients) return;
      final ctx = _highlightKey.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 350),
          alignment: 0.25,
        );
        return;
      }
      // 目标未构建：按「目标序次 / 消息总数」比例粗跳到附近。
      final state = ref.read(chatControllerProvider(widget.sessionId));
      final index = state.messages.indexWhere(
        (m) => m.id == _highlightTargetId,
      );
      if (index < 0 || state.messages.isEmpty) return;
      final ratio = index / state.messages.length;
      final target = _controller.position.maxScrollExtent * ratio;
      _controller.jumpTo(target);
      // 下一帧再精确对准（此时目标多半已入视口构建）。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final retryCtx = _highlightKey.currentContext;
        if (retryCtx != null) {
          Scrollable.ensureVisible(
            retryCtx,
            duration: const Duration(milliseconds: 250),
            alignment: 0.25,
          );
        }
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
    final transcript = ref.watch(transcriptMessagesProvider(sessionId));
    final streaming = ref.watch(streamingMessageProvider(sessionId));
    final toolGroups = ref.watch(toolGroupsProvider(sessionId));
    final reasoningGroups = ref.watch(reasoningGroupsProvider(sessionId));
    final phase = ref.watch(chatPhaseProvider(sessionId));
    _positionInitialView(
      hasContent: transcript.isNotEmpty || streaming != null,
    );

    // 搜索定位：解析目标（幂等）→ 首次到位时触发滚动一次。
    if (_resolveHighlightTarget() && !_highlightPositioned) {
      _highlightPositioned = true;
      _scrollToHighlight();
    }

    // 滚动跟随：每次 flush 出内容（16ms 合并节流）后，若用户在底部则跟随。
    ref.listen<int>(
      chatControllerProvider(sessionId).select((s) => s.streamingScrollTrigger),
      (_, _) {
        if (_nearBottom) _scrollToBottom();
      },
    );
    // 发送/流开始：回到底部。
    ref.listen<ChatPhase>(chatPhaseProvider(sessionId), (previous, next) {
      if (next == ChatPhase.sending || next == ChatPhase.streaming) {
        _scrollToBottom();
      }
    });

    final streamingTools = streaming == null
        ? const <ToolCallGroup>[]
        : toolGroups
              .where((g) => g.anchorMessageID == streaming.messageId)
              .toList();
    final streamingReasoning = streaming == null
        ? const <ReasoningGroup>[]
        : reasoningGroups
              .where((g) => g.anchorMessageId == streaming.messageId)
              .toList();

    var itemCount = transcript.length;
    if (streaming != null) itemCount++;
    if (phase == ChatPhase.sending) itemCount++;

    return ListView.builder(
      controller: _controller,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        if (phase == ChatPhase.sending && index == itemCount - 1) {
          return const _SendingIndicator();
        }
        if (streaming != null &&
            index == itemCount - (phase == ChatPhase.sending ? 2 : 1)) {
          return _StreamingBubble(
            message: streaming,
            toolGroups: streamingTools,
            reasoningGroups: streamingReasoning,
          );
        }
        final entry = transcript[index];
        final groups = toolGroups
            .where((g) => g.anchorMessageID == entry.message.messageId)
            .toList();
        final reasoning = reasoningGroups
            .where((g) => g.anchorMessageId == entry.message.messageId)
            .toList();
        final noticeId = entry.message.id;
        final expanded = _expandedNoticeIds.contains(noticeId);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onLongPress: () => _showMessageActions(entry.message),
          onSecondaryTapDown: (_) => _showMessageActions(entry.message),
          child: KeyedSubtree(
            key:
                _highlightTargetId != null &&
                    entry.message.id == _highlightTargetId
                ? _highlightKey
                : null,
            child: SearchMessageHighlight(
              highlight:
                  _highlightTargetId != null &&
                  entry.message.id == _highlightTargetId,
              child: ChatMessageBubble(
                key: ValueKey(entry.message.id),
                message: entry.message,
                toolGroups: groups,
                reasoningGroups: reasoning,
                collapseInjectedEnabled: collapseEnabled,
                injectedExpanded: expanded,
                onToggleInjected: () {
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
    final l10n = AppLocalizations.of(context);
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
                  style: const TextStyle(
                    fontSize: 14,
                    color: CupertinoColors.secondaryLabel,
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
                  style: const TextStyle(
                    fontSize: 14,
                    color: CupertinoColors.secondaryLabel,
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
