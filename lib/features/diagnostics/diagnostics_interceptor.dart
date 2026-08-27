import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'diagnostics_models.dart';
import 'diagnostics_service.dart';

/// Dio 网络诊断拦截器（方法/路径/状态码/耗时/Headers脱敏/Body截断/ErrorKind）。
class DiagnosticsInterceptor extends Interceptor {
  DiagnosticsInterceptor({DiagnosticsService? service})
      : _service = service ?? DiagnosticsService.instance;

  final DiagnosticsService _service;

  static const String _startTimeKey = 'diagnostics_start_time';
  static const int maxResponseBodyLength = 3000;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (_service.enabled) {
      options.extra[_startTimeKey] = DateTime.now().millisecondsSinceEpoch;
      final sanitizedHeaders = sanitizeHeaders(options.headers);
      final sanitizedData = _sanitizeRequestData(options.data);
      _service.log(
        level: DiagnosticsLogLevel.verbose,
        tag: 'dio',
        message: '${options.method} ${options.uri}',
        details: {
          'type': 'request',
          'method': options.method,
          'url': options.uri.toString(),
          'headers': sanitizedHeaders,
          'data': ?sanitizedData,
        },
      );
    }
    handler.next(options);
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    if (_service.enabled) {
      final startTime = response.requestOptions.extra[_startTimeKey] as int?;
      final durationMs = startTime != null
          ? DateTime.now().millisecondsSinceEpoch - startTime
          : null;
      final statusCode = response.statusCode ?? -1;
      final isError = statusCode >= 400;
      final level =
          isError ? DiagnosticsLogLevel.warn : DiagnosticsLogLevel.info;

      final sanitizedHeaders = sanitizeHeaders(
        response.requestOptions.headers,
      );
      final responsePreview = truncateResponseBody(
        response.data,
        maxResponseBodyLength,
      );

      _service.log(
        level: level,
        tag: 'dio',
        message:
            '${response.requestOptions.method} ${response.requestOptions.uri.path} -> $statusCode',
        durationMs: durationMs,
        details: {
          'type': 'response',
          'method': response.requestOptions.method,
          'url': response.requestOptions.uri.toString(),
          'statusCode': statusCode,
          'durationMs': ?durationMs,
          'requestHeaders': sanitizedHeaders,
          'responseBody': ?responsePreview,
        },
      );
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (_service.enabled) {
      final startTime = err.requestOptions.extra[_startTimeKey] as int?;
      final durationMs = startTime != null
          ? DateTime.now().millisecondsSinceEpoch - startTime
          : null;
      final statusCode = err.response?.statusCode;
      final sanitizedHeaders = sanitizeHeaders(err.requestOptions.headers);
      final responsePreview = truncateResponseBody(
        err.response?.data,
        maxResponseBodyLength,
      );

      _service.log(
        level: DiagnosticsLogLevel.error,
        tag: 'dio',
        message:
            '${err.requestOptions.method} ${err.requestOptions.uri.path} -> ERROR: ${err.message ?? err.type.name}',
        durationMs: durationMs,
        errorKind: err.type.name,
        details: {
          'type': 'error',
          'method': err.requestOptions.method,
          'url': err.requestOptions.uri.toString(),
          'statusCode': ?statusCode,
          'durationMs': ?durationMs,
          'errorType': err.type.name,
          'errorMessage': err.message,
          'requestHeaders': sanitizedHeaders,
          'responseBody': ?responsePreview,
        },
      );
    }
    handler.next(err);
  }

  Object? _sanitizeRequestData(Object? data) {
    if (data == null) return null;
    if (data is Uint8List) {
      return '<binary ${data.length} bytes>';
    }
    if (data is FormData) {
      return '<FormData fields=${data.fields.length} files=${data.files.length}>';
    }
    return sanitizeDataPayload(data);
  }
}
