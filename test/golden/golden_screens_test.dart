import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermex_flutter/core/api/api_client.dart';
import 'package:hermex_flutter/core/api/sse_client.dart';
import 'package:hermex_flutter/core/connections/connection_providers.dart';
import 'package:hermex_flutter/core/connections/connection_store.dart';
import 'package:hermex_flutter/core/connections/server_connection.dart';
import 'package:hermex_flutter/core/models/cron.dart';
import 'package:hermex_flutter/core/models/git_workspace.dart';
import 'package:hermex_flutter/core/models/insights.dart';
import 'package:hermex_flutter/core/models/kanban.dart';
import 'package:hermex_flutter/core/models/memory.dart';
import 'package:hermex_flutter/core/models/server_catalog.dart';
import 'package:hermex_flutter/core/models/session.dart';
import 'package:hermex_flutter/core/models/skills.dart';
import 'package:hermex_flutter/core/models/workspace.dart';
import 'package:hermex_flutter/features/chat/chat_page.dart';
import 'package:hermex_flutter/features/chat/chat_providers.dart';
import 'package:hermex_flutter/features/chat/chat_server_api.dart';
import 'package:hermex_flutter/features/git/git_api.dart';
import 'package:hermex_flutter/features/git/git_page.dart';
import 'package:hermex_flutter/features/insights/insights_api.dart';
import 'package:hermex_flutter/features/insights/insights_page.dart';
import 'package:hermex_flutter/features/kanban/kanban_page.dart';
import 'package:hermex_flutter/features/kanban/kanban_providers.dart';
import 'package:hermex_flutter/features/memory/memory_api.dart';
import 'package:hermex_flutter/features/memory/memory_page.dart';
import 'package:hermex_flutter/features/onboarding/onboarding_page.dart';
import 'package:hermex_flutter/features/session_list/session_list_page.dart';
import 'package:hermex_flutter/features/session_list/session_list_providers.dart';
import 'package:hermex_flutter/features/settings/settings_page.dart';
import 'package:hermex_flutter/features/settings/settings_providers.dart';
import 'package:hermex_flutter/features/skills/skills_api.dart';
import 'package:hermex_flutter/features/skills/skills_page.dart';
import 'package:hermex_flutter/features/tasks/tasks_page.dart';
import 'package:hermex_flutter/features/tasks/tasks_providers.dart';
import 'package:hermex_flutter/features/workspace/workspace_page.dart';
import 'package:hermex_flutter/features/workspace/workspace_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_git_api.dart';
import '../helpers/fake_insights_api.dart';
import '../helpers/fake_kanban_api.dart';
import '../helpers/fake_memory_api.dart';
import '../helpers/fake_session_list_api.dart';
import '../helpers/fake_settings_api.dart';
import '../helpers/fake_skills_api.dart';
import '../helpers/fake_tasks_api.dart';
import '../helpers/fake_workspace_api.dart';
import '../helpers/in_memory_secure_storage.dart';
import 'golden_helpers.dart';

// ---------------------------------------------------------------------------
// 测试数据构造（刻意用长文案驱动换行 / 省略 / 溢出路径，供人工核对）
// ---------------------------------------------------------------------------

/// epoch 秒时间戳辅助。
double secOf(DateTime dt) => dt.millisecondsSinceEpoch / 1000;

/// 相对现在的 epoch 秒时间戳。
double secAgo(Duration ago) => secOf(DateTime.now().subtract(ago));

/// 会话摘要样例。
SessionSummary buildSession(
  String id,
  String title, {
  bool pinned = false,
  bool isStreaming = false,
  double? at,
}) {
  return SessionSummary(
    sessionId: id,
    title: title,
    pinned: pinned,
    isStreaming: isStreaming,
    lastMessageAt: at ?? secAgo(const Duration(hours: 2)),
  );
}

/// 定时任务样例。
CronJob buildJob(String id, {String? name, String? state, bool? enabled}) {
  return CronJob(
    jobId: id,
    name: name ?? '任务 $id',
    prompt: '每早 9 点读取 TODO 并生成今日计划，输出到指定会话（提示词较长用于测试列表行溢出）。',
    schedule: const CronSchedule(expression: '0 9 * * *'),
    state: state,
    enabled: enabled,
  );
}

