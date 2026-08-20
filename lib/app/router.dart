import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'deep_link.dart';
import 'shell/adaptive_shell.dart';
import '../core/connections/connection_providers.dart';
import '../core/providers/file_picker_provider.dart';
import '../features/chat/chat_page.dart';
import '../features/git/git_page.dart';
import '../features/insights/insights_page.dart';
import '../features/kanban/kanban_page.dart';
import '../features/memory/memory_page.dart';
import '../features/onboarding/onboarding_page.dart';
import '../features/session_list/session_list_page.dart';
import '../features/settings/settings_page.dart';
import '../features/skills/skills_page.dart';
import '../features/tasks/tasks_page.dart';
import '../features/workspace/workspace_page.dart';

/// 全局路由表（app_shell_spec.md §3 / TASK W2 自适应外壳）。
///
/// | 路径 | 页面 | 说明 |
/// |---|---|---|
/// | `/onboarding` | OnboardingPage | 顶层独立路由（不进外壳，全屏向导） |
/// | `/` | SessionListPage | 会话列表主页（宽屏下左侧常驻列表，右侧空态占位） |
/// | `/chat` / `/chat/:sessionId` | ChatPage | 聊天页（无 sessionId = 新会话） |
/// | `/settings` | SettingsPage | 设置页 |
/// | `/tasks` | TasksPage | 定时任务管理 |
/// | `/skills` | SkillsPage | 技能管理 |
/// | `/memory` | MemoryPage | 记忆管理 |
/// | `/workspace/:sessionId` | WorkspacePage | 会话工作区文件 |
/// | `/kanban` | KanbanPage | 看板 |
/// | `/git/:sessionId` | GitPage | 会话工作区 Git |
/// | `/insights` | InsightsPage | 用量统计 |
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
    initialLocation: resolveInitialRoute(
      PlatformDispatcher.instance.defaultRouteName,
    ),
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
      ShellRoute(
        builder: (context, state, child) => AdaptiveShell(
          state: state,
          child: child,
        ),
        routes: [
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
              searchQuery: state.uri.queryParameters['q'],
              matchType: state.uri.queryParameters['match'],
            ),
          ),
          GoRoute(
            path: '/settings',
            builder: (context, state) => const SettingsPage(),
          ),
          GoRoute(
            path: '/tasks',
            builder: (context, state) => const TasksPage(),
          ),
          GoRoute(
            path: '/skills',
            builder: (context, state) => const SkillsPage(),
          ),
          GoRoute(
            path: '/memory',
            builder: (context, state) => const MemoryPage(),
          ),
          GoRoute(
            path: '/workspace/:sessionId',
            builder: (context, state) => WorkspacePage(
              sessionId: state.pathParameters['sessionId'] ?? '',
              filePicker: () async {
                final service = ref.read(filePickerServiceProvider);
                final picked = await service.pickFile();
                if (picked == null) return null;
                return WorkspacePickedFile(
                  name: picked.name,
                  bytes: picked.bytes,
                );
              },
            ),
          ),
          GoRoute(
            path: '/kanban',
            builder: (context, state) => const KanbanPage(),
          ),
          GoRoute(
            path: '/git/:sessionId',
            builder: (context, state) => GitPage(
              sessionId: state.pathParameters['sessionId'] ?? '',
            ),
          ),
          GoRoute(
            path: '/insights',
            builder: (context, state) => const InsightsPage(),
          ),
        ],
      ),
    ],
  );
});
