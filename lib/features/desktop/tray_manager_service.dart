import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../../app/router.dart';
import '../../core/connections/connection_providers.dart';
import '../../core/models/session.dart';
import '../session_list/session_list_providers.dart';
import 'desktop_settings.dart';

/// 从 asset 加载托盘图标并写入临时文件，返回临时文件的绝对路径。
///
/// 避免 Windows 下直接引用相对路径导致图标无法加载的问题。
/// Windows 下 [tray_manager] 的原生侧通过 `LoadImage(IMAGE_ICON, LR_LOADFROMFILE)`
/// 仅可靠加载 `.ico`，传入 `.png` 会静默失败导致托盘空白；因此 Windows 分支
/// 应传入 `assets/branding/tray_icon.ico` 并以 `.ico` 后缀落盘。
/// 当 [fileName] 以 `.ico` 结尾时直接写入资产字节即可（资产本身即为合法 ICO）。
Future<String> prepareTrayIconFile({
  AssetBundle? assetBundle,
  Directory? tempDir,
  String assetPath = 'assets/branding/tray_icon_32.png',
  String fileName = 'hermes_tray_icon_32.png',
}) async {
  final bundle = assetBundle ?? rootBundle;
  final dir = tempDir ?? Directory.systemTemp;
  final file = File('${dir.path}${Platform.pathSeparator}$fileName');

  final byteData = await bundle.load(assetPath);
  final bytes = byteData.buffer.asUint8List(
    byteData.offsetInBytes,
    byteData.lengthInBytes,
  );

  await file.writeAsBytes(bytes, flush: true);
  return file.absolute.path;
}

/// 会话状态映射为托盘显示文案（运行中 / 排队中 / 已归档 / 只读 / null）。
String? formatSessionStatus(SessionSummary session) {
  if (session.isStreaming == true ||
      (session.activeStreamId != null && session.activeStreamId!.isNotEmpty)) {
    return '运行中';
  }
  if (session.hasPendingUserMessage == true) {
    return '排队中';
  }
  if (session.archived == true) {
    return '已归档';
  }
  if (session.isSessionReadOnly) {
    return '只读';
  }
  return null;
}

/// 格式化托盘最近会话菜单项文案（含标题截断与状态标签）。
String formatRecentSessionLabel(
  SessionSummary session, {
  int maxTitleLength = 24,
}) {
  final rawTitle = session.title?.trim();
  String title = (rawTitle != null && rawTitle.isNotEmpty)
      ? rawTitle
      : 'Untitled';

  if (title.characters.length > maxTitleLength) {
    title = '${title.characters.take(maxTitleLength).toString()}...';
  }

  final status = formatSessionStatus(session);
  if (status != null && status.isNotEmpty) {
    return '$title ($status)';
  }
  return title;
}

/// 系统托盘服务。
///
/// 职责：
/// 1. 创建并维护系统托盘图标（Windows 下写出真实临时文件）；
/// 2. 设置右键上下文菜单（显示主窗口 / 新建会话 / 最近会话列表 / 退出应用）；
/// 3. 处理托盘点击恢复窗口与最近会话跳转；
/// 4. 非桌面平台安全降级 no-op。
class TrayManagerService with TrayListener {
  /// 菜单项 Key 常量
  static const String menuItemShowWindow = 'show_window';
  static const String menuItemNewSession = 'new_session';
  static const String menuItemNoRecentSessions = 'no_recent_sessions';
  static const String menuItemQuitApp = 'quit_app';
  static const String recentSessionPrefix = 'recent_';

  /// 唤起主窗口回调（可自定义用于测试）。
  final FutureOr<void> Function()? onShowWindow;

  /// 新建会话回调（可自定义用于测试）。
  final FutureOr<void> Function()? onNewSession;

  /// 打开指定会话回调（可自定义用于测试）。
  final FutureOr<void> Function(String sessionId)? onOpenSession;

  /// 退出应用回调（可自定义用于测试）。
  final FutureOr<void> Function()? onQuit;

  /// 获取最近会话列表函数（同步读取，用于刷新菜单）。
  final List<SessionSummary>? Function()? getRecentSessions;

  /// 异步拉取最近会话列表函数。
  final Future<List<SessionSummary>?> Function()? fetchRecentSessions;

  /// 是否为桌面平台。
  final bool isDesktop;

  bool _initialized = false;
  List<SessionSummary> _cachedSessions = const [];

  /// 构造系统托盘服务。
  TrayManagerService({
    this.onShowWindow,
    this.onNewSession,
    this.onOpenSession,
    this.onQuit,
    this.getRecentSessions,
    this.fetchRecentSessions,
    bool? isDesktop,
  }) : isDesktop = isDesktop ?? isDesktopPlatform();

