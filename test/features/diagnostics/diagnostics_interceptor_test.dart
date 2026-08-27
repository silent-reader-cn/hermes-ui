import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/features/diagnostics/diagnostics_interceptor.dart';
import 'package:hermes_ui/features/diagnostics/diagnostics_models.dart';
import 'package:hermes_ui/features/diagnostics/diagnostics_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DiagnosticsService service;
  late DiagnosticsInterceptor interceptor;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    service = DiagnosticsService(customPrefs: prefs);
    await service.init(prefs: prefs);
    interceptor = DiagnosticsInterceptor(service: service);
  });

  group('DiagnosticsInterceptor', () {
    test('does not log when diagnostics is disabled', () {
      expect(service.enabled, false);

      final reqOptions = RequestOptions(
        path: '/api/sessions',
        method: 'GET',
        headers: {'Authorization': 'Bearer 12345'},
      );

      interceptor.onRequest(reqOptions, RequestInterceptorHandler());
      expect(service.logs, isEmpty);
    });

    test('logs request and response with sanitized headers and duration when enabled', () async {
      await service.setEnabled(true);

      final reqOptions = RequestOptions(
        path: '/api/sessions',
        method: 'POST',
        headers: {
          'Authorization': 'Bearer secret-key',
          'Cookie': 'sessionId=abc',
          'Accept': 'application/json',
        },
        data: {'password': 'pass', 'name': 'test'},
      );

      interceptor.onRequest(reqOptions, RequestInterceptorHandler());
      expect(service.logs.length, 1);
      final reqLog = service.logs.first;
      expect(reqLog.level, DiagnosticsLogLevel.verbose);
      expect(reqLog.tag, 'dio');
      expect(reqLog.message, contains('POST /api/sessions'));
      expect(reqLog.details?['headers'], {
        'Authorization': '***',
        'Cookie': '***',
        'Accept': 'application/json',
      });

      final response = Response<String>(
        requestOptions: reqOptions,
        statusCode: 200,
        data: '{"status": "ok"}',
      );

      interceptor.onResponse(response, ResponseInterceptorHandler());
      expect(service.logs.length, 2);
      final resLog = service.logs.last;
      expect(resLog.level, DiagnosticsLogLevel.info);
      expect(resLog.tag, 'dio');
      expect(resLog.message, contains('POST /api/sessions -> 200'));
      expect(resLog.details?['statusCode'], 200);
      expect(resLog.details?['responseBody'], '{"status": "ok"}');
    });

    test('logs error with errorKind and status code', () async {
      await service.setEnabled(true);

      final reqOptions = RequestOptions(
        path: '/api/chat',
        method: 'GET',
        headers: {'X-Api-Key': 'key-123'},
      );

      final dioError = DioException(
        requestOptions: reqOptions,
        type: DioExceptionType.connectionTimeout,
        message: 'Connection timed out',
      );

      runZonedGuarded(() {
        final handler = ErrorInterceptorHandler();
        interceptor.onError(dioError, handler);
      }, (e, s) {});

      expect(service.logs.length, 1);
      final errLog = service.logs.first;
      expect(errLog.level, DiagnosticsLogLevel.error);
      expect(errLog.tag, 'dio');
      expect(errLog.errorKind, 'connectionTimeout');
      expect(errLog.message, contains('ERROR: Connection timed out'));
      expect(errLog.details?['requestHeaders'], {'X-Api-Key': '***'});
    });
  });
}
