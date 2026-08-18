import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermex_flutter/core/api/api_client.dart';
import 'package:hermex_flutter/core/api/api_client_workspace.dart';
import 'package:hermex_flutter/core/api/api_exception.dart';
import 'package:hermex_flutter/core/api/custom_header.dart';
import 'package:hermex_flutter/core/api/endpoints.dart';

void main() {
  const base = 'http://hermes.local:8787';

  ApiClient buildClient(
    _RecordingAdapter adapter, {
    List<CustomHeader> headers = const [],
  }) {
    final dio = Dio(
      BaseOptions(validateStatus: (_) => true, followRedirects: false),
    );
    dio.httpClientAdapter = adapter;
    final publicDio = Dio(
      BaseOptions(validateStatus: (_) => true, followRedirects: false),
    );
    publicDio.httpClientAdapter = adapter;
    return ApiClient(
      baseUrl: base,
      dio: dio,
      publicMediaDio: publicDio,
      initialHeaders: headers,
    );
  }

  group('错误归一化（APIError → ApiException）', () {
    test('401 → UnauthorizedException', () async {
      final adapter = _RecordingAdapter(
        responder: (_) => ResponseBody.fromString('{"error":"no"}', 401),
      );
      final client = buildClient(adapter);
      await expectLater(
        client.sendJson(Endpoint.health),
        throwsA(isA<UnauthorizedException>()),
      );
    });

    test('409 + stale → HttpException.indicatesExpiredPendingPrompt', () async {
      final adapter = _RecordingAdapter(
        responder: (_) => ResponseBody.fromString('{"stale":true}', 409),
      );
      final client = buildClient(adapter);
      await expectLater(
        client.sendJson(
          Endpoint.approvalRespond,
          method: 'POST',
          body: const {},
        ),
        throwsA(
          isA<HttpException>()
              .having((e) => e.statusCode, 'statusCode', 409)
              .having((e) => e.indicatesExpiredPendingPrompt, 'stale', isTrue),
        ),
      );
    });

    test('404 stream not found → indicatesMissingStream', () async {
      final adapter = _RecordingAdapter(
        responder: (_) =>
            ResponseBody.fromString('{"error":"stream not found"}', 404),
      );
      final client = buildClient(adapter);
      await expectLater(
        client.sendJson(Endpoint.chatStreamStatus('st1')),
        throwsA(
          isA<HttpException>().having(
            (e) => e.indicatesMissingStream,
            'missing',
            isTrue,
          ),
        ),
      );
    });

    test('500 + {error} → serverMessage 透传', () async {
      final adapter = _RecordingAdapter(
        responder: (_) => ResponseBody.fromString('{"error":"boom"}', 500),
      );
      final client = buildClient(adapter);
      await expectLater(
        client.sendJson(Endpoint.health),
        throwsA(
          isA<HttpException>()
              .having((e) => e.serverMessage, 'serverMessage', 'boom')
              .having((e) => e.statusCode, 'statusCode', 500),
        ),
      );
    });

    test(
      '超时（DioException receiveTimeout）→ NetworkException.timedOut',
      () async {
        final adapter = _RecordingAdapter(
          responder: (_) => throw DioException(
            requestOptions: RequestOptions(path: '/health'),
            type: DioExceptionType.receiveTimeout,
          ),
        );
        final client = buildClient(adapter);
        await expectLater(
          client.sendJson(Endpoint.health),
          throwsA(
            isA<NetworkException>().having(
              (e) => e.kind,
              'kind',
              NetworkExceptionKind.timedOut,
            ),
          ),
        );
      },
    );

    test('取消 → NetworkException.cancelled', () async {
      final adapter = _RecordingAdapter(
        responder: (_) => throw DioException(
          requestOptions: RequestOptions(path: '/health'),
          type: DioExceptionType.cancel,
        ),
      );
      final client = buildClient(adapter);
      await expectLater(
        client.sendJson(Endpoint.health),
        throwsA(
          isA<NetworkException>().having(
            (e) => e.kind,
            'kind',
            NetworkExceptionKind.cancelled,
          ),
        ),
      );
    });

    test('连接错误（SocketException DNS）→ cannotFindHost', () async {
      final adapter = _RecordingAdapter(
        responder: (_) => throw DioException(
          requestOptions: RequestOptions(path: '/health'),
          type: DioExceptionType.connectionError,
          error: const SocketException(
            'Failed host lookup: hermes.local',
            osError: OSError('Failed host lookup', 11001),
          ),
        ),
      );
      final client = buildClient(adapter);
      await expectLater(
        client.sendJson(Endpoint.health),
        throwsA(
          isA<NetworkException>().having(
            (e) => e.kind,
            'kind',
            NetworkExceptionKind.cannotFindHost,
          ),
        ),
      );
    });
  });

  group('sendJson / sendData 解析', () {
    test('2xx JSON → 解码后的 Map', () async {
      final adapter = _RecordingAdapter(
        responder: (_) => ResponseBody.fromString('{"status":"ok","n":3}', 200),
      );
      final client = buildClient(adapter);
      final json = await client.sendJson(Endpoint.health);
      expect(json, {'status': 'ok', 'n': 3});
    });

    test('2xx 空 body → null', () async {
      final adapter = _RecordingAdapter(
        responder: (_) => ResponseBody.fromString('', 200),
      );
      final client = buildClient(adapter);
      expect(await client.sendJson(Endpoint.health), isNull);
    });

    test('2xx 非 JSON → DecodingException', () async {
      final adapter = _RecordingAdapter(
        responder: (_) => ResponseBody.fromString('<html>oops', 200),
      );
      final client = buildClient(adapter);
      await expectLater(
        client.sendJson(Endpoint.health),
        throwsA(isA<DecodingException>()),
      );
    });

    test('sendData 返回原始字节；Accept 可覆盖为 */*', () async {
      final adapter = _RecordingAdapter(
        responder: (_) => ResponseBody.fromString('raw-bytes', 200),
      );
      final client = buildClient(adapter);
      final data = await client.sendData(
        Endpoint.rawFile(sessionId: 's1', path: 'a.txt'),
        accept: '*/*',
      );
      expect(String.fromCharCodes(data), 'raw-bytes');
      expect(adapter.requests.single.headers['Accept'], '*/*');
    });

    test('sendDataReturningResponse 携带响应头（Content-Disposition）', () async {
      final adapter = _RecordingAdapter(
        responder: (_) => ResponseBody.fromString(
          'html',
          200,
          headers: {
            'content-disposition': ['attachment; filename="hermes-s1.html"'],
          },
        ),
      );
      final client = buildClient(adapter);
      final response = await client.sendDataReturningResponse(
        Endpoint.exportSession(sessionId: 's1', format: 'html'),
        accept: '*/*',
      );
      expect(
        response.headers.value('content-disposition'),
        contains('hermes-s1.html'),
      );
      expect(String.fromCharCodes(response.data), 'html');
    });
  });

  group('自定义 header 注入（内置头恒胜）', () {
    test('非冲突自定义头注入，冲突时内置头胜出', () async {
      final adapter = _RecordingAdapter(
        responder: (_) => ResponseBody.fromString('{}', 200),
      );
      final client = buildClient(
        adapter,
        headers: const [
          CustomHeader(name: 'Accept', value: 'application/json'), // 与内置冲突
          CustomHeader(name: 'X-Api-Key', value: 'k-123'),
          CustomHeader(
            name: ' Authorization ',
            value: 'Bearer t',
          ), // sanitize 后注入
          CustomHeader(name: 'Bad\nName', value: 'x'), // 非法名跳过
          CustomHeader(name: 'ok', value: 'has\nnewline'), // 换行值跳过
          CustomHeader(name: '  ', value: 'blank'), // 空名跳过
        ],
      );
      await client.sendJson(Endpoint.health);

      final headers = adapter.requests.single.headers;
      expect(headers['Accept'], 'application/json');
      expect(headers['X-Api-Key'], 'k-123');
      expect(headers['Authorization'], 'Bearer t');
      expect(headers.containsKey('Bad\nName'), isFalse);
      expect(headers.containsKey('ok'), isFalse);
      expect(headers.containsKey('  '), isFalse);
      expect(headers['Cache-Control'], 'no-cache');
    });

    test('改 headerStore 即时生效（不重建 client）', () async {
      final adapter = _RecordingAdapter(
        responder: (_) => ResponseBody.fromString('{}', 200),
      );
      final client = buildClient(adapter);
      await client.sendJson(Endpoint.health);
      client.headerStore.replace(const [
        CustomHeader(name: 'X-Token', value: 'v2'),
      ]);
      await client.sendJson(Endpoint.health);

      expect(adapter.requests.first.headers.containsKey('X-Token'), isFalse);
      expect(adapter.requests.last.headers['X-Token'], 'v2');
    });
  });

  group('cookie 会话', () {
    test('登录响应 Set-Cookie 落库，后续请求自动携带', () async {
      var call = 0;
      final adapter = _RecordingAdapter(
        responder: (_) {
          call++;
          if (call == 1) {
            return ResponseBody.fromString(
              '{"ok":true}',
              200,
              headers: {
                'set-cookie': ['sid=abc123; Path=/; HttpOnly'],
              },
            );
          }
          return ResponseBody.fromString('{"status":"ok"}', 200);
        },
      );
      final client = buildClient(adapter);

      await client.sendJson(
        Endpoint.login,
        method: 'POST',
        body: {'password': 'p'},
      );
      expect(client.cookieStore.length, 1);
      await client.sendJson(Endpoint.health);

      expect(adapter.requests[0].headers.containsKey('Cookie'), isFalse);
      expect(adapter.requests[1].headers['Cookie'], 'sid=abc123');
    });

    test('Domain/Path 作用域：其他 host 不携带', () async {
      final client = buildClient(
        _RecordingAdapter(responder: (_) => ResponseBody.fromString('{}', 200)),
      );
      client.cookieStore.setCookies(
        Uri.parse('http://hermes.local:8787/api/auth/login'),
        ['sid=abc; Path=/; Domain=hermes.local'],
      );
      expect(
        client.cookieStore.cookieHeaderFor(
          Uri.parse('http://hermes.local:8787/api/health'),
        ),
        'sid=abc',
      );
      expect(
        client.cookieStore.cookieHeaderFor(
          Uri.parse('http://other.local:8787/api/health'),
        ),
        isNull,
      );
    });
  });

  group('同域判定（scheme + host + 归一化端口）', () {
    test('默认端口归一化', () {
      final baseUri = Uri.parse('http://hermes.local');
      expect(
        ApiClient.isSameOriginUri(
          Uri.parse('http://hermes.local:80/x'),
          baseUri,
        ),
        isTrue,
      );
      expect(
        ApiClient.isSameOriginUri(Uri.parse('http://hermes.local/x'), baseUri),
        isTrue,
      );
      expect(
        ApiClient.isSameOriginUri(Uri.parse('https://hermes.local/x'), baseUri),
        isFalse,
      );
      expect(
        ApiClient.isSameOriginUri(
          Uri.parse('http://hermes.local:8787/x'),
          baseUri,
        ),
        isFalse,
      );
      expect(
        ApiClient.isSameOriginUri(Uri.parse('http://other.local/x'), baseUri),
        isFalse,
      );
    });

    test('https 默认 443', () {
      final baseUri = Uri.parse('https://hermes.local:443');
      expect(
        ApiClient.isSameOriginUri(Uri.parse('https://hermes.local/x'), baseUri),
        isTrue,
      );
    });
  });

  group('重定向处理（自定义头跨域剥离）', () {
    test('同域重定向保留自定义头', () async {
      var call = 0;
      final adapter = _RecordingAdapter(
        responder: (_) {
          call++;
          if (call == 1) {
            return ResponseBody.fromString(
              '',
              302,
              headers: {
                'location': ['http://hermes.local:8787/api/health'],
              },
            );
          }
          return ResponseBody.fromString('{"ok":true}', 200);
        },
      );
      final client = buildClient(
        adapter,
        headers: const [CustomHeader(name: 'X-Api-Key', value: 'k-123')],
      );

      await client.sendJson(Endpoint.health);
      expect(adapter.requests, hasLength(2));
      expect(adapter.requests[0].headers['X-Api-Key'], 'k-123');
      expect(adapter.requests[1].headers['X-Api-Key'], 'k-123'); // 保留
    });

    test('跨域重定向剥离全部自定义头（防泄密，#277）', () async {
      var call = 0;
      final adapter = _RecordingAdapter(
        responder: (_) {
          call++;
          if (call == 1) {
            return ResponseBody.fromString(
              '',
              302,
              headers: {
                'location': ['http://evil.example:9999/api/health'],
              },
            );
          }
          return ResponseBody.fromString('{"ok":true}', 200);
        },
      );
      final client = buildClient(
        adapter,
        headers: const [CustomHeader(name: 'X-Api-Key', value: 'secret')],
      );

      await client.sendJson(Endpoint.health);
      expect(adapter.requests, hasLength(2));
      expect(adapter.requests[0].uri.host, 'hermes.local');
      expect(adapter.requests[0].headers['X-Api-Key'], 'secret');
      expect(adapter.requests[1].uri.host, 'evil.example');
      expect(
        adapter.requests[1].headers.containsKey('X-Api-Key'),
        isFalse,
      ); // 剥离
      // 内置头仍在（裸客户端也要 Accept）
      expect(adapter.requests[1].headers['Accept'], 'application/json');
    });

    test('相对 Location 按当前 URL 解析', () async {
      var call = 0;
      final adapter = _RecordingAdapter(
        responder: (_) {
          call++;
          if (call == 1) {
            return ResponseBody.fromString(
              '',
              301,
              headers: {
                'location': ['/api/auth/status'],
              },
            );
          }
          return ResponseBody.fromString('{"auth_enabled":true}', 200);
        },
      );
      final client = buildClient(adapter);
      await client.sendJson(Endpoint.health);
      expect(adapter.requests[1].uri.toString(), '$base/api/auth/status');
    });

    test('重定向超过 maxRedirects → HttpException', () async {
      final adapter = _RecordingAdapter(
        responder: (_) => ResponseBody.fromString(
          '',
          302,
          headers: {
            'location': ['http://hermes.local:8787/api/health'],
          },
        ),
      );
      final client = buildClient(adapter);
      await expectLater(
        client.sendJson(Endpoint.health),
        throwsA(isA<HttpException>()),
      );
    });
  });

  group('downloadData（外部媒体同域/跨域分流）', () {
    test('同域走主客户端（带自定义头）', () async {
      final adapter = _RecordingAdapter(
        responder: (_) => ResponseBody.fromString('img', 200),
      );
      final client = buildClient(
        adapter,
        headers: const [CustomHeader(name: 'X-Api-Key', value: 'k')],
      );
      final data = await client.downloadData(
        Uri.parse('$base/api/media?session_id=s1&path=a.png'),
      );
      expect(String.fromCharCodes(data), 'img');
      expect(adapter.requests.single.headers['X-Api-Key'], 'k');
    });

    test('跨域走裸客户端（无自定义头、无 cookie）', () async {
      final adapter = _RecordingAdapter(
        responder: (_) => ResponseBody.fromString('ext', 200),
      );
      final client = buildClient(
        adapter,
        headers: const [CustomHeader(name: 'X-Api-Key', value: 'k')],
      );
      client.cookieStore.setCookies(Uri.parse('http://hermes.local:8787/x'), [
        'sid=abc',
      ]);
      final data = await client.downloadData(
        Uri.parse('https://cdn.example.com/img.png'),
      );
      expect(String.fromCharCodes(data), 'ext');
      final headers = adapter.requests.single.headers;
      expect(headers.containsKey('X-Api-Key'), isFalse);
      expect(headers.containsKey('Cookie'), isFalse);
      expect(headers['Accept'], '*/*');
    });
  });

  group('workspace 文件操作（POST 路径与 body）', () {
    Map<String, Object?> bodyOf(RequestOptions req) {
      final raw = req.data;
      final text = raw is String ? raw : utf8.decode(raw as List<int>);
      return jsonDecode(text) as Map<String, Object?>;
    }

    test('deleteFile → POST /api/file/delete，body 带 recursive=true', () async {
      final adapter = _RecordingAdapter(
        responder: (_) =>
            ResponseBody.fromString('{"ok":true,"path":"a.txt"}', 200),
      );
      final client = buildClient(adapter);
      await client.deleteFile(sessionId: 's1', path: 'a.txt', recursive: true);
      final req = adapter.requests.single;
      expect(req.method, 'POST');
      expect(req.uri.toString(), '$base/api/file/delete');
      final body = bodyOf(req);
      expect(body['session_id'], 's1');
      expect(body['path'], 'a.txt');
      expect(body['recursive'], true);
    });

    test('deleteFile 目录默认 recursive=false（文件删除不递归）', () async {
      final adapter = _RecordingAdapter(
        responder: (_) =>
            ResponseBody.fromString('{"ok":true,"path":"a.txt"}', 200),
      );
      final client = buildClient(adapter);
      await client.deleteFile(sessionId: 's1', path: 'a.txt');
      expect(bodyOf(adapter.requests.single)['recursive'], false);
    });

    test('renameFile → POST /api/file/rename，body 带 new_name', () async {
      final adapter = _RecordingAdapter(
        responder: (_) => ResponseBody.fromString(
          '{"ok":true,"old_path":"a.txt","new_path":"b.txt"}',
          200,
        ),
      );
      final client = buildClient(adapter);
      final json = await client.renameFile(
        sessionId: 's1',
        path: 'a.txt',
        newName: 'b.txt',
      );
      final req = adapter.requests.single;
      expect(req.method, 'POST');
      expect(req.uri.toString(), '$base/api/file/rename');
      final body = bodyOf(req);
      expect(body['session_id'], 's1');
      expect(body['path'], 'a.txt');
      expect(body['new_name'], 'b.txt');
      expect((json as Map<String, Object?>)['new_path'], 'b.txt');
    });
  });
}

/// 记录请求的假 HttpClientAdapter。
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
