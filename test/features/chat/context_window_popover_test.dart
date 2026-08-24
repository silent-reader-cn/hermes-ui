import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermex_flutter/core/api/api_client.dart';
import 'package:hermex_flutter/core/connections/connection_providers.dart';
import 'package:hermex_flutter/core/models/context_window_snapshot.dart';
import 'package:hermex_flutter/features/chat/chat_providers.dart';
import 'package:hermex_flutter/features/chat/widgets/chat_input_bar.dart';
import 'package:hermex_flutter/features/chat/widgets/context_window_popover.dart';

import '../../helpers/fake_chat_api.dart';

ApiClient _buildTestClient(ResponseBody Function(RequestOptions options) responder) {
  final adapter = _RecordingAdapter(responder: responder);
  final dio = Dio(BaseOptions(validateStatus: (_) => true, followRedirects: false));
  dio.httpClientAdapter = adapter;
  return ApiClient(baseUrl: 'http://test.local:30002', dio: dio);
}

ApiClient buildClient(ResponseBody Function(RequestOptions options) responder) => _buildTestClient(responder);

ApiClient _buildMockApiClient({required ResponseBody Function(RequestOptions options) handler}) => _buildTestClient(handler);

class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter({required this.responder});

  final ResponseBody Function(RequestOptions options) responder;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return responder(options);
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();



