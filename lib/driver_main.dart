import 'dart:developer' as developer;

import 'package:flutter/widgets.dart';
// flutter_driver 依赖在 dev_dependencies；本文件是 driver 专用测试入口，
// 仅经 `flutter run -t` / `flutter drive` 编译，不属于常规生产 lib 代码。
// ignore: depend_on_referenced_packages
import 'package:flutter_driver/driver_extension.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'app/app.dart';
import 'core/api/cookie_store.dart';
import 'core/connections/connection_store.dart';
import 'features/chat/chat_providers.dart';
import 'features/desktop/desktop_settings.dart';
import 'features/notifications/notification_providers.dart';

/// flutter driver 专用入口：与 main.dart 相同的初始化，仅多启用 driver 扩展。
///
/// 供 `flutter_driver_command` 驱动运行中的 app 做端到端测试。
/// 用法：`flutter run -d windows -t lib/driver_main.dart`。
Future<void> main() async {
  // 必须在任何 binding 创建之前调用：DriverBinding 会创建自己的 binding，
  // 若先 ensureInitialized()（创建 WidgetsFlutterBinding）会导致
  // "Binding is already initialized" 断言崩溃。
  enableFlutterDriverExtension();
  WidgetsFlutterBinding.ensureInitialized();
  if (isDesktopPlatform()) {
    try {
      await windowManager.ensureInitialized();
      await windowManager.setMinimumSize(const Size(720, 480));
    } catch (e, st) {
      developer.log(
        'windowManager.ensureInitialized failed',
        name: 'driver_main',
        error: e,
        stackTrace: st,
      );
    }
  }
  CookieStore.shared = CookieStore(storage: const FlutterSecureStorageAdapter());
  await CookieStore.shared.restore();
  runApp(
    ProviderScope(
      overrides: [
        chatTurnCompletedCallbackProvider.overrideWith(
          (ref) => ref.watch(turnNotificationHookProvider),
        ),
      ],
      child: const HermesApp(),
    ),
  );
}
