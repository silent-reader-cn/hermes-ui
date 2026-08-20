import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hermex_flutter/app/theme/cupertino_theme.dart';
import 'package:hermex_flutter/core/api/api_client.dart';
import 'package:hermex_flutter/core/connections/connection_providers.dart';
import 'package:hermex_flutter/core/connections/connection_store.dart';
import 'package:hermex_flutter/core/models/cron.dart';
import 'package:hermex_flutter/core/models/server_catalog.dart';
import 'package:hermex_flutter/core/models/session.dart';
import 'package:hermex_flutter/core/models/workspace.dart';
import 'package:hermex_flutter/features/chat/chat_page.dart';
import 'package:hermex_flutter/features/chat/chat_providers.dart';
import '../helpers/fake_chat_api.dart';
import 'package:hermex_flutter/features/projects/project_providers.dart';
import 'package:hermex_flutter/features/session_list/session_list_page.dart';
import 'package:hermex_flutter/features/session_list/session_list_providers.dart';
import 'package:hermex_flutter/features/settings/settings_page.dart';
import 'package:hermex_flutter/features/settings/settings_providers.dart';
import 'package:hermex_flutter/features/tasks/tasks_page.dart';
import 'package:hermex_flutter/features/tasks/tasks_providers.dart';
import 'package:hermex_flutter/features/workspace/workspace_page.dart';
import 'package:hermex_flutter/features/workspace/workspace_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_session_list_api.dart';
import '../helpers/fake_settings_api.dart';
import '../helpers/fake_tasks_api.dart';
import '../helpers/fake_workspace_api.dart';
import '../helpers/in_memory_secure_storage.dart';

ApiClient _dummyClient() => ApiClient(baseUrl: 'http://test.local:30002');

class _StubProjectApi implements ProjectApi {
  @override
  Future<ProjectsResponse> fetchProjects() async =>
      const ProjectsResponse(projects: []);

  @override
  Future<ProjectMutationResponse> createProject({
    required String name,
    String? color,
  }) async => const ProjectMutationResponse(ok: true);

  @override
  Future<ProjectMutationResponse> renameProject({
    required String projectId,
    required String name,
    String? color,
  }) async => const ProjectMutationResponse(ok: true);

  @override
  Future<ProjectMutationResponse> deleteProject(String projectId) async =>
      const ProjectMutationResponse(ok: true);
}

typedef _A11yChatApi = FakeChatApi;

