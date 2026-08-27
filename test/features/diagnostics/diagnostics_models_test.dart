import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/features/diagnostics/diagnostics_models.dart';

void main() {
  group('DiagnosticsLogLevel', () {
    test('fromString parses correctly for all variants', () {
      expect(DiagnosticsLogLevel.fromString('v'), DiagnosticsLogLevel.verbose);
      expect(
        DiagnosticsLogLevel.fromString('VERBOSE'),
        DiagnosticsLogLevel.verbose,
      );
      expect(DiagnosticsLogLevel.fromString('d'), DiagnosticsLogLevel.debug);
      expect(
        DiagnosticsLogLevel.fromString('debug'),
        DiagnosticsLogLevel.debug,
      );
      expect(DiagnosticsLogLevel.fromString('i'), DiagnosticsLogLevel.info);
      expect(DiagnosticsLogLevel.fromString('INFO'), DiagnosticsLogLevel.info);
      expect(DiagnosticsLogLevel.fromString('w'), DiagnosticsLogLevel.warn);
      expect(
        DiagnosticsLogLevel.fromString('warning'),
        DiagnosticsLogLevel.warn,
      );
      expect(DiagnosticsLogLevel.fromString('e'), DiagnosticsLogLevel.error);
      expect(
        DiagnosticsLogLevel.fromString('error'),
        DiagnosticsLogLevel.error,
      );
      expect(DiagnosticsLogLevel.fromString(null), DiagnosticsLogLevel.info);
      expect(
        DiagnosticsLogLevel.fromString('unknown'),
        DiagnosticsLogLevel.info,
      );
    });

    test('codes and labels are defined', () {
      expect(DiagnosticsLogLevel.verbose.code, 'V');
      expect(DiagnosticsLogLevel.verbose.label, 'VERBOSE');
      expect(DiagnosticsLogLevel.error.code, 'E');
      expect(DiagnosticsLogLevel.error.label, 'ERROR');
    });
  });

  group('DiagnosticsLogEntry', () {
    test('serialization and deserialization roundtrip', () {
      final now = DateTime.utc(2026, 8, 28, 12, 30, 45, 123);
      final entry = DiagnosticsLogEntry(
        id: 'test-123',
        timestamp: now,
        level: DiagnosticsLogLevel.warn,
        tag: 'dio',
        message: 'GET /api/status -> 404',
        details: {'path': '/api/status', 'code': 404},
        durationMs: 150,
        errorKind: 'Http404',
      );

      final json = entry.toJson();
      expect(json['id'], 'test-123');
      expect(json['level'], 'warn');
      expect(json['tag'], 'dio');
      expect(json['duration_ms'], 150);
      expect(json['error_kind'], 'Http404');

      final deserialized = DiagnosticsLogEntry.fromJson(json);
      expect(deserialized.id, entry.id);
      expect(deserialized.level, entry.level);
      expect(deserialized.tag, entry.tag);
      expect(deserialized.message, entry.message);
      expect(deserialized.durationMs, entry.durationMs);
      expect(deserialized.errorKind, entry.errorKind);
      expect(deserialized.details?['code'], 404);
    });

    test('toExportString formats accurately', () {
      final now = DateTime(2026, 8, 28, 10, 15, 30, 500);
      final entry = DiagnosticsLogEntry(
        id: 'test-exp',
        timestamp: now,
        level: DiagnosticsLogLevel.info,
        tag: 'sse',
        message: 'done',
        durationMs: 200,
        details: {'tokens': 100},
      );

      final export = entry.toExportString();
      expect(export, contains('[2026-08-28 10:15:30.500]'));
      expect(export, contains('[INFO   ]'));
      expect(export, contains('[sse] done (200ms)'));
      expect(export, contains('Details:'));
      expect(export, contains('"tokens": 100'));
    });
  });

  group('Sanitization and Truncation', () {
    test('sanitizeHeaders masks Authorization, Cookie, and API keys', () {
      final headers = <String, dynamic>{
        'Accept': 'application/json',
        'Authorization': 'Bearer secret-token-123',
        'Cookie': 'session=abc; other=def',
        'Set-Cookie': 'auth=xyz',
        'X-Api-Key': 'my-super-secret-key',
        'custom-header': 'safe-value',
        'auth-token': 'token-value',
      };

      final sanitized = sanitizeHeaders(headers);
      expect(sanitized['Accept'], 'application/json');
      expect(sanitized['Authorization'], '***');
      expect(sanitized['Cookie'], '***');
      expect(sanitized['Set-Cookie'], '***');
      expect(sanitized['X-Api-Key'], '***');
      expect(sanitized['auth-token'], '***');
      expect(sanitized['custom-header'], 'safe-value');
    });

    test('sanitizeDataPayload recursively redacts sensitive fields', () {
      final data = {
        'username': 'admin',
        'password': 'superSecretPassword!',
        'nested': {
          'api_key': 'key-999',
          'public_info': 'hello',
        },
        'list': [
          {'token': 'abc', 'value': 42},
        ],
      };

      final sanitized = sanitizeDataPayload(data) as Map<String, Object?>;
      expect(sanitized['username'], 'admin');
      expect(sanitized['password'], '***');
      final nested = sanitized['nested'] as Map<String, Object?>;
      expect(nested['api_key'], '***');
      expect(nested['public_info'], 'hello');
      final list = sanitized['list'] as List;
      final firstItem = list[0] as Map<String, Object?>;
      expect(firstItem['token'], '***');
      expect(firstItem['value'], 42);
    });

    test('truncateResponseBody truncates strings over 3000 chars', () {
      final shortBody = 'Short response text';
      expect(truncateResponseBody(shortBody), 'Short response text');

      final longBody = 'A' * 3500;
      final truncated = truncateResponseBody(longBody, 3000);
      expect(truncated, startsWith('A' * 3000));
      expect(truncated, contains('... [truncated 500 chars]'));
      expect(truncated!.length, lessThan(3100));
    });

    test('truncateResponseBody handles Uint8List bytes', () {
      final bytes = Uint8List.fromList('Hello binary data'.codeUnits);
      expect(truncateResponseBody(bytes), 'Hello binary data');
    });
  });
}
