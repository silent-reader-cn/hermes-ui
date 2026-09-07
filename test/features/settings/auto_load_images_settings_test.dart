import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/connections/connection_store.dart';
import 'package:hermes_ui/core/connections/server_connection.dart';
import 'package:hermes_ui/features/chat/widgets/chat_media_view.dart';
import 'package:hermes_ui/features/settings/settings_page.dart';
import 'package:hermes_ui/features/settings/settings_providers.dart';
import 'package:hermes_ui/l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_settings_api.dart';
import '../../helpers/in_memory_secure_storage.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('#85 AutoLoadImagesController 状态与持久化', () {
    test('默认值为 true（默认自动加载图片）', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final state = container.read(autoLoadImagesProvider);
      expect(state, isTrue);
    });

    test('初始状态从 SharedPreferences 读取（false）', () async {
      SharedPreferences.setMockInitialValues({
        kAutoLoadImagesKey: false,
      });

      final container = ProviderContainer();
      addTearDown(container.dispose);

      final controller = container.read(autoLoadImagesProvider.notifier);
      await controller.load();

      expect(container.read(autoLoadImagesProvider), isFalse);
    });

    test('初始状态从 SharedPreferences 读取（true）', () async {
      SharedPreferences.setMockInitialValues({
        kAutoLoadImagesKey: true,
      });

      final container = ProviderContainer();
      addTearDown(container.dispose);

      final controller = container.read(autoLoadImagesProvider.notifier);
      await controller.load();

      expect(container.read(autoLoadImagesProvider), isTrue);
    });

    test('setEnabled 修改配置并写入 SharedPreferences (round-trip)', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final controller = container.read(autoLoadImagesProvider.notifier);
      await controller.setEnabled(false);

      expect(container.read(autoLoadImagesProvider), isFalse);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(kAutoLoadImagesKey), isFalse);

      await controller.setEnabled(true);
      expect(container.read(autoLoadImagesProvider), isTrue);
      expect(prefs.getBool(kAutoLoadImagesKey), isTrue);
    });
  });

  group('#85 SettingsPage 自动加载图片开关', () {
    testWidgets('渲染「自动加载图片」开关并支持切换', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final fakeApi = FakeSettingsApi();
      final connection = ServerConnection(
        id: 'conn-1',
        name: 'Test Server',
        baseUrl: 'http://test.local:30002',
        createdAt: DateTime.utc(2026, 1, 1),
      );
      final store = ConnectionStore(storage: InMemorySecureStorage());
      await store.save(connection);
      await store.setActive(connection.id);

      final client = ApiClient(baseUrl: connection.baseUrl);

      final container = ProviderContainer(
        overrides: [
          connectionStoreProvider.overrideWithValue(store),
          apiClientProvider.overrideWithValue(client),
          settingsApiFactoryProvider.overrideWithValue((_) => fakeApi),
        ],
      );
      addTearDown(container.dispose);

      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const CupertinoApp(
            localizationsDelegates: [
              AppLocalizationsDelegate(),
              DefaultCupertinoLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            supportedLocales: [Locale('zh'), Locale('en')],
            home: CupertinoPageScaffold(child: SettingsPage()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final switchFinder = find.byKey(
        const ValueKey('settings-auto-load-images'),
      );
      expect(switchFinder, findsOneWidget);

      // 默认开启
      final switchWidget = tester.widget<CupertinoSwitch>(switchFinder);
      expect(switchWidget.value, isTrue);

      // 点击切换为关闭
      await tester.tap(switchFinder);
      await tester.pumpAndSettle();

      final switchWidgetAfter = tester.widget<CupertinoSwitch>(switchFinder);
      expect(switchWidgetAfter.value, isFalse);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(kAutoLoadImagesKey), isFalse);
    });
  });

  group('#85 ChatInlineMediaWidget 自动加载闸门行为', () {
    Widget buildTestApp({
      required Widget child,
      required ProviderContainer container,
    }) {
      return UncontrolledProviderScope(
        container: container,
        child: CupertinoApp(
          localizationsDelegates: const [
            AppLocalizationsDelegate(),
            DefaultCupertinoLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: const [Locale('zh'), Locale('en')],
          home: CupertinoPageScaffold(child: child),
        ),
      );
    }

    testWidgets('关闭自动加载时，网络图片展示点击加载占位，点击后解除闸门', (tester) async {
      final container = ProviderContainer(
        overrides: [
          autoLoadImagesProvider.overrideWith(
            _FakeDisabledAutoLoadImagesController.new,
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        buildTestApp(
          container: container,
          child: const ChatInlineMediaWidget(
            rawUri: 'https://example.com/test.png',
            alt: '测试图片说明',
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 未加载态占位：展示 alt 文本与点击加载按钮
      expect(find.text('测试图片说明'), findsOneWidget);
      final tapToLoadBtn = find.byKey(
        const ValueKey('chat-inline-media-tap-to-load'),
      );
      expect(tapToLoadBtn, findsOneWidget);

      // 点击加载
      await tester.tap(tapToLoadBtn);
      await tester.pump();

      // 点击后占位按钮消失，进入原加载链路
      expect(
        find.byKey(const ValueKey('chat-inline-media-tap-to-load')),
        findsNothing,
      );
    });

    testWidgets('关闭自动加载时，Data URI 不受阻碍直接渲染', (tester) async {
      final container = ProviderContainer(
        overrides: [
          autoLoadImagesProvider.overrideWith(
            _FakeDisabledAutoLoadImagesController.new,
          ),
        ],
      );
      addTearDown(container.dispose);

      // 1x1 透明 PNG base64
      const tinyPng =
          'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';

      await tester.pumpWidget(
        buildTestApp(
          container: container,
          child: const ChatInlineMediaWidget(
            rawUri: tinyPng,
            alt: '内联图片',
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Data URI 不设闸：不出现 tap-to-load 按钮
      expect(
        find.byKey(const ValueKey('chat-inline-media-tap-to-load')),
        findsNothing,
      );
      expect(find.byType(Image), findsOneWidget);
    });
  });
}

class _FakeDisabledAutoLoadImagesController extends AutoLoadImagesController {
  @override
  bool build() => false;
}
