import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hermes_ui/app/router.dart';
import 'package:hermes_ui/features/desktop/desktop_lifecycle_observer.dart';
import 'package:hermes_ui/features/desktop/desktop_shortcuts.dart';
import 'package:hermes_ui/features/desktop/tray_manager_service.dart';
import 'package:hermes_ui/features/desktop/window_memory.dart';
import 'package:hermes_ui/features/desktop/window_title_service.dart';
import 'package:hermes_ui/features/webui_sidecar/webui_sidecar_providers.dart';

class _FakeSidecarConfigStorage extends Fake
    implements WebuiSidecarConfigStorage {
  _FakeSidecarConfigStorage({SidecarConfig initialConfig = const SidecarConfig()})
      : config = initialConfig;

  SidecarConfig config;

  @override
  Future<SidecarConfig> load() async => config;

  @override
  Future<void> save(SidecarConfig newConfig) async {
    config = newConfig;
  }

  @override
  Future<void> setEnabled(bool value) async {
    config = config.copyWith(enabled: value);
  }

  @override
  Future<void> setHost(String value) async {
    config = config.copyWith(host: value);
  }

  @override
  Future<void> setPort(int value) async {
    config = config.copyWith(port: value);
  }

  @override
  Future<void> setPassword(String value) async {
    config = config.copyWith(password: value);
  }
}

class _FakeSidecarFileSystem extends Fake implements SidecarFileSystem {
  _FakeSidecarFileSystem({this.isWindowsPlatform = true});

  final bool isWindowsPlatform;

  @override
  bool get isWindows => isWindowsPlatform;

  @override
  bool isBundleAvailable() => true;
}

class _FakeSidecarService implements WebuiSidecarService {
  _FakeSidecarService({
    SidecarState initialState = SidecarState.initial,
  }) : _state = initialState;

  SidecarState _state;
  final StreamController<SidecarState> _controller =
      StreamController<SidecarState>.broadcast();

  int startCallCount = 0;
  int stopCallCount = 0;

  @override
  SidecarState get currentState => _state;

  @override
  Stream<SidecarState> get states => _controller.stream;

  @override
  Future<void> start() async {
    startCallCount++;
    emitState(_state.copyWith(status: SidecarStatus.running));
  }

  @override
  Future<void> stop() async {
    stopCallCount++;
  }

  @override
  Future<void> restart() async {
    await stop();
    await start();
  }

  void emitState(SidecarState newState) {
    _state = newState;
    _controller.add(newState);
  }