Widget _scaledApp({
  required Widget child,
  required double textScale,
  Brightness brightness = Brightness.light,
  bool useGoRouter = false,
}) {
  final content = MediaQuery(
    data: const MediaQueryData(
      size: Size(390, 844),
      padding: EdgeInsets.only(top: 47, bottom: 34),
    ).copyWith(
      textScaler: TextScaler.linear(textScale),
    ),
    child: child,
  );

  if (useGoRouter) {
    return CupertinoApp.router(
      theme: buildCupertinoTheme(brightness),
      routerConfig: GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(path: '/', builder: (_, _) => content),
          GoRoute(path: '/settings', builder: (_, _) => const SettingsPage()),
        ],
      ),
    );
  }

  return CupertinoApp(
    theme: buildCupertinoTheme(brightness),
    home: content,
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('动态字号审计 (1.3x / 2.0x Text Scale 无 RenderFlex 溢出)', () {
    const scales = [1.3, 2.0];

    for (final scale in scales) {
      group('字号缩放 ${scale}x', () {
        testWidgets('1. session_list 页面正常态、搜索态与多选批量栏', (tester) async {
          tester.view.physicalSize = const Size(390, 844);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

          final now = DateTime.now();
          final noon = DateTime(now.year, now.month, now.day, 12);
          double sec(DateTime t) => t.millisecondsSinceEpoch / 1000;
          final api = FakeSessionListApi(
            sessions: [
              SessionSummary(
                sessionId: 'p1',
                title: '置顶会话 - 这是一个较长的置顶会话标题用于测试字体缩放与布局溢出',
                pinned: true,
                lastMessageAt: sec(noon),
                messageCount: 42,
                workspace: '/projects/hermex',
                sourceLabel: 'webui',
                estimatedCost: 0.15,
              ),
              SessionSummary(
                sessionId: 't1',
                title: '今天讨论配色方案与大字号无障碍支持',
                lastMessageAt: sec(noon.subtract(const Duration(hours: 2))),
                messageCount: 15,
              ),
            ],
          );

          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                apiClientProvider.overrideWithValue(_dummyClient()),
                sessionListApiFactoryProvider.overrideWithValue((_) => api),
                projectApiFactoryProvider.overrideWithValue(
                  (_) => _StubProjectApi(),
                ),
              ],
              child: _scaledApp(
                child: const SessionListPage(),
                textScale: scale,
                useGoRouter: true,
              ),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 50));

          // 验证会话标题正常呈现且无 overflow
          expect(find.textContaining('置顶会话'), findsOneWidget);

          // 验证长按进入多选模式，底部批量栏渲染不溢出
          final row = find.textContaining('置顶会话');
          await tester.longPress(row);
          await tester.pumpAndSettle();

          expect(find.textContaining('已选'), findsOneWidget);
          expect(find.text('全选'), findsOneWidget);

          // 卸载
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        });

        testWidgets('2. chat 页面消息流、Markdown、工具卡片与输入栏', (tester) async {
          tester.view.physicalSize = const Size(390, 844);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

          final api = _A11yChatApi();
          api.sessionResult = {
            'session': {
              'session_id': 's1',
              'title': '长标题聊天会话测试字号缩放无障碍',
              'messages': [
                {
                  'role': 'user',
                  'content': '测试超长用户输入文本在两倍字号下的展示效果是否有任何布局溢出错误',
                  'message_id': 'u1',
                },
                {
                  'role': 'assistant',
                  'content':
                      '# 标题一\n\n正文段落包含 **加粗文字** 与 `inline_code` 格式。\n\n> 引用块内容\n\n```json\n{"key": "value"}\n```',
                  'message_id': 'a1',
                },
              ],
            },
          };

          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                chatApiProvider.overrideWithValue(api),
                chatAvailableModelsProvider.overrideWithValue(const [
                  'gpt-5',
                  'claude',
                ]),
              ],
              child: _scaledApp(
                child: const ChatPage(sessionId: 's1'),
                textScale: scale,
              ),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 50));

          expect(find.textContaining('测试超长用户输入'), findsOneWidget);

          // 触发输入文本并发送，测试流式中的 steer / stop 按钮排布
          await tester.enterText(
            find.byKey(const ValueKey('chat-input-field')),
            '继续执行任务',
          );
          await tester.pump();
          await tester.tap(find.byKey(const ValueKey('chat-send-button')));
          await tester.pump();
          await tester.pump();

          expect(
            find.byKey(const ValueKey('chat-stop-button')),
            findsOneWidget,
          );

          // 卸载
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        });

        testWidgets('3. settings 页面设置列表、外观主题切换与服务器列表', (tester) async {
          tester.view.physicalSize = const Size(390, 844);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

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
            ],
          });
          api.reasoningResponse = const ReasoningStatusResponse(
            ok: true,
            reasoningEffort: 'medium',
            supportedEfforts: ['low', 'medium', 'high'],
            supportsReasoningEffort: true,
          );
          final storage = InMemorySecureStorage();

          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                connectionStoreProvider.overrideWithValue(
                  ConnectionStore(storage: storage),
                ),
                apiClientProvider.overrideWithValue(_dummyClient()),
                settingsApiFactoryProvider.overrideWithValue((_) => api),
              ],
              child: _scaledApp(
                child: const SettingsPage(),
                textScale: scale,
              ),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 50));

          expect(find.text('外观'), findsOneWidget);
          expect(find.text('主题'), findsOneWidget);

          // 卸载
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        });

        testWidgets('4. tasks 定时任务列表与表单编辑页', (tester) async {
          tester.view.physicalSize = const Size(390, 844);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

          final api = FakeTasksApi(
            jobs: [
              const CronJob(
                jobId: 'j1',
                name: '每日晨报自动生成与投递长任务标题',
                prompt: '生成今日摘要并分析系统状态指标',
                schedule: CronSchedule(expression: '0 9 * * *'),
                state: 'running',
                enabled: true,
              ),
              const CronJob(
                jobId: 'j2',
                name: '周报汇总任务',
                prompt: '汇总本周进展',
                schedule: CronSchedule(expression: '0 18 * * 5'),
                state: 'paused',
              ),
            ],
          );

          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                apiClientProvider.overrideWithValue(_dummyClient()),
                tasksApiFactoryProvider.overrideWithValue((_) => api),
              ],
              child: _scaledApp(
                child: const TasksPage(),
                textScale: scale,
              ),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 50));

          expect(find.textContaining('每日晨报自动生成'), findsOneWidget);

          // 打开新建任务表单
          await tester.tap(find.byKey(const ValueKey('tasks-create')));
          await tester.pumpAndSettle();

          expect(find.text('新建任务'), findsOneWidget);
          expect(find.text('调度表达式'), findsOneWidget);

          // 卸载
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        });

        testWidgets('5. workspace 文件浏览与路径面包屑', (tester) async {
          tester.view.physicalSize = const Size(390, 844);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

          final modified =
              DateTime.now()
                  .subtract(const Duration(hours: 1))
                  .millisecondsSinceEpoch /
              1000;
          final api = FakeWorkspaceApi(
            directories: {
              '.': [
                const WorkspaceEntry(
                  name: 'source_code_directory',
                  type: 'directory',
                  path: 'source_code_directory',
                ),
                WorkspaceEntry(
                  name: 'long_filename_documentation_test_project.markdown',
                  type: 'file',
                  path: 'long_filename_documentation_test_project.markdown',
                  size: 2048,
                  modified: modified,
                ),
              ],
            },
          );

          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                apiClientProvider.overrideWithValue(_dummyClient()),
                workspaceApiFactoryProvider.overrideWithValue((_) => api),
              ],
              child: _scaledApp(
                child: const WorkspacePage(sessionId: 's1'),
                textScale: scale,
                useGoRouter: true,
              ),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 50));

          expect(find.text('位置'), findsOneWidget);
          expect(find.byKey(const ValueKey('workspace-root')), findsOneWidget);
          expect(find.byKey(const ValueKey('workspace-up')), findsOneWidget);
          expect(find.textContaining('source_code_directory'), findsOneWidget);

          // 卸载
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        });
      });
    }
  });
}
