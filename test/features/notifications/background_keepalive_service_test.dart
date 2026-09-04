import 'package:flutter/cupertino.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/features/notifications/background_keepalive_service.dart';
import 'package:hermes_ui/features/notifications/background_keepalive_settings_page.dart';
import 'package:hermes_ui/features/notifications/notification_providers.dart';
import 'package:hermes_ui/features/notifications/turn_notification_service.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    registerFallbackValue(workmanagerCallbackDispatcher);
    registerFallbackValue(const Duration(minutes: 15));
    registerFallbackValue(ExistingPeriodicWorkPolicy.keep);
    registerFallbackValue(BackoffPolicy.exponential);
    registerFallbackValue(Constraints(networkType: NetworkType.connected));
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('FakeBackgroundKeepaliveService 生命周期与保活逻辑', () {
    late FakeBackgroundKeepaliveService service;

    setUp(() {
      service = FakeBackgroundKeepaliveService();
    });

    test('初始化后 isInitialized 为 true', () async {
      expect(service.isInitialized, isFalse);
      await service.initialize();
      expect(service.isInitialized, isTrue);
    });

    test('切后台 + 正在流式生成 + 前台服务已开启 → 启动前台服务并调度 OneOff', () async {
      await service.onAppLifecycleChanged(
        state: AppLifecycleState.paused,
        activeSessionId: 'sess-123',
        activeStreamId: 'stream-abc',
        isStreaming: true,
        foregroundServiceEnabled: true,
      );

      expect(service.startedForegroundServices, ['sess-123']);
      expect(service.scheduledOneOffPolls, [('sess-123', 'stream-abc')]);
      expect(service.stoppedForegroundServices, isEmpty);
      expect(service.currentActiveCount, 1);
      expect(service.isForegroundServiceRunning, isTrue);
    });

    test('切后台 + 正在流式生成 + 前台服务关闭（默认） → 仅调度 OneOff 探活，不启前台服务', () async {
      await service.onAppLifecycleChanged(
        state: AppLifecycleState.paused,
        activeSessionId: 'sess-123',
        activeStreamId: 'stream-abc',
        isStreaming: true,
        foregroundServiceEnabled: false,
      );

      expect(service.startedForegroundServices, isEmpty);
      expect(service.scheduledOneOffPolls, [('sess-123', 'stream-abc')]);
      expect(service.isForegroundServiceRunning, isFalse);
    });

    test('回到前台（resumed） → 取消 OneOff 任务且不停止常驻前台服务', () async {
      service.isForegroundServiceRunning = true;
      await service.onAppLifecycleChanged(
        state: AppLifecycleState.resumed,
        activeSessionId: 'sess-123',
        activeStreamId: null,
        isStreaming: false,
        foregroundServiceEnabled: true,
      );

      // 回到前台不再调用 stopForegroundService，服务保持常驻
      expect(service.isForegroundServiceRunning, isTrue);
      expect(service.cancelledOneOffPolls, ['sess-123']);
      expect(service.currentActiveCount, 0);
    });
  });

  group('开关直启与常驻保活联动（Switch Direct Start/Stop & Persistent）', () {
    test('开关打开 → 立即 startForegroundService（前后台都启），关闭 → 立即 stopForegroundService(force: true)', () async {
      SharedPreferences.setMockInitialValues({});
      final fakeKeepalive = FakeBackgroundKeepaliveService();
      final container = ProviderContainer(
        overrides: [
          backgroundKeepaliveServiceProvider.overrideWithValue(fakeKeepalive),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(notificationSettingsProvider.notifier);
      expect(fakeKeepalive.isForegroundServiceRunning, isFalse);

      // 1. 开关打开 → 立即启动前台服务常驻
      await notifier.setBgForegroundServiceEnabled(true);
      expect(fakeKeepalive.startedForegroundServices, hasLength(1));
      expect(fakeKeepalive.isForegroundServiceRunning, isTrue);

      // 2. 开关关闭 → 立即停止前台服务
      await notifier.setBgForegroundServiceEnabled(false);
      expect(fakeKeepalive.stoppedForegroundServices, contains('stopped'));
      expect(fakeKeepalive.isForegroundServiceRunning, isFalse);
    });

    test('流开始/结束 → 文本 0 ↔ N 动态更新，无会话时显示「暂无」且不 stop', () async {
      final fakeKeepalive = FakeBackgroundKeepaliveService();

      // 启动常驻服务（初始无活跃会话，count = 0）
      await fakeKeepalive.startForegroundService(activeCount: 0);
      expect(fakeKeepalive.isForegroundServiceRunning, isTrue);
      expect(fakeKeepalive.currentActiveCount, 0);

      // 流开始：更新为 1 个会话生成中
      await fakeKeepalive.updateNotification(activeCount: 1);
      expect(fakeKeepalive.currentActiveCount, 1);
      expect(fakeKeepalive.isForegroundServiceRunning, isTrue);

      // 多流并发：更新为 2 个会话生成中
      await fakeKeepalive.updateNotification(activeCount: 2);
      expect(fakeKeepalive.currentActiveCount, 2);

      // 流结束：调用非强制 stopForegroundService → 计数归 0，常驻服务不消失
      await fakeKeepalive.stopForegroundService(force: false);
      expect(fakeKeepalive.currentActiveCount, 0);
      expect(fakeKeepalive.isForegroundServiceRunning, isTrue);
    });
  });

  group('常驻通知文本格式化 formatNotificationText', () {
    test('中文格式：0 -> 暂无进行中会话，N -> N 个会话正在生成', () {
      expect(
        ProductionBackgroundKeepaliveService.formatNotificationText(0),
        '暂无进行中会话',
      );
      expect(
        ProductionBackgroundKeepaliveService.formatNotificationText(1),
        '1 个会话正在生成',
      );
      expect(
        ProductionBackgroundKeepaliveService.formatNotificationText(3),
        '3 个会话正在生成',
      );
    });

    test('英文格式：0 -> No active sessions，1 -> 1 session generating，N -> N sessions generating', () {
      expect(
        ProductionBackgroundKeepaliveService.formatNotificationText(0, isEnglish: true),
        'No active sessions',
      );
      expect(
        ProductionBackgroundKeepaliveService.formatNotificationText(1, isEnglish: true),
        '1 session generating',
      );
      expect(
        ProductionBackgroundKeepaliveService.formatNotificationText(2, isEnglish: true),
        '2 sessions generating',
      );
    });
  });

  group('回合通知去重逻辑（Deduplication）', () {
    late ProductionBackgroundKeepaliveService service;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      service = ProductionBackgroundKeepaliveService();
    });

    test('未记录的回合返回 isTurnAlreadyNotified == false', () async {
      final notified = await service.isTurnAlreadyNotified(
        sessionId: 'sess-test',
        streamId: 'stream-test',
      );
      expect(notified, isFalse);
    });

    test('调用 recordTurnNotified 后，同一 streamId 判定为已通知', () async {
      await service.recordTurnNotified(
        sessionId: 'sess-test',
        streamId: 'stream-test',
      );

      final notified = await service.isTurnAlreadyNotified(
        sessionId: 'sess-test',
        streamId: 'stream-test',
      );
      expect(notified, isTrue);

      final otherStreamNotified = await service.isTurnAlreadyNotified(
        sessionId: 'other-sess',
        streamId: 'other-stream',
      );
      expect(otherStreamNotified, isFalse);
    });
  });

  group('NotificationSettings 与持久化', () {
    test('默认 bgForegroundServiceEnabled 为 false', () {
      const settings = NotificationSettings();
      expect(settings.bgForegroundServiceEnabled, isFalse);
      expect(settings.notifyTurnsEnabled, isTrue);
    });

    test('setBgForegroundServiceEnabled 切换并保存至 SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({});
      final fakeKeepalive = FakeBackgroundKeepaliveService();
      final container = ProviderContainer(
        overrides: [
          backgroundKeepaliveServiceProvider.overrideWithValue(fakeKeepalive),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(notificationSettingsProvider.notifier);
      expect(
        container.read(notificationSettingsProvider).bgForegroundServiceEnabled,
        isFalse,
      );

      await notifier.setBgForegroundServiceEnabled(true);
      expect(
        container.read(notificationSettingsProvider).bgForegroundServiceEnabled,
        isTrue,
      );

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('bg_foreground_service_enabled'), isTrue);

      await notifier.setBgForegroundServiceEnabled(false);
      expect(
        container.read(notificationSettingsProvider).bgForegroundServiceEnabled,
        isFalse,
      );
      expect(prefs.getBool('bg_foreground_service_enabled'), isFalse);
    });
  });

  group('HyperOS 设置跳转', () {
    late FakeBackgroundKeepaliveService service;

    setUp(() {
      service = FakeBackgroundKeepaliveService();
    });

    test('打开各个 HyperOS 设置项记录到 openedSettings', () async {
      await service.openHyperOsSetting(HyperOsSettingType.autoStart);
      await service.openHyperOsSetting(HyperOsSettingType.batteryOptimization);
      await service.openHyperOsSetting(HyperOsSettingType.networkControl);
      await service.openHyperOsSetting(HyperOsSettingType.notificationSettings);

      expect(service.openedSettings, [
        HyperOsSettingType.autoStart,
        HyperOsSettingType.batteryOptimization,
        HyperOsSettingType.networkControl,
        HyperOsSettingType.notificationSettings,
      ]);
    });
  });

  group('通知 Hook 与 Keepalive 联动', () {
    test(
      '回合完成 hook 触发时调用 keepalive.recordTurnNotified & stopForegroundService',
      () {
        final fakeKeepalive = FakeBackgroundKeepaliveService();
        final fakeTurnService = _FakeTurnNotificationService();
        final container = ProviderContainer(
          overrides: [
            backgroundKeepaliveServiceProvider.overrideWithValue(fakeKeepalive),
            turnNotificationServiceProvider.overrideWithValue(fakeTurnService),
          ],
        );
        addTearDown(container.dispose);

        container
            .read(appLifecycleStateProvider.notifier)
            .setState(AppLifecycleState.paused);
        final hook = container.read(turnNotificationHookProvider);

        hook('sess-100', 'Title', 'Preview content');

        expect(fakeTurnService.notifyCalls, hasLength(1));
        expect(fakeKeepalive.stoppedForegroundServices, ['stopped']);
        expect(fakeKeepalive.cancelledOneOffPolls, ['sess-100']);
        expect(fakeKeepalive.notifiedRecords, [('sess-100', null)]);
      },
    );
  });

  group('TASK K: 安卓前台服务保活修复（init 顺序/标志位 + callback + 失败可见化）', () {
    late MockWorkmanager mockWm;
    late FakeForegroundTaskWrapper fakeFg;
    late ProductionBackgroundKeepaliveService service;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      mockWm = MockWorkmanager();
      fakeFg = FakeForegroundTaskWrapper();
      service = ProductionBackgroundKeepaliveService(
        workmanager: mockWm,
        foregroundTaskWrapper: fakeFg,
      );

      when(() => mockWm.initialize(any())).thenAnswer((_) async {});
      when(
        () => mockWm.registerPeriodicTask(
          any(),
          any(),
          tag: any(named: 'tag'),
          frequency: any(named: 'frequency'),
          constraints: any(named: 'constraints'),
          existingWorkPolicy: any(named: 'existingWorkPolicy'),
          backoffPolicy: any(named: 'backoffPolicy'),
          backoffPolicyDelay: any(named: 'backoffPolicyDelay'),
        ),
      ).thenAnswer((_) async {});
    });

    test('1. init 顺序与分步标志：WorkManager 失败时 fgTask.init 仍完成且 fgTaskReady=true, wmReady=false', () async {
      when(() => mockWm.initialize(any())).thenThrow(
        Exception('WorkManager initialize failed on device'),
      );

      expect(service.fgTaskReady, isFalse);
      expect(service.wmReady, isFalse);
      expect(service.isInitialized, isFalse);

      await service.initialize();

      // FlutterForegroundTask.init 作为第一步已完成
      expect(fakeFg.initCallCount, 1);
      expect(
        fakeFg.capturedAndroidNotificationOptions?.channelId,
        'hermes_foreground_service',
      );
      expect(
        fakeFg.capturedAndroidNotificationOptions?.channelName,
        '后台生成保活',
      );
      expect(service.fgTaskReady, isTrue);
      expect(service.wmReady, isFalse);
      expect(service.isInitialized, isFalse);

      // 再次调用 initialize：WorkManager 恢复后完成重试，且 fgTask 不重复 init
      when(() => mockWm.initialize(any())).thenAnswer((_) async {});
      await service.initialize();

      expect(fakeFg.initCallCount, 1);
      expect(service.fgTaskReady, isTrue);
      expect(service.wmReady, isTrue);
      expect(service.isInitialized, isTrue);
    });

    test('2. startForegroundService 收到非空 callback 参数（foregroundTaskCallback）', () async {
      await service.initialize();
      await service.startForegroundService(activeCount: 1);

      expect(fakeFg.startServiceCallCount, 1);
      expect(fakeFg.lastCallback, isNotNull);
      expect(fakeFg.lastCallback, equals(foregroundTaskCallback));
      expect(fakeFg.lastNotificationTitle, 'Hermes');
      expect(fakeFg.lastNotificationText, contains('1 个会话正在生成'));
    });

    test('3. startForegroundService 失败异常向上冒泡（ServiceRequestFailure 时 throw）', () async {
      await service.initialize();
      fakeFg.startServiceResult = ServiceRequestFailure(
        error: Exception('ServiceTimeoutException: service failed to start within 5s'),
      );

      expect(
        () => service.startForegroundService(activeCount: 1),
        throwsA(isA<Exception>()),
      );
    });

    test('4. 开关失败 → provider 状态回滚 false + error 字段可读', () async {
      final fakeKeepalive = FakeBackgroundKeepaliveService();
      fakeKeepalive.shouldFailStartForegroundServiceWith = Exception(
        'ServiceNotInitializedException: ForegroundTask not ready',
      );

      final container = ProviderContainer(
        overrides: [
          backgroundKeepaliveServiceProvider.overrideWithValue(fakeKeepalive),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(notificationSettingsProvider.notifier);
      expect(
        container.read(notificationSettingsProvider).bgForegroundServiceEnabled,
        isFalse,
      );
      expect(
        container.read(notificationSettingsProvider).error,
        isNull,
      );

      // 打开开关触发异常
      await notifier.setBgForegroundServiceEnabled(true);

      final settings = container.read(notificationSettingsProvider);
      // 状态回滚为 false
      expect(settings.bgForegroundServiceEnabled, isFalse);
      // error 字段可读
      expect(settings.error, isNotNull);
      expect(
        settings.error,
        contains('ServiceNotInitializedException'),
      );
      expect(settings.keepaliveError, equals(settings.error));

      // 持久化保存也回滚为 false
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('bg_foreground_service_enabled'), isFalse);
    });

    test('5. 冷启动条件拉起路径回归（开关为 true 时拉起，文本根据流状态动态计算）', () async {
      // 开启开关 + 正在流式生成
      SharedPreferences.setMockInitialValues({
        'bg_foreground_service_enabled': true,
        ProductionBackgroundKeepaliveService.keyIsStreaming: true,
      });

      await service.initialize();

      expect(fakeFg.startServiceCallCount, 1);
      expect(fakeFg.lastCallback, equals(foregroundTaskCallback));
      expect(fakeFg.lastNotificationText, '1 个会话正在生成');
    });

    test('6. 冷启动条件拉起路径回归（开关为 false 时不拉起）', () async {
      SharedPreferences.setMockInitialValues({
        'bg_foreground_service_enabled': false,
        ProductionBackgroundKeepaliveService.keyIsStreaming: true,
      });

      await service.initialize();

      expect(fakeFg.startServiceCallCount, 0);
    });

    test('7. HermesKeepaliveTaskHandler 契约各方法健全性验证', () async {
      final handler = HermesKeepaliveTaskHandler();
      await handler.onStart(DateTime.now(), TaskStarter.developer);
      handler.onRepeatEvent(DateTime.now());
      await handler.onDestroy(DateTime.now());
      handler.onStop();
    });

    testWidgets('8. UI 就地错误提示展示（开关失败后显示红色错误 Tile）', (tester) async {
      final container = ProviderContainer(
        overrides: [
          notificationSettingsProvider.overrideWith(
            () => _ErrorMockNotificationSettingsNotifier(
              'ServiceNotInitializedException: ForegroundTask not ready',
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const CupertinoApp(
            home: CupertinoPageScaffold(
              child: BackgroundKeepAliveSection(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final errorTile = find.byKey(
        const ValueKey('settings-bg-foreground-service-error'),
      );
      expect(errorTile, findsOneWidget);
      expect(find.text('前台保活服务启动失败'), findsOneWidget);
      expect(
        find.text('ServiceNotInitializedException: ForegroundTask not ready'),
        findsOneWidget,
      );
    });
  });
}

class MockWorkmanager extends Mock implements Workmanager {}

class FakeForegroundTaskWrapper implements ForegroundTaskWrapper {
  int initCallCount = 0;
  AndroidNotificationOptions? capturedAndroidNotificationOptions;
  IOSNotificationOptions? capturedIosNotificationOptions;
  ForegroundTaskOptions? capturedForegroundTaskOptions;

  bool isRunning = false;
  int startServiceCallCount = 0;
  String? lastNotificationTitle;
  String? lastNotificationText;
  Function? lastCallback;
  ServiceRequestResult startServiceResult = const ServiceRequestSuccess();

  int updateServiceCallCount = 0;
  ServiceRequestResult updateServiceResult = const ServiceRequestSuccess();

  int stopServiceCallCount = 0;
  ServiceRequestResult stopServiceResult = const ServiceRequestSuccess();

  @override
  void init({
    required AndroidNotificationOptions androidNotificationOptions,
    required IOSNotificationOptions iosNotificationOptions,
    required ForegroundTaskOptions foregroundTaskOptions,
  }) {
    initCallCount++;
    capturedAndroidNotificationOptions = androidNotificationOptions;
    capturedIosNotificationOptions = iosNotificationOptions;
    capturedForegroundTaskOptions = foregroundTaskOptions;
  }

  @override
  Future<bool> get isRunningService async => isRunning;

  @override
  Future<ServiceRequestResult> startService({
    required String notificationTitle,
    required String notificationText,
    Function? callback,
  }) async {
    startServiceCallCount++;
    lastNotificationTitle = notificationTitle;
    lastNotificationText = notificationText;
    lastCallback = callback;
    if (startServiceResult is ServiceRequestSuccess) {
      isRunning = true;
    }
    return startServiceResult;
  }

  @override
  Future<ServiceRequestResult> updateService({
    required String notificationTitle,
    required String notificationText,
  }) async {
    updateServiceCallCount++;
    lastNotificationTitle = notificationTitle;
    lastNotificationText = notificationText;
    return updateServiceResult;
  }

  @override
  Future<ServiceRequestResult> stopService() async {
    stopServiceCallCount++;
    if (stopServiceResult is ServiceRequestSuccess) {
      isRunning = false;
    }
    return stopServiceResult;
  }
}

class _ErrorMockNotificationSettingsNotifier
    extends NotificationSettingsNotifier {
  _ErrorMockNotificationSettingsNotifier(this.initialError);
  final String initialError;

  @override
  NotificationSettings build() {
    return NotificationSettings(
      bgForegroundServiceEnabled: false,
      error: initialError,
    );
  }
}

class _FakeTurnNotificationService implements TurnNotificationService {
  final List<(String, String, String)> notifyCalls = [];
  final List<(String, String)> clarifyCalls = [];
  final List<(String, String, String)> errorCalls = [];
  int clearAllCalls = 0;

  @override
  Future<void> notifyTurnCompleted(
    String sessionId,
    String title,
    String preview,
  ) async {
    notifyCalls.add((sessionId, title, preview));
  }

  @override
  Future<void> notifyClarificationNeeded(
    String sessionId,
    String question,
  ) async {
    clarifyCalls.add((sessionId, question));
  }

  @override
  Future<void> notifySessionError(
    String sessionId,
    String title,
    String preview,
  ) async {
    errorCalls.add((sessionId, title, preview));
  }

  @override
  Future<void> notifyDownloadCompleted(
    String downloadId,
    String fileName,
    int byteSize,
  ) async {}

  @override
  Future<void> clearAll() async {
    clearAllCalls++;
  }

  @override
  Future<bool> areNotificationsEnabled() async => true;
  @override
  Future<String?> getLaunchSessionId() async => null;

  @override
  Future<bool> requestPermission() async => true;
}
