import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/app/app.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/connections/connection_store.dart';
import 'package:hermes_ui/core/install/install_detector.dart';
import 'package:hermes_ui/features/session_list/session_list_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_session_list_api.dart';
import '../../helpers/in_memory_secure_storage.dart';

class _FakeInstallDetector implements InstallDetector {
  _FakeInstallDetector();

  @override
  bool isWindows = true;
  bool installed = false;

  @override
  String get localAppDataPath => r'C:\Users\Admin\AppData\Local';
  @override
  String get hermesHomePath => r'C:\Users\Admin\AppData\Local\hermes';
  @override
  String get hermesAgentPath => r'C:\Users\Admin\AppData\Local\hermes\hermes-agent';
  @override
  String get webuiPath => r'C:\Users\Admin\AppData\Local\hermes\webui';

  @override
  Future<bool> agentInstalled() async => installed;

  @override
  bool bundledWebuiAvailable() => false;

  @override
  Future<bool> isInstalled() async => installed;
}

void main() {
  late InMemorySecureStorage storage;
  late _FakeInstallDetector detector;

  setUp(() {
    storage = InMemorySecureStorage();
    detector = _FakeInstallDetector();
    SharedPreferences.setMockInitialValues({'app_locale_mode': 'zh'});
  });

  Widget buildApp() {
    return ProviderScope(
      overrides: [
        connectionStoreProvider.overrideWithValue(
          ConnectionStore(storage: storage),
        ),
        installDetectorProvider.overrideWithValue(detector),
        sessionListApiFactoryProvider.overrideWithValue(
          (_) => FakeSessionListApi(),
        ),
      ],
      child: const HermesApp(),
    );
  }

  testWidgets('OnboardingPage 已裁撤旧版本地部署 Banner（Windows 未安装时也不再展示）', (tester) async {
    detector.isWindows = true;
    detector.installed = false;

    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    expect(find.text('本机部署'), findsNothing);
    expect(find.byKey(const ValueKey('onboarding-local-deploy-btn')), findsNothing);
  });

  testWidgets('非 Windows 平台 → OnboardingPage 亦不显示「本机部署」入口', (tester) async {
    detector.isWindows = false;
    detector.installed = false;

    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    expect(find.text('本机部署'), findsNothing);
    expect(find.byKey(const ValueKey('onboarding-local-deploy-btn')), findsNothing);
  });
}
