import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermex_flutter/app/theme/status_colors.dart';
import 'package:hermex_flutter/core/api/api_client.dart';
import 'package:hermex_flutter/core/api/sse_client.dart';
import 'package:hermex_flutter/core/connections/connection_providers.dart';
import 'package:hermex_flutter/core/providers/file_picker_provider.dart';
import 'package:hermex_flutter/core/utils/file_picker.dart';
import 'package:hermex_flutter/features/chat/chat_page.dart';
import 'package:hermex_flutter/features/chat/chat_providers.dart';
import 'package:hermex_flutter/features/chat/chat_server_api.dart';

void main() {
  group('Chat 附件上传链路 Widget 测试', () {
    testWidgets('成功路径：选择文件 → 调用 uploadFile → 本地消息入流 + 成功弹窗', (tester) async {
      final chatApi = _FakeChatApi();
      final picker = FakeFilePickerService(
        result: FilePickerResult(
          name: 'report.pdf',
          bytes: Uint8List.fromList([10, 20, 30]),
        ),
      );
      final adapter = _RecordingAdapter(
        responder: (_) =>
            ResponseBody.fromString('{"ok":true,"filename":"report.pdf"}', 200),
      );
      final client = _buildClient(adapter);

      await _pumpPage(
        tester,
        chatApi: chatApi,
        filePicker: picker,
        apiClient: client,
      );

      expect(find.byKey(const ValueKey('chat-attach-button')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('chat-attach-button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // 断言 uploadFile 真实请求被发出且参数正确
      expect(adapter.requests.length, 1);
      final req = adapter.requests.first;
      expect(req.uri.path, '/api/upload');
      final bodyStr = utf8.decode(req.data as Uint8List, allowMalformed: true);
      expect(bodyStr, contains('name="session_id"\r\n\r\ns1'));
      expect(bodyStr, contains('filename="report.pdf"'));

      // 断言聊天控制器追加了本地附件消息
      expect(chatApi.startChatCalls, 1);
      expect(chatApi.lastSentText, '📎 report.pdf');
      expect(find.text('📎 report.pdf'), findsOneWidget);

      // 断言成功提示对话框出现
      expect(find.text('上传成功'), findsOneWidget);
      expect(find.text('附件「report.pdf」已上传。'), findsOneWidget);

      // 关闭弹窗
      await tester.tap(find.text('好'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('上传成功'), findsNothing);

      await _unmount(tester);
    });

    testWidgets('取消路径：picker 返回 null → 无上传调用、无对话框', (tester) async {
      final chatApi = _FakeChatApi();
      final picker = FakeFilePickerService(result: null);
      final adapter = _RecordingAdapter(
        responder: (_) => ResponseBody.fromString('{"ok":true}', 200),
      );
      final client = _buildClient(adapter);

      await _pumpPage(
        tester,
        chatApi: chatApi,
        filePicker: picker,
        apiClient: client,
      );

      await tester.tap(find.byKey(const ValueKey('chat-attach-button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // 断言未调用 uploadFile，也未发送聊天消息
      expect(adapter.requests, isEmpty);
      expect(chatApi.startChatCalls, 0);

      // 断言无任何弹窗出现
      expect(find.byType(CupertinoAlertDialog), findsNothing);

      await _unmount(tester);
    });

    testWidgets('上传失败路径：uploadFile 抛错 → 失败对话框出现且包含错误信息与 statusRedText 样式', (
      tester,
    ) async {
      final chatApi = _FakeChatApi();
      final picker = FakeFilePickerService(
        result: FilePickerResult(
          name: 'large_image.png',
          bytes: Uint8List.fromList([1, 2, 3]),
        ),
      );
      final adapter = _RecordingAdapter(
        responder: (_) => ResponseBody.fromString('{"error":"服务器内部错误"}', 500),
      );
      final client = _buildClient(adapter);

      await _pumpPage(
        tester,
        chatApi: chatApi,
        filePicker: picker,
        apiClient: client,
      );

      await tester.tap(find.byKey(const ValueKey('chat-attach-button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // 断言请求发出但 chat 未发送本地消息
      expect(adapter.requests.length, 1);
      expect(chatApi.startChatCalls, 0);

      // 断言失败对话框展示，且内容文字为 statusRedText 颜色
      expect(find.text('上传失败'), findsOneWidget);
      final errorFinder = find.text('服务器返回 HTTP 500。');
      expect(errorFinder, findsOneWidget);
      final errorWidget = tester.widget<Text>(errorFinder);
      expect(errorWidget.style?.color, statusRedText);

      // 关闭弹窗
      await tester.tap(find.text('好'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('上传失败'), findsNothing);

      await _unmount(tester);
    });

    testWidgets('选择失败路径：picker 抛异常 → 选择失败对话框出现且内容为 statusRedText', (
      tester,
    ) async {
      final chatApi = _FakeChatApi();
      final picker = FakeFilePickerService(error: Exception('访问相册权限被拒绝'));
      final adapter = _RecordingAdapter(
        responder: (_) => ResponseBody.fromString('{"ok":true}', 200),
      );
      final client = _buildClient(adapter);

      await _pumpPage(
        tester,
        chatApi: chatApi,
        filePicker: picker,
        apiClient: client,
      );

      await tester.tap(find.byKey(const ValueKey('chat-attach-button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // 断言未调用 uploadFile，也未发送消息
      expect(adapter.requests, isEmpty);
      expect(chatApi.startChatCalls, 0);

      // 断言选择失败对话框展示
      expect(find.text('选择文件失败'), findsOneWidget);
      final errorFinder = find.textContaining('访问相册权限被拒绝');
      expect(errorFinder, findsOneWidget);
      final errorWidget = tester.widget<Text>(errorFinder);
      expect(errorWidget.style?.color, statusRedText);

      // 关闭弹窗
      await tester.tap(find.text('好'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('选择文件失败'), findsNothing);

      await _unmount(tester);
    });
  });
}

Future<void> _pumpPage(
  WidgetTester tester, {
  required _FakeChatApi chatApi,
  required FilePickerService filePicker,
  required ApiClient apiClient,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        chatApiProvider.overrideWithValue(chatApi),
        filePickerServiceProvider.overrideWithValue(filePicker),
        apiClientProvider.overrideWithValue(apiClient),
      ],
      child: const CupertinoApp(home: ChatPage(sessionId: 's1')),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

ApiClient _buildClient(_RecordingAdapter adapter) {
  final dio = Dio(
    BaseOptions(validateStatus: (_) => true, followRedirects: false),
  );
  dio.httpClientAdapter = adapter;
  final publicDio = Dio(
    BaseOptions(validateStatus: (_) => true, followRedirects: false),
  );
  publicDio.httpClientAdapter = adapter;
  return ApiClient(
    baseUrl: 'http://test.local:30002',
    dio: dio,
    publicMediaDio: publicDio,
  );
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

class _FakeChatApi implements ChatServerApi {
  Map<String, Object?>? sessionResult;
  int startChatCalls = 0;
  String? lastSentText;

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
    startChatCalls++;
    lastSentText = message;
    return {'stream_id': 'stream-1', 'session_id': sessionId};
  }

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
  Future<Object?> steerChat({
    required String sessionId,
    required String text,
  }) async => {'accepted': true};

  @override
  Future<Object?> cancelChat(String streamId) async => {'ok': true};

  @override
  Future<Object?> chatStreamStatus(String streamId) async => {
    'active': false,
    'replay_available': false,
  };

  @override
  Future<Object?> respondApproval({
    required String sessionId,
    required String choice,
    String? approvalId,
  }) async => {'ok': true};

  @override
  Future<Object?> respondClarification({
    required String sessionId,
    required String response,
    String? clarifyId,
  }) async => {'ok': true};

  @override
  Future<Object?> renameSession({
    required String sessionId,
    required String title,
  }) async => {'ok': true};

  @override
  Future<Object?> pinSession({
    required String sessionId,
    required bool pinned,
  }) async => {'ok': true};

  @override
  Future<Object?> archiveSession({
    required String sessionId,
    required bool archived,
  }) async => {'ok': true};

  @override
  Future<Object?> deleteSession(String sessionId) async => {'ok': true};

  @override
  Future<Object?> branchSession(String sessionId, {int? keepCount}) async => {
    'session_id': 'branch-$sessionId',
    'parent_session_id': sessionId,
  };

  @override
  Future<Object?> truncateSession({
    required String sessionId,
    required int keepCount,
  }) async => {'ok': true};

  @override
  Future<Object?> compressSession({
    required String sessionId,
    String? focusTopic,
  }) async => {'ok': true};

  @override
  Future<Object?> undoSession(String sessionId) async => {'ok': true};

  @override
  Future<Object?> retrySession(String sessionId) async => {'ok': true};

  @override
  Future<Object?> updateSession({
    required String sessionId,
    String? workspace,
    String? model,
    String? modelProvider,
  }) async => {'ok': true};

  @override
  Future<Object?> getYolo(String sessionId) async => {
    'ok': true,
    'yolo_enabled': false,
  };

  @override
  Future<Object?> setYolo({
    required String sessionId,
    required bool enabled,
  }) async => {'ok': true, 'yolo_enabled': enabled};

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