  void dispose() {
    unawaited(_controller.close());
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late GoRouter testRouter;

  setUp(() {
    testRouter = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const SizedBox(),
        ),
      ],
    );
  });

  tearDown(() {
    testRouter.dispose();
  });

  group('DesktopLifecycleObserver Sidecar 启动链测试', () {
    testWidgets('enabled=true: _initDesktopServices 启动 sidecar',
        (tester) async {
      final fakeStorage = _FakeSidecarConfigStorage(
        initialConfig: const SidecarConfig(enabled: true),
      );
      final fakeSidecar = _FakeSidecarService();
      final fakeFs = _FakeSidecarFileSystem(isWindowsPlatform: true);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            routerProvider.overrideWithValue(testRouter),
            windowTitleServiceProvider
                .overrideWithValue(WindowTitleService(isDesktop: false)),
            trayManagerServiceProvider
                .overrideWithValue(TrayManagerService(isDesktop: false)),
            windowMemoryServiceProvider
                .overrideWithValue(WindowMemoryService(isDesktop: false)),
            desktopShortcutsServiceProvider
                .overrideWithValue(DesktopShortcutsService(isDesktop: false)),
            webuiSidecarConfigStorageProvider.overrideWithValue(fakeStorage),
            webuiSidecarServiceProvider.overrideWithValue(fakeSidecar),
            sidecarFileSystemProvider.overrideWithValue(fakeFs),
          ],
          child: const DesktopLifecycleObserver(
            isDesktop: true,
            child: SizedBox(),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(fakeSidecar.startCallCount, 1);
    });

    testWidgets('enabled=false: _initDesktopServices 不拉起 sidecar',
        (tester) async {
      final fakeStorage = _FakeSidecarConfigStorage(
        initialConfig: const SidecarConfig(enabled: false),
      );
      final fakeSidecar = _FakeSidecarService();
      final fakeFs = _FakeSidecarFileSystem(isWindowsPlatform: true);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            routerProvider.overrideWithValue(testRouter),
            windowTitleServiceProvider
                .overrideWithValue(WindowTitleService(isDesktop: false)),
            trayManagerServiceProvider
                .overrideWithValue(TrayManagerService(isDesktop: false)),
            windowMemoryServiceProvider
                .overrideWithValue(WindowMemoryService(isDesktop: false)),
            desktopShortcutsServiceProvider
                .overrideWithValue(DesktopShortcutsService(isDesktop: false)),
            webuiSidecarConfigStorageProvider.overrideWithValue(fakeStorage),
            webuiSidecarServiceProvider.overrideWithValue(fakeSidecar),
            sidecarFileSystemProvider.overrideWithValue(fakeFs),
          ],
          child: const DesktopLifecycleObserver(
            isDesktop: true,
            child: SizedBox(),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(fakeSidecar.startCallCount, 0);
    });

    testWidgets('非桌面平台: 安全 no-op，不拉起 sidecar', (tester) async {
      final fakeStorage = _FakeSidecarConfigStorage(
        initialConfig: const SidecarConfig(enabled: true),
      );
      final fakeSidecar = _FakeSidecarService();
      final fakeFs = _FakeSidecarFileSystem(isWindowsPlatform: true);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            routerProvider.overrideWithValue(testRouter),
            windowTitleServiceProvider
                .overrideWithValue(WindowTitleService(isDesktop: false)),
            trayManagerServiceProvider
                .overrideWithValue(TrayManagerService(isDesktop: false)),
            windowMemoryServiceProvider
                .overrideWithValue(WindowMemoryService(isDesktop: false)),
            desktopShortcutsServiceProvider
                .overrideWithValue(DesktopShortcutsService(isDesktop: false)),
            webuiSidecarConfigStorageProvider.overrideWithValue(fakeStorage),
            webuiSidecarServiceProvider.overrideWithValue(fakeSidecar),
            sidecarFileSystemProvider.overrideWithValue(fakeFs),
          ],
          child: const DesktopLifecycleObserver(
            isDesktop: false,
            child: SizedBox(),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(fakeSidecar.startCallCount, 0);
    });

    testWidgets('运行期 Sidecar 配置 false->true 跳变时自动触发 start', (tester) async {
      final fakeStorage = _FakeSidecarConfigStorage(
        initialConfig: const SidecarConfig(enabled: false),
      );
      final fakeSidecar = _FakeSidecarService();
      final fakeFs = _FakeSidecarFileSystem(isWindowsPlatform: true);

      late WidgetRef capturedRef;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            routerProvider.overrideWithValue(testRouter),
            windowTitleServiceProvider
                .overrideWithValue(WindowTitleService(isDesktop: false)),
            trayManagerServiceProvider
                .overrideWithValue(TrayManagerService(isDesktop: false)),
            windowMemoryServiceProvider
                .overrideWithValue(WindowMemoryService(isDesktop: false)),
            desktopShortcutsServiceProvider
                .overrideWithValue(DesktopShortcutsService(isDesktop: false)),
            webuiSidecarConfigStorageProvider.overrideWithValue(fakeStorage),
            webuiSidecarServiceProvider.overrideWithValue(fakeSidecar),
            sidecarFileSystemProvider.overrideWithValue(fakeFs),
          ],
          child: DesktopLifecycleObserver(
            isDesktop: true,
            child: Consumer(
              builder: (context, ref, _) {
                capturedRef = ref;
                return const SizedBox();
              },
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(fakeSidecar.startCallCount, 0);

      // 用户在设置页启用了 sidecar
      await capturedRef
          .read(webuiSidecarConfigProvider.notifier)
          .setEnabled(true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(fakeSidecar.startCallCount, 1);
    });
  });
}
