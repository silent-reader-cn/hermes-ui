import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:window_manager/window_manager.dart';

import '../../app/router.dart';
import '../chat/chat_providers.dart';
import '../session_list/session_list_providers.dart';
import '../webui_sidecar/webui_sidecar_providers.dart';
import 'desktop_settings.dart';
import 'desktop_shortcuts.dart';
import 'tray_manager_service.dart';
import 'window_memory.dart';
import 'window_title_service.dart';

/// 桌面平台生命周期观察器（挂载在 App 壳根部）。
///
/// 职责：
/// 1. 桌面端启动初始化：托盘服务、窗口记忆与恢复、全局快捷键注册、窗口标题重置、内置 WebUI 服务拉起；
/// 2. 监听桌面设置变化并动态更新服务状态（开关快捷键、更新关闭拦截）；
/// 3. 监听路由变化与活跃会话标题变更，同步更新桌面端窗口标题；
/// 4. 监听会话列表变化，动态更新托盘上下文菜单的最近会话组；
/// 5. 监听 WebUI Sidecar 配置与状态，实现随状态动态拉起与托盘菜单节流刷新；
/// 6. 非桌面平台安全 no-op。
class DesktopLifecycleObserver extends ConsumerStatefulWidget {
  const DesktopLifecycleObserver({
    super.key,
    required this.child,
    this.isDesktop,
  });

  /// 被包裹的根 Widget。
  final Widget child;

  /// 是否为桌面平台（测试注入用，默认走 [isDesktopPlatform]）。
  final bool? isDesktop;

  @override
  ConsumerState<DesktopLifecycleObserver> createState() =>
      _DesktopLifecycleObserverState();
}

class _DesktopLifecycleObserverState
    extends ConsumerState<DesktopLifecycleObserver>
    with WidgetsBindingObserver {
  GoRouter? _router;

  /// 托盘服务引用（didChangeLocales 刷新菜单用，initDesktop 后非空）。
  TrayManagerService? _trayService;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_initDesktopServices());
    });
  }

  /// 自动模式下系统语言中途变更 → 刷新托盘菜单（服务层文案经 LocaleResolver
  /// 取语言，widget 树内文案由 CupertinoApp locale 重建自动刷新，无需额外处理）。
  @override
  void didChangeLocales(List<Locale>? locales) {
    if (widget.isDesktop ?? isDesktopPlatform()) {
      _trayService?.scheduleThrottledUpdateContextMenu();
    }
  }

  Future<void> _initDesktopServices() async {
    final isDesktop = widget.isDesktop ?? isDesktopPlatform();
    if (!isDesktop) return;

    try {
      final titleService = ref.read(windowTitleServiceProvider);
      await titleService.resetTitle();

      final trayService = ref.read(trayManagerServiceProvider);
      _trayService = trayService;
      await trayService.initialize();

      final memoryService = ref.read(windowMemoryServiceProvider);
      await memoryService.initialize();
      await memoryService.restoreWindowBounds();

      final settings = ref.read(desktopSettingsProvider);
      if (settings.globalShortcutsEnabled) {
        final shortcutsService = ref.read(desktopShortcutsServiceProvider);
        await shortcutsService.registerShortcuts();
      }

      // 内置 WebUI Sidecar 启动链：
      // 【正常启动与静默启动（--silent）均能走到 DesktopLifecycleObserver】：
      // 在 main.dart 中，无论是常规启动还是携带 --silent / -s 静默启动（由 isSilentStart 判定），
      // windowManager 处理完显示/隐藏逻辑后，均会无条件调用 runApp(const ProviderScope(child: HermesApp()))；
      // 而 HermesApp 根部顶层始终包裹并挂载 DesktopLifecycleObserver（作为最外层壳 Widget）。
      // 因此无论正常还是静默启动，DesktopLifecycleObserver 均会实例化并进入 initState，
      // 继而触发 postFrameCallback 执行本 _initDesktopServices() 方法。
      //
      // 此处先显式调用 load() 完成异步持久化配置加载（解决 S1 初始快照 enabled 默认为 false 的时序差），
      // 若 enabled == true 则调起 WebuiSidecarController.start()。
      await ref.read(webuiSidecarConfigProvider.notifier).load();
      final sidecarConfig = ref.read(webuiSidecarConfigProvider);
      final currentStatus = ref.read(webuiSidecarControllerProvider).status;
      if (sidecarConfig.enabled &&
          currentStatus != SidecarStatus.running &&
          currentStatus != SidecarStatus.starting) {
        unawaited(ref.read(webuiSidecarControllerProvider.notifier).start());
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
    final isDesktop = widget.isDesktop ?? isDesktopPlatform();
    if (!isDesktop || !mounted) return;
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
    WidgetsBinding.instance.removeObserver(this);
    _router?.routerDelegate.removeListener(_onRouteChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = widget.isDesktop ?? isDesktopPlatform();

    ref.listen<DesktopSettings>(desktopSettingsProvider, (previous, next) {
      if (!isDesktop) return;

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
      if (!isDesktop) return;
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
          if (!isDesktop) return;
          unawaited(
            ref.read(windowTitleServiceProvider).updateSessionTitle(next),
          );
        },
      );
    }

    ref.listen(sessionListControllerProvider, (previous, next) {
      if (!isDesktop) return;
      final sessions = next.valueOrNull?.sessions;
      if (sessions != null) {
        unawaited(
          ref
              .read(trayManagerServiceProvider)
              .updateContextMenu(sessions: sessions),
        );
      }
    });

    // 监听 Sidecar 配置变更（捕获异步首值跳变 false->true 及设置页开关联动）
    ref.listen<SidecarConfig>(
      webuiSidecarConfigProvider,
      (previous, next) {
        if (!isDesktop) return;
        final currentStatus = ref.read(webuiSidecarControllerProvider).status;
        if (previous?.enabled != true &&
            next.enabled &&
            currentStatus != SidecarStatus.running &&
            currentStatus != SidecarStatus.starting) {
          unawaited(ref.read(webuiSidecarControllerProvider.notifier).start());
        }
        if (previous?.enabled != next.enabled ||
            previous?.host != next.host ||
            previous?.port != next.port) {
          ref.read(trayManagerServiceProvider).scheduleThrottledUpdateContextMenu();
        }
      },
    );

    // 监听 Sidecar 运行状态变更（状态机转换触发托盘菜单刷新，带 500ms 节流）
    ref.listen<SidecarState>(webuiSidecarControllerProvider, (previous, next) {
      if (!isDesktop) return;
      if (previous?.status != next.status) {
        ref.read(trayManagerServiceProvider).scheduleThrottledUpdateContextMenu();
      }
    });

    return widget.child;
  }
}
