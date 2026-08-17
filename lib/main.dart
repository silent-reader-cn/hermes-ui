import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/api/cookie_store.dart';
import 'core/connections/connection_store.dart';
import 'features/chat/chat_providers.dart';
import 'features/notifications/notification_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 启动时恢复持久化的登录 cookie，避免 App 重启后登录态丢失（401）。
  // 未登录/无 cookie 时静默跳过；失败静默（会话列表会走自动重登兜底）。
  CookieStore.shared = CookieStore(storage: const FlutterSecureStorageAdapter());
  await CookieStore.shared.restore();
  runApp(
    ProviderScope(
      overrides: [
        // 回合完成 → 后台通知 hook（chat_controller 的 done/stream_end
        // 收尾处调用；前台不发、后台发，见 notifications feature）。
        chatTurnCompletedCallbackProvider.overrideWith(
          (ref) => ref.watch(turnNotificationHookProvider),
        ),
      ],
      child: const HermexApp(),
    ),
  );
}
