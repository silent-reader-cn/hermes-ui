import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/features/notifications/background_keepalive_service.dart';
import 'package:hermes_ui/features/notifications/notification_providers.dart';
import 'package:hermes_ui/features/notifications/turn_notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
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
    });

    test('回到前台（resumed） → 停止前台服务并取消 OneOff 任务', () async {
      await service.onAppLifecycleChanged(
        state: AppLifecycleState.resumed,
        activeSessionId: 'sess-123',
        activeStreamId: null,
        isStreaming: false,
        foregroundServiceEnabled: true,
      );

      expect(service.stoppedForegroundServices, ['stopped']);
      expect(service.cancelledOneOffPolls, ['sess-123']);
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
      final container = ProviderContainer();
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
    test('回合完成 hook 触发时调用 keepalive.recordTurnNotified & stopForegroundService', () {
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
    });
  });
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
  Future<void> clearAll() async {
    clearAllCalls++;
  }

  @override
  Future<String?> getLaunchSessionId() async => null;

  @override
  Future<bool> requestPermission() async => true;
}
