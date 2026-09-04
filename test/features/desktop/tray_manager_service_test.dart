import 'dart:async';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/models/session.dart';
import 'package:hermes_ui/features/desktop/tray_manager_service.dart';
import 'package:hermes_ui/features/webui_sidecar/webui_sidecar_providers.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

class _FakeAssetBundle extends CachingAssetBundle {
  _FakeAssetBundle(this.bytes);

  final Uint8List bytes;

  @override
  Future<ByteData> load(String key) async {
    return ByteData.view(bytes.buffer);
  }
}

class _FakeUrlLauncher extends UrlLauncherPlatform {
  String? launchedUrl;
  LaunchOptions? lastOptions;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launchedUrl = url;
    lastOptions = options;
    return true;
  }
}

class _FakeSidecarService implements WebuiSidecarService {
  _FakeSidecarService({
    this.onStop,
    SidecarState initialState = SidecarState.initial,
  }) : _state = initialState;

  final Future<void> Function()? onStop;
  SidecarState _state;
  final StreamController<SidecarState> _controller =
      StreamController<SidecarState>.broadcast();

  int stopCallCount = 0;
  int startCallCount = 0;

  @override
  SidecarState get currentState => _state;

  @override
  Stream<SidecarState> get states => _controller.stream;

  @override
  Future<void> start() async {
    startCallCount++;
  }

