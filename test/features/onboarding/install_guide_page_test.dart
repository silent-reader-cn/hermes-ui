import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hermes_ui/app/app.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/connections/connection_store.dart';
import 'package:hermes_ui/core/install/install_detector.dart';
import 'package:hermes_ui/core/install/llm_onboarding.dart';
import 'package:hermes_ui/core/install/powershell_installer.dart';
import 'package:hermes_ui/core/install/webui_bootstrap.dart';
import 'package:hermes_ui/features/onboarding/onboarding_page.dart';
import 'package:hermes_ui/features/session_list/session_list_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_session_list_api.dart';
import '../../helpers/in_memory_secure_storage.dart';

class _FakeInstallDetector implements InstallDetector {
  _FakeInstallDetector();

  @override
  bool isWindows = true;

  @override
  String get localAppDataPath => r'C:\Users\Admin\AppData\Local';
  @override
  String get hermesHomePath => r'C:\Users\Admin\AppData\Local\hermes';
  @override
  String get hermesAgentPath => r'C:\Users\Admin\AppData\Local\hermes\hermes-agent';
  @override
  String get webuiPath => r'C:\Users\Admin\AppData\Local\hermes\webui';

  @override
  Future<bool> agentInstalled() async => false;

  @override
  bool bundledWebuiAvailable() => false;

  @override
  Future<bool> isInstalled() async => agentInstalled();
}

class _FakePowershellInstaller implements PowershellInstaller {
  _FakePowershellInstaller();

  Map<String, String> stageFailures = {};
  final List<String> stagesExecuted = [];

  @override
  Future<String> ensureScriptCached({
    String url = PowershellInstaller.defaultScriptUrl,
    String? destinationPath,
  }) async =>
      destinationPath ?? r'C:\Users\Admin\AppData\Local\hermes\install.ps1';

  @override
  Future<List<String>> getManifest({String? scriptPath}) async =>
      ['prereqs', 'agent', 'deps'];

  @override
  Stream<InstallerEvent> runStage(
    String stageName, {
    String? scriptPath,
    String? hermesHome,
  }) async* {
    stagesExecuted.add(stageName);
    yield InstallerEvent.stageStart(stageName, title: 'Starting $stageName');
    yield InstallerEvent.log('Running step $stageName...', stage: stageName);

    if (stageFailures.containsKey(stageName)) {
      yield InstallerEvent.stageFailure(
        stageName,
        stageFailures[stageName]!,
      );
      return;
    }

    yield InstallerEvent.stageSuccess(
      stageName,
      message: '$stageName ok',
    );
  }
}

class _FakeWebuiBootstrap implements WebuiBootstrap {
  _FakeWebuiBootstrap();

  final List<String> executed = [];

  @override
  Future<bool> waitForHealth({String baseUrl = 'http://127.0.0.1:8787', Duration timeout = const Duration(seconds: 30), Duration interval = const Duration(milliseconds: 500)}) async {
    executed.add('health');
    return true;
  }

  @override
  String resolvePythonPath() => 'python.exe';
}

class _FakeLlmOnboardingApi implements LlmOnboardingApi {
  _FakeLlmOnboardingApi();

  LlmOnboardingConfig? lastConfig;

  @override
  Future<bool> saveConfig({
    required String serverBaseUrl,
    required LlmOnboardingConfig config,
  }) async {
    lastConfig = config;
    return true;
  }
}