  /// 服务是否已初始化。
  bool get isInitialized => _initialized;

  /// 初始化托盘图标与上下文菜单。
  Future<void> initialize() async {
    if (!isDesktop || _initialized) return;

    try {
      trayManager.addListener(this);
      await _setupTrayIcon();
      await updateContextMenu();
      _initialized = true;
    } catch (e, st) {
      developer.log(
        'Failed to initialize TrayManagerService',
        name: 'TrayManagerService',
        error: e,
        stackTrace: st,
      );
    }
  }

  /// 设置托盘图标与悬浮提示。
  Future<void> _setupTrayIcon() async {
    try {
      String iconPath;
      if (defaultTargetPlatform == TargetPlatform.macOS) {
        iconPath =
            'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_32.png';
      } else if (defaultTargetPlatform == TargetPlatform.windows) {
        iconPath = await prepareTrayIconFile(
          assetPath: 'assets/branding/tray_icon.ico',
          fileName: 'hermes_tray_icon.ico',
        );
      } else {
        iconPath = await prepareTrayIconFile();
      }
      await trayManager.setIcon(iconPath);
      await trayManager.setToolTip('Hermes');
    } catch (e, st) {
      developer.log(
        'Failed to set tray icon / tooltip',
        name: 'TrayManagerService',
        error: e,
        stackTrace: st,
      );
    }
  }

  /// 构建托盘菜单项纯函数。
  static List<MenuItem> buildMenuItems({
    List<SessionSummary> sessions = const [],
    int maxRecentSessions = 6,
    void Function(String sessionId)? onOpenSession,
    void Function()? onShowWindow,
    void Function()? onNewSession,
    void Function()? onQuit,
  }) {
    final items = <MenuItem>[
      MenuItem(
        key: menuItemShowWindow,
        label: '显示主窗口',
        onClick: onShowWindow != null ? (_) => onShowWindow() : null,
      ),
      MenuItem(
        key: menuItemNewSession,
        label: '新建会话',
        onClick: onNewSession != null ? (_) => onNewSession() : null,
      ),
      MenuItem.separator(),
    ];

    final visibleSessions = sessions
        .where(
          (s) =>
              s.sessionId != null &&
              s.sessionId!.isNotEmpty &&
              s.shouldAppearInSessionList,
        )
        .take(maxRecentSessions)
        .toList();

    if (visibleSessions.isEmpty) {
      items.add(
        MenuItem(
          key: menuItemNoRecentSessions,
          label: '暂无最近会话',
          disabled: true,
        ),
      );
    } else {
      for (final session in visibleSessions) {
        final sid = session.sessionId!;
        items.add(
          MenuItem(
            key: '$recentSessionPrefix$sid',
            label: formatRecentSessionLabel(session),
            onClick: onOpenSession != null ? (_) => onOpenSession(sid) : null,
          ),
        );
      }
    }

    items.add(MenuItem.separator());
    items.add(
      MenuItem(
        key: menuItemQuitApp,
        label: '退出应用',
        onClick: onQuit != null ? (_) => onQuit() : null,
      ),
    );

    return items;
  }

  /// 构建并设置托盘上下文菜单。
  Future<void> updateContextMenu({List<SessionSummary>? sessions}) async {
    if (!isDesktop) return;

    try {
      List<SessionSummary> sessionList = sessions ?? _cachedSessions;
      if (sessions == null && getRecentSessions != null) {
        sessionList = getRecentSessions!() ?? sessionList;
      } else if (sessions == null && fetchRecentSessions != null) {
        try {
          final fetched = await fetchRecentSessions!();
          if (fetched != null) {
            sessionList = fetched;
          }
        } catch (e) {
          developer.log(
            'Failed to fetch recent sessions for tray menu',
            name: 'TrayManagerService',
            error: e,
          );
        }
      }
      _cachedSessions = sessionList;

      final items = buildMenuItems(
        sessions: sessionList,
        onOpenSession: (sid) => unawaited(handleOpenSession(sid)),
        onShowWindow: () => unawaited(handleShowWindow()),
        onNewSession: () => unawaited(handleNewSession()),
        onQuit: () => unawaited(handleQuit()),
      );

      final menu = Menu(items: items);
      await trayManager.setContextMenu(menu);
    } catch (e, st) {
      developer.log(
        'Failed to set tray context menu',
        name: 'TrayManagerService',
        error: e,
        stackTrace: st,
      );
    }
  }