/// 会话列表页的静态数据。
Future<List<Override>> sessionListOverrides() async {
  final api = FakeSessionListApi(
    sessions: [
      buildSession(
        's-pin',
        '置顶会话：长期进行中的金色回归与主题对比度修复项目讨论纪要（标题很长用于测试两行省略）',
        pinned: true,
        at: secAgo(const Duration(minutes: 10)),
      ),
      buildSession(
        's-stream',
        '正在生成的会话',
        isStreaming: true,
        at: secAgo(const Duration(minutes: 30)),
      ),
      buildSession('s-today', '今天：Flutter 主题对比度修复进展', at: secAgo(const Duration(hours: 1))),
      buildSession('s-y1', '昨天会话', at: secAgo(const Duration(days: 1))),
      buildSession('s-old', '更早：golden 截图回归计划', at: secAgo(const Duration(days: 3))),
      buildSession(
        's-old2',
        '更早的另一个会话标题也很长用来测试元数据行与标题行的换行表现是否正常',
        at: secAgo(const Duration(days: 10)),
      ),
    ],
  );
  return [
    apiClientProvider.overrideWithValue(
      ApiClient(baseUrl: 'http://test.local:30002'),
    ),
    sessionListApiFactoryProvider.overrideWithValue((_) => api),
  ];
}

// ---------------------------------------------------------------------------
// 截图用例注册
// ---------------------------------------------------------------------------

/// 为 [pageName] 注册浅色 + 深色两枚截图用例（PNG 输出到 test/golden/goldens/）。
///
/// [size] 透传给 pump（缺省竖屏 390x844 逻辑尺寸）。
void goldenPair(
  String pageName, {
  required Widget Function() page,
  required Future<List<Override>> Function() overrides,
  Size size = goldenSurfaceSize,
}) {
  for (final brightness in Brightness.values) {
    final themeName = brightness == Brightness.light ? 'light' : 'dark';
    testWidgets('$pageName $themeName', (tester) async {
      await pumpHermexPage(
        tester,
        page: page(),
        brightness: brightness,
        overrides: await overrides(),
        size: size,
      );
      await expectLater(
        find.byType(CupertinoApp),
        matchesGoldenFile('goldens/${pageName}_$themeName.png'),
      );
      await unmountHermexPage(tester);
    });
  }
}

/// 通用 fake 工厂：占位 ApiClient + 注入 fake（工厂 override 忽略占位客户端，
/// 不发任何网络请求）。
List<Override> apiOverrides(Override factoryOverride) {
  return [
    apiClientProvider.overrideWithValue(
      ApiClient(baseUrl: 'http://test.local:30002'),
    ),
    factoryOverride,
  ];
}

