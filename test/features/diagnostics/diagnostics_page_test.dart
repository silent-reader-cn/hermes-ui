import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/app/theme/cupertino_theme.dart';
import 'package:hermes_ui/features/diagnostics/diagnostics_detail_sheet.dart';
import 'package:hermes_ui/features/diagnostics/diagnostics_models.dart';
import 'package:hermes_ui/features/diagnostics/diagnostics_page.dart';
import 'package:hermes_ui/features/diagnostics/diagnostics_providers.dart';
import 'package:hermes_ui/features/diagnostics/diagnostics_service.dart';
import 'package:hermes_ui/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _buildTestApp({
  required DiagnosticsService service,
  Widget child = const DiagnosticsPage(),
  Locale locale = const Locale('zh'),
}) {
  return ProviderScope(
    overrides: [
      diagnosticsServiceProvider.overrideWithValue(service),
    ],
    child: CupertinoApp(
      locale: locale,
      supportedLocales: const [Locale('zh'), Locale('en')],
      theme: buildCupertinoTheme(Brightness.light),
      localizationsDelegates: const [
        AppLocalizationsDelegate(),
        DefaultCupertinoLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      home: child,
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DiagnosticsService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    service = DiagnosticsService(customPrefs: prefs);
    await service.init(prefs: prefs);
  });

  tearDown(() {
    service.clearMemoryOnly();
  });

  group('DiagnosticsPage Widget Tests', () {
    testWidgets('shows empty placeholder when disabled', (tester) async {
      await tester.pumpWidget(_buildTestApp(service: service));
      await tester.pumpAndSettle();

      expect(find.text('调试/诊断'), findsOneWidget);
      expect(find.text('调试模式'), findsOneWidget);
      expect(find.text('打开调试模式后开始记录'), findsOneWidget);
    });

    testWidgets('switch toggles debug mode and persists', (tester) async {
      await tester.pumpWidget(_buildTestApp(service: service));
      await tester.pumpAndSettle();

      final switchFinder = find.byKey(
        const ValueKey('diagnostics-switch-enable'),
      );
      expect(switchFinder, findsOneWidget);

      final switchWidget = tester.widget<CupertinoSwitch>(switchFinder);
      expect(switchWidget.value, false);

      await tester.tap(switchFinder);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      expect(service.enabled, true);
    });

    testWidgets('displays log entries and level badges', (tester) async {
      tester.view.physicalSize = const Size(1000, 1500);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await service.setEnabled(true);
      service.log(
        level: DiagnosticsLogLevel.info,
        tag: 'dio',
        message: 'GET /api/status -> 200',
        durationMs: 45,
      );
      service.log(
        level: DiagnosticsLogLevel.error,
        tag: 'sse',
        message: 'SSE connection failed',
        errorKind: 'Timeout',
      );

      await tester.pumpWidget(_buildTestApp(service: service));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      expect(find.text('GET /api/status -> 200'), findsOneWidget);
      expect(find.text('SSE connection failed'), findsOneWidget);
      expect(find.text('45ms'), findsOneWidget);
      expect(find.text('Timeout'), findsOneWidget);
    });

    testWidgets('filtering by level chips updates displayed list', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1000, 1500);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await service.setEnabled(true);
      service.log(
        level: DiagnosticsLogLevel.info,
        tag: 'dio',
        message: 'INFO message',
      );
      service.log(
        level: DiagnosticsLogLevel.error,
        tag: 'dio',
        message: 'ERROR message',
      );

      await tester.pumpWidget(_buildTestApp(service: service));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      expect(find.text('INFO message'), findsOneWidget);
      expect(find.text('ERROR message'), findsOneWidget);

      // Toggle off INFO level chip (code 'I')
      final infoChip = find.byKey(const ValueKey('diagnostics-filter-level-I'));
      await tester.tap(infoChip);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      expect(find.text('INFO message'), findsNothing);
      expect(find.text('ERROR message'), findsOneWidget);
    });

    testWidgets('search filters entries with debounce', (tester) async {
      tester.view.physicalSize = const Size(1000, 1500);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await service.setEnabled(true);
      service.log(
        level: DiagnosticsLogLevel.info,
        tag: 'chat',
        message: 'Sending user message alpha',
      );
      service.log(
        level: DiagnosticsLogLevel.info,
        tag: 'chat',
        message: 'Receiving reply beta',
      );

      await tester.pumpWidget(_buildTestApp(service: service));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      expect(find.text('Sending user message alpha'), findsOneWidget);
      expect(find.text('Receiving reply beta'), findsOneWidget);

      final searchField = find.byKey(
        const ValueKey('diagnostics-search-field'),
      );
      await tester.enterText(searchField, 'alpha');
      // Advance debounce timer (200ms)
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      expect(find.text('Sending user message alpha'), findsOneWidget);
      expect(find.text('Receiving reply beta'), findsNothing);
    });

    testWidgets('clear logs shows confirmation dialog and clears buffer', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1000, 1500);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await service.setEnabled(true);
      service.log(
        level: DiagnosticsLogLevel.info,
        tag: 'dio',
        message: 'Log to be cleared',
      );

      await tester.pumpWidget(_buildTestApp(service: service));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      expect(find.text('Log to be cleared'), findsOneWidget);

      final clearBtn = find.byKey(const ValueKey('diagnostics-clear-btn'));
      await tester.tap(clearBtn);
      await tester.pumpAndSettle();

      expect(find.text('确定要清空所有诊断日志吗？'), findsOneWidget);

      final confirmBtn = find.byKey(
        const ValueKey('diagnostics-clear-confirm'),
      );
      await tester.tap(confirmBtn);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      expect(service.logs, isEmpty);
      expect(find.text('暂无日志记录'), findsOneWidget);
    });

    testWidgets('tap log row opens detail sheet', (tester) async {
      tester.view.physicalSize = const Size(1000, 1500);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await service.setEnabled(true);
      service.log(
        level: DiagnosticsLogLevel.info,
        tag: 'dio',
        message: 'Detailed log message',
        details: {'info': 'value123'},
      );

      await tester.pumpWidget(_buildTestApp(service: service));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      final row = find.text('Detailed log message');
      await tester.tap(row);
      await tester.pumpAndSettle();

      expect(find.byType(DiagnosticsDetailSheet), findsOneWidget);
      expect(find.text('日志详情'), findsOneWidget);
      expect(find.textContaining('value123'), findsOneWidget);
    });

    testWidgets('multi-select mode allows selection and exiting', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1000, 1500);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await service.setEnabled(true);
      service.log(
        level: DiagnosticsLogLevel.info,
        tag: 'tag1',
        message: 'Entry 1',
      );
      service.log(
        level: DiagnosticsLogLevel.info,
        tag: 'tag2',
        message: 'Entry 2',
      );

      await tester.pumpWidget(_buildTestApp(service: service));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      // Enter selection mode
      final enterBtn = find.byKey(
        const ValueKey('diagnostics-enter-selection-btn'),
      );
      await tester.tap(enterBtn);
      await tester.pumpAndSettle();

      expect(find.text('已选择 0 条'), findsOneWidget);
      expect(find.text('全选'), findsOneWidget);

      // Tap select all
      await tester.tap(find.text('全选'));
      await tester.pumpAndSettle();

      expect(find.text('已选择 2 条'), findsOneWidget);

      // Exit selection mode
      final exitBtn = find.byKey(
        const ValueKey('diagnostics-exit-selection-btn'),
      );
      await tester.tap(exitBtn);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('diagnostics-enter-selection-btn')),
        findsOneWidget,
      );
    });
  });
}
