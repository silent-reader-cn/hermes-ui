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

  group('SmoothStreamingSpeedPreset 参数与解析', () {
    test('五档参数准确无误', () {
      expect(
        SmoothStreamingSpeedPreset.charByChar.revealInterval,
        const Duration(milliseconds: 100),
      );
      expect(SmoothStreamingSpeedPreset.charByChar.wordUnitsPerTick, 1);
      expect(SmoothStreamingSpeedPreset.charByChar.cjkChunkSize, 1);
      expect(
        SmoothStreamingSpeedPreset.charByChar.maxRevealLag,
        const Duration(seconds: 8),
      );
      expect(SmoothStreamingSpeedPreset.charByChar.isAdaptive, isFalse);

      expect(
        SmoothStreamingSpeedPreset.slow.revealInterval,
        const Duration(milliseconds: 80),
      );
      expect(SmoothStreamingSpeedPreset.slow.wordUnitsPerTick, 1);
      expect(SmoothStreamingSpeedPreset.slow.cjkChunkSize, 2);
      expect(
        SmoothStreamingSpeedPreset.slow.maxRevealLag,
        const Duration(seconds: 5),
      );
      expect(SmoothStreamingSpeedPreset.slow.isAdaptive, isFalse);

      expect(
        SmoothStreamingSpeedPreset.standard.revealInterval,
        const Duration(milliseconds: 64),
      );
      expect(SmoothStreamingSpeedPreset.standard.wordUnitsPerTick, 2);
      expect(SmoothStreamingSpeedPreset.standard.cjkChunkSize, 2);
      expect(
        SmoothStreamingSpeedPreset.standard.maxRevealLag,
        const Duration(seconds: 3),
      );
      expect(SmoothStreamingSpeedPreset.standard.isAdaptive, isFalse);

      expect(
        SmoothStreamingSpeedPreset.fast.revealInterval,
        const Duration(milliseconds: 48),
      );
      expect(SmoothStreamingSpeedPreset.fast.wordUnitsPerTick, 3);
      expect(SmoothStreamingSpeedPreset.fast.cjkChunkSize, 4);
      expect(
        SmoothStreamingSpeedPreset.fast.maxRevealLag,
        const Duration(seconds: 2),
      );
      expect(SmoothStreamingSpeedPreset.fast.isAdaptive, isTrue);

      expect(
        SmoothStreamingSpeedPreset.veryFast.revealInterval,
        const Duration(milliseconds: 48),
      );
      expect(SmoothStreamingSpeedPreset.veryFast.wordUnitsPerTick, 5);
      expect(SmoothStreamingSpeedPreset.veryFast.cjkChunkSize, 8);
      expect(
        SmoothStreamingSpeedPreset.veryFast.maxRevealLag,
        const Duration(seconds: 1),
      );
      expect(SmoothStreamingSpeedPreset.veryFast.isAdaptive, isTrue);
    });

    test('fromId 容错解析', () {
      expect(
        SmoothStreamingSpeedPreset.fromId('charByChar'),
        SmoothStreamingSpeedPreset.charByChar,
      );
      expect(
        SmoothStreamingSpeedPreset.fromId('slow'),
        SmoothStreamingSpeedPreset.slow,
      );
      expect(
        SmoothStreamingSpeedPreset.fromId('standard'),
        SmoothStreamingSpeedPreset.standard,
      );
      expect(
        SmoothStreamingSpeedPreset.fromId('fast'),
        SmoothStreamingSpeedPreset.fast,
      );
      expect(
        SmoothStreamingSpeedPreset.fromId('veryFast'),
        SmoothStreamingSpeedPreset.veryFast,
      );
      expect(
        SmoothStreamingSpeedPreset.fromId(null),
        SmoothStreamingSpeedPreset.standard,
      );
      expect(
        SmoothStreamingSpeedPreset.fromId(''),
        SmoothStreamingSpeedPreset.standard,
      );
      expect(
        SmoothStreamingSpeedPreset.fromId('unknown_invalid_preset'),
        SmoothStreamingSpeedPreset.standard,
      );
    });
  });

  group('SmoothStreamingSpeedController 状态与持久化', () {
    test('默认值为 standard', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final state = container.read(smoothStreamingSpeedProvider);
      expect(state, SmoothStreamingSpeedPreset.standard);
    });

    test('初始状态从 SharedPreferences 读取', () async {
      SharedPreferences.setMockInitialValues({
        kSmoothStreamingSpeedKey: 'charByChar',
      });

      final container = ProviderContainer();
      addTearDown(container.dispose);

      final controller = container.read(smoothStreamingSpeedProvider.notifier);
      await controller.load();

      final state = container.read(smoothStreamingSpeedProvider);
      expect(state, SmoothStreamingSpeedPreset.charByChar);
    });

    test('未知值回退为 standard', () async {
      SharedPreferences.setMockInitialValues({
        kSmoothStreamingSpeedKey: 'invalid',
      });

      final container = ProviderContainer();
      addTearDown(container.dispose);

      final controller = container.read(smoothStreamingSpeedProvider.notifier);
      await controller.load();

      final state = container.read(smoothStreamingSpeedProvider);
      expect(state, SmoothStreamingSpeedPreset.standard);
    });

    test('setSpeed 修改配置并写入 SharedPreferences', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final controller = container.read(smoothStreamingSpeedProvider.notifier);
      await controller.setSpeed(SmoothStreamingSpeedPreset.slow);

      expect(
        container.read(smoothStreamingSpeedProvider),
        SmoothStreamingSpeedPreset.slow,
      );

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(kSmoothStreamingSpeedKey), 'slow');

      await controller.setSpeed(SmoothStreamingSpeedPreset.veryFast);
      expect(
        container.read(smoothStreamingSpeedProvider),
        SmoothStreamingSpeedPreset.veryFast,
      );
      expect(prefs.getString(kSmoothStreamingSpeedKey), 'veryFast');
    });
  });

  group('SettingsPage 平滑输出设置项 Widget 测试', () {
    testWidgets('渲染平滑输出开关与速度选择行，联动切换及 action sheet 选档持久化', (tester) async {
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
          child: const CupertinoApp(home: SettingsPage()),
        ),
      );

      await tester.pumpAndSettle();

      final tileFinder = find.byKey(
        const ValueKey('settings-smooth-streaming'),
      );
      expect(tileFinder, findsOneWidget);

      final switchFinder = find.byKey(
        const ValueKey('settings-switch-smooth-streaming'),
      );
      expect(switchFinder, findsOneWidget);

      expect(find.text('对话'), findsOneWidget);
      expect(find.text('平滑输出'), findsOneWidget);
      expect(find.text('逐字平滑输出，积压时自适应加速'), findsOneWidget);

      // 默认开启，速度选择行可见，且默认显示「标准」
      expect(tester.widget<CupertinoSwitch>(switchFinder).value, isTrue);
      final speedTileFinder = find.byKey(
        const ValueKey('settings-smooth-streaming-speed'),
      );
      expect(speedTileFinder, findsOneWidget);
      expect(find.text('打字机速度'), findsOneWidget);
      expect(find.text('标准'), findsOneWidget);

      // 点击速度行打开 ActionSheet
      await tester.tap(speedTileFinder);
      await tester.pumpAndSettle();

      expect(find.byType(CupertinoActionSheet), findsOneWidget);
      expect(find.text('逐字'), findsOneWidget);
      expect(find.text('慢'), findsOneWidget);
      expect(find.text('快'), findsOneWidget);
      expect(find.text('极快'), findsOneWidget);

      // 选中「逐字」
      final charByCharAction = find.byKey(
        const ValueKey('smooth-streaming-speed-charByChar'),
      );
      expect(charByCharAction, findsOneWidget);
      await tester.tap(charByCharAction);
      await tester.pumpAndSettle();

      // ActionSheet 关闭，速度更新为「逐字」，持久化更新
      expect(find.byType(CupertinoActionSheet), findsNothing);
      expect(
        container.read(smoothStreamingSpeedProvider),
        SmoothStreamingSpeedPreset.charByChar,
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(kSmoothStreamingSpeedKey), 'charByChar');
      expect(find.text('逐字'), findsOneWidget);

      // 点击切换为关闭平滑输出
      await tester.tap(switchFinder);
      await tester.pumpAndSettle();

      expect(container.read(smoothStreamingProvider), isFalse);
      expect(prefs.getBool(kSmoothStreamingKey), isFalse);
      // 速度行隐藏
      expect(
        find.byKey(const ValueKey('settings-smooth-streaming-speed')),
        findsNothing,
      );

      // 再次点击恢复开启
      await tester.tap(switchFinder);
      await tester.pumpAndSettle();

      expect(container.read(smoothStreamingProvider), isTrue);
      expect(prefs.getBool(kSmoothStreamingKey), isTrue);
      // 速度行重新显示，且档位保留上次的「逐字」
      expect(
        find.byKey(const ValueKey('settings-smooth-streaming-speed')),
        findsOneWidget,
      );
      expect(find.text('逐字'), findsOneWidget);
      expect(
        container.read(smoothStreamingSpeedProvider),
        SmoothStreamingSpeedPreset.charByChar,
      );
    });
  });
}
