import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/connections/connection_store.dart';
import 'package:hermes_ui/features/onboarding/onboarding_providers.dart';
import 'package:hermes_ui/features/settings/settings_page.dart';
import 'package:hermes_ui/features/settings/settings_providers.dart';
import 'package:hermes_ui/features/settings/smooth_streaming_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_onboarding_login_api.dart';
import '../../helpers/fake_settings_api.dart';
import '../../helpers/in_memory_secure_storage.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('SmoothStreamingController 状态与持久化', () {
    test('默认值为 true', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final state = container.read(smoothStreamingProvider);
      expect(state, isTrue);
    });

    test('初始状态从 SharedPreferences 读取', () async {
      SharedPreferences.setMockInitialValues({kSmoothStreamingKey: false});

      final container = ProviderContainer();
      addTearDown(container.dispose);

      final controller = container.read(smoothStreamingProvider.notifier);
      await controller.load();

      final state = container.read(smoothStreamingProvider);
      expect(state, isFalse);
    });

    test('setSmoothStreaming 修改配置并写入 SharedPreferences', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final controller = container.read(smoothStreamingProvider.notifier);
      await controller.setSmoothStreaming(false);

      expect(container.read(smoothStreamingProvider), isFalse);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(kSmoothStreamingKey), isFalse);

      await controller.setSmoothStreaming(true);
      expect(container.read(smoothStreamingProvider), isTrue);
      expect(prefs.getBool(kSmoothStreamingKey), isTrue);
    });
  });

  group('SettingsPage 平滑输出设置项 Widget 测试', () {
    testWidgets('渲染平滑输出开关并响应点击切换', (tester) async {
      final container = ProviderContainer(
        overrides: [
          connectionStoreProvider.overrideWithValue(
            ConnectionStore(storage: InMemorySecureStorage()),
          ),
          apiClientProvider.overrideWithValue(
            ApiClient(baseUrl: 'http://test.local:30002'),
          ),
          settingsApiFactoryProvider.overrideWithValue(
            (_) => FakeSettingsApi(),
          ),
          onboardingApiFactoryProvider.overrideWithValue(
            (_, _) => FakeOnboardingLoginApi(),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const CupertinoApp(
            home: SettingsPage(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final tileFinder = find.byKey(const ValueKey('settings-smooth-streaming'));
      expect(tileFinder, findsOneWidget);

      final switchFinder = find.byKey(
        const ValueKey('settings-switch-smooth-streaming'),
      );
      expect(switchFinder, findsOneWidget);

      expect(find.text('对话'), findsOneWidget);
      expect(find.text('平滑输出'), findsOneWidget);
      expect(find.text('逐字平滑输出，积压时自适应加速'), findsOneWidget);

      // 默认开启
      expect(tester.widget<CupertinoSwitch>(switchFinder).value, isTrue);

      // 点击切换为关闭
      await tester.tap(switchFinder);
      await tester.pumpAndSettle();

      expect(container.read(smoothStreamingProvider), isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(kSmoothStreamingKey), isFalse);

      // 再次点击恢复开启
      await tester.tap(switchFinder);
      await tester.pumpAndSettle();

      expect(container.read(smoothStreamingProvider), isTrue);
      expect(prefs.getBool(kSmoothStreamingKey), isTrue);
    });
  });
}