  @override
  Future<void> stop() async {
    stopCallCount++;
    if (onStop != null) await onStop!();
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

  group('prepareTrayIconFile 临时图标落盘测试', () {
    test('从 assetBundle 读取字节并成功写入指定临时文件', () async {
      final tempDir = Directory.systemTemp.createTempSync('tray_test_');
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });

      final testBytes = Uint8List.fromList([
        0x89,
        0x50,
        0x4E,
        0x47,
        0x0D,
        0x0A,
      ]);
      final fakeBundle = _FakeAssetBundle(testBytes);

      final iconPath = await prepareTrayIconFile(
        assetBundle: fakeBundle,
        tempDir: tempDir,
        assetPath: 'assets/branding/tray_icon_32.png',
        fileName: 'test_tray_icon.png',
      );

      final file = File(iconPath);
      expect(file.existsSync(), isTrue);
      expect(file.lengthSync(), testBytes.length);
      expect(await file.readAsBytes(), testBytes);
    });
  });

  group('会话状态与文案格式化纯函数测试', () {
    test('formatSessionStatus 状态映射', () {
      expect(
        formatSessionStatus(const SessionSummary(isStreaming: true)),
        '运行中',
      );
      expect(
        formatSessionStatus(const SessionSummary(activeStreamId: 'stream-123')),
        '运行中',
      );
      expect(
        formatSessionStatus(const SessionSummary(hasPendingUserMessage: true)),
        '排队中',
      );
      expect(formatSessionStatus(const SessionSummary(archived: true)), '已归档');
      expect(formatSessionStatus(const SessionSummary(readOnly: true)), '只读');
      expect(formatSessionStatus(const SessionSummary(isReadOnly: true)), '只读');
      expect(
        formatSessionStatus(const SessionSummary(sourceTag: 'subagent')),
        '只读',
      );
      expect(formatSessionStatus(const SessionSummary()), isNull);
    });

    test('formatRecentSessionLabel 标题与状态组合及截断', () {
      expect(
        formatRecentSessionLabel(const SessionSummary(title: '日常答疑')),
        '日常答疑',
      );
      expect(
        formatRecentSessionLabel(
          const SessionSummary(title: '日常答疑', isStreaming: true),
        ),
        '日常答疑 (运行中)',
      );
      expect(
        formatRecentSessionLabel(
          const SessionSummary(title: '', archived: true),
        ),
        'Untitled (已归档)',
      );

      const longTitle = '一二三四五六七八九十一二三四五六七八九十一二三四五六七八九十';
      expect(longTitle.length, 30);
      final labeled = formatRecentSessionLabel(
        const SessionSummary(title: longTitle, archived: true),
        maxTitleLength: 24,
      );
      expect(labeled, '${longTitle.substring(0, 24)}... (已归档)');
    });
  });

  group('buildMenuItems 菜单构建纯函数测试', () {
    test('空会话列表展示 "暂无最近会话" 禁用项', () {
      final items = TrayManagerService.buildMenuItems(sessions: const []);
      expect(items.length, 9);
      expect(items[0].key, TrayManagerService.menuItemShowWindow);
      expect(items[1].key, TrayManagerService.menuItemNewSession);
      // items[2] is separator
      expect(items[3].key, TrayManagerService.menuItemOpenWebui);
      expect(items[4].key, TrayManagerService.menuItemWebuiStatus);
      // items[5] is separator
      expect(items[6].key, TrayManagerService.menuItemNoRecentSessions);
      expect(items[6].label, '暂无最近会话');
      expect(items[6].disabled, isTrue);
      // items[7] is separator
      expect(items[8].key, TrayManagerService.menuItemQuitApp);
    });

    test('running 状态下 open_webui 启用且状态显示 "WebUI 服务：运行中"', () {
      final items = TrayManagerService.buildMenuItems(
        sidecarStatus: SidecarStatus.running,
        sidecarEnabled: true,
      );

      final openItem = items.firstWhere(
        (it) => it.key == TrayManagerService.menuItemOpenWebui,
      );
      final statusItem = items.firstWhere(
        (it) => it.key == TrayManagerService.menuItemWebuiStatus,
      );

      expect(openItem.label, '打开 WebUI');
      expect(openItem.disabled, isFalse);
      expect(statusItem.label, 'WebUI 服务：运行中');
      expect(statusItem.disabled, isTrue);
    });

    test('failed 状态下 open_webui 置灰且状态显示 "WebUI 服务：失败"', () {
      final items = TrayManagerService.buildMenuItems(
        sidecarStatus: SidecarStatus.failed,
        sidecarEnabled: true,
      );

      final openItem = items.firstWhere(
        (it) => it.key == TrayManagerService.menuItemOpenWebui,
      );
      final statusItem = items.firstWhere(
        (it) => it.key == TrayManagerService.menuItemWebuiStatus,
      );

      expect(openItem.label, '打开 WebUI');
      expect(openItem.disabled, isTrue);
      expect(statusItem.label, 'WebUI 服务：失败');
      expect(statusItem.disabled, isTrue);
    });

    test('stopped 状态下 open_webui 置灰且状态显示 "WebUI 服务：已停止"', () {
      final items = TrayManagerService.buildMenuItems(
        sidecarStatus: SidecarStatus.stopped,
        sidecarEnabled: false,
      );

      final openItem = items.firstWhere(
        (it) => it.key == TrayManagerService.menuItemOpenWebui,
      );
      final statusItem = items.firstWhere(
        (it) => it.key == TrayManagerService.menuItemWebuiStatus,
      );

      expect(openItem.label, '打开 WebUI');
      expect(openItem.disabled, isTrue);
      expect(statusItem.label, 'WebUI 服务：已停止');
      expect(statusItem.disabled, isTrue);
    });

    test('starting 状态下 open_webui 置灰且状态显示 "WebUI 服务：启动中"', () {
      final items = TrayManagerService.buildMenuItems(
        sidecarStatus: SidecarStatus.starting,
        sidecarEnabled: true,
      );

      final openItem = items.firstWhere(
        (it) => it.key == TrayManagerService.menuItemOpenWebui,
      );
      final statusItem = items.firstWhere(
        (it) => it.key == TrayManagerService.menuItemWebuiStatus,
      );

      expect(openItem.label, '打开 WebUI');
      expect(openItem.disabled, isTrue);
      expect(statusItem.label, 'WebUI 服务：启动中');
      expect(statusItem.disabled, isTrue);
    });

    test('running 但 enabled=false 时 open_webui 仍置灰', () {
      final items = TrayManagerService.buildMenuItems(
        sidecarStatus: SidecarStatus.running,
        sidecarEnabled: false,
      );

      final openItem = items.firstWhere(
        (it) => it.key == TrayManagerService.menuItemOpenWebui,
      );
      expect(openItem.disabled, isTrue);
      final statusItem = items.firstWhere(
        (it) => it.key == TrayManagerService.menuItemWebuiStatus,
      );
      expect(statusItem.label, 'WebUI 服务：运行中');
    });

    test('会话列表渲染最近会话项并截取上限', () {
      final sessions = List.generate(
        10,
        (i) => SessionSummary(
          sessionId: 'sess_$i',
          title: '会话 $i',
          messageCount: 5,
        ),
      );

      final items = TrayManagerService.buildMenuItems(
        sessions: sessions,
        maxRecentSessions: 5,
      );

      final recentItems = items
          .where(
            (it) =>
                it.key?.startsWith(TrayManagerService.recentSessionPrefix) ==
                true,
          )
          .toList();

      expect(recentItems.length, 5);
      expect(recentItems[0].key, 'recent_sess_0');
      expect(recentItems[0].label, '会话 0');
      expect(recentItems[4].key, 'recent_sess_4');
      expect(recentItems[4].label, '会话 4');
    });

    test('自动过滤无消息占位会话', () {
      final sessions = [
        const SessionSummary(
          sessionId: 'placeholder',
          title: 'Untitled',
          messageCount: 0,
        ),
        const SessionSummary(
          sessionId: 'real_sess',
          title: '真实会话',
          messageCount: 2,
        ),
      ];

      final items = TrayManagerService.buildMenuItems(sessions: sessions);
      final recentItems = items
          .where(
            (it) =>
                it.key?.startsWith(TrayManagerService.recentSessionPrefix) ==
                true,
          )
          .toList();

      expect(recentItems.length, 1);
      expect(recentItems.first.key, 'recent_real_sess');
      expect(recentItems.first.label, '真实会话');
    });
  });

  group('TrayManagerService 系统托盘逻辑测试', () {
    test('非桌面平台 initialize / updateContextMenu / dispose 安全 no-op', () async {
      final service = TrayManagerService(isDesktop: false);

      await service.initialize();
      expect(service.isInitialized, isFalse);

      await service.updateContextMenu();
      await service.dispose();
    });

    test('handleShowWindow 触发自定义回调', () async {
      bool showCalled = false;
      final service = TrayManagerService(
        isDesktop: false,
        onShowWindow: () {
          showCalled = true;
        },
      );

      await service.handleShowWindow();
      expect(showCalled, isTrue);
    });

    test('handleNewSession 触发自定义回调', () async {
      bool newSessionCalled = false;
      final service = TrayManagerService(
        isDesktop: false,
        onNewSession: () {
          newSessionCalled = true;
        },
      );

      await service.handleNewSession();
      expect(newSessionCalled, isTrue);
    });

    test('handleOpenSession 触发自定义回调', () async {
      String? openedId;
      final service = TrayManagerService(
        isDesktop: false,
        onOpenSession: (sid) {
          openedId = sid;
        },
      );

      await service.handleOpenSession('target_session_999');
      expect(openedId, 'target_session_999');
    });

    test('handleQuit 触发自定义回调', () async {
      bool quitCalled = false;
      final service = TrayManagerService(
        isDesktop: false,
        onQuit: () {
          quitCalled = true;
        },
      );

      await service.handleQuit();
      expect(quitCalled, isTrue);
    });

    test('handleQuit: stop 先于 window destroy 被调用', () async {
      final calls = <String>[];
      final fakeSidecar = _FakeSidecarService(
        onStop: () async {
          calls.add('sidecar.stop');
        },
      );
      final service = TrayManagerService(
        isDesktop: false,
        sidecarService: fakeSidecar,
        onQuit: () async {
          calls.add('window.destroy');
        },
      );

      await service.handleQuit();

      expect(calls, ['sidecar.stop', 'window.destroy']);
      expect(fakeSidecar.stopCallCount, 1);
    });

    test('handleQuit: sidecar.stop 挂死 5s 时仍兜底继续退出', () {
      fakeAsync((async) {
        final calls = <String>[];
        final completer = Completer<void>();
        final fakeSidecar = _FakeSidecarService(
          onStop: () => completer.future,
        );
        final service = TrayManagerService(
          isDesktop: false,
          sidecarService: fakeSidecar,
          onQuit: () async {
            calls.add('window.destroy');
          },
        );

        bool quitFinished = false;
        unawaited(service.handleQuit().then((_) {
          quitFinished = true;
        }));

        async.elapse(const Duration(seconds: 4));
        expect(quitFinished, isFalse);
        expect(calls, isEmpty);

        async.elapse(const Duration(seconds: 1)); // 达到 5 秒超时
        async.flushMicrotasks();
        expect(quitFinished, isTrue);
        expect(calls, ['window.destroy']);
      });
    });

    test('handleOpenWebui: running 状态下通过 url_launcher 打开有效 URL', () async {
      final fakeLauncher = _FakeUrlLauncher();
      final oldLauncher = UrlLauncherPlatform.instance;
      UrlLauncherPlatform.instance = fakeLauncher;
      addTearDown(() => UrlLauncherPlatform.instance = oldLauncher);

      final service = TrayManagerService(
        isDesktop: false,
        getSidecarState: () => const SidecarState(status: SidecarStatus.running),
        getSidecarConfig: () => const SidecarConfig(
          enabled: true,
          host: '127.0.0.1',
          port: 8787,
        ),
      );

      await service.handleOpenWebui();

      expect(fakeLauncher.launchedUrl, 'http://127.0.0.1:8787');
      expect(
        fakeLauncher.lastOptions?.mode,
        PreferredLaunchMode.externalApplication,
      );
    });

    test('handleOpenWebui: host 为 0.0.0.0 时自动转为 127.0.0.1 打开', () async {
      final fakeLauncher = _FakeUrlLauncher();
      final oldLauncher = UrlLauncherPlatform.instance;
      UrlLauncherPlatform.instance = fakeLauncher;
      addTearDown(() => UrlLauncherPlatform.instance = oldLauncher);

      final service = TrayManagerService(
        isDesktop: false,
        getSidecarState: () => const SidecarState(status: SidecarStatus.running),
        getSidecarConfig: () => const SidecarConfig(
          enabled: true,
          host: '0.0.0.0',
          port: 9090,
        ),
      );

      await service.handleOpenWebui();

      expect(fakeLauncher.launchedUrl, 'http://127.0.0.1:9090');
    });

    test('handleOpenWebui: stopped 或 failed 状态下点击不调 url_launcher（防 Windows 托盘 bug）', () async {
      final fakeLauncher = _FakeUrlLauncher();
      final oldLauncher = UrlLauncherPlatform.instance;
      UrlLauncherPlatform.instance = fakeLauncher;
      addTearDown(() => UrlLauncherPlatform.instance = oldLauncher);

      final stoppedService = TrayManagerService(
        isDesktop: false,
        getSidecarState: () => const SidecarState(status: SidecarStatus.stopped),
        getSidecarConfig: () => const SidecarConfig(enabled: true),
      );
      await stoppedService.handleOpenWebui();
      expect(fakeLauncher.launchedUrl, isNull);

      final failedService = TrayManagerService(
        isDesktop: false,
        getSidecarState: () => const SidecarState(status: SidecarStatus.failed),
        getSidecarConfig: () => const SidecarConfig(enabled: true),
      );
      await failedService.handleOpenWebui();
      expect(fakeLauncher.launchedUrl, isNull);

      final disabledService = TrayManagerService(
        isDesktop: false,
        getSidecarState: () => const SidecarState(status: SidecarStatus.running),
        getSidecarConfig: () => const SidecarConfig(enabled: false),
      );
      await disabledService.handleOpenWebui();
      expect(fakeLauncher.launchedUrl, isNull);
    });

    test('onTrayIconMouseDown 触发 handleShowWindow', () async {
      bool showCalled = false;
      final service = TrayManagerService(
        isDesktop: false,
        onShowWindow: () {
          showCalled = true;
        },
      );

      service.onTrayIconMouseDown();
      await pumpEventQueue();
      expect(showCalled, isTrue);
    });

    test('onTrayMenuItemClick 菜单项分发（包含最近会话分发与 open_webui）', () async {
      final fakeLauncher = _FakeUrlLauncher();
      final oldLauncher = UrlLauncherPlatform.instance;
      UrlLauncherPlatform.instance = fakeLauncher;
      addTearDown(() => UrlLauncherPlatform.instance = oldLauncher);

      bool showCalled = false;
      bool newSessionCalled = false;
      String? openedSessionId;
      bool quitCalled = false;

      final service = TrayManagerService(
        isDesktop: false,
        onShowWindow: () => showCalled = true,
        onNewSession: () => newSessionCalled = true,
        onOpenSession: (sid) => openedSessionId = sid,
        onQuit: () => quitCalled = true,
        getSidecarState: () => const SidecarState(status: SidecarStatus.running),
        getSidecarConfig: () => const SidecarConfig(
          enabled: true,
          host: '127.0.0.1',
          port: 8787,
        ),
      );

      service.onTrayMenuItemClick(
        MenuItem(key: TrayManagerService.menuItemShowWindow, label: '显示主窗口'),
      );
      await pumpEventQueue();
      expect(showCalled, isTrue);

      service.onTrayMenuItemClick(
        MenuItem(key: TrayManagerService.menuItemNewSession, label: '新建会话'),
      );
      await pumpEventQueue();
      expect(newSessionCalled, isTrue);

      service.onTrayMenuItemClick(
        MenuItem(key: TrayManagerService.menuItemOpenWebui, label: '打开 WebUI'),
      );
      await pumpEventQueue();
      expect(fakeLauncher.launchedUrl, 'http://127.0.0.1:8787');

      service.onTrayMenuItemClick(
        MenuItem(key: 'recent_sess_abc', label: '会话 ABC'),
      );
      await pumpEventQueue();
      expect(openedSessionId, 'sess_abc');

      service.onTrayMenuItemClick(
        MenuItem(key: TrayManagerService.menuItemQuitApp, label: '退出应用'),
      );
      await pumpEventQueue();
      expect(quitCalled, isTrue);
    });

    test('Provider 注入与释放测试', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final service = container.read(trayManagerServiceProvider);
      expect(service, isNotNull);
    });
  });

  group('prepareTrayIconFile ICO 分支', () {
    test('写入 .ico 资产时保留 ICO 字节与 .ico 后缀', () async {
      final tempDir = Directory.systemTemp.createTempSync('tray_ico_test_');
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });

      // 最小合法 ICO 头：保留字 0 + 类型 1 + 数量 1，后续 16 字节目录项
      // 这里仅验证字节透传能力，不要求图像合法
      final icoBytes = Uint8List.fromList([
        0x00, 0x00, // reserved
        0x01, 0x00, // type = 1 (ICO)
        0x01, 0x00, // count = 1
        0x10, 0x10, 0x00, 0x00, 0x01, 0x00, 0x04, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x16, 0x00, 0x00, 0x00,
        0x28, 0x00, 0x00, 0x00,
      ]);
      final fakeBundle = _FakeAssetBundle(icoBytes);

      final iconPath = await prepareTrayIconFile(
        assetBundle: fakeBundle,
        tempDir: tempDir,
        assetPath: 'assets/branding/tray_icon.ico',
        fileName: 'hermes_tray_icon.ico',
      );

      expect(iconPath.endsWith('.ico'), isTrue);
      final file = File(iconPath);
      expect(file.existsSync(), isTrue);
      expect(file.absolute.path, iconPath);
      expect(await file.readAsBytes(), icoBytes);
    });

    test('返回路径为绝对路径', () async {
      final tempDir = Directory.systemTemp.createTempSync('tray_abs_test_');
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });
      final fakeBundle = _FakeAssetBundle(Uint8List.fromList([0x00, 0x01]));
      final iconPath = await prepareTrayIconFile(
        assetBundle: fakeBundle,
        tempDir: tempDir,
        assetPath: 'assets/branding/tray_icon.ico',
        fileName: 'hermes_tray_icon.ico',
      );
      expect(File(iconPath).isAbsolute, isTrue);
    });
  });
}
