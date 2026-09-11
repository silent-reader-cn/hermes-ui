import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/connections/connection_store.dart';
import 'package:hermes_ui/core/connections/server_connection.dart';
import 'package:hermes_ui/features/chat/widgets/markdown_styles.dart';
import 'package:hermes_ui/features/settings/settings_page.dart';
import 'package:hermes_ui/features/settings/settings_providers.dart';
import 'package:hermes_ui/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_settings_api.dart';
import '../../helpers/in_memory_secure_storage.dart';

Widget _buildTestApp({required Widget child, ProviderContainer? container}) {
  final app = CupertinoApp(
    localizationsDelegates: const [
      AppLocalizationsDelegate(),
      DefaultCupertinoLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
    ],
    supportedLocales: const [Locale('zh'), Locale('en')],
    home: CupertinoPageScaffold(child: child),
  );
  if (container != null) {
    return UncontrolledProviderScope(container: container, child: app);
  }
  return ProviderScope(child: app);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('MermaidCodeBlock 渲染与回退', () {
    testWidgets(
      'MarkdownBody 渲染合法 ```mermaid：出现 mermaid-diagram，不出现 code-block-fallback',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        const data = '```mermaid\ngraph TD\n  A-->B\n```';

        await tester.pumpWidget(
          _buildTestApp(
            child: Builder(
              builder: (context) => MarkdownBody(
                data: data,
                styleSheet: buildAssistantMarkdownStyleSheet(context),
                builders: createAssistantMarkdownBuilders(context),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('mermaid-diagram')), findsOneWidget);
        expect(find.byKey(const ValueKey('code-block-fallback')), findsNothing);
      },
    );

    testWidgets(
      '非法 mermaid（class=language-mermaid 但内容语法错误）：回退 code-block-fallback 且不抛异常',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        const data = '```mermaid\nthis is invalid syntax !!!\n```';

        await tester.pumpWidget(
          _buildTestApp(
            child: Builder(
              builder: (context) => MarkdownBody(
                data: data,
                styleSheet: buildAssistantMarkdownStyleSheet(context),
                builders: createAssistantMarkdownBuilders(context),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(
          find.byKey(const ValueKey('code-block-fallback')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('mermaid-diagram')), findsNothing);
        expect(
          find.textContaining('this is invalid syntax !!!'),
          findsOneWidget,
        );
      },
    );

    testWidgets('普通 ```dart 块：仍走兜底渲染（mermaid key 不出现），断言文本内容在', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      const data = '```dart\nvoid main() {\n  print("hello");\n}\n```';

      await tester.pumpWidget(
        _buildTestApp(
          child: Builder(
            builder: (context) => MarkdownBody(
              data: data,
              styleSheet: buildAssistantMarkdownStyleSheet(context),
              builders: createAssistantMarkdownBuilders(context),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('code-block-fallback')), findsOneWidget);
      expect(find.byKey(const ValueKey('mermaid-diagram')), findsNothing);
      expect(find.textContaining('void main()'), findsOneWidget);
    });

    testWidgets('无 class 但内容以 sequenceDiagram 开头：识别为 mermaid 并渲染', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      const data = '```\nsequenceDiagram\n  Alice->>Bob: Hello\n```';

      await tester.pumpWidget(
        _buildTestApp(
          child: Builder(
            builder: (context) => MarkdownBody(
              data: data,
              styleSheet: buildAssistantMarkdownStyleSheet(context),
              builders: createAssistantMarkdownBuilders(context),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('mermaid-diagram')), findsOneWidget);
      expect(find.byKey(const ValueKey('code-block-fallback')), findsNothing);
    });

    testWidgets('开关关闭（chat_render_mermaid: false）：```mermaid 走兜底渲染', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({'chat_render_mermaid': false});

      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      const data = '```mermaid\ngraph TD\n  A-->B\n```';

      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(chatRenderMermaidProvider.notifier).load();

      await tester.pumpWidget(
        _buildTestApp(
          container: container,
          child: Builder(
            builder: (context) => MarkdownBody(
              data: data,
              styleSheet: buildAssistantMarkdownStyleSheet(context),
              builders: createAssistantMarkdownBuilders(context),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('code-block-fallback')), findsOneWidget);
      expect(find.byKey(const ValueKey('mermaid-diagram')), findsNothing);
      expect(find.textContaining('graph TD'), findsOneWidget);
    });

    testWidgets('全屏按钮 tap：打开全屏页并出现 ValueKey(mermaid-fullscreen-view)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      const data = '```mermaid\ngraph TD\n  A-->B\n```';

      await tester.pumpWidget(
        _buildTestApp(
          child: Builder(
            builder: (context) => MarkdownBody(
              data: data,
              styleSheet: buildAssistantMarkdownStyleSheet(context),
              builders: createAssistantMarkdownBuilders(context),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final fullscreenBtn = find.byKey(
        const ValueKey('mermaid-fullscreen-button'),
      );
      expect(fullscreenBtn, findsOneWidget);

      await tester.tap(fullscreenBtn);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('mermaid-fullscreen-view')),
        findsOneWidget,
      );

      // 点击关闭按钮可正常返回
      final closeBtn = find.byIcon(CupertinoIcons.xmark);
      expect(closeBtn, findsOneWidget);
      await tester.tap(closeBtn);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('mermaid-fullscreen-view')),
        findsNothing,
      );
    });
  });

  group('设置页 Mermaid 开关', () {
    testWidgets('SettingsPage 渲染「渲染 Mermaid 图表」开关并支持持久化切换', (tester) async {
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
        _buildTestApp(
          container: container,
          child: const CupertinoPageScaffold(child: SettingsPage()),
        ),
      );
      await tester.pumpAndSettle();

      final switchFinder = find.byKey(
        const ValueKey('settings-mermaid-toggle'),
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
      expect(prefs.getBool(kChatRenderMermaidKey), isFalse);
    });
  });
}