  /// 处理「显示主窗口」操作。
  Future<void> handleShowWindow() async {
    if (onShowWindow != null) {
      await onShowWindow!();
      return;
    }
    try {
      await windowManager.show();
      await windowManager.focus();
    } catch (e, st) {
      developer.log(
        'Failed to show window',
        name: 'TrayManagerService',
        error: e,
        stackTrace: st,
      );
    }
  }

  /// 处理「新建会话」操作。
  Future<void> handleNewSession() async {
    if (onNewSession != null) {
      await onNewSession!();
      return;
    }
    try {
      await windowManager.show();
      await windowManager.focus();
    } catch (e, st) {
      developer.log(
        'Failed to handle new session',
        name: 'TrayManagerService',
        error: e,
        stackTrace: st,
      );
    }
  }

  /// 处理「打开指定会话」操作。
  Future<void> handleOpenSession(String sessionId) async {
    if (onOpenSession != null) {
      await onOpenSession!(sessionId);
      return;
    }
    try {
      await windowManager.show();
      await windowManager.focus();
    } catch (e, st) {
      developer.log(
        'Failed to open session: $sessionId',
        name: 'TrayManagerService',
        error: e,
        stackTrace: st,
      );
    }
  }

  /// 处理「退出应用」操作。
  Future<void> handleQuit() async {
    if (onQuit != null) {
      await onQuit!();
      return;
    }
    try {
      await windowManager.destroy();
    } catch (e, st) {
      developer.log(
        'Failed to destroy window on quit',
        name: 'TrayManagerService',
        error: e,
        stackTrace: st,
      );
    }
  }

  @override
  void onTrayIconMouseDown() {
    unawaited(handleShowWindow());
  }

  @override
  void onTrayIconRightMouseDown() {
    try {
      unawaited(trayManager.popUpContextMenu());
    } catch (e, st) {
      developer.log(
        'Failed to pop up tray context menu',
        name: 'TrayManagerService',
        error: e,
        stackTrace: st,
      );
    }
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    final key = menuItem.key;
    if (key == null) return;
    if (key == menuItemShowWindow) {
      unawaited(handleShowWindow());
    } else if (key == menuItemNewSession) {
      unawaited(handleNewSession());
    } else if (key == menuItemQuitApp) {
      unawaited(handleQuit());
    } else if (key.startsWith(recentSessionPrefix)) {
      final sessionId = key.substring(recentSessionPrefix.length);
      unawaited(handleOpenSession(sessionId));
    }
  }

  /// 销毁托盘服务。
  Future<void> dispose() async {
    if (!isDesktop) return;

    try {
      trayManager.removeListener(this);
      await trayManager.destroy();
    } catch (e, st) {
      developer.log(
        'Failed to dispose tray manager',
        name: 'TrayManagerService',
        error: e,
        stackTrace: st,
      );
    }
    _initialized = false;
  }
}

/// 系统托盘服务 Provider。
final trayManagerServiceProvider = Provider<TrayManagerService>((ref) {
  final service = TrayManagerService(
    onShowWindow: () async {
      try {
        await windowManager.show();
        await windowManager.focus();
      } catch (e) {
        developer.log(
          'Failed to show window',
          name: 'TrayManagerService',
          error: e,
        );
      }
    },
    onNewSession: () async {
      try {
        await windowManager.show();
        await windowManager.focus();
        ref.read(routerProvider).go('/chat');
      } catch (e) {
        developer.log(
          'Failed to show window and navigate to /chat',
          name: 'TrayManagerService',
          error: e,
        );
      }
    },
    onOpenSession: (sessionId) async {
      try {
        await windowManager.show();
        await windowManager.focus();
        ref.read(routerProvider).go('/chat/$sessionId');
      } catch (e) {
        developer.log(
          'Failed to show window and navigate to /chat/$sessionId',
          name: 'TrayManagerService',
          error: e,
        );
      }
    },
    getRecentSessions: () =>
        ref.read(sessionListControllerProvider).valueOrNull?.sessions,
    fetchRecentSessions: () async {
      try {
        final api = ref.read(sessionListApiFactoryProvider)(
          ref.read(apiClientProvider),
        );
        final response = await api.fetchSessions();
        return response.sessions;
      } catch (e) {
        developer.log(
          'Failed to fetch sessions for tray menu',
          name: 'TrayManagerService',
          error: e,
        );
        return null;
      }
    },
    onQuit: () async {
      try {
        await windowManager.destroy();
      } catch (e) {
        developer.log(
          'Failed to destroy window',
          name: 'TrayManagerService',
          error: e,
        );
      }
    },
  );
  ref.onDispose(() {
    unawaited(service.dispose());
  });
  return service;
});
