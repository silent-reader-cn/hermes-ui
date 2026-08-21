import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermex_flutter/core/api/api_client.dart';
import 'package:hermex_flutter/core/api/api_exception.dart';
import 'package:hermex_flutter/features/workspace_manager/workspace_manager_api.dart';

/// 工作区管理注册表域生产包装层（[WorkspaceManagerApiClient]）回归测试。
///
/// 用真实 `ApiClient`（Dio + 假 adapter）走全链路（HTTP → ApiClient 扩展解码
/// → 包装层），验证字段透传与端点路径/参数，覆盖「双层解析陷阱」回归。
void main() {
  const base = 'http://hermes.local:30002';

  (ApiClient, _SequenceAdapter) buildClient(List<_Stub> stubs) {
    final adapter = _SequenceAdapter(stubs);
    final dio = Dio(
      BaseOptions(validateStatus: (_) => true, followRedirects: false),
    );
    dio.httpClientAdapter = adapter;
    final publicDio = Dio(
      BaseOptions(validateStatus: (_) => true, followRedirects: false),
    );
    publicDio.httpClientAdapter = adapter;
    return (
      ApiClient(baseUrl: base, dio: dio, publicMediaDio: publicDio),
      adapter,
    );
  }

  group('WorkspaceManagerApiClient', () {
    test(
      'fetchWorkspaces 透传解码 workspaces/last/terminalRemoteBackend',
      () async {
        final (client, adapter) = buildClient([
          _json({
            'workspaces': [
              {'path': 'C:\\Users\\Admin\\workspace', 'name': 'Home'},
              {'path': 'D:\\projects\\hermex-flutter', 'name': 'HERMEX'},
            ],
            'last': 'D:\\projects\\hermex-flutter',
            'terminal_remote_backend': true,
          }),
        ]);
        final api = WorkspaceManagerApiClient(client);

        final response = await api.fetchWorkspaces();

        expect(adapter.requests.single.uri.path, '/api/workspaces');
        expect(response.workspaces, hasLength(2));
        expect(response.workspaces!.first.path, r'C:\Users\Admin\workspace');
        expect(response.workspaces!.first.name, 'Home');
        expect(response.last, r'D:\projects\hermex-flutter');
        expect(response.terminalRemoteBackend, isTrue);
      },
    );

    test(
      'addWorkspace 发 POST /api/workspaces/add 且 body 含 path/name/create',
      () async {
        final (client, adapter) = buildClient([
          _json({
            'ok': true,
            'workspaces': [
              {'path': '/home/u/proj', 'name': 'proj'},
            ],
          }),
        ]);
        final api = WorkspaceManagerApiClient(client);

        final response = await api.addWorkspace(
          path: '/home/u/proj',
          name: 'proj',
          create: true,
        );

        final request = adapter.requests.single;
        expect(request.method, 'POST');
        expect(request.uri.path, '/api/workspaces/add');
        final body = jsonDecode(request.data as String) as Map<String, dynamic>;
        expect(body['path'], '/home/u/proj');
        expect(body['name'], 'proj');
        expect(body['create'], isTrue);
        expect(response.ok, isTrue);
        expect(response.workspaces!.single.name, 'proj');
      },
    );

    test('rename/remove 发对应端点', () async {
      final (client, adapter) = buildClient([
        _json({'ok': true, 'workspaces': []}),
        _json({'ok': true, 'workspaces': []}),
      ]);
      final api = WorkspaceManagerApiClient(client);

      await api.renameWorkspace(path: '/a', name: 'A');
      await api.removeWorkspace('/a');

      expect(adapter.requests[0].uri.path, '/api/workspaces/rename');
      expect(adapter.requests[1].uri.path, '/api/workspaces/remove');
      final renameBody = jsonDecode(
        adapter.requests[0].data as String,
      ) as Map<String, dynamic>;
      expect(renameBody, {'path': '/a', 'name': 'A'});
      final removeBody = jsonDecode(
        adapter.requests[1].data as String,
      ) as Map<String, dynamic>;
      expect(removeBody, {'path': '/a'});
    });

    test('findSessionIdForWorkspace：字面匹配 + Windows 规范化匹配 + 无匹配 null', () async {
      final (client, adapter) = buildClient([
        _json({
          'sessions': [
            {
              'session_id': 's1',
              'title': 'Home',
              'workspace': r'D:\Projects\Hermex-Flutter',
            },
            {'session_id': 's2', 'title': 'Other', 'workspace': '/tmp/x'},
            {'session_id': 's3', 'title': 'No workspace'},
          ],
        }),
      ]);
      final api = WorkspaceManagerApiClient(client);

      // 字面匹配（服务器原样回传的路径）
      expect(
        await api.findSessionIdForWorkspace(r'D:\Projects\Hermex-Flutter'),
        's1',
      );
      // 规范化匹配：斜杠/小写等价
      expect(
        await api.findSessionIdForWorkspace('d:/projects/hermex-flutter'),
        's1',
      );
      // 无匹配
      expect(await api.findSessionIdForWorkspace('/nope'), isNull);
      expect(adapter.requests, hasLength(3));
      expect(
        adapter.requests.every((r) => r.uri.path == '/api/sessions'),
        isTrue,
      );
    });

    test('裸 503（空 body）自动重试一次；JSON 503 不重试', () async {
      // 首次裸 503（worker 池过载，server.py:124-129）→ 重试 → 200
      final (client, adapter) = buildClient([
        _text(503, ''),
        _json({
          'workspaces': [
            {'path': '/a', 'name': 'A'},
          ],
        }),
      ]);
      final api = WorkspaceManagerApiClient(client);

      final response = await api.fetchWorkspaces();

      expect(adapter.requests, hasLength(2));
      expect(response.workspaces!.single.name, 'A');

      // JSON body 的 503（如 office 依赖缺失）不重试，直接抛 HttpException
      final (client2, adapter2) = buildClient([
        _json({'error': 'office deps missing'}, status: 503),
      ]);
      final api2 = WorkspaceManagerApiClient(client2);
      await expectLater(
        api2.fetchWorkspaces(),
        throwsA(
          isA<HttpException>().having((e) => e.statusCode, 'statusCode', 503),
        ),
      );
      expect(adapter2.requests, hasLength(1));
    });
  });
}

/// 单次响应 stub。
class _Stub {
  _Stub(this.statusCode, this.body, {required this.contentType});

  final int statusCode;
  final String body;
  final String? contentType;
}

_Stub _json(Map<String, Object?> body, {int status = 200}) =>
    _Stub(status, jsonEncode(body), contentType: 'application/json');

_Stub _text(int status, String body) =>
    _Stub(status, body, contentType: 'application/json');

/// 按队列顺序回放响应的假 HttpClientAdapter（记录请求）。
class _SequenceAdapter implements HttpClientAdapter {
  _SequenceAdapter(List<_Stub> stubs) : _queue = List.of(stubs);

  final List<_Stub> _queue;
  _Stub? _lastStub;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final stub = _queue.isNotEmpty ? _queue.removeAt(0) : _lastStub!;
    _lastStub = stub;
    return ResponseBody.fromString(
      stub.body,
      stub.statusCode,
      headers: {
        'content-type': [stub.contentType ?? 'application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
