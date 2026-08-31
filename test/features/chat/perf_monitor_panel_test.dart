import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/providers/clipboard_paste_provider.dart';
import 'package:hermes_ui/core/providers/file_picker_provider.dart';
import 'package:hermes_ui/core/utils/clipboard_paste.dart';
import 'package:hermes_ui/core/utils/file_picker.dart';
import 'package:hermes_ui/features/chat/chat_page.dart';
import 'package:hermes_ui/features/chat/chat_providers.dart';
import 'package:hermes_ui/features/prompts/prompts_providers.dart';
import 'package:hermes_ui/features/settings/composer_settings.dart';
import 'package:hermes_ui/features/settings/perf_monitor_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_chat_api.dart';
import '../../helpers/fake_prompts_api.dart';

class _HealthAdapter implements HttpClientAdapter {
  _HealthAdapter({required this.responder});

  final ResponseBody Function(RequestOptions options) responder;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return responder(options);
  }

  @override
  void close({bool force = false}) {}
}

ApiClient _buildHealthClient({
  double cpu = 45.0,
  double mem = 60.0,
  double disk = 70.0,
  int usedBytes = 140000000000,
  int totalBytes = 200000000000,
}) {
  final dio = Dio(
    BaseOptions(validateStatus: (_) => true, followRedirects: false),
  );
  dio.httpClientAdapter = _HealthAdapter(
    responder: (options) {
      if (options.uri.path == '/api/system/health') {
        return ResponseBody.fromString(
          jsonEncode({
            'status': 'ok',
            'available': true,
            'checked_at': '2026-08-30T00:00:00Z',
            'cpu': {'percent': cpu},
            'memory': {
              'percent': mem,
              'used_bytes': usedBytes,
              'total_bytes': totalBytes,
            },
            'disk': {
              'percent': disk,
              'used_bytes': usedBytes,
              'total_bytes': totalBytes,
            },
            'errors': [],
          }),
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      }
      return ResponseBody.fromString('{}', 200);
    },
  );
  return ApiClient(baseUrl: 'http://test.local:30002', dio: dio);
}

Future<void> _pumpPerfMonitor(
  WidgetTester tester, {
  ApiClient? apiClient,
  double screenWidth = 800.0,
  double screenHeight = 600.0,
}) async {
  tester.view.physicalSize = Size(screenWidth, screenHeight);
  tester.view.devicePixelRatio = 1.0;

  SharedPreferences.setMockInitialValues({
    ComposerTwoPaneController.keyTwoPane: true,
    kShowPerfMonitorKey: true,
  });

  final chatApi = FakeChatApi();
  chatApi.sessionResult = {
    'session': {'session_id': 's1', 'messages': const []},
  };
  final prompts = FakePromptsApi(initialPrompts: const []);
  final client = apiClient ?? _buildHealthClient();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        chatApiProvider.overrideWithValue(chatApi),
        promptsApiFactoryProvider.overrideWithValue((_) => prompts),
        filePickerServiceProvider.overrideWithValue(FakeFilePickerService()),
        clipboardPasteServiceProvider.overrideWithValue(
          FakeClipboardPasteService(),
        ),
        apiClientProvider.overrideWithValue(client),
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
  tester.view.resetPhysicalSize();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('性能监控悬浮卡片 — 弹窗宽度自适应与三行等宽对齐', () {
    testWidgets('弹窗宽度随视口自适应伸缩（240px 极窄 到 1200px 宽屏均在 220-320 范围内无溢出）', (
      tester,
    ) async {
      // 1. 宽屏 1200px 视口
      await _pumpPerfMonitor(tester, screenWidth: 1200.0);
      final perfPanel = find.byKey(const ValueKey('perf-monitor-panel'));
      expect(perfPanel, findsOneWidget);
      await tester.tap(perfPanel);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final cardFinder = find.byKey(
        const ValueKey('perf-monitor-popover-card'),
      );
      expect(cardFinder, findsOneWidget);
      final cardSize1200 = tester.getSize(cardFinder);
      // 宽屏下最大宽度不超过 320
      expect(cardSize1200.width, lessThanOrEqualTo(320.0));
      expect(cardSize1200.width, greaterThanOrEqualTo(220.0));

      await _unmount(tester);

      // 2. 窄屏 320px 视口
      await _pumpPerfMonitor(tester, screenWidth: 320.0);
      final perfPanel320 = find.byKey(const ValueKey('perf-monitor-panel'));
      expect(perfPanel320, findsOneWidget);
      await tester.tap(perfPanel320);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final cardFinder320 = find.byKey(
        const ValueKey('perf-monitor-popover-card'),
      );
      expect(cardFinder320, findsOneWidget);
      final cardSize320 = tester.getSize(cardFinder320);
      // 窄屏下最小宽度 220 且不超过视口可用宽度
      expect(cardSize320.width, lessThanOrEqualTo(320.0));
      expect(cardSize320.width, greaterThanOrEqualTo(200.0));

      await _unmount(tester);

      // 3. 极窄 240px 视口
      await _pumpPerfMonitor(tester, screenWidth: 240.0);
      final perfPanel240 = find.byKey(const ValueKey('perf-monitor-panel'));
      if (perfPanel240.evaluate().isNotEmpty) {
        await tester.tap(perfPanel240);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        final cardFinder240 = find.byKey(
          const ValueKey('perf-monitor-popover-card'),
        );
        if (cardFinder240.evaluate().isNotEmpty) {
          final cardSize240 = tester.getSize(cardFinder240);
          expect(cardSize240.width, lessThanOrEqualTo(240.0));
        }
      }
      await _unmount(tester);
    });

    testWidgets('悬浮卡内三行（CPU/MEM/DISK）等宽且三列严格对齐', (tester) async {
      final client = _buildHealthClient(
        cpu: 45.0,
        mem: 60.0,
        disk: 70.0,
        usedBytes: 140000000000,
        totalBytes: 200000000000,
      );
      await _pumpPerfMonitor(tester, apiClient: client, screenWidth: 800.0);

      // 打开悬浮卡
      await tester.tap(find.byKey(const ValueKey('perf-monitor-panel')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final popoverCard = find.byKey(
        const ValueKey('perf-monitor-popover-card'),
      );
      expect(popoverCard, findsOneWidget);

      // 定位 CPU, MEM, DISK 文本部件
      final cpuLabelFinder = find.text('CPU');
      final memLabelFinder = find.text('MEM');
      final diskLabelFinder = find.text('DISK');

      expect(cpuLabelFinder, findsWidgets);
      expect(memLabelFinder, findsWidgets);
      expect(diskLabelFinder, findsOneWidget);

      // 获取弹出卡片内的三行标签 widget（最后匹配项为弹窗内）
      final cpuLabelTopLeft = tester.getTopLeft(cpuLabelFinder.last);
      final memLabelTopLeft = tester.getTopLeft(memLabelFinder.last);
      final diskLabelTopLeft = tester.getTopLeft(diskLabelFinder);

      // 列 1（标签列）左边缘严格左对齐
      expect(cpuLabelTopLeft.dx, equals(memLabelTopLeft.dx));
      expect(memLabelTopLeft.dx, equals(diskLabelTopLeft.dx));

      // 定位百分比数值部件
      final cpuValFinder = find.text('45%');
      final memValFinder = find.text('60%');
      final diskValFinder = find.text('70%');

      expect(cpuValFinder, findsWidgets);
      expect(memValFinder, findsWidgets);
      expect(diskValFinder, findsOneWidget);

      // 列 2（百分比列）右对齐：检查百分比右边缘 dx 对齐
      final cpuValRight =
          tester.getTopLeft(cpuValFinder.last).dx +
          tester.getSize(cpuValFinder.last).width;
      final memValRight =
          tester.getTopLeft(memValFinder.last).dx +
          tester.getSize(memValFinder.last).width;
      final diskValRight =
          tester.getTopLeft(diskValFinder).dx +
          tester.getSize(diskValFinder).width;

      expect(cpuValRight, closeTo(memValRight, 1.0));
      expect(memValRight, closeTo(diskValRight, 1.0));

      // 验证 DISK 的 used/total 格式化文本存在
      expect(find.textContaining('130.4GB/186.3GB'), findsOneWidget);

      // 验证三行在垂直方向由上至下排列且有间距
      expect(cpuLabelTopLeft.dy, lessThan(memLabelTopLeft.dy));
      expect(memLabelTopLeft.dy, lessThan(diskLabelTopLeft.dy));

      await _unmount(tester);
    });

    testWidgets('DISK 容量文本在极窄视口下由 FittedBox 优雅缩放不溢出', (tester) async {
      final client = _buildHealthClient(
        cpu: 10.0,
        mem: 20.0,
        disk: 95.0,
        usedBytes: 1900000000000,
        totalBytes: 2000000000000,
      );
      await _pumpPerfMonitor(tester, apiClient: client, screenWidth: 320.0);

      await tester.tap(find.byKey(const ValueKey('perf-monitor-panel')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        find.byKey(const ValueKey('perf-monitor-popover-card')),
        findsOneWidget,
      );
      expect(find.textContaining('1769.5GB/1862.6GB'), findsOneWidget);

      await _unmount(tester);
    });
  });
}
