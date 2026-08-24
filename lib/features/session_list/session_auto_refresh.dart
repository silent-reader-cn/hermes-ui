import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../desktop/desktop_settings.dart';
import '../notifications/notification_providers.dart';
import 'session_list_providers.dart';

/// 窗口焦点状态（桌面端 WindowListener 驱动，非桌面恒 true）。
final windowFocusedProvider = StateProvider<bool>((ref) => true);

/// 测试环境标记：为避免 30s 周期 Timer 在非单测场景中残留导致
/// `verifyInvariants(!timersPending)` 失败，Observer 的周期轮询仅在
/// [enableSessionAutoRefresh] 为 true 时生效（测试可显式置 false）。
bool enableSessionAutoRefresh = true;

/// 监听窗口焦点并同步 [windowFocusedProvider]。
class WindowFocusObserver extends ConsumerStatefulWidget {
  const WindowFocusObserver({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<WindowFocusObserver> createState() =>
      _WindowFocusObserverState();
}

class _WindowFocusObserverState extends ConsumerState<WindowFocusObserver>
    with WindowListener {
  @override
  void initState() {
    super.initState();
    if (isDesktopPlatform()) {
      windowManager.addListener(this);
      ref.read(windowFocusedProvider.notifier).state =
          true; // 启动时保守置 true，后续由事件驱动。
    }
  }

  @override
  void dispose() {
    if (isDesktopPlatform()) {
      windowManager.removeListener(this);
    }
    super.dispose();
  }

  @override
  void onWindowFocus() {
    if (!mounted) return;
    ref.read(windowFocusedProvider.notifier).state = true;
  }

  @override
  void onWindowBlur() {
    if (!mounted) return;
    ref.read(windowFocusedProvider.notifier).state = false;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// 会话列表自动刷新 Observer：挂载到 SessionListPage，驱动 30s 轮询 +
/// 获焦/前台 1s debounce + 失焦即停 + 10s 去重/并发互斥（在 Controller 层）。
///
/// 双条件约束：仅当 `resumed && windowFocused && mounted` 时运行定时器；任一
/// 为 false 立即 cancel。
class SessionAutoRefreshObserver extends ConsumerStatefulWidget {
  const SessionAutoRefreshObserver({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  ConsumerState<SessionAutoRefreshObserver> createState() =>
      _SessionAutoRefreshObserverState();
}

class _SessionAutoRefreshObserverState
    extends ConsumerState<SessionAutoRefreshObserver> {
  Timer? _focusDebounce;
  Timer? _periodic;
  bool _didInit = false;

  bool get _shouldPoll {
    if (!mounted) return false;
    final lifecycle = ref.read(appLifecycleStateProvider);
    final focused = ref.read(windowFocusedProvider);
    return lifecycle == AppLifecycleState.resumed && focused;
  }

  Duration get _pollPeriod {
    final failures = ref
            .read(sessionListControllerProvider)
            .valueOrNull
            ?.consecutiveFailures ??
        0;
    return SessionListController.nextAutoRefreshDelay(failures);
  }

  void _startPeriodic() {
    if (!enableSessionAutoRefresh) return;
    _periodic?.cancel();
    final period = _pollPeriod;
    _periodic = Timer.periodic(period, (_) {
      if (!mounted || !_shouldPoll) {
        _periodic?.cancel();
        _periodic = null;
        return;
      }
      unawaited(
        ref.read(sessionListControllerProvider.notifier).refreshIfStale(),
      );
    });
  }

  void _stopPeriodic() {
    _periodic?.cancel();
    _periodic = null;
  }

  void _maybeSchedulePoll() {
    if (!mounted || !enableSessionAutoRefresh) return;
    if (_shouldPoll) {
      _startPeriodic();
    } else {
      _stopPeriodic();
    }
  }

  void _onFocusGained() {
    if (!mounted) return;
    _focusDebounce?.cancel();
    _focusDebounce = Timer(const Duration(seconds: 1), () {
      if (!mounted) return;
      _maybeSchedulePoll();
      unawaited(
        ref.read(sessionListControllerProvider.notifier).refreshIfStale(),
      );
    });
  }

  void _onFocusLost() {
    _focusDebounce?.cancel();
    _stopPeriodic();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _didInit = true;
      _maybeSchedulePoll();
    });
  }

  @override
  void dispose() {
    _focusDebounce?.cancel();
    _stopPeriodic();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AppLifecycleState>(appLifecycleStateProvider, (prev, next) {
      if (!mounted || !_didInit) return;
      if (next == AppLifecycleState.resumed) {
        _onFocusGained();
      } else {
        _onFocusLost();
      }
    });
    ref.listen<bool>(windowFocusedProvider, (prev, next) {
      if (!mounted || !_didInit) return;
      if (next) {
        _onFocusGained();
      } else {
        _onFocusLost();
      }
    });
    // 监听失败次数变化以重建退避周期
    ref.listen(sessionListControllerProvider, (prev, next) {
      if (!mounted || !_didInit) return;
      final pf = prev?.valueOrNull?.consecutiveFailures ?? 0;
      final nf = next.valueOrNull?.consecutiveFailures ?? 0;
      if (pf != nf && _shouldPoll && _periodic != null) {
        _startPeriodic();
      }
    });
    return widget.child;
  }
}
