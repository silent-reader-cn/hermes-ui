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
import 'package:hermex_flutter/features/chat/widgets/context_window_popover.dart';

import '../../helpers/fake_chat_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ApiClient buildClient(ResponseBody Function(RequestOptions options) responder) {
    final adapter = _RecordingAdapter(responder: responder);
    final dio = Dio(
      BaseOptions(validateStatus: (_) => true, followRedirects: false),
    );
    dio.httpClientAdapter = adapter;
    return ApiClient(baseUrl: 'http://test.local:30002', dio: dio);
  }

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
}

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