void main() {
  setUpAll(() async {
    await loadHermexGoldenFonts();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  goldenPair(
    'onboarding',
    page: () => const OnboardingPage(),
    overrides: () async => const [],
  );

  goldenPair(
    'session_list',
    page: () => const SessionListPage(),
    overrides: sessionListOverrides,
  );

  goldenPair(
    'chat',
    page: () => const ChatPage(sessionId: 's1'),
    overrides: () async {
      final api = _StaticChatApi();
      api.sessionResult = {
        'session': {
          'session_id': 's1',
          'title': '对比度与溢出检查',
          'messages': [
            {
              'role': 'user',
              'content': '帮我把 Hermex 客户端的所有页面文字对比度检查一遍，'
                  '特别是深色模式下次要文字的可读性，同时排查列表行标题被截断的问题。',
              'message_id': 'u1',
            },
            {
              'role': 'assistant',
              'content': '**好的，我来分析。**\n\n'
                  '当前进度：\n\n'
                  '- 主题基建已完成（CupertinoThemeData 双色）\n'
                  '- 深色对比度修复进行中\n'
                  '- 文字溢出排查待启动\n\n'
                  '示例代码：\n'
                  '```dart\n'
                  'final theme = buildCupertinoTheme(brightness);\n'
                  '```\n\n'
                  '这是一段较长的说明文字，用于验证消息气泡内长段落自动换行而不是溢出截断'
                  '：当容器宽度不足以容纳整行时，文本应该在气泡内部折行显示，并保持可读性。',
              'message_id': 'a1',
            },
            {
              'role': 'user',
              'content': '好的，那就按这个方案继续，重点检查 secondaryLabel 的深色值。',
              'message_id': 'u2',
            },
          ],
        },
      };
      return [
        chatApiProvider.overrideWithValue(api),
      ];
    },
  );

  goldenPair(
    'tasks',
    page: () => const TasksPage(),
    overrides: () async => apiOverrides(
      tasksApiFactoryProvider.overrideWithValue(
        (_) => FakeTasksApi(
          jobs: [
            buildJob('j1', name: '运行中的任务：早间新闻摘要生成与推送', state: 'running'),
            buildJob('j2', name: '已暂停的任务', state: 'paused'),
            buildJob('j3', name: '正常的定时任务：每晚备份数据库并压缩上传'),
            buildJob(
              'j4',
              name: '一个非常长的任务名称用来测试列表行标题的省略显示是否正常且不截断',
              enabled: false,
            ),
          ],
        ),
      ),
    ),
  );

  goldenPair(
    'skills',
    page: () => const SkillsPage(),
    overrides: () async => apiOverrides(
      skillsApiFactoryProvider.overrideWithValue(
        (_) => FakeSkillsApi(
          skills: [
            const SkillSummary(
              name: 'flutter-golden-testing',
              category: '测试工程',
              description: '使用 golden_toolkit 建立双主题截图回归基线，'
                  '人工核对文字对比度与溢出问题（描述很长用于测试换行）。',
              path: 'skills/flutter-golden-testing/',
              tags: ['flutter', 'golden', '测试'],
            ),
            const SkillSummary(
              name: 'chat-debugging',
              category: '调试',
              description: '聊天流式渲染问题排查与 SSE 事件序列分析。',
              path: 'skills/chat-debugging/',
              tags: ['chat', 'sse'],
            ),
            const SkillSummary(
              name: 'theme-contrast-audit',
              category: '设计',
              description: '浅色/深色双主题下的文字对比度审计清单与修复流程。',
              path: 'skills/theme-contrast-audit/',
              tags: ['主题', '对比度'],
            ),
          ],
        ),
      ),
    ),
  );

  goldenPair(
    'memory',
    page: () => const MemoryPage(),
    overrides: () async => apiOverrides(
      memoryApiFactoryProvider.overrideWithValue(
        (_) => FakeMemoryApi(
          response: const MemoryResponse(
            memory: '用户偏好：界面使用中文，喜欢 iOS 风格设计；'
                '正在推进 hermex-flutter 客户端移植，关注主题对比度与文字溢出问题。\n'
                '常用命令通过 f.bat 封装执行 Flutter 命令。',
            user: '用户名：Admin\n偏好：深色模式\n活跃时间：夜间',
            soul: '你是一个乐于助人的 AI 助手，回答使用中文，'
                '注重可读性与排版细节。',
            projectContext: '当前项目 hermex-flutter（Flutter + Cupertino 移植 iOS Hermex '
                '客户端）。并行推进：主题对比度修复、golden 截图回归基建。',
            projectContextName: 'hermex-flutter (D:/projects/hermex-flutter)',
          ),
        ),
      ),
    ),
  );

  goldenPair(
    'settings',
    page: () => const SettingsPage(),
    overrides: () async {
      final storage = InMemorySecureStorage();
      final store = ConnectionStore(storage: storage);
      await store.save(
        ServerConnection(
          id: 'c1',
          name: 'Home 服务器',
          baseUrl: 'http://hermes.local:30002',
          createdAt: DateTime.utc(2026, 1, 1),
        ),
      );
      await store.setActive('c1');
      final api = FakeSettingsApi();
      api.modelsResponse = ModelsResponse.fromJson({
        'default_model': 'gpt-4o',
        'active_provider': 'openai',
        'groups': [
          {
            'provider_id': 'openai',
            'name': 'OpenAI',
            'models': [
              {'id': 'gpt-4o', 'name': 'GPT-4o'},
              {'id': 'gpt-4o-mini', 'name': 'GPT-4o mini'},
            ],
          },
          {
            'provider_id': 'anthropic',
            'name': 'Anthropic',
            'models': [
              {'id': 'claude-sonnet-4', 'name': 'Claude Sonnet 4'},
            ],
          },
        ],
      });
      api.reasoningResponse = const ReasoningStatusResponse(
        ok: true,
        reasoningEffort: 'medium',
        supportedEfforts: ['low', 'medium', 'high'],
        supportsReasoningEffort: true,
      );
      return [
        connectionStoreProvider.overrideWithValue(store),
        apiClientProvider.overrideWithValue(
          ApiClient(baseUrl: 'http://test.local:30002'),
        ),
        settingsApiFactoryProvider.overrideWithValue((_) => api),
      ];
    },
  );

  goldenPair(
    'workspace',
    page: () => const WorkspacePage(sessionId: 's1'),
    // 常规竖屏：该页曾缺 largeTitle 触发框架 debug 断言，已修复改用竖屏。
    size: goldenSurfaceSize,
    overrides: () async => apiOverrides(
      workspaceApiFactoryProvider.overrideWithValue(
        (_) => FakeWorkspaceApi(
          directories: {
            '.': [
              const WorkspaceEntry(
                name: 'lib',
                path: 'lib',
                type: 'directory',
                isDirectory: true,
              ),
              const WorkspaceEntry(
                name: '一个非常长的目录名称用来测试目录路径显示省略是否正常',
                path: '一个非常长的目录名称用来测试目录路径显示省略是否正常',
                type: 'directory',
                isDirectory: true,
              ),
              const WorkspaceEntry(
                name: 'pubspec.yaml',
                path: 'pubspec.yaml',
                type: 'file',
                size: 2048,
                modified: 1750000000,
              ),
              const WorkspaceEntry(
                name: 'analysis_options_flutter_lints_very_long_name.yaml',
                path: 'analysis_options_flutter_lints_very_long_name.yaml',
                type: 'file',
                size: 1024,
                modified: 1750000100,
              ),
              const WorkspaceEntry(
                name: 'README 中文说明文档并且文件名比较长的文件.md',
                path: 'README 中文说明文档并且文件名比较长的文件.md',
                type: 'file',
                size: 12345678,
                modified: 1750000200,
              ),
            ],
          },
        ),
      ),
    ),
  );

  goldenPair(
    'git',
    page: () => const GitPage(sessionId: 's1'),
    overrides: () async => apiOverrides(
      gitApiFactoryProvider.overrideWithValue(
        (_) => FakeGitApi(
          status: GitStatus(
            isGit: true,
            branch: 'main',
            upstream: 'origin/main',
            ahead: 1,
            behind: 2,
            totals: const GitTotals(
              changed: 3,
              staged: 1,
              unstaged: 2,
              untracked: 1,
            ),
            files: [
              GitFile(
                path: 'lib/app/theme/cupertino_theme.dart',
                status: 'M',
                staged: true,
                additions: 3,
                deletions: 1,
              ),
              GitFile(
                path: 'lib/features/chat/chat_page.dart',
                status: 'M',
                unstaged: true,
                additions: 120,
                deletions: 8,
              ),
              GitFile(
                path: '新增的未跟踪文件名称很长用于测试溢出显示.md',
                untracked: true,
              ),
            ],
          ),
        ),
      ),
    ),
  );

  goldenPair(
    'kanban',
    page: () => const KanbanPage(),
    overrides: () async {
      final api = FakeKanbanApi(
        boards: [const KanbanBoard(slug: 'default', name: '主看板')],
        currentSlug: 'default',
        snapshots: {
          'default': const KanbanBoardSnapshot(
            columns: [
              KanbanColumn(
                name: 'todo',
                cards: [
                  KanbanCard(
                    cardID: 'c1',
                    title: '实现 golden 截图回归',
                    status: KanbanStatus('todo'),
                    assignee: 'alice',
                    linkCounts: KanbanLinkCounts(parents: 2),
                  ),
                  KanbanCard(
                    cardID: 'c2',
                    title: '实现深色主题对比度修复（卡片标题很长用于测试列内显示效果）',
                    status: KanbanStatus('todo'),
                    assignee: 'bob',
                  ),
                  KanbanCard(
                    cardID: 'c3',
                    title: '收集用户反馈',
                    status: KanbanStatus('todo'),
                  ),
                ],
              ),
              KanbanColumn(
                name: 'running',
                cards: [
                  KanbanCard(
                    cardID: 'c4',
                    title: '主题基建',
                    status: KanbanStatus('running'),
                    assignee: 'alice',
                  ),
                ],
              ),
              KanbanColumn(
                name: 'done',
                cards: [
                  KanbanCard(
                    cardID: 'c5',
                    title: '搭建脚手架',
                    status: KanbanStatus('done'),
                    assignee: 'bob',
                  ),
                ],
              ),
            ],
          ),
        },
      );
      return [
        apiClientProvider.overrideWithValue(
          ApiClient(baseUrl: 'http://test.local:30002'),
        ),
        kanbanApiFactoryProvider.overrideWithValue((_) => api),
      ];
    },
  );

  goldenPair(
    'insights',
    page: () => const InsightsPage(),
    overrides: () async => apiOverrides(
      insightsApiFactoryProvider.overrideWithValue(
        (_) => FakeInsightsApi(
          response: const InsightsResponse(
            periodDays: 30,
            totalSessions: 12,
            totalMessages: 1234,
            totalInputTokens: 1000000,
            totalOutputTokens: 250000,
            totalTokens: 1250000,
            totalCost: 1.2345,
            totalCacheReadTokens: 5000,
            totalCacheHitPercent: 87.5,
            models: [
              InsightsModelBreakdown(
                model: 'gpt-4o',
                totalTokens: 1000,
                tokenShare: 60,
              ),
              InsightsModelBreakdown(
                model: 'claude-sonnet-4',
                totalTokens: 500,
                tokenShare: 40,
              ),
            ],
            dailyTokens: [
              InsightsDailyToken(
                date: '08-16',
                inputTokens: 100,
                outputTokens: 50,
                sessions: 2,
                cost: 0.01,
              ),
              InsightsDailyToken(
                date: '08-15',
                inputTokens: 60,
                outputTokens: 30,
                sessions: 1,
              ),
              InsightsDailyToken(
                date: '08-14',
                inputTokens: 40,
                outputTokens: 20,
                sessions: 1,
              ),
            ],
            activityByDay: [
              InsightsActivityByDay(day: '2026-08-16', sessions: 5),
            ],
            activityByHour: [
              InsightsActivityByHour(hour: 14, sessions: 3),
            ],
          ),
        ),
      ),
    ),
  );
}

/// 静态聊天 API fake（返回预置会话消息，不发任何网络请求、不启动流）。
class _StaticChatApi implements ChatServerApi {
  /// `session` 返回的原始会话 JSON（页面加载后静态渲染）。
  Map<String, Object?>? sessionResult;

  @override
  Future<Object?> startChat({
    required String sessionId,
    required String message,
    String? workspace,
    String? model,
    String? modelProvider,
    String? profile,
    bool explicitModelPick = false,
    List<Map<String, Object?>>? attachments,
  }) async {
    return {'stream_id': 'stream-1', 'session_id': sessionId};
  }

  @override
  Future<Object?> steerChat({
    required String sessionId,
    required String text,
  }) async {
    return {'accepted': true};
  }

  @override
  Future<Object?> cancelChat(String streamId) async => {'ok': true};

  @override
  Future<Object?> chatStreamStatus(String streamId) async =>
      {'active': false, 'replay_available': false};

  @override
  Future<Object?> session({
    required String sessionId,
    bool includeMessages = true,
    int? messageLimit,
    int? messageBefore,
    bool expandRenderable = false,
  }) async {
    return sessionResult ??
        {
          'session': {'session_id': sessionId, 'messages': const []},
        };
  }

  @override
  Future<Object?> respondApproval({
    required String sessionId,
    required String choice,
    String? approvalId,
  }) async {
    return {'ok': true};
  }

  @override
  Future<Object?> respondClarification({
    required String sessionId,
    required String response,
    String? clarifyId,
  }) async {
    return {'ok': true};
  }

  @override
  Future<Object?> renameSession({
    required String sessionId,
    required String title,
  }) async {
    return {'ok': true, 'session': {'session_id': sessionId, 'title': title}};
  }

  @override
  Future<Object?> pinSession({
    required String sessionId,
    required bool pinned,
  }) async {
    return {'ok': true};
  }

  @override
  Future<Object?> archiveSession({
    required String sessionId,
    required bool archived,
  }) async {
    return {'ok': true};
  }

  @override
  Future<Object?> deleteSession(String sessionId) async => {'ok': true};

  @override
  Future<Object?> branchSession(String sessionId) async => {
        'session_id': 'branch-$sessionId',
        'parent_session_id': sessionId,
      };

  @override
  Future<Object?> compressSession({
    required String sessionId,
    String? focusTopic,
  }) async {
    return {'ok': true};
  }

  @override
  Future<Object?> undoSession(String sessionId) async => {'ok': true};

  @override
  Future<Object?> retrySession(String sessionId) async => {
        'ok': true,
        'text': '最后一条用户消息',
      };

  @override
  Future<Object?> updateSession({
    required String sessionId,
    String? workspace,
    String? model,
    String? modelProvider,
  }) async {
    return {'ok': true};
  }

  @override
  Future<Object?> getYolo(String sessionId) async => {
        'ok': true,
        'yolo_enabled': false,
      };

  @override
  Future<Object?> setYolo({
    required String sessionId,
    required bool enabled,
  }) async {
    return {'ok': true, 'yolo_enabled': enabled};
  }

  @override
  Future<void> startStream(
    String streamId, {
    int? replayAfterSeq,
    required void Function(SseEvent event) onEvent,
    void Function(String eventId)? onEventId,
    required void Function(String message) onTransportError,
    required void Function() onClosed,
  }) async {}

  @override
  void stopStream() {}
}