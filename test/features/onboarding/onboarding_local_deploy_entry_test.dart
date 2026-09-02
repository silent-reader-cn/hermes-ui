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
  Future<bool> isInstalled() async => installed;
}

void main() {
  late InMemorySecureStorage storage;
  late _FakeInstallDetector detector;

  setUp(() {
    storage = InMemorySecureStorage();
    detector = _FakeInstallDetector();
    SharedPreferences.setMockInitialValues({});
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

  testWidgets('Windows 且未安装 Hermes → OnboardingPage 显示「本机部署」入口并可跳转', (tester) async {
    detector.isWindows = true;
    detector.installed = false;

    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    expect(find.text('本机部署'), findsOneWidget);
    expect(find.byKey(const ValueKey('onboarding-local-deploy-btn')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('onboarding-local-deploy-btn')));
    await tester.pumpAndSettle();

    expect(find.text('Windows 本机部署向导'), findsAtLeastNWidgets(1));
  });

  testWidgets('Windows 但已安装 Hermes → OnboardingPage 不显示「本机部署」入口', (tester) async {
    detector.isWindows = true;
    detector.installed = true;

    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    expect(find.text('本机部署'), findsNothing);
    expect(find.byKey(const ValueKey('onboarding-local-deploy-btn')), findsNothing);
  });

  testWidgets('非 Windows 平台 → OnboardingPage 不显示「本机部署」入口', (tester) async {
    detector.isWindows = false;
    detector.installed = false;

    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    expect(find.text('本机部署'), findsNothing);
    expect(find.byKey(const ValueKey('onboarding-local-deploy-btn')), findsNothing);
  });
}
