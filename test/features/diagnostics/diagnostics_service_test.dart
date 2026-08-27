import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/features/diagnostics/diagnostics_models.dart';
import 'package:hermes_ui/features/diagnostics/diagnostics_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DiagnosticsService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    service = DiagnosticsService(customPrefs: prefs, maxCapacity: 5);
    await service.init(prefs: prefs);
  });

  group('DiagnosticsService', () {
    test('default state is disabled', () {
      expect(service.enabled, false);
      expect(service.logs, isEmpty);
    });

    test('setting enabled persists in SharedPreferences', () async {
      final prefs = await SharedPreferences.getInstance();
      await service.setEnabled(true, prefs: prefs);
      expect(service.enabled, true);
      expect(prefs.getBool(kDiagnosticsEnabledKey), true);

      await service.setEnabled(false, prefs: prefs);
      expect(service.enabled, false);
      expect(prefs.getBool(kDiagnosticsEnabledKey), false);
    });

    test('log does nothing when disabled', () {
      expect(service.enabled, false);
      service.log(
        level: DiagnosticsLogLevel.info,
        tag: 'test',
        message: 'Should not be recorded',
      );
      expect(service.logs, isEmpty);
    });

    test('log records entries and enforces ring buffer max capacity', () async {
      await service.setEnabled(true);

      for (var i = 1; i <= 7; i++) {
        service.log(
          level: DiagnosticsLogLevel.info,
          tag: 'tag-$i',
          message: 'Message $i',
        );
      }

      // Max capacity is 5, so entries 3, 4, 5, 6, 7 remain
      expect(service.logs.length, 5);
      expect(service.logs.first.message, 'Message 3');
      expect(service.logs.last.message, 'Message 7');
    });

    test('clear wipes memory buffer and storage', () async {
      final prefs = await SharedPreferences.getInstance();
      await service.setEnabled(true, prefs: prefs);
      service.log(
        level: DiagnosticsLogLevel.error,
        tag: 'err',
        message: 'An error occurred',
      );
      expect(service.logs.length, 1);

      await service.clear(prefs: prefs);
      expect(service.logs, isEmpty);
      expect(prefs.getString(kDiagnosticsLogsStorageKey), isNull);
    });

    test('init prunes logs older than 7 days from storage', () async {
      final now = DateTime.now();
      final freshDate = now.subtract(const Duration(days: 2));
      final oldDate = now.subtract(const Duration(days: 10));

      final storedEntries = [
        DiagnosticsLogEntry(
          id: 'old-1',
          timestamp: oldDate,
          level: DiagnosticsLogLevel.info,
          tag: 'old',
          message: 'Old log message',
        ).toJson(),
        DiagnosticsLogEntry(
          id: 'fresh-1',
          timestamp: freshDate,
          level: DiagnosticsLogLevel.info,
          tag: 'fresh',
          message: 'Fresh log message',
        ).toJson(),
      ];

      SharedPreferences.setMockInitialValues({
        kDiagnosticsEnabledKey: true,
        kDiagnosticsLogsStorageKey: jsonEncode(storedEntries),
      });

      final prefs = await SharedPreferences.getInstance();
      final newService = DiagnosticsService(customPrefs: prefs);
      await newService.init(prefs: prefs);

      expect(newService.enabled, true);
      expect(newService.logs.length, 1);
      expect(newService.logs.first.id, 'fresh-1');
    });

    test('formatExportText generates valid formatted output', () {
      final entries = [
        DiagnosticsLogEntry(
          id: '1',
          timestamp: DateTime(2026, 8, 28, 12, 0, 0),
          level: DiagnosticsLogLevel.info,
          tag: 'dio',
          message: 'GET /api/test -> 200',
        ),
      ];

      final text = DiagnosticsService.formatExportText(
        entries,
        DateTime(2026, 8, 28, 12, 0, 0),
      );
      expect(text, contains('Hermes Diagnostics Log Export'));
      expect(text, contains('Total Entries: 1'));
      expect(text, contains('[dio] GET /api/test -> 200'));
    });

    test('generateExportFileName creates proper filename format', () {
      final name = DiagnosticsService.generateExportFileName(
        DateTime(2026, 8, 28, 14, 30, 45),
      );
      expect(name, 'Diagnostics_20260828_143045.txt');
    });
  });
}
