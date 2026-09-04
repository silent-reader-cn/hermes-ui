import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/features/webui_sidecar/webui_sidecar_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeSidecarFileSystem implements SidecarFileSystem {
  _FakeSidecarFileSystem();

  @override
  bool isWindows = true;
  bool bundleAvailable = true;

  @override
  bool isBundleAvailable() => isWindows && bundleAvailable;

  @override
  Future<void> appendLogLine(String path, String line) async {}

  @override
  Future<void> createDirectory(String path, {bool recursive = true}) async {}

  @override
  String get defaultSidecarDir => r'C:\app\webui';

  @override
  bool directoryExists(String path) => true;

  @override
  String? get envSidecarRoot => null;

  @override
  bool fileExists(String path) => true;

  @override
  String get logDirectoryPath => r'C:\logs';

  @override
  String get logFilePath => r'C:\logs\webui.log';

  @override
  String resolveBundleDir() => r'C:\app\webui';

  @override
  Future<void> rotateLogIfNeeded(
    String path, {
    int maxSizeBytes = 5 * 1024 * 1024,
  }) async {}
}

class _FakeSecureStorage implements SidecarSecureStorage {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

class _MockWebuiSidecarService implements WebuiSidecarService {
  _MockWebuiSidecarService({SidecarState? initialState})
      : _state = initialState ?? SidecarState.initial;

  SidecarState _state;
  final StreamController<SidecarState> _controller =
      StreamController<SidecarState>.broadcast();

  int startCalls = 0;
  int stopCalls = 0;
  int restartCalls = 0;

  void emitState(SidecarState state) {
    _state = state;
    _controller.add(state);
  }

  @override
  SidecarState get currentState => _state;

  @override
  Stream<SidecarState> get states => _controller.stream;

  @override
  Future<void> start() async {
    startCalls++;
    emitState(const SidecarState(status: SidecarStatus.running, pid: 1234));
  }

  @override
  Future<void> stop() async {
    stopCalls++;
    emitState(const SidecarState(status: SidecarStatus.stopped));
  }

  @override
  Future<void> restart() async {
    restartCalls++;
    emitState(const SidecarState(status: SidecarStatus.running, pid: 5678));
  }
}

void main() {
  group('WebuiSidecar Providers', () {
    late _FakeSidecarFileSystem fakeFs;
    late _FakeSecureStorage fakeSecureStorage;
    late _MockWebuiSidecarService mockService;
    late ProviderContainer container;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      fakeFs = _FakeSidecarFileSystem();
      fakeSecureStorage = _FakeSecureStorage();
      mockService = _MockWebuiSidecarService();

      container = ProviderContainer(
        overrides: [
          sidecarFileSystemProvider.overrideWithValue(fakeFs),
          webuiSidecarConfigStorageProvider.overrideWithValue(
            WebuiSidecarConfigStorage(
              prefs: SharedPreferences.getInstance(),
              secureStorage: fakeSecureStorage,
            ),
          ),
          webuiSidecarServiceProvider.overrideWithValue(mockService),
        ],
      );
    });

    tearDown(() {
      container.dispose();
    });

    test('bundledWebuiAvailableProvider 反映平台与安装包状态', () {
      expect(container.read(bundledWebuiAvailableProvider), isTrue);

      fakeFs.bundleAvailable = false;
      final container2 = ProviderContainer(
        overrides: [
          sidecarFileSystemProvider.overrideWithValue(fakeFs),
        ],
      );
      expect(container2.read(bundledWebuiAvailableProvider), isFalse);
      container2.dispose();

      fakeFs.bundleAvailable = true;
      fakeFs.isWindows = false;
      final container3 = ProviderContainer(
        overrides: [
          sidecarFileSystemProvider.overrideWithValue(fakeFs),
        ],
      );
      expect(container3.read(bundledWebuiAvailableProvider), isFalse);
      container3.dispose();
    });

    test('webuiSidecarConfigProvider load 与各项变更', () async {
      final configController =
          container.read(webuiSidecarConfigProvider.notifier);

      await configController.load();
      expect(container.read(webuiSidecarConfigProvider).host, '127.0.0.1');
      expect(container.read(webuiSidecarConfigProvider).port, 8787);

      await configController.setEnabled(true);
      expect(container.read(webuiSidecarConfigProvider).enabled, isTrue);

      await configController.setPort(9090);
      expect(container.read(webuiSidecarConfigProvider).port, 9090);

      await configController.setHost('0.0.0.0');
      expect(container.read(webuiSidecarConfigProvider).host, '0.0.0.0');

      await configController.setPassword('new_secret_key');
      expect(
        container.read(webuiSidecarConfigProvider).password,
        'new_secret_key',
      );
    });

    test('webuiSidecarControllerProvider start/stop 委派并响应状态变更', () async {
      final controller =
          container.read(webuiSidecarControllerProvider.notifier);

      expect(container.read(webuiSidecarControllerProvider).status,
          SidecarStatus.stopped);

      await controller.start();
      expect(mockService.startCalls, 1);
      expect(container.read(webuiSidecarControllerProvider).status,
          SidecarStatus.running);
      expect(container.read(webuiSidecarControllerProvider).pid, 1234);

      await controller.stop();
      expect(mockService.stopCalls, 1);
      expect(container.read(webuiSidecarControllerProvider).status,
          SidecarStatus.stopped);
    });

    test('改配置语义：running 状态下修改 port/host/password 自动触发 restart', () async {
      final controller =
          container.read(webuiSidecarControllerProvider.notifier);
      final configController =
          container.read(webuiSidecarConfigProvider.notifier);

      await configController.load();
      await controller.start();
      expect(container.read(webuiSidecarControllerProvider).status,
          SidecarStatus.running);
      expect(mockService.restartCalls, 0);

      // 运行中修改端口
      await configController.setPort(8989);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(mockService.restartCalls, 1);
    });

    test('改配置语义：stopped 状态下修改配置不触发 restart', () async {
      container.read(webuiSidecarControllerProvider);
      final configController =
          container.read(webuiSidecarConfigProvider.notifier);

      expect(container.read(webuiSidecarControllerProvider).status,
          SidecarStatus.stopped);

      await configController.setEnabled(true);
      await configController.setPort(9999);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(mockService.restartCalls, 0);
    });

    test('非 Windows 平台 start() 直接置 failed(startFailed)+detail 说明', () async {
      fakeFs.isWindows = false;
      final controller =
          container.read(webuiSidecarControllerProvider.notifier);

      await controller.start();

      expect(mockService.startCalls, 0);
      final state = container.read(webuiSidecarControllerProvider);
      expect(state.status, SidecarStatus.failed);
      expect(state.reason, SidecarFailureReason.startFailed);
      expect(state.detail, contains('only supported on Windows'));
    });
  });
}
