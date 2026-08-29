import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
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
import 'message_highlight.dart';
import '../../settings/injected_notice_settings.dart';
import '../../settings/tool_group_settings.dart';
import 'selected_context_card.dart';
import 'steer_banner.dart';
import 'tool_call_card.dart';

/// 阅读锚点快照（离底阅读时记录视口顶部第一条可见条目及偏移，todo.md #14）。
class _ReadingAnchor {
  const _ReadingAnchor({
    required this.candidateKey,
    this.renderId,
    this.liveRenderKey,
    this.toolGroupId,
    this.messageId,
    required this.topOffset,
  });

  final String candidateKey;
  final String? renderId;
  final String? liveRenderKey;
  final String? toolGroupId;
  final String? messageId;
  final double topOffset;
}

/// 安全 Markdown 渲染组件（增量流式解析异常兜底为纯文本，防止大灰屏，todo.md #8）。
class _SafeMarkdownBody extends StatelessWidget {
  const _SafeMarkdownBody({
    required this.data,
    required this.styleSheet,
    required this.builders,
    required this.imageBuilder,
    this.selectable = true,
  });

  final String data;
  final MarkdownStyleSheet styleSheet;
  final Map<String, MarkdownElementBuilder> builders;
  final Widget Function(Uri, String?, String?) imageBuilder;
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    try {
      return MarkdownBody(
        data: data,
        selectable: selectable,
        styleSheet: styleSheet,
        builders: builders,
        // ignore: deprecated_member_use
        imageBuilder: imageBuilder,
      );
    } catch (e, st) {
      developer.log(
        'MarkdownBody incremental parse error, fallback to Text',
        name: 'chat.markdown',
        error: e,
        stackTrace: st,
      );
      return Text(
        data,
        style: TextStyle(
          fontSize: 15,
          height: 1.4,
          color: CupertinoColors.label.resolveFrom(context),
        ),
      );
    }
  }
}

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
  final Map<String, GlobalKey> _itemKeys = <String, GlobalKey>{};
  _ReadingAnchor? _readingAnchor;
  double? _lastBottomInset;

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
  ChatPhase? _lastPhase;
  bool _justSent = false;
  bool _isAnimatingToBottom = false;

  /// 非动画跳底收敛链（`_settleJumpToBottom`）复核次数上限（#23）。
  /// 发送/流式路径只需追平「新气泡未布局完」的增长窗口，几帧内即收敛，
  /// 刻意远小于初始定位 `_settleToBottom` 的 24 轮上限。
  static const int _maxJumpResettle = 3;

  /// 非动画跳底收敛链是否在途：防止同帧多次触发叠出并行跳转链。
  bool _jumpSettling = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
    _scrollTriggerSub = ref.listenManual<int>(
      chatControllerProvider(widget.sessionId)
          .select((s) => s.streamingScrollTrigger),
      (_, _) {
        if (!mounted) return;
        if (_nearBottom) _scrollToBottom(animated: false);
      },
    );
    _phaseSub = ref.listenManual<ChatPhase>(
      chatPhaseProvider(widget.sessionId),
      (previous, next) {
        if (!mounted) return;
        if (next == ChatPhase.sending) {
          // 刚发送门控：用户刚发送，置位门控，重置离底阅读标志（#13/#14）
          _justSent = true;
          _userHasScrolled = false;
          _nearBottom = true;
          _readingAnchor = null;
        } else if (next == ChatPhase.streaming) {
          final transcript = ref.read(
            transcriptMessagesProvider(widget.sessionId),
          );
          final isUserLast =
              transcript.isNotEmpty && transcript.last.message.role == 'user';
          if (_justSent ||
              _nearBottom ||
              previous == ChatPhase.sending ||
              isUserLast) {
            _justSent = true;
            _userHasScrolled = false;
            _nearBottom = true;
            _readingAnchor = null;
          }
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
      _itemKeys.clear();
      _readingAnchor = null;
      _lastBottomInset = null;
      _lastPhase = null;
      _justSent = false;
      _isAnimatingToBottom = false;
      _nearBottom = true;
      _layoutGeneration++;
      _scrollTriggerSub = ref.listenManual<int>(
        chatControllerProvider(widget.sessionId)
            .select((s) => s.streamingScrollTrigger),
        (_, _) {
          if (!mounted) return;
          if (_nearBottom) _scrollToBottom(animated: false);
        },
      );
      _phaseSub = ref.listenManual<ChatPhase>(
        chatPhaseProvider(widget.sessionId),
        (previous, next) {
          if (!mounted) return;
          if (next == ChatPhase.sending) {
            _justSent = true;
            _userHasScrolled = false;
            _nearBottom = true;
            _readingAnchor = null;
          } else if (next == ChatPhase.streaming) {
            final transcript = ref.read(
              transcriptMessagesProvider(widget.sessionId),
            );
            final isUserLast =
                transcript.isNotEmpty && transcript.last.message.role == 'user';
            if (_justSent ||
                _nearBottom ||
                previous == ChatPhase.sending ||
                isUserLast) {
              _justSent = true;
              _userHasScrolled = false;
              _nearBottom = true;
              _readingAnchor = null;
            }
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
      if (nearBottom) {
        _userHasScrolled = false;
        _readingAnchor = null;
      } else {
        if (_userHasScrolled) {
          _updateReadingAnchor();
        }
      }
      if (nearBottom != _nearBottom && !_isAnimatingToBottom) {
        if (mounted) setState(() => _nearBottom = nearBottom);
      }
    }
    if (position.pixels <= 80 &&
        _initialPositioned &&
        !_restoringOlderPosition) {
      unawaited(_loadOlderMessages());
    }
  }

  /// 记录视口顶部第一条可见条目 + 偏移（候选锚点优先级：renderId → liveRenderKey → toolGroupId → messageId，todo.md #14）。
  void _updateReadingAnchor() {
    if (!_controller.hasClients || _nearBottom || !mounted) return;
    final scrollableBox = context.findRenderObject() as RenderBox?;
    if (scrollableBox == null || !scrollableBox.attached) return;

    final transcript = ref.read(transcriptMessagesProvider(widget.sessionId));
    final liveTimeline = ref.read(liveTimelineProvider(widget.sessionId));
    final toolGroups = ref.read(toolGroupsProvider(widget.sessionId));

    _ReadingAnchor? candidate;

    // 1. 优先扫描 transcript 消息
    for (final entry in transcript) {
      final key = _itemKeys[entry.renderId];
      if (key?.currentContext == null) continue;
      final box = key!.currentContext!.findRenderObject() as RenderBox?;
      if (box == null || !box.attached) continue;
      final localOffset = box.localToGlobal(
        Offset.zero,
        ancestor: scrollableBox,
      );
      final dy = localOffset.dy;
      if (dy + box.size.height > 0) {
        final group = toolGroups
            .where(
              (g) =>
                  g.anchorMessageID == entry.message.messageId ||
                  g.anchorMessageID == entry.anchorId,
            )
            .firstOrNull;
        candidate = _ReadingAnchor(
          candidateKey: entry.renderId,
          renderId: entry.renderId,
          toolGroupId: group?.id,
          messageId: entry.message.messageId ?? entry.message.id,
          topOffset: dy,
        );
        break;
      }
    }

    // 2. 其次扫描 liveTimeline 段落
    if (candidate == null && liveTimeline != null) {
      for (final entry in liveTimeline) {
        final key = _itemKeys[entry.renderKey];
        if (key?.currentContext == null) continue;
        final box = key!.currentContext!.findRenderObject() as RenderBox?;
        if (box == null || !box.attached) continue;
        final localOffset = box.localToGlobal(
          Offset.zero,
          ancestor: scrollableBox,
        );
        final dy = localOffset.dy;
        if (dy + box.size.height > 0) {
          candidate = _ReadingAnchor(
            candidateKey: entry.renderKey,
            liveRenderKey: entry.renderKey,
            toolGroupId: entry.toolGroup?.id,
            topOffset: dy,
          );
          break;
        }
      }
    }

    if (candidate != null) {
      _readingAnchor = candidate;
    }
  }

  /// 内容变化 postFrame 无动画跳回锚点，绝不拉回底部（todo.md #14）。
  void _maybeRestoreReadingAnchor() {
    if (!mounted ||
        !_controller.hasClients ||
        _nearBottom ||
        !_userHasScrolled ||
        !_initialPositioned ||
        _positioningActive ||
        _restoringOlderPosition) {
      return;
    }
    final anchor = _readingAnchor;
    if (anchor == null) return;

    final scrollableBox = context.findRenderObject() as RenderBox?;
    if (scrollableBox == null || !scrollableBox.attached) return;

    // 按优先级解析锚点：transcript renderId → live entry.renderKey → 工具组 id → messageId
    GlobalKey? targetKey;
    if (anchor.renderId != null && _itemKeys.containsKey(anchor.renderId)) {
      targetKey = _itemKeys[anchor.renderId];
    } else if (anchor.liveRenderKey != null &&
        _itemKeys.containsKey(anchor.liveRenderKey)) {
      targetKey = _itemKeys[anchor.liveRenderKey];
    } else if (anchor.toolGroupId != null &&
        _itemKeys.containsKey(anchor.toolGroupId)) {
      targetKey = _itemKeys[anchor.toolGroupId];
    } else if (anchor.messageId != null &&
        _itemKeys.containsKey(anchor.messageId)) {
      targetKey = _itemKeys[anchor.messageId];
    }

    if (targetKey?.currentContext == null) return;
    final box = targetKey!.currentContext!.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return;

    final localOffset = box.localToGlobal(Offset.zero, ancestor: scrollableBox);
    final currentDy = localOffset.dy;
    final diff = currentDy - anchor.topOffset;

    if (diff.abs() > 0.5) {
      final newPixels = (_controller.position.pixels + diff).clamp(
        0.0,
        _controller.position.maxScrollExtent,
      );
      if ((newPixels - _controller.position.pixels).abs() > 0.5) {
        _controller.jumpTo(newPixels);
      }
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
    // 若此时允许 animateTo 或额外 jump，会与收敛链竞争，并在估算 extent 上
    // 越界后被 ClampingScrollPhysics 弹簧拉回 → 视觉「撞击反弹」。
    if (_positioningActive) return;
    final target = _controller.position.maxScrollExtent;
    if (target <= 0) return;
    if (animated) {
      _isAnimatingToBottom = true;
      unawaited(
        _controller
            .animateTo(
              target,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
            )
            .whenComplete(() {
              if (mounted) {
                _isAnimatingToBottom = false;
                // 动画期间 extent 可能继续变化（新气泡入场/懒加载估算修正），
                // 落点未必是真实底部：用轻量收敛链复核，避免停在半途（#23）。
                _settleJumpToBottom(attempts: 0);
              }
            }),
      );
    } else {
      if (_isAnimatingToBottom) return;
      // 非动画单跳改为轻量收敛链：post-frame 读真实 extent + 单帧复核，
      // 根治「jumpTo 落点与真实底部不一致 → 越界 → Spring 拉回」回弹（#23）。
      _settleJumpToBottom(attempts: 0);
    }
  }

  /// 非动画跳底的轻量收敛链（#23 发送/流式跟随路径）。
  ///
  /// 旧实现 `jumpTo(target)` 在调用时**同步**读取 `maxScrollExtent`：若此刻
  /// 新气泡尚未布局完（extent 仍处增长/估算态，如 sending 指示器、流式气泡、
  /// live 时间线条目刚入场），目标与真实底部不一致；`jumpTo` 又**不做任何
  /// 边界修正**（`forcePixels` 直写），落点越界后其收尾的 `goBallistic(0)`
  /// 被 ClampingScrollPhysics 判为 `outOfRange`，随即启动 ScrollSpringSimulation
  /// 弹簧把像素拉回边界 → 肉眼「下拉拉超又弹回」。
  ///
  /// 本方法沿用 `_settleToBottom` 的「extent 收敛」思想但刻意轻量：
  /// ① 每次跳转都在 **post-frame 读取 extent**——拿到的是「刚布局完」的
  /// 真实底部，跳转目标恒等于当帧 `maxScrollExtent`，落点必在界内
  /// （pixels == max ⇒ outOfRange 为 false，引擎不会起弹簧）；
  /// ② 复核链最多 `_maxJumpResettle` 轮就收手（发送路径不跑 24 轮收敛），
  /// 收敛条件 = 跳后一帧 extent 不再增长（pixels 已贴住 maxScrollExtent）。
  void _settleJumpToBottom({required int attempts}) {
    if (_jumpSettling || !mounted || !_controller.hasClients) return;
    _jumpSettling = true;
    final generation = _layoutGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !_controller.hasClients ||
          generation != _layoutGeneration ||
          _isAnimatingToBottom) {
        _jumpSettling = false;
        return;
      }
      final position = _controller.position;
      final max = position.maxScrollExtent;
      // 已贴底（且未越界）：上一轮跳转已收敛，无需动作。
      if ((max - position.pixels).abs() <= 0.5) {
        _jumpSettling = false;
        return;
      }
      // 落点恒为当帧 maxScrollExtent（界内）：goBallistic(0) 不会起弹簧。
      // 若前帧 extent 收缩导致像素越界，此跳亦完成精准拉回（直跳非弹簧）。
      // 注意：链内不做 _userHasScrolled 拦截——「粘底阈值内 token 重新贴底」
      // 是既有语义（调用点已按 _nearBottom 门控），链内再加拦截会破坏它在
      // 用户上滑 120px 内的自动粘底行为（#14 回归测试覆盖）。
      _controller.jumpTo(max);
      if (attempts >= _maxJumpResettle) {
        _jumpSettling = false;
        return;
      }
      // 下一帧复核：extent 若仍在增长（新气泡未布局完）则继续追底。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            !_controller.hasClients ||
            generation != _layoutGeneration ||
            _isAnimatingToBottom) {
          _jumpSettling = false;
          return;
        }
        _jumpSettling = false;
        _settleJumpToBottom(attempts: attempts + 1);
      });
    });
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

    final phaseChanged = _lastPhase != phase;
    _lastPhase = phase;

    // Android 输入法软键盘监听（仅 defaultTargetPlatform == android 生效，todo.md #13）
    final isAndroid = defaultTargetPlatform == TargetPlatform.android;
    final currentBottomInset = MediaQuery.viewInsetsOf(context).bottom;
    if (isAndroid) {
      if (_lastBottomInset != null && _lastBottomInset != currentBottomInset) {
        if (_nearBottom &&
            _initialPositioned &&
            !_positioningActive &&
            !_restoringOlderPosition) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || !_controller.hasClients) return;
            if (_nearBottom &&
                !_positioningActive &&
                !_restoringOlderPosition) {
              _scrollToBottom(animated: false);
            }
          });
        }
      }
      _lastBottomInset = currentBottomInset;
    }

    // 消息刷新与内容变化：若 _nearBottom 则无动画 jump 回底（#13）；若离底阅读则保持锚点不拉底（#14）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients) return;
      final isUserLast =
          transcript.isNotEmpty && transcript.last.message.role == 'user';
      if (_justSent ||
          (phaseChanged &&
              (phase == ChatPhase.sending ||
                  isUserLast ||
                  (phase == ChatPhase.streaming && _nearBottom)))) {
        // 用户刚发送或阶段切换（sending/streaming 开始）保持 200ms animateTo 平滑动画（#13/#14）
        _justSent = false;
        _scrollToBottom(animated: true);
      } else if (_nearBottom &&
          _initialPositioned &&
          !_positioningActive &&
          !_restoringOlderPosition) {
        // 消息刷新与增量更新无动画 jump 回底（#13）
        _scrollToBottom(animated: false);
      } else if (!_nearBottom &&
          _userHasScrolled &&
          !_justSent &&
          _initialPositioned) {
        _maybeRestoreReadingAnchor();
      }
    });

    // live 时间线模式：streaming 且 provider 非 null（null = 重连归档等
    // 无法还原段落边界的场景，回退旧分组式流式气泡）。
    final timelineActive = streaming != null && liveTimeline != null;
    final liveReasoningText = ref
        .read(chatControllerProvider(sessionId))
        .liveReasoningText;
    final hideThinking = ref.watch(hideReasoningProvider);
    // legacy（非时间线）模式：live 思考并入工具组（think 子卡行前置）。
    final streamingTools = streaming == null || liveTimeline != null
        ? const <ToolCallGroup>[]
        : [
            for (final g in toolGroups)
              if (g.anchorMessageID == streaming.messageId)
                (hideThinking || liveReasoningText.trim().isEmpty)
                    ? g
                    : ToolCallGroup(
                        id: g.id,
                        anchorMessageID: g.anchorMessageID,
                        toolCalls: [
                          ToolCall.thinking(liveReasoningText.trim()),
                          ...g.toolCalls,
                        ],
                      ),
          ];

    final showQueuedBanner = queuedMessages.isNotEmpty;
    // 落地兜底：仅在 coalesce==true 且 transcript 为空且无可挂载 anchor 时渲染聚合视图
    final needFallback =
        coalesce &&
        transcript.isEmpty &&
        streaming == null &&
        phase != ChatPhase.sending &&
        toolGroups.isNotEmpty;

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

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is UserScrollNotification) {
          if (notification.direction != ScrollDirection.idle) {
            if (_initialPositioned &&
                !_initialPositioning &&
                !_restoringOlderPosition) {
              _userHasScrolled = true;
            }
          }
        } else if (notification is ScrollUpdateNotification) {
          if (notification.dragDetails != null) {
            if (_initialPositioned &&
                !_initialPositioning &&
                !_restoringOlderPosition) {
              _userHasScrolled = true;
            }
          }
        }
        return false;
      },
      child: ListView.builder(
        controller: _controller,
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: itemCount,
        itemBuilder: (context, index) {
          // 统一尾部顺序：transcript | queued | steer | streaming | sending | fallback
          if (index < transcript.length) {
            final entry = transcript[index];
            final groups =
                entryToolGroups[entry.renderId] ?? const <ToolCallGroup>[];
            final noticeId = entry.message.id;
            final expanded = _expandedNoticeIds.contains(noticeId);
            final isHighlightTarget =
                _highlightTargetRenderId != null &&
                entry.renderId == _highlightTargetRenderId;
            final entryKey = _itemKeys.putIfAbsent(
              entry.renderId,
              () => GlobalKey(),
            );
            if (entry.message.messageId != null &&
                entry.message.messageId!.isNotEmpty) {
              _itemKeys.putIfAbsent(entry.message.messageId!, () => entryKey);
            }
            for (final g in groups) {
              _itemKeys.putIfAbsent(g.id, () => entryKey);
            }

            return KeyedSubtree(
              key: isHighlightTarget ? _highlightKey : entryKey,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onLongPress: () => _showMessageActions(entry.message),
                onSecondaryTapDown: (_) => _showMessageActions(entry.message),
                child: SearchMessageHighlight(
                  highlight: isHighlightTarget,
                  child: ChatMessageBubble(
                    key: ValueKey(entry.renderId),
                    message: entry.message,
                    toolGroups: groups,
                    hideThinking: hideThinking,
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
                hideThinking: hideThinking,
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
                final liveEntry = liveTimeline[tail];
                final liveKey = _itemKeys.putIfAbsent(
                  liveEntry.renderKey,
                  () => GlobalKey(),
                );
                if (liveEntry.toolGroup != null) {
                  _itemKeys.putIfAbsent(liveEntry.toolGroup!.id, () => liveKey);
                }
                return KeyedSubtree(
                  key: liveKey,
                  child: _LiveTimelineItem(
                    entry: liveEntry,
                    streamingMessage: streaming,
                    hideThinking: hideThinking,
                  ),
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
                hideThinking: hideThinking,
              );
            }
            tail--;
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }
}

/// 流式气泡（独立渲染层：思考中指示器 + 流式文本 + 实时工具卡片）。
class _StreamingBubble extends StatelessWidget {
  const _StreamingBubble({
    required this.message,
    required this.toolGroups,
    required this.hideThinking,
  });

  final ChatMessage message;
  final List<ToolCallGroup> toolGroups;
  final bool hideThinking;

  @override
  Widget build(BuildContext context) {
    final hasContent = (message.content ?? '').isNotEmpty;
    final isEmpty = !hasContent && toolGroups.isEmpty;
    if (!isEmpty) {
      return ChatMessageBubble(
        message: message,
        toolGroups: toolGroups,
        hideThinking: hideThinking,
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
    required this.hideThinking,
  });

  final LiveTimelineEntry entry;
  final ChatMessage streamingMessage;
  final bool hideThinking;

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: ValueKey(entry.renderKey),
      child: switch (entry.kind) {
        // 思考已并入工具卡子卡（think 行），不再产出独立思考条目；此分支
        // 为防御（旧数据/异常路径），不渲染任何内容。
        LiveSegmentKind.thinking => const SizedBox.shrink(),
        LiveSegmentKind.text => _LiveTextBlock(
          slice: entry.textSlice,
          streamingMessage: streamingMessage,
        ),
        LiveSegmentKind.tools => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          child: ToolCallGroupCard(
            group: entry.toolGroup!,
            hideThinking: hideThinking,
          ),
        ),
      },
    );
  }
}

/// 流式文本段（Markdown 渲染，增量解析 try/catch 兜底，镜像历史 assistant 气泡的 content 处理管线）。
class _LiveTextBlock extends StatelessWidget {
  const _LiveTextBlock({required this.slice, required this.streamingMessage});

  final String slice;
  final ChatMessage streamingMessage;

  @override
  Widget build(BuildContext context) {
    SelectedContextParse selected;
    try {
      selected = SelectedContextParser.parse(slice);
    } catch (_) {
      selected = SelectedContextParse(blocks: const [], cleanText: slice);
    }
    final blocks = selected.blocks;
    final cleanText = selected.cleanText;
    final hasMediaMarker =
        cleanText.contains('MEDIA:') || cleanText.contains('file://');
    String parsedContent;
    try {
      parsedContent = hasMediaMarker
          ? ChatMediaParser.parseMediaMarkers(cleanText)
          : cleanText;
    } catch (_) {
      parsedContent = cleanText;
    }
    final sections = <Widget>[];
    if (blocks.isNotEmpty) {
      sections.add(SelectedContextCardGroup(blocks: blocks));
    }
    if (parsedContent.isNotEmpty) {
      sections.add(
        _SafeMarkdownBody(
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
    required this.hideThinking,
  });

  final List<ToolCallGroup> toolGroups;
  final bool hideThinking;

  @override
  Widget build(BuildContext context) {
    // 复用与 assistant 气泡相同的 horizontal 12 外边距；区块间统一固定间距
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final group in toolGroups) ...[
            ToolCallGroupCard(group: group, hideThinking: hideThinking),
            if (group != toolGroups.last) const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}