group('ContextWindowPopover 工作区下拉与手动输入', () {
    testWidgets('初始加载并匹配工作区名称（path — name）', (tester) async {
      final client = buildClient((options) {
        if (options.path.contains('/api/workspaces')) {
          return ResponseBody.fromString(
            jsonEncode({
              'workspaces': [
                {'path': '/home/user/project-a', 'name': 'Project Alpha'},
                {'path': '/home/user/project-b', 'name': ''},
              ],
              'last': '/home/user/project-a',
            }),
            200,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            },
          );
        }
        return ResponseBody.fromString('{}', 200);
      });

      final fakeChatApi = FakeChatApi();
      fakeChatApi.sessionResult = {
        'session': {
          'session_id': 's1',
          'workspace': '/home/user/project-a',
          'model': 'gpt-4o',
        },
      };

      final snap = ContextWindowSnapshot.fromJson({
        'context_length': 100000,
        'last_prompt_tokens': 25000,
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            chatApiProvider.overrideWithValue(fakeChatApi),
            apiClientProvider.overrideWithValue(client),
          ],
          child: CupertinoApp(
            home: CupertinoPageScaffold(
              child: Center(
                child: ContextWindowPopover(
                  sessionId: 's1',
                  snapshot: snap,
                  currentModel: 'gpt-4o',
                  onClose: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        find.text('/home/user/project-a — Project Alpha'),
        findsOneWidget,
      );
    });

    testWidgets('点击展开工作区下拉列表 → 选中新工作区 → updateSessionSettings 被调用并自动收起', (
      tester,
    ) async {
      final client = buildClient((options) {
        if (options.path.contains('/api/workspaces')) {
          return ResponseBody.fromString(
            jsonEncode({
              'workspaces': [
                {'path': '/home/user/project-a', 'name': 'Project Alpha'},
                {'path': '/home/user/project-b', 'name': 'Project Beta'},
              ],
            }),
            200,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            },
          );
        }
        return ResponseBody.fromString('{}', 200);
      });

      final fakeChatApi = FakeChatApi();
      fakeChatApi.sessionResult = {
        'session': {
          'session_id': 's1',
          'workspace': '/home/user/project-a',
        },
      };

      final snap = ContextWindowSnapshot.fromJson({
        'context_length': 100000,
        'last_prompt_tokens': 25000,
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            chatApiProvider.overrideWithValue(fakeChatApi),
            apiClientProvider.overrideWithValue(client),
          ],
          child: CupertinoApp(
            home: CupertinoPageScaffold(
              child: Center(
                child: ContextWindowPopover(
                  sessionId: 's1',
                  snapshot: snap,
                  currentModel: null,
                  onClose: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // 展开下拉列表前，未展示下拉列表项
      expect(
        find.byKey(const ValueKey('workspace-item-/home/user/project-b')),
        findsNothing,
      );

      // 点击触发器展开下拉列表
      await tester.tap(
        find.byKey(const ValueKey('context-popover-workspace-trigger')),
      );
      await tester.pump();

      // 验证列表项已展开
      expect(
        find.byKey(const ValueKey('workspace-item-/home/user/project-a')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('workspace-item-/home/user/project-b')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('workspace-item-default')),
        findsOneWidget,
      );

      // 点击选中 project-b
      await tester.tap(
        find.byKey(const ValueKey('workspace-item-/home/user/project-b')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // 验证 updateSessionSettings 调用
      expect(fakeChatApi.updateSessionCalls, 1);
      expect(fakeChatApi.lastUpdatedWorkspace, '/home/user/project-b');

      // 验证下拉列表已自动收起
      expect(
        find.byKey(const ValueKey('workspace-item-/home/user/project-b')),
        findsNothing,
      );
      // 触发器文案更新
      expect(
        find.text('/home/user/project-b — Project Beta'),
        findsOneWidget,
      );
    });

    testWidgets('工作区列表为空或加载异常时展示友好提示', (tester) async {
      final client = buildClient((options) {
        return ResponseBody.fromString(
          jsonEncode({'workspaces': <Map<String, Object?>>[]}),
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      });

      final fakeChatApi = FakeChatApi();
      fakeChatApi.sessionResult = {
        'session': {
          'session_id': 's1',
          'workspace': null,
        },
      };

      final snap = ContextWindowSnapshot.fromJson({
        'context_length': 100000,
        'last_prompt_tokens': 1000,
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            chatApiProvider.overrideWithValue(fakeChatApi),
            apiClientProvider.overrideWithValue(client),
          ],
          child: CupertinoApp(
            home: CupertinoPageScaffold(
              child: Center(
                child: ContextWindowPopover(
                  sessionId: 's1',
                  snapshot: snap,
                  currentModel: null,
                  onClose: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // 点击触发器展开下拉列表
      await tester.tap(
        find.byKey(const ValueKey('context-popover-workspace-trigger')),
      );
      await tester.pump();

      // 包含空态提示和跟随默认项
      expect(
        find.byKey(const ValueKey('workspace-item-default')),
        findsOneWidget,
      );
      expect(
        find.text('暂无可用工作区（可在设置→工作区管理中添加）'),
        findsOneWidget,
      );
    });

    testWidgets('手动输入逃生通道：展开 TextField 并保存任意路径', (tester) async {
      final client = buildClient((options) {
        return ResponseBody.fromString(
          jsonEncode({'workspaces': <Map<String, Object?>>[]}),
          200,
        );
      });

      final fakeChatApi = FakeChatApi();
      fakeChatApi.sessionResult = {
        'session': {
          'session_id': 's1',
          'workspace': null,
        },
      };

      final snap = ContextWindowSnapshot.fromJson({
        'context_length': 100000,
        'last_prompt_tokens': 1000,
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            chatApiProvider.overrideWithValue(fakeChatApi),
            apiClientProvider.overrideWithValue(client),
          ],
          child: CupertinoApp(
            home: CupertinoPageScaffold(
              child: Center(
                child: ContextWindowPopover(
                  sessionId: 's1',
                  snapshot: snap,
                  currentModel: null,
                  onClose: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // 初始未展示手动输入框
      expect(
        find.byKey(const ValueKey('context-popover-workspace-field')),
        findsNothing,
      );

      // 点击手动输入切换按钮
      await tester.tap(
        find.byKey(const ValueKey('context-popover-workspace-manual-toggle')),
      );
      await tester.pump();

      // 输入框与保存按钮出现
      expect(
        find.byKey(const ValueKey('context-popover-workspace-field')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('context-popover-workspace-save')),
        findsOneWidget,
      );

      // 输入自定义路径
      await tester.enterText(
        find.byKey(const ValueKey('context-popover-workspace-field')),
        '/custom/manual/dir',
      );
      await tester.pump();

      // 点击保存
      await tester.tap(
        find.byKey(const ValueKey('context-popover-workspace-save')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(fakeChatApi.updateSessionCalls, 1);
      expect(fakeChatApi.lastUpdatedWorkspace, '/custom/manual/dir');
      // 保存后输入区域折叠收起
      expect(
        find.byKey(const ValueKey('context-popover-workspace-field')),
        findsNothing,
      );
    });
  });


  final testSnapshot = ContextWindowSnapshot.fromJson({
    'context_length': 128000,
    'last_prompt_tokens': 1200,
    'last_completion_tokens': 300,
    'threshold_tokens': 100000,
    'cost': '\$0.02',
  });

  Widget wrap({
    required Widget child,
    List<Override> overrides = const [],
  }) {
    return ProviderScope(
      overrides: overrides,
      child: CupertinoApp(
        home: CupertinoPageScaffold(
          child: Center(child: child),
        ),
      ),
    );
  }

  group('ContextWindowPopover 模型切换交互测试', () {
    testWidgets('触发器初始展示当前模型名称，选项列表默认折叠', (tester) async {
      final fakeChat = FakeChatApi();
      await tester.pumpWidget(
        wrap(
          overrides: [
            chatApiProvider.overrideWithValue(fakeChat),
            chatAvailableModelsProvider.overrideWithValue(const [
              'gpt-4o',
              'claude-3-5-sonnet',
            ]),
          ],
          child: ContextWindowPopover(
            sessionId: 's1',
            snapshot: testSnapshot,
            currentModel: 'claude-3-5-sonnet',
            onClose: () {},
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // 触发器上应显示当前模型名
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('context-popover-model-trigger')),
          matching: find.text('claude-3-5-sonnet'),
        ),
        findsOneWidget,
      );
      // 触发器按钮存在
      expect(
        find.byKey(const ValueKey('context-popover-model-trigger')),
        findsOneWidget,
      );
    });

    testWidgets('点击触发器展开选项列表，再次点击收起', (tester) async {
      final fakeChat = FakeChatApi();
      await tester.pumpWidget(
        wrap(
          overrides: [
            chatApiProvider.overrideWithValue(fakeChat),
            chatAvailableModelsProvider.overrideWithValue(const [
              'gpt-4o',
              'claude-3-5-sonnet',
            ]),
          ],
          child: ContextWindowPopover(
            sessionId: 's1',
            snapshot: testSnapshot,
            currentModel: 'claude-3-5-sonnet',
            onClose: () {},
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // 点击展开
      await tester.tap(find.byKey(const ValueKey('context-popover-model-trigger')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('context-popover-model-gpt-4o')), findsOneWidget);
      expect(find.byKey(const ValueKey('context-popover-model-claude-3-5-sonnet')), findsOneWidget);
      expect(find.byKey(const ValueKey('context-popover-model-default')), findsOneWidget);

      // 再次点击收起
      await tester.tap(find.byKey(const ValueKey('context-popover-model-trigger')));
      await tester.pumpAndSettle();
    });

    testWidgets('点击模型选项调用 selectModel 并触发 onClose', (tester) async {
      final fakeChat = FakeChatApi();
      var closed = false;

      late WidgetRef capturedRef;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            chatApiProvider.overrideWithValue(fakeChat),
            chatAvailableModelsProvider.overrideWithValue(const [
              'gpt-4o',
              'claude-3-5-sonnet',
            ]),
          ],
          child: CupertinoApp(
            home: Consumer(
              builder: (context, ref, _) {
                capturedRef = ref;
                return CupertinoPageScaffold(
                  child: ContextWindowPopover(
                    sessionId: 's1',
                    snapshot: testSnapshot,
                    currentModel: 'claude-3-5-sonnet',
                    onClose: () => closed = true,
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // 展开下拉列表
      await tester.tap(find.byKey(const ValueKey('context-popover-model-trigger')));
      await tester.pumpAndSettle();

      // 点击 gpt-4o
      await tester.tap(find.byKey(const ValueKey('context-popover-model-gpt-4o')));
      await tester.pumpAndSettle();

      expect(closed, isTrue);
      expect(capturedRef.read(chatControllerProvider('s1')).model, 'gpt-4o');
    });

    testWidgets('点击跟随服务器默认选项调用 selectModel(null) 并触发 onClose', (tester) async {
      final fakeChat = FakeChatApi();
      var closed = false;

      late WidgetRef capturedRef;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            chatApiProvider.overrideWithValue(fakeChat),
            chatAvailableModelsProvider.overrideWithValue(const [
              'gpt-4o',
              'claude-3-5-sonnet',
            ]),
          ],
          child: CupertinoApp(
            home: Consumer(
              builder: (context, ref, _) {
                capturedRef = ref;
                return CupertinoPageScaffold(
                  child: ContextWindowPopover(
                    sessionId: 's1',
                    snapshot: testSnapshot,
                    currentModel: 'claude-3-5-sonnet',
                    onClose: () => closed = true,
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // 先设置为某模型
      capturedRef.read(chatControllerProvider('s1').notifier).selectModel('claude-3-5-sonnet');
      expect(capturedRef.read(chatControllerProvider('s1')).model, 'claude-3-5-sonnet');

      // 展开下拉列表
      await tester.tap(find.byKey(const ValueKey('context-popover-model-trigger')));
      await tester.pumpAndSettle();

      // 点击跟随服务器默认
      await tester.tap(find.byKey(const ValueKey('context-popover-model-default')));
      await tester.pumpAndSettle();

      expect(closed, isTrue);
      expect(capturedRef.read(chatControllerProvider('s1')).model, isNull);
    });

    testWidgets('chatAvailableModelsProvider 为空时，通过 ApiClient 异步拉取 modelsLive', (tester) async {
      final fakeChat = FakeChatApi();
      final mockClient = _buildMockApiClient(
        handler: (options) {
          if (options.path.endsWith('/api/models/live')) {
            final body = jsonEncode({
              'provider': 'openai',
              'models': [
                {'id': 'gpt-4o-mini', 'name': 'GPT-4o Mini'},
                {'id': 'o1-preview', 'name': 'o1 Preview'},
              ],
            });
            return ResponseBody.fromString(
              body,
              200,
              headers: {
                Headers.contentTypeHeader: [Headers.jsonContentType],
              },
            );
          }
          return ResponseBody.fromString('{}', 404);
        },
      );

      await tester.pumpWidget(
        wrap(
          overrides: [
            chatApiProvider.overrideWithValue(fakeChat),
            apiClientProvider.overrideWithValue(mockClient),
          ],
          child: ContextWindowPopover(
            sessionId: 's1',
            snapshot: testSnapshot,
            currentModel: null,
            onClose: () {},
          ),
        ),
      );
      // 触发 postFrameCallback 中的 _maybeFetchModels
      await tester.pump();
      await tester.pumpAndSettle();

      // 展开选项列表
      await tester.tap(find.byKey(const ValueKey('context-popover-model-trigger')));
      await tester.pumpAndSettle();

      // 验证拉取到的模型列表正常展示
      expect(find.byKey(const ValueKey('context-popover-model-gpt-4o-mini')), findsOneWidget);
      expect(find.byKey(const ValueKey('context-popover-model-o1-preview')), findsOneWidget);
      expect(find.byKey(const ValueKey('context-popover-model-default')), findsOneWidget);
    });

    testWidgets('ApiClient 请求异常时静默降级为仅显示跟随默认', (tester) async {
      final fakeChat = FakeChatApi();
      final mockClient = _buildMockApiClient(
        handler: (options) {
          return ResponseBody.fromString('{"error": "server error"}', 500);
        },
      );

      await tester.pumpWidget(
        wrap(
          overrides: [
            chatApiProvider.overrideWithValue(fakeChat),
            apiClientProvider.overrideWithValue(mockClient),
          ],
          child: ContextWindowPopover(
            sessionId: 's1',
            snapshot: testSnapshot,
            currentModel: null,
            onClose: () {},
          ),
        ),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      // 展开选项列表
      await tester.tap(find.byKey(const ValueKey('context-popover-model-trigger')));
      await tester.pumpAndSettle();

      // 静默降级，仅展示跟随默认
      expect(find.byKey(const ValueKey('context-popover-model-default')), findsOneWidget);
    });
  });

  group('ContextWindowPopover 宽屏与自适应外壳下的下拉锚点位置与互斥测试', () {
    testWidgets('宽屏 1200 视口下点击上下文指示器打开 popover，模型/工作区下拉紧贴触发器不飘到屏幕左侧', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final fakeChat = FakeChatApi();
      fakeChat.sessionResult = {
        'session': {
          'session_id': 's1',
          'workspace': '/home/user/my-project',
          'model': 'gpt-4o',
          'context_window_snapshot': {
            'context_length': 128000,
            'last_prompt_tokens': 1200,
            'last_completion_tokens': 300,
            'threshold_tokens': 100000,
            'cost': '\$0.02',
          },
        },
      };

      final client = buildClient((options) {
        if (options.path.contains('/api/workspaces')) {
          return ResponseBody.fromString(
            jsonEncode({
              'workspaces': [
                {'path': '/home/user/my-project', 'name': 'My Project'},
                {'path': '/home/user/other-project', 'name': 'Other Project'},
              ],
            }),
            200,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            },
          );
        }
        return ResponseBody.fromString('{}', 200);
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            chatApiProvider.overrideWithValue(fakeChat),
            apiClientProvider.overrideWithValue(client),
            chatAvailableModelsProvider.overrideWithValue(const [
              'gpt-4o',
              'claude-3-5-sonnet',
            ]),
          ],
          child: const CupertinoApp(
            home: CupertinoPageScaffold(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: ChatInputBar(sessionId: 's1'),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // 点击上下文窗口指示器打开 popover
      final indicatorFinder = find.byKey(
        const ValueKey('chat-context-indicator-button'),
      );
      expect(indicatorFinder, findsOneWidget);
      await tester.tap(indicatorFinder);
      await tester.pumpAndSettle();

      // 验证 popover 已展示
      final modelTriggerFinder = find.byKey(
        const ValueKey('context-popover-model-trigger'),
      );
      expect(modelTriggerFinder, findsOneWidget);
      final modelTriggerTopLeft = tester.getTopLeft(modelTriggerFinder);

      // 1. 点击模型触发器展开模型下拉
      await tester.tap(modelTriggerFinder);
      await tester.pumpAndSettle();

      final modelOptionFinder = find.byKey(
        const ValueKey('context-popover-model-gpt-4o'),
      );
      expect(modelOptionFinder, findsOneWidget);

      final modelOptionTopLeft = tester.getTopLeft(modelOptionFinder);
      // 验证下拉选项位于宽屏右侧内容区（>= 320），且紧贴模型触发器水平坐标，绝不飘到屏幕左侧（dx < 100）
      expect(modelOptionTopLeft.dx, greaterThanOrEqualTo(320.0));
      expect((modelOptionTopLeft.dx - modelTriggerTopLeft.dx).abs(), lessThan(30.0));
      // 验证工作区下拉处于收起状态（互斥）
      expect(find.byKey(const ValueKey('workspace-item-default')), findsNothing);

      // 2. 点击工作区触发器展开工作区下拉，模型下拉自动收起
      final workspaceTriggerFinder = find.byKey(
        const ValueKey('context-popover-workspace-trigger'),
      );
      expect(workspaceTriggerFinder, findsOneWidget);
      await tester.ensureVisible(workspaceTriggerFinder);
      await tester.pumpAndSettle();
      final workspaceTriggerTopLeft = tester.getTopLeft(workspaceTriggerFinder);

      await tester.tap(workspaceTriggerFinder);
      await tester.pumpAndSettle();

      // 验证模型下拉已收起
      expect(
        find.byKey(const ValueKey('context-popover-model-gpt-4o')),
        findsNothing,
      );
      // 验证工作区下拉项展示
      final workspaceOptionFinder = find.byKey(
        const ValueKey('workspace-item-/home/user/other-project'),
      );
      expect(workspaceOptionFinder, findsOneWidget);

      final workspaceOptionTopLeft = tester.getTopLeft(workspaceOptionFinder);
      // 验证工作区下拉选项位于宽屏右侧内容区（>= 320），且紧贴工作区触发器水平坐标，不飘到屏幕左侧
      expect(workspaceOptionTopLeft.dx, greaterThanOrEqualTo(320.0));
      expect(
        (workspaceOptionTopLeft.dx - workspaceTriggerTopLeft.dx).abs(),
        lessThan(30.0),
      );

      // 3. 点击手动输入切换按钮，工作区下拉自动收起，手动输入框展示
      final manualToggleFinder = find.byKey(
        const ValueKey('context-popover-workspace-manual-toggle'),
      );
      await tester.ensureVisible(manualToggleFinder);
      await tester.pumpAndSettle();
      await tester.tap(manualToggleFinder);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('workspace-item-/home/user/other-project')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('context-popover-workspace-field')),
        findsOneWidget,
      );
    });

    testWidgets('窄屏 400 视口下点击上下文指示器打开 popover，模型/工作区下拉紧贴触发器', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(400, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final fakeChat = FakeChatApi();
      fakeChat.sessionResult = {
        'session': {
          'session_id': 's1',
          'workspace': '/home/user/proj',
          'model': 'gpt-4o',
          'context_window_snapshot': {
            'context_length': 128000,
            'last_prompt_tokens': 1200,
            'last_completion_tokens': 300,
            'threshold_tokens': 100000,
            'cost': '\$0.02',
          },
        },
      };

      final client = buildClient((options) {
        if (options.path.contains('/api/workspaces')) {
          return ResponseBody.fromString(
            jsonEncode({
              'workspaces': [
                {'path': '/home/user/proj', 'name': 'Project'},
              ],
            }),
            200,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            },
          );
        }
        return ResponseBody.fromString('{}', 200);
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            chatApiProvider.overrideWithValue(fakeChat),
            apiClientProvider.overrideWithValue(client),
            chatAvailableModelsProvider.overrideWithValue(const [
              'gpt-4o',
              'claude-3-5-sonnet',
            ]),
          ],
          child: const CupertinoApp(
            home: CupertinoPageScaffold(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: ChatInputBar(sessionId: 's1'),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final indicatorFinder = find.byKey(
        const ValueKey('chat-context-indicator-button'),
      );
      await tester.tap(indicatorFinder);
      await tester.pumpAndSettle();

      final modelTriggerFinder = find.byKey(
        const ValueKey('context-popover-model-trigger'),
      );
      final modelTriggerTopLeft = tester.getTopLeft(modelTriggerFinder);

      await tester.tap(modelTriggerFinder);
      await tester.pumpAndSettle();

      final modelOptionFinder = find.byKey(
        const ValueKey('context-popover-model-gpt-4o'),
      );
      expect(modelOptionFinder, findsOneWidget);
      final modelOptionTopLeft = tester.getTopLeft(modelOptionFinder);
      expect(
        (modelOptionTopLeft.dx - modelTriggerTopLeft.dx).abs(),
        lessThan(30.0),
      );
    });

    testWidgets('多模型选项列表在 PopoverDropdownCard 内受到 maxHeight 约束且可滚动', (
      tester,
    ) async {
      final fakeChat = FakeChatApi();
      final manyModels = List.generate(20, (i) => 'model-v$i');

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            chatApiProvider.overrideWithValue(fakeChat),
            chatAvailableModelsProvider.overrideWithValue(manyModels),
          ],
          child: CupertinoApp(
            home: CupertinoPageScaffold(
              child: Center(
                child: ContextWindowPopover(
                  sessionId: 's1',
                  snapshot: testSnapshot,
                  currentModel: 'model-v0',
                  onClose: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      await tester.tap(find.byKey(const ValueKey('context-popover-model-trigger')));
      await tester.pumpAndSettle();

      // 第一项可见
      expect(find.byKey(const ValueKey('context-popover-model-model-v0')), findsOneWidget);
      // 最后一项在初始可视区之外，可通过滚动找到
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('context-popover-model-model-v19')),
        50.0,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('context-popover-model-model-v19')), findsOneWidget);
    });
  });
}
