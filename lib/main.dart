import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'app/app.dart';
import 'core/api/cookie_store.dart';
import 'core/cache/app_database.dart';
import 'core/cache/cache_providers.dart';
import 'core/connections/connection_store.dart';
import 'features/chat/chat_providers.dart';
import 'features/desktop/desktop_settings.dart';
import 'features/desktop/startup_registrar.dart';
import 'features/diagnostics/diagnostics_models.dart';
import 'features/diagnostics/diagnostics_service.dart';
import 'features/notifications/notification_providers.dart';

/// 全局渲染/网络错误可恢复卡片（替代默认大灰屏/红屏，todo.md #8）。
class RecoverableErrorCard extends StatefulWidget {
  const RecoverableErrorCard({
    super.key,
    this.details,
    this.onRetry,
    this.message,
  });

  final FlutterErrorDetails? details;
  final VoidCallback? onRetry;
  final String? message;

  @override
  State<RecoverableErrorCard> createState() => _RecoverableErrorCardState();
}

class _RecoverableErrorCardState extends State<RecoverableErrorCard> {
  bool _retried = false;

  @override
  Widget build(BuildContext context) {
    final displayText = widget.message ?? '已断开 / 网络错误，重试';
    Widget card = Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C1E).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: CupertinoColors.systemRed.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            CupertinoIcons.exclamationmark_triangle_fill,
            color: CupertinoColors.systemRed,
            size: 20,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              displayText,
              style: const TextStyle(
                fontSize: 14,
                color: CupertinoColors.label,
                decoration: TextDecoration.none,
              ),
            ),
          ),
          const SizedBox(width: 8),
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            color: CupertinoColors.activeBlue,
            borderRadius: BorderRadius.circular(8),
            onPressed: () {
              setState(() => _retried = true);
              widget.onRetry?.call();
            },
            child: Text(
              _retried ? '已重试' : '重试',
              style: const TextStyle(
                fontSize: 12,
                color: CupertinoColors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );

    if (Directionality.maybeOf(context) == null) {
      card = Directionality(
        textDirection: TextDirection.ltr,
        child: card,
      );
    }
    return Center(child: card);
  }
}

/// 进程级唯一持久库单例
///
/// 用 `overrideWithValue` 注入 [appDatabaseProvider]，避免
/// `overrideWith((ref) => AppDatabase.production())` 每次 rebuild 都 `new`
/// 一个 `driftDatabase(name: 'hermes_cache')` 导致同名 QueryExecutor 争用
/// （见渲染层崩溃族：GeneratedDatabase 被实例化两次）。
final AppDatabase _productionDatabase = AppDatabase.production();

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  // 注册全局错误处理与可恢复卡片 builder（todo.md #8 渲染层兜底）
  FlutterError.onError = (FlutterErrorDetails details) {
    developer.log(
      'FlutterError caught: ${details.exceptionAsString()}',
      name: 'hermes.error',
      error: details.exception,
      stackTrace: details.stack,
    );
    DiagnosticsService.instance.log(
      level: DiagnosticsLogLevel.error,
      tag: 'flutter_error',
      message: details.exceptionAsString(),
      details: {
        'library': details.library,
        'context': details.context?.toString(),
        if (details.stack != null) 'stackTrace': details.stack.toString(),
      },
      errorKind: details.exception.runtimeType.toString(),
    );
    FlutterError.presentError(details);
  };
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    developer.log(
      'PlatformDispatcher error caught: $error',
      name: 'hermes.error',
      error: error,
      stackTrace: stack,
    );
    DiagnosticsService.instance.log(
      level: DiagnosticsLogLevel.error,
      tag: 'platform_error',
      message: error.toString(),
      details: {
        'stackTrace': stack.toString(),
      },
      errorKind: error.runtimeType.toString(),
    );
    return true;
  };
  ErrorWidget.builder = (FlutterErrorDetails details) {
    developer.log(
      'ErrorWidget.builder caught: ${details.exceptionAsString()}',
      name: 'hermes.error',
      error: details.exception,
      stackTrace: details.stack,
    );
    DiagnosticsService.instance.log(
      level: DiagnosticsLogLevel.error,
      tag: 'error_widget',
      message: details.exceptionAsString(),
      details: {
        'library': details.library,
        'context': details.context?.toString(),
        if (details.stack != null) 'stackTrace': details.stack.toString(),
      },
      errorKind: details.exception.runtimeType.toString(),
    );
    return RecoverableErrorCard(details: details);
  };

  unawaited(DiagnosticsService.instance.init());

  final silentStart = isSilentStart(
    args: args,
    executableArguments: Platform.executableArguments,
  );
  if (isDesktopPlatform()) {
    try {
      await windowManager.ensureInitialized();
      await windowManager.setTitle('Hermes');
      // 兜底最小窗口：避免拖到 0 宽/过窄时 Windows EGL 上下文丢失
      // （gpu_surface_gl_impeller.cc Context Lost 循环刷屏）。
      await windowManager.setMinimumSize(const Size(720, 480));
      if (silentStart) {
        // 静默启动：不显示主窗口，仅驻留系统托盘；
        // 托盘「显示主窗口」可随时唤出。无参启动路径行为不变。
        unawaited(
          windowManager.waitUntilReadyToShow(null, () async {
            try {
              await windowManager.hide();
            } catch (e, st) {
              developer.log(
                'Failed to hide window on silent start',
                name: 'main',
                error: e,
                stackTrace: st,
              );
            }
          }),
        );
      }
    } catch (e, st) {
      developer.log(
        'windowManager.ensureInitialized failed',
        name: 'main',
        error: e,
        stackTrace: st,
      );
    }
  }
  // 启动时恢复持久化的登录 cookie，避免 App 重启后登录态丢失（401）。
  // 未登录/无 cookie 时静默跳过；失败静默（会话列表会走自动重登兜底）。
  CookieStore.shared = CookieStore(
    storage: const FlutterSecureStorageAdapter(),
  );
  await CookieStore.shared.restore();
  runApp(
    ProviderScope(
      overrides: [
        // 回合完成 → 后台通知 hook（chat_controller 的 done/stream_end
        // 收尾处调用；前台不发、后台发，见 notifications feature）。
        chatTurnCompletedCallbackProvider.overrideWith(
          (ref) => ref.watch(turnNotificationHookProvider),
        ),
        // 启用生产持久缓存数据库：会话列表 / 消息 /（未来）媒体的离线缓存
        // 真正落盘（默认 appDatabaseProvider 为内存库，重启即清空）。
        // 单例注入：全进程唯一实例，避免 drift 同名库双开。
        appDatabaseProvider.overrideWithValue(_productionDatabase),
      ],
      child: const HermesApp(),
    ),
  );
}
