import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'deep_link.dart';
import 'shell/adaptive_shell.dart';
import '../core/connections/connection_providers.dart';
import '../core/providers/file_picker_provider.dart';
import '../features/chat/chat_page.dart';
import '../features/downloads/download_page.dart';
import '../features/git/git_page.dart';
import '../features/insights/insights_page.dart';
import '../features/kanban/kanban_page.dart';
import '../features/memory/memory_page.dart';
import '../features/onboarding/install_guide_page.dart';
import '../features/onboarding/onboarding_page.dart';
import '../features/session_list/session_list_page.dart';
import '../features/settings/settings_page.dart';
import '../features/skills/skills_page.dart';
import '../features/tasks/tasks_page.dart';
import '../features/workspace/workspace_page.dart';
import '../features/workspace_manager/workspace_manager_page.dart';
import 'widgets/hermes_page_route.dart';

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
/// | `/workspaces` | WorkspaceManagerPage | 工作区管理（注册表） |
/// | `/kanban` | KanbanPage | 看板 |
/// | `/git/:sessionId` | GitPage | 会话工作区 Git |
/// | `/insights` | InsightsPage | 用量统计 |
/// | `/downloads` | DownloadPage | 下载管理 |
///
/// 路由守卫（§2.1 初始化顺序 + §3 守卫）：未配置服务器 → 一律重定向
/// `/onboarding`；已有激活连接 → `/onboarding` 重定向 `/`（配置完成后自动
/// 进入 SessionList）。激活连接变化（首次加载完成 / 切换 / 清除）经
/// 全局根导航 Key。
///
/// ShellRoute 内全部顶层路由统一 `pageBuilder + HermesPage`（todo #22
/// 补充，2026-08-29 实机反馈）：此前 `/` `/chat/:id` `/settings` `/tasks`
/// 等用 `builder` 走 go_router 默认 MaterialPage 转场——pop 时底层页被
/// 驱动（视觉「底层从右滑入」），且顶层滑出方向与 iOS 标准不一致；
/// 改用 HermesPage 后 push 从右滑入、pop 当前页向右滑出、底层静止，
/// 与 `/workspace/:id` `/git/:id` 详情页一致。
final rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'rootNavigator');

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier(0);
  ref.onDispose(refresh.dispose);
  ref.listen(activeConnectionProvider, (_, _) {
    refresh.value++;
  });

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: resolveInitialRoute(
      PlatformDispatcher.instance.defaultRouteName,
    ),
    refreshListenable: refresh,
    redirect: (context, state) {
      final hasActive = ref.read(activeConnectionProvider) != null;
      final isOnboarding = state.matchedLocation == '/onboarding';
      final isInstallGuide = state.matchedLocation == '/install-guide';
      if (!hasActive && !isOnboarding && !isInstallGuide) return '/onboarding';
      if (hasActive && (isOnboarding || isInstallGuide)) return '/';
      return null;
    },
    routes: [
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingPage(),
      ),
      GoRoute(
        path: '/install-guide',
        builder: (context, state) => const InstallGuidePage(),
      ),
      ShellRoute(
        builder: (context, state, child) =>
            AdaptiveShell(state: state, child: child),
        routes: [
          GoRoute(
            path: '/',
            pageBuilder: (context, state) => HermesPage<void>(
              key: const ValueKey('home'),
              builder: (_) => const SessionListPage(),
            ),
          ),
          GoRoute(
            path: '/chat',
            pageBuilder: (context, state) => HermesPage<void>(
              key: const ValueKey('chat-new'),
              builder: (_) => const ChatPage(sessionId: ''),
            ),
          ),
          GoRoute(
            path: '/chat/:sessionId',
            pageBuilder: (context, state) => HermesPage<void>(
              key: ValueKey('chat-${state.pathParameters['sessionId']}'),
              builder: (_) => ChatPage(
                sessionId: state.pathParameters['sessionId'] ?? '',
                searchQuery: state.uri.queryParameters['q'],
                matchType: state.uri.queryParameters['match'],
              ),
            ),
          ),
          GoRoute(
            path: '/settings',
            pageBuilder: (context, state) => HermesPage<void>(
              key: const ValueKey('settings'),
              builder: (_) => const SettingsPage(),
            ),
          ),
          GoRoute(
            path: '/tasks',
            pageBuilder: (context, state) => HermesPage<void>(
              key: const ValueKey('tasks'),
              builder: (_) => const TasksPage(),
            ),
          ),
          GoRoute(
            path: '/skills',
            pageBuilder: (context, state) => HermesPage<void>(
              key: const ValueKey('skills'),
              builder: (_) => const SkillsPage(),
            ),
          ),
          GoRoute(
            path: '/memory',
            pageBuilder: (context, state) => HermesPage<void>(
              key: const ValueKey('memory'),
              builder: (_) => const MemoryPage(),
            ),
          ),
          GoRoute(
            path: '/workspace/:sessionId',
            // pageBuilder + HermesPage：context.push 进入/返回统一走 Hermes
            // 转场（push 从右滑入、pop 当前页向右滑出、底层静止）。
            pageBuilder: (context, state) => HermesPage<void>(
              key: ValueKey('workspace-${state.pathParameters['sessionId']}'),
              builder: (_) => WorkspacePage(
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
          ),
          GoRoute(
            path: '/workspaces',
            pageBuilder: (context, state) => HermesPage<void>(
              key: const ValueKey('workspaces'),
              builder: (_) => const WorkspaceManagerPage(),
            ),
          ),
          GoRoute(
            path: '/kanban',
            pageBuilder: (context, state) => HermesPage<void>(
              key: const ValueKey('kanban'),
              builder: (_) => const KanbanPage(),
            ),
          ),
          GoRoute(
            path: '/git/:sessionId',
            // pageBuilder + HermesPage：context.push 进入/返回统一走 Hermes
            // 转场（push 从右滑入、pop 当前页向右滑出、底层静止）。
            pageBuilder: (context, state) => HermesPage<void>(
              key: ValueKey('git-${state.pathParameters['sessionId']}'),
              builder: (_) =>
                  GitPage(sessionId: state.pathParameters['sessionId'] ?? ''),
            ),
          ),
          GoRoute(
            path: '/insights',
            pageBuilder: (context, state) => HermesPage<void>(
              key: const ValueKey('insights'),
              builder: (_) => const InsightsPage(),
            ),
          ),
          GoRoute(
            path: '/downloads',
            pageBuilder: (context, state) => HermesPage<void>(
              key: const ValueKey('downloads'),
              builder: (_) => const DownloadPage(),
            ),
          ),
        ],
      ),
    ],
  );
});
