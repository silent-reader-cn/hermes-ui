import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/connections/connection_providers.dart';
import '../features/chat/chat_page.dart';
import '../features/onboarding/onboarding_page.dart';
import '../features/session_list/session_list_page.dart';
import '../features/settings/settings_page.dart';

/// 全局路由表（app_shell_spec.md §3）。
///
/// | 路径 | 页面 |
/// |---|---|
/// | `/onboarding` | OnboardingPage |
/// | `/` | SessionListPage |
/// | `/chat` / `/chat/:sessionId` | ChatPage（无 sessionId = 新会话） |
/// | `/settings` | SettingsPage |
///
/// 路由守卫（§2.1 初始化顺序 + §3 守卫）：未配置服务器 → 一律重定向
/// `/onboarding`；已有激活连接 → `/onboarding` 重定向 `/`（配置完成后自动
/// 进入 SessionList）。激活连接变化（首次加载完成 / 切换 / 清除）经
/// [refreshListenable] 触发重算。
final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier(0);
  ref.onDispose(refresh.dispose);
  ref.listen(activeConnectionProvider, (_, _) {
    refresh.value++;
  });

  return GoRouter(
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: (context, state) {
      final hasActive = ref.read(activeConnectionProvider) != null;
      final isOnboarding = state.matchedLocation == '/onboarding';
      if (!hasActive && !isOnboarding) return '/onboarding';
      if (hasActive && isOnboarding) return '/';
      return null;
    },
    routes: [
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingPage(),
      ),
      GoRoute(
        path: '/',
        builder: (context, state) => const SessionListPage(),
      ),
      GoRoute(
        path: '/chat',
        builder: (context, state) => const ChatPage(sessionId: ''),
      ),
      GoRoute(
        path: '/chat/:sessionId',
        builder: (context, state) => ChatPage(
          sessionId: state.pathParameters['sessionId'] ?? '',
        ),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsPage(),
      ),
    ],
  );
});