void main() {
  late InMemorySecureStorage storage;
  late _FakeInstallDetector detector;
  late _FakePowershellInstaller psInstaller;
  late _FakeWebuiBootstrap webuiBootstrap;
  late _FakeLlmOnboardingApi llmApi;

  setUp(() {
    storage = InMemorySecureStorage();
    detector = _FakeInstallDetector();
    psInstaller = _FakePowershellInstaller();
    webuiBootstrap = _FakeWebuiBootstrap();
    llmApi = _FakeLlmOnboardingApi();
    SharedPreferences.setMockInitialValues({'app_locale_mode': 'zh'});
  });

  Widget buildTestApp(WidgetTester tester, {bool isWindows = true}) {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    detector.isWindows = isWindows;
    return ProviderScope(
      overrides: [
        connectionStoreProvider.overrideWithValue(
          ConnectionStore(storage: storage),
        ),
        installDetectorProvider.overrideWithValue(detector),
        powershellInstallerProvider.overrideWithValue(psInstaller),
        webuiBootstrapProvider.overrideWithValue(webuiBootstrap),
        llmOnboardingApiProvider.overrideWithValue(llmApi),
        sessionListApiFactoryProvider.overrideWithValue(
          (_) => FakeSessionListApi(),
        ),
      ],
      child: const HermesApp(),
    );
  }

  testWidgets('非 Windows 平台进入安装引导页 → 显示「仅支持 Windows」提示并可返回', (tester) async {
    await tester.pumpWidget(buildTestApp(tester, isWindows: false));
    await tester.pumpAndSettle();

    // 在已渲染的 OnboardingPage 内部 context 进行路由跳转
    final BuildContext context = tester.element(find.byType(OnboardingPage));
    GoRouter.of(context).go('/install-guide');
    await tester.pumpAndSettle();

    expect(find.text('本机部署向导仅支持 Windows 系统'), findsOneWidget);
    expect(find.text('返回远程连接'), findsOneWidget);

    await tester.tap(find.text('返回远程连接'));
    await tester.pumpAndSettle();

    expect(find.text('连接你的 Hermes 服务器'), findsOneWidget);
  });

  testWidgets('Windows 平台首启向导页 → 渲染各 stage 列表与「开始一键安装」按钮', (tester) async {
    await tester.pumpWidget(buildTestApp(tester, isWindows: true));
    await tester.pumpAndSettle();

    final BuildContext context = tester.element(find.byType(OnboardingPage));
    GoRouter.of(context).go('/install-guide');
    await tester.pumpAndSettle();

    expect(find.text('Windows 本机部署向导'), findsAtLeastNWidgets(1));
    expect(find.text('环境检查'), findsOneWidget);
    expect(find.text('拉取 Agent'), findsOneWidget);
    expect(find.text('安装依赖'), findsOneWidget);
    expect(find.text('配置模型'), findsOneWidget);
    expect(find.byKey(const ValueKey('install-guide-start-btn')), findsOneWidget);
  });

  testWidgets('点击一键安装 → 依次执行 stages → 顺利抵达模型配置阶段', (tester) async {
    await tester.pumpWidget(buildTestApp(tester, isWindows: true));
    await tester.pumpAndSettle();

    final BuildContext context = tester.element(find.byType(OnboardingPage));
    GoRouter.of(context).go('/install-guide');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('install-guide-start-btn')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    // 验证调度执行了全部安装步骤
    expect(psInstaller.stagesExecuted, ['prereqs', 'agent', 'deps']);
    expect(webuiBootstrap.executed, isEmpty);

    // 成功切换到模型配置表单
    expect(find.text('选择模型服务商'), findsOneWidget);
    expect(find.byKey(const ValueKey('install-guide-save-model-btn')), findsOneWidget);
    expect(find.byKey(const ValueKey('install-guide-skip-model-btn')), findsOneWidget);
  });

  testWidgets('步骤失败 → 显示错误卡片与重试按钮 → 点击重试成功后继续前进', (tester) async {
    psInstaller.stageFailures = {'agent': 'Git clone failed'};
    await tester.pumpWidget(buildTestApp(tester, isWindows: true));
    await tester.pumpAndSettle();

    final BuildContext context = tester.element(find.byType(OnboardingPage));
    GoRouter.of(context).go('/install-guide');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('install-guide-start-btn')));
    await tester.pumpAndSettle();

    // 验证失败态展示
    expect(find.text('步骤失败: 拉取 Agent'), findsOneWidget);
    expect(find.text('Git clone failed'), findsOneWidget);
    expect(find.byKey(const ValueKey('install-guide-retry-btn')), findsOneWidget);

    // 修复错误并点击重试
    psInstaller.stageFailures = {};
    await tester.tap(find.byKey(const ValueKey('install-guide-retry-btn')));
    await tester.pumpAndSettle();

    // 重试后成功进入模型配置
    expect(find.text('选择模型服务商'), findsOneWidget);
  });

  testWidgets('模型配置页：未填 API Key 校验提示；填入并提交 → 保存连接并进入会话列表', (tester) async {
    await tester.pumpWidget(buildTestApp(tester, isWindows: true));
    await tester.pumpAndSettle();

    final BuildContext context = tester.element(find.byType(OnboardingPage));
    GoRouter.of(context).go('/install-guide');
    await tester.pumpAndSettle();

    // 运行安装到达模型配置
    await tester.tap(find.byKey(const ValueKey('install-guide-start-btn')));
    await tester.pumpAndSettle();

    // 尝试直接提交（默认选 OpenRouter 需要 API Key）
    await tester.tap(find.byKey(const ValueKey('install-guide-save-model-btn')));
    await tester.pumpAndSettle();

    expect(find.text('❌ 该服务商需要填写 API Key'), findsOneWidget);
    expect(llmApi.lastConfig, isNull);

    // 填入 API Key 后提交
    await tester.enterText(
      find.byKey(const ValueKey('install-guide-apikey-input')),
      'sk-or-v1-my-key',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('install-guide-save-model-btn')));
    await tester.pumpAndSettle();

    expect(llmApi.lastConfig?.provider, 'openrouter');
    expect(llmApi.lastConfig?.apiKey, 'sk-or-v1-my-key');

    // 验证连接已持久化并跳转会话列表
    final activeId = storage.data[ConnectionStore.activeConnectionKey];
    expect(activeId, isNotNull);
    expect(find.text('暂无会话'), findsOneWidget);
  });

  testWidgets('模型配置页：点「暂不配置，稍后设置」→ 写入本地连接并跳转会话列表', (tester) async {
    await tester.pumpWidget(buildTestApp(tester, isWindows: true));
    await tester.pumpAndSettle();

    final BuildContext context = tester.element(find.byType(OnboardingPage));
    GoRouter.of(context).go('/install-guide');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('install-guide-start-btn')));
    await tester.pumpAndSettle();

    // 点击跳过
    await tester.tap(find.byKey(const ValueKey('install-guide-skip-model-btn')));
    await tester.pumpAndSettle();

    expect(llmApi.lastConfig, isNull);
    final activeId = storage.data[ConnectionStore.activeConnectionKey];
    expect(activeId, isNotNull);
    expect(find.text('暂无会话'), findsOneWidget);
  });
}
