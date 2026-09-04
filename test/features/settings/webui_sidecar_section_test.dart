import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/features/settings/settings_subpages.dart';
import 'package:hermes_ui/features/settings/webui_sidecar_section.dart';
import 'package:hermes_ui/features/webui_sidecar/webui_sidecar_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeSidecarFileSystem implements SidecarFileSystem {
  @override
  bool isWindows = true;
  bool bundleAvailable = true;

  @override
  bool isBundleAvailable() => isWindows && bundleAvailable;

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
  Future<void> appendLogLine(String path, String line) async {}

  @override
  Future<void> createDirectory(String path, {bool recursive = true}) async {}

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
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeSidecarFileSystem fakeFs;
  late _FakeSecureStorage fakeSecureStorage;
  late _MockWebuiSidecarService mockService;
  late ProviderContainer container;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    fakeFs = _FakeSidecarFileSystem();
    fakeSecureStorage = _FakeSecureStorage();
    mockService = _MockWebuiSidecarService();

    fakeSecureStorage.values[WebuiSidecarConfigStorage.keyPassword] =
        'init-secret-123456';

    container = ProviderContainer(
      overrides: [
        sidecarFileSystemProvider.overrideWithValue(fakeFs),
        webuiSidecarConfigStorageProvider.overrideWithValue(
          WebuiSidecarConfigStorage(
            prefs: prefs,
            secureStorage: fakeSecureStorage,
          ),
        ),
        webuiSidecarServiceProvider.overrideWithValue(mockService),
      ],
    );
    await container.read(webuiSidecarConfigProvider.notifier).load();
  });

  tearDown(() {
    container.dispose();
  });

  Widget buildTestWidget({Widget? child}) {
    return UncontrolledProviderScope(
      container: container,
      child: CupertinoApp(
        home: CupertinoPageScaffold(
          child: ListView(
            children: [
              child ?? const WebuiSidecarSection(),
            ],
          ),
        ),
      ),
    );
  }

  group('WebuiSidecarSection 开关与生命周期联动', () {
    testWidgets('开关切换联动 setEnabled 与 start/stop', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      final switchFinder = find.byKey(
        const ValueKey('settings-webui-enable-switch'),
      );
      expect(switchFinder, findsOneWidget);
      expect(tester.widget<CupertinoSwitch>(switchFinder).value, isFalse);

      // 切换开启 -> 触发 setEnabled(true) 与 start()
      await tester.tap(switchFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(mockService.startCalls, 1);
      expect(container.read(webuiSidecarConfigProvider).enabled, isTrue);
      expect(tester.widget<CupertinoSwitch>(switchFinder).value, isTrue);

      // 切换关闭 -> 触发 setEnabled(false) 与 stop()
      await tester.tap(switchFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(mockService.stopCalls, 1);
      expect(container.read(webuiSidecarConfigProvider).enabled, isFalse);
      expect(tester.widget<CupertinoSwitch>(switchFinder).value, isFalse);
    });
  });

  group('WebuiSidecarSection 监听 IP 校验与提交', () {
    testWidgets('非法 IPv4 红字就地提示且不提交；合法 IPv4 失焦提交', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      final hostFieldFinder = find.byKey(
        const ValueKey('settings-webui-host-input'),
      );
      expect(hostFieldFinder, findsOneWidget);

      // 输入非法 IPv4
      await tester.enterText(hostFieldFinder, '999.999.999.999');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.text('请输入合法的 IPv4 地址'), findsOneWidget);
      expect(
        container.read(webuiSidecarConfigProvider).host,
        SidecarConfig.defaultHost,
      );

      // 输入字母非法 IP
      await tester.enterText(hostFieldFinder, 'invalid-ip');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.text('请输入合法的 IPv4 地址'), findsOneWidget);
      expect(
        container.read(webuiSidecarConfigProvider).host,
        SidecarConfig.defaultHost,
      );

      // 输入合法 IPv4 (0.0.0.0 允许)
      await tester.enterText(hostFieldFinder, '0.0.0.0');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.text('请输入合法的 IPv4 地址'), findsNothing);
      expect(container.read(webuiSidecarConfigProvider).host, '0.0.0.0');

      // 输入 192.168.1.100 合法
      await tester.enterText(hostFieldFinder, '192.168.1.100');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.text('请输入合法的 IPv4 地址'), findsNothing);
      expect(container.read(webuiSidecarConfigProvider).host, '192.168.1.100');
    });
  });

  group('WebuiSidecarSection 端口输入与校验', () {
    testWidgets('非法端口（<1 或 >65535 或非数字）红字提示且不提交；合法端口提交', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      final portFieldFinder = find.byKey(
        const ValueKey('settings-webui-port-input'),
      );
      expect(portFieldFinder, findsOneWidget);

      // 0 非法
      await tester.enterText(portFieldFinder, '0');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.text('端口号必须在 1-65535 之间'), findsOneWidget);
      expect(
        container.read(webuiSidecarConfigProvider).port,
        SidecarConfig.defaultPort,
      );

      // 70000 超限非法
      await tester.enterText(portFieldFinder, '70000');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.text('端口号必须在 1-65535 之间'), findsOneWidget);
      expect(
        container.read(webuiSidecarConfigProvider).port,
        SidecarConfig.defaultPort,
      );

      // 非数字非法
      await tester.enterText(portFieldFinder, 'abc');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.text('端口号必须在 1-65535 之间'), findsOneWidget);

      // 合法端口 8080
      await tester.enterText(portFieldFinder, '8080');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.text('端口号必须在 1-65535 之间'), findsNothing);
      expect(container.read(webuiSidecarConfigProvider).port, 8080);
    });
  });

  group('WebuiSidecarSection 密码脱敏展示、编辑与复制', () {
    testWidgets('显示态脱敏展示，编辑按钮明文就地切换，复制按钮存入剪贴板', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // 显示态脱敏验证
      final maskedFinder = find.byKey(
        const ValueKey('settings-webui-password-display'),
      );
      expect(maskedFinder, findsOneWidget);
      expect(find.text('••••••••'), findsOneWidget);
      expect(find.text('init-secret-123456'), findsNothing);

      // 复制功能测试
      String? clipboardText;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall methodCall) async {
          if (methodCall.method == 'Clipboard.setData') {
            clipboardText = (methodCall.arguments as Map)['text'] as String?;
            return null;
          }
          if (methodCall.method == 'Clipboard.getData') {
            return {'text': clipboardText};
          }
          return null;
        },
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        );
      });

      final copyBtnFinder = find.byKey(
        const ValueKey('settings-webui-copy-password-btn'),
      );
      expect(copyBtnFinder, findsOneWidget);
      await tester.tap(copyBtnFinder);
      await tester.pump();

      expect(clipboardText, 'init-secret-123456');

      // 点击编辑 -> 就地切换明文输入框
      final editBtnFinder = find.byKey(
        const ValueKey('settings-webui-edit-password-btn'),
      );
      expect(editBtnFinder, findsOneWidget);
      await tester.tap(editBtnFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final passwordInputFinder = find.byKey(
        const ValueKey('settings-webui-password-input'),
      );
      expect(passwordInputFinder, findsOneWidget);
      final textField = tester.widget<CupertinoTextField>(passwordInputFinder);
      expect(textField.obscureText, isFalse);
      expect(textField.controller?.text, 'init-secret-123456');

      // 空密码校验
      await tester.enterText(passwordInputFinder, '');
      final saveBtnFinder = find.byKey(
        const ValueKey('settings-webui-save-password-btn'),
      );
      await tester.tap(saveBtnFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('密码不能为空'), findsOneWidget);
      expect(
        fakeSecureStorage.values[WebuiSidecarConfigStorage.keyPassword],
        'init-secret-123456',
      );

      // 取消按钮测试
      final cancelBtnFinder = find.byKey(
        const ValueKey('settings-webui-cancel-password-btn'),
      );
      await tester.tap(cancelBtnFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(maskedFinder, findsOneWidget);
      expect(passwordInputFinder, findsNothing);

      // 再次点击编辑并保存新密码
      await tester.tap(editBtnFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.enterText(
        find.byKey(const ValueKey('settings-webui-password-input')),
        'new-secret-999888',
      );
      await tester.tap(
        find.byKey(const ValueKey('settings-webui-save-password-btn')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(maskedFinder, findsOneWidget);
      expect(find.text('new-secret-999888'), findsNothing);
      expect(container.read(webuiSidecarConfigProvider).password, 'new-secret-999888');
      expect(
        fakeSecureStorage.values[WebuiSidecarConfigStorage.keyPassword],
        'new-secret-999888',
      );
    });
  });

  group('WebuiSidecarSection 状态指示四态渲染断言', () {
    testWidgets('已停止 (stopped) 状态渲染', (tester) async {
      mockService.emitState(const SidecarState(status: SidecarStatus.stopped));
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('服务状态'), findsOneWidget);
      expect(find.text('○ 已停止'), findsOneWidget);
    });

    testWidgets('启动中 (starting) 状态渲染', (tester) async {
      mockService.emitState(const SidecarState(status: SidecarStatus.starting));
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('服务状态'), findsOneWidget);
      expect(find.text('◐ 启动中…'), findsOneWidget);
    });

    testWidgets('运行中 (running) 状态渲染附 PID', (tester) async {
      mockService.emitState(
        const SidecarState(status: SidecarStatus.running, pid: 4567),
      );
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('服务状态'), findsOneWidget);
      expect(find.text('● 运行中'), findsOneWidget);
      expect(find.text('PID: 4567'), findsOneWidget);
    });

    testWidgets('失败 (failed) 状态渲染附四种 reason 文案', (tester) async {
      // 1. 端口占用
      mockService.emitState(
        const SidecarState(
          status: SidecarStatus.failed,
          reason: SidecarFailureReason.portOccupied,
        ),
      );
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('● 启动失败'), findsOneWidget);
      expect(find.text('端口占用'), findsOneWidget);

      // 2. 缺内置包
      mockService.emitState(
        const SidecarState(
          status: SidecarStatus.failed,
          reason: SidecarFailureReason.missingBundle,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('缺内置包'), findsOneWidget);

      // 3. 健康超时
      mockService.emitState(
        const SidecarState(
          status: SidecarStatus.failed,
          reason: SidecarFailureReason.healthTimeout,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('健康超时'), findsOneWidget);

      // 4. 启动失败
      mockService.emitState(
        const SidecarState(
          status: SidecarStatus.failed,
          reason: SidecarFailureReason.startFailed,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('启动失败'), findsWidgets);
    });
  });

  group('WebuiSidecarSection 平台与内置包缺失提示', () {
    testWidgets('缺少内置包时渲染顶部灰字提示', (tester) async {
      fakeFs.bundleAvailable = false;
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      final hintFinder = find.byKey(
        const ValueKey('settings-webui-missing-bundle-hint'),
      );
      expect(hintFinder, findsOneWidget);
      expect(find.text('未检测到内置 WebUI 包'), findsOneWidget);
    });

    testWidgets('内置包存在且 Windows 平台时不渲染缺失提示', (tester) async {
      fakeFs.bundleAvailable = true;
      fakeFs.isWindows = true;
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      final hintFinder = find.byKey(
        const ValueKey('settings-webui-missing-bundle-hint'),
      );
      expect(hintFinder, findsNothing);
    });
  });

  group('WebuiSidecarSection 日志入口与二级页集成', () {
    testWidgets('渲染打开日志目录行项', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      final openLogsFinder = find.byKey(
        const ValueKey('settings-webui-open-logs'),
      );
      expect(openLogsFinder, findsOneWidget);
      expect(find.text('打开日志目录'), findsOneWidget);
    });

    testWidgets('DesktopSettingsPage 在 Windows 下渲染内置 WebUI 分组', (tester) async {
      // DesktopSettingsPage 自带 ListView，不能再套滚动容器（嵌套 viewport 无界高度）
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const CupertinoApp(home: DesktopSettingsPage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('内置 WebUI 服务'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('settings-webui-enable-switch')),
        findsOneWidget,
      );
    });
  });
}
