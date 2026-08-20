import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:window_manager/window_manager.dart';

import '../../app/router.dart';
import '../chat/chat_providers.dart';
import '../session_list/session_list_providers.dart';
import 'desktop_settings.dart';
import 'desktop_shortcuts.dart';
import 'tray_manager_service.dart';
import 'window_memory.dart';
import 'window_title_service.dart';

/// 桌面平台生命周期观察器（挂载在 App 壳根部）。
///
/// 职责：
/// 1. 桌面端启动初始化：托盘服务、窗口记忆与恢复、全局快捷键注册、窗口标题重置；
/// 2. 监听桌面设置变化并动态更新服务状态（开关快捷键、更新关闭拦截）；
/// 3. 监听路由变化与活跃会话标题变更，同步更新桌面端窗口标题；
/// 4. 监听会话列表变化，动态更新托盘上下文菜单的最近会话组；
/// 5. 非桌面平台安全 no-op。
class DesktopLifecycleObserver extends ConsumerStatefulWidget {
  const DesktopLifecycleObserver({super.key, required this.child});

  /// 被包裹的根 Widget。
  final Widget child;

  @override
  ConsumerState<DesktopLifecycleObserver> createState() =>
      _DesktopLifecycleObserverState();
}

class _DesktopLifecycleObserverState
    extends ConsumerState<DesktopLifecycleObserver> {
  GoRouter? _router;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_initDesktopServices());
    });
  }

  Future<void> _initDesktopServices() async {
    if (!isDesktopPlatform()) return;

    try {
      final titleService = ref.read(windowTitleServiceProvider);
      await titleService.resetTitle();

      final trayService = ref.read(trayManagerServiceProvider);
      await trayService.initialize();

      final memoryService = ref.read(windowMemoryServiceProvider);
      await memoryService.initialize();
      await memoryService.restoreWindowBounds();

      final settings = ref.read(desktopSettingsProvider);
      if (settings.globalShortcutsEnabled) {
        final shortcutsService = ref.read(desktopShortcutsServiceProvider);
        await shortcutsService.registerShortcuts();
      }

      final router = ref.read(routerProvider);
      _router = router;
      router.routerDelegate.addListener(_onRouteChanged);
      _onRouteChanged();
    } catch (e, st) {
      developer.log(
        'Failed to initialize desktop services',
        name: 'DesktopLifecycleObserver',
        error: e,
        stackTrace: st,
      );
    }
  }

  void _onRouteChanged() {
    if (!isDesktopPlatform() || !mounted) return;
    final router = _router;
    if (router == null) return;

    final uri = router.routerDelegate.currentConfiguration.uri;
    final segments = uri.pathSegments;
    String? sessionId;
    if (segments.length >= 2 &&
        (segments[0] == 'chat' ||
            segments[0] == 'workspace' ||
            segments[0] == 'git')) {
      final sid = segments[1].trim();
      if (sid.isNotEmpty) {
        sessionId = sid;
      }
    }

    if (ref.read(activeSessionIdProvider) != sessionId) {
      ref.read(activeSessionIdProvider.notifier).state = sessionId;
    }
  }

  void _syncSessionTitle(String sessionId) {
    // 1. 尝试从已有的 chatController 读取 displayTitle
    final chatState = ref.read(chatControllerProvider(sessionId));
    final displayTitle = chatState.displayTitle.trim();
    if (displayTitle.isNotEmpty &&
        displayTitle.toLowerCase() != 'untitled' &&
        displayTitle.toLowerCase() != 'untitled session') {
      unawaited(
        ref.read(windowTitleServiceProvider).updateSessionTitle(displayTitle),
      );
      return;
    }

    // 2. 尝试从 sessionListController 中查找标题
    final sessionList = ref
        .read(sessionListControllerProvider)
        .valueOrNull
        ?.sessions;
    final found = sessionList
        ?.where((s) => s.sessionId == sessionId)
        .firstOrNull;
    if (found?.title != null && found!.title!.trim().isNotEmpty) {
      unawaited(
        ref.read(windowTitleServiceProvider).updateSessionTitle(found.title),
      );
      return;
    }

    // 兜底默认标题
    unawaited(
      ref.read(windowTitleServiceProvider).updateSessionTitle(displayTitle),
    );
  }

  @override
  void dispose() {
    _router?.routerDelegate.removeListener(_onRouteChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<DesktopSettings>(desktopSettingsProvider, (previous, next) {
      if (!isDesktopPlatform()) return;

      if (previous?.globalShortcutsEnabled != next.globalShortcutsEnabled) {
        final shortcutsService = ref.read(desktopShortcutsServiceProvider);
        if (next.globalShortcutsEnabled) {
          unawaited(shortcutsService.registerShortcuts());
        } else {
          unawaited(shortcutsService.unregisterShortcuts());
        }
      }

      if (previous?.minimizeToTray != next.minimizeToTray) {
        try {
          unawaited(windowManager.setPreventClose(next.minimizeToTray));
        } catch (e) {
          developer.log(
            'Failed to update preventClose',
            name: 'DesktopLifecycleObserver',
            error: e,
          );
        }
      }
    });

    ref.listen<String?>(activeSessionIdProvider, (previous, next) {
      if (!isDesktopPlatform()) return;
      if (next == null || next.isEmpty) {
        unawaited(ref.read(windowTitleServiceProvider).resetTitle());
      } else {
        _syncSessionTitle(next);
      }
    });

    final activeSessionId = ref.watch(activeSessionIdProvider);
    if (activeSessionId != null && activeSessionId.isNotEmpty) {
      ref.listen<String>(
        chatControllerProvider(activeSessionId).select((s) => s.displayTitle),
        (previous, next) {
          if (!isDesktopPlatform()) return;
          unawaited(
            ref.read(windowTitleServiceProvider).updateSessionTitle(next),
          );
        },
      );
    }

    ref.listen(sessionListControllerProvider, (previous, next) {
      if (!isDesktopPlatform()) return;
      final sessions = next.valueOrNull?.sessions;
      if (sessions != null) {
        unawaited(
          ref
              .read(trayManagerServiceProvider)
              .updateContextMenu(sessions: sessions),
        );
      }
    });

    return widget.child;
  }
}
