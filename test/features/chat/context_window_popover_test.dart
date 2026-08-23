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

class _MockHttpClientAdapter implements HttpClientAdapter {
  _MockHttpClientAdapter(this.handler);

  final ResponseBody Function(RequestOptions options) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ApiClient _buildMockApiClient({
  required ResponseBody Function(RequestOptions options) handler,
}) {
  final dio = Dio(
    BaseOptions(validateStatus: (_) => true, followRedirects: false),
  );
  dio.httpClientAdapter = _MockHttpClientAdapter(handler);
  return ApiClient(
    baseUrl: 'http://test.local:30002',
    dio: dio,
  );
}

void main() {
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
}
