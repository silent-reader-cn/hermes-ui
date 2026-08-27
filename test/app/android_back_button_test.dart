import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hermes_ui/app/shell/adaptive_shell.dart';
import 'package:hermes_ui/app/shell/empty_detail_pane.dart';
import 'package:hermes_ui/app/widgets/adaptive_popover.dart';
import 'package:hermes_ui/features/session_list/session_auto_refresh.dart';
import 'package:hermes_ui/features/session_list/session_list_page.dart';
import 'package:hermes_ui/features/session_list/session_list_providers.dart';
import 'package:hermes_ui/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_session_list_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    enableSessionAutoRefresh = false;
    AdaptivePopover.debugReset();
  });

  tearDown(() {
    AdaptivePopover.debugReset();
    enableSessionAutoRefresh = true;
    debugDefaultTargetPlatformOverride = null;
  });

  const List<LocalizationsDelegate<dynamic>> testDelegates = [
    AppLocalizationsDelegate(),
    DefaultCupertinoLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  Widget buildBackTestApp({
    required GoRouter router,
    Size size = const Size(390, 844),
    FakeSessionListApi? sessionApi,
  }) {
    return ProviderScope(
      overrides: [
        if (sessionApi != null)
          sessionListApiFactoryProvider.overrideWithValue((_) => sessionApi),
      ],
      child: MediaQuery(
        data: MediaQueryData(size: size),
        child: CupertinoApp.router(
          routerConfig: router,
          locale: const Locale('zh'),
          supportedLocales: const [Locale('zh'), Locale('en')],
          localizationsDelegates: testDelegates,
        ),
      ),
    );
  }

  GoRouter createTestRouter({String initialLocation = '/'}) {
    final rootNavKey = GlobalKey<NavigatorState>(debugLabel: 'testRootNav');
    final shellNavKey = GlobalKey<NavigatorState>(debugLabel: 'testShellNav');

    return GoRouter(
      navigatorKey: rootNavKey,
      initialLocation: initialLocation,
      routes: [
        ShellRoute(
          navigatorKey: shellNavKey,
          builder: (context, state, child) =>
              AdaptiveShell(state: state, child: child),
          routes: [
            GoRoute(
              path: '/',
              builder: (context, state) {
                final homePopoverAnchorKey = GlobalKey();
                return Stack(
                  children: [
                    const SessionListPage(),
                    Positioned(
                      top: 0,
                      left: 0,
                      child: SizedBox(
                        width: 1,
                        height: 1,
                        child: CupertinoButton(
                          key: const ValueKey('open-home-popover-btn'),
                          padding: EdgeInsets.zero,
                          onPressed: () {
                            unawaited(
                              showAdaptivePopover(
                                context: context,
                                anchorKey: homePopoverAnchorKey,
                                builder: (popCtx, close) => Container(
                                  key: const ValueKey('home-popover-content'),
                                  padding: const EdgeInsets.all(16),
                                  child: const Text('Home Popover Content'),
                                ),
                              ),
                            );
                          },
                          child: Container(
                            key: homePopoverAnchorKey,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
            GoRoute(
              path: '/tasks',
              builder: (context, state) {
                final tasksPopoverAnchorKey = GlobalKey();
                final nestedPopoverAnchorKey = GlobalKey();
                return CupertinoPageScaffold(
                  navigationBar: const CupertinoNavigationBar(
                    middle: Text('Tasks'),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CupertinoButton(
                          key: const ValueKey('open-tasks-dialog-btn'),
                          onPressed: () {
                            unawaited(
                              showCupertinoDialog<void>(
                                context: context,
                                builder: (dialogCtx) => CupertinoAlertDialog(
                                  title: const Text('Tasks Dialog'),
                                  actions: [
                                    CupertinoDialogAction(
                                      child: const Text('OK'),
                                      onPressed: () {
                                        Navigator.of(dialogCtx).pop();
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                          child: const Text('Open Dialog'),
                        ),
                        CupertinoButton(
                          key: const ValueKey('open-tasks-popover-btn'),
                          onPressed: () {
                            unawaited(
                              showAdaptivePopover(
                                context: context,
                                anchorKey: tasksPopoverAnchorKey,
                                builder: (popCtx, close) => Container(
                                  key: const ValueKey('tasks-popover-content'),
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Text('Tasks Popover Content'),
                                      CupertinoButton(
                                        key: const ValueKey('open-nested-popover-btn'),
                                        onPressed: () {
                                          unawaited(
                                            showAdaptivePopover(
                                              context: context,
                                              anchorKey: nestedPopoverAnchorKey,
                                              builder: (nestedCtx, nestedClose) => Container(
                                                key: const ValueKey('nested-popover-content'),
                                                padding: const EdgeInsets.all(16),
                                                child: const Text('Nested Popover Content'),
                                              ),
                                            ),
                                          );
                                        },
                                        child: Container(
                                          key: nestedPopoverAnchorKey,
                                          child: const Text('Open Nested'),
                                        ),
                                      ),
                                      CupertinoButton(
                                        key: const ValueKey('close-popover-item-btn'),
                                        onPressed: close,
                                        child: const Text('Close Item'),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                          child: Container(
                            key: tasksPopoverAnchorKey,
                            child: const Text('Open Popover'),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            GoRoute(
              path: '/settings',
              builder: (context, state) => const CupertinoPageScaffold(
                navigationBar: CupertinoNavigationBar(
                  middle: Text('Settings'),
                ),
                child: Center(
                  child: Text('Settings Page', key: ValueKey('settings-page')),
                ),
              ),
            ),
            GoRoute(
              path: '/chat/:sessionId',
              builder: (context, state) => CupertinoPageScaffold(
                navigationBar: const CupertinoNavigationBar(
                  middle: Text('Chat'),
                ),
                child: Center(
                  child: Text(
                    'Chat ${state.pathParameters['sessionId']}',
                    key: const ValueKey('chat-page'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  group('平台门控测试 (Platform Gating)', () {
    testWidgets('Windows 平台下：PopScope canPop 为 true，系统返回不拦截且不弹出退出 toast', (
      tester,
    ) async {
      try {
        debugDefaultTargetPlatformOverride = TargetPlatform.windows;
        final router = createTestRouter(initialLocation: '/');

        await tester.pumpWidget(
          buildBackTestApp(router: router, sessionApi: FakeSessionListApi()),
        );
        await tester.pumpAndSettle();

        final popScope = tester.widget<PopScope>(
          find.byKey(const ValueKey('adaptive-shell-pop-scope')),
        );
        expect(popScope.canPop, isTrue);

        await tester.binding.handlePopRoute();
        await tester.pump();

        expect(
          find.byKey(const ValueKey('android-back-exit-toast')),
          findsNothing,
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('iOS 平台下：PopScope canPop 为 true，系统返回不拦截', (tester) async {
      try {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        final router = createTestRouter(initialLocation: '/');

        await tester.pumpWidget(
          buildBackTestApp(router: router, sessionApi: FakeSessionListApi()),
        );
        await tester.pumpAndSettle();

        final popScope = tester.widget<PopScope>(
          find.byKey(const ValueKey('adaptive-shell-pop-scope')),
        );
        expect(popScope.canPop, isTrue);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('Android 平台下：PopScope canPop 为 false，由 Flutter 接管返回分流', (
      tester,
    ) async {
      try {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        final router = createTestRouter(initialLocation: '/');

        await tester.pumpWidget(
          buildBackTestApp(router: router, sessionApi: FakeSessionListApi()),
        );
        await tester.pumpAndSettle();

        final popScope = tester.widget<PopScope>(
          find.byKey(const ValueKey('adaptive-shell-pop-scope')),
        );
        expect(popScope.canPop, isFalse);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  group('一级分流测试（弹层/覆盖层/Dialog 优先关闭）', () {
    testWidgets('首页 `/` 弹出 CupertinoDialog 时，按系统返回优先关闭对话框，不触发退出 Toast', (
      tester,
    ) async {
      try {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        final router = createTestRouter(initialLocation: '/');

        await tester.pumpWidget(
          buildBackTestApp(router: router, sessionApi: FakeSessionListApi()),
        );
        await tester.pumpAndSettle();

        // 在当前 context 弹出一个 Dialog
        final shellContext = tester.element(find.byType(SessionListPage));
        unawaited(
          showCupertinoDialog<void>(
            context: shellContext,
            builder: (ctx) => const CupertinoAlertDialog(
              title: Text('首页弹窗', key: ValueKey('test-home-dialog')),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('test-home-dialog')),
          findsOneWidget,
        );

        // 触发系统返回
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();

        // 对话框被关闭
        expect(find.byKey(const ValueKey('test-home-dialog')), findsNothing);
        // 仍然停留在首页
        expect(find.byType(SessionListPage), findsOneWidget);
        // 没有弹出退出 Toast
        expect(
          find.byKey(const ValueKey('android-back-exit-toast')),
          findsNothing,
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('二级页 `/tasks` 弹出弹窗时，按系统返回优先关闭弹窗，不回退到首页', (tester) async {
      try {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        final router = createTestRouter(initialLocation: '/tasks');

        await tester.pumpWidget(
          buildBackTestApp(router: router, sessionApi: FakeSessionListApi()),
        );
        await tester.pumpAndSettle();

        // 打开弹窗
        final openBtn = find.byKey(const ValueKey('open-tasks-dialog-btn'));
        expect(openBtn, findsOneWidget);
        await tester.tap(openBtn);
        await tester.pumpAndSettle();

        expect(find.text('Tasks Dialog'), findsOneWidget);

        // 触发系统返回
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();

        // 弹窗被关闭
        expect(find.text('Tasks Dialog'), findsNothing);
        // 依然停留在 /tasks 页面
        expect(find.byKey(const ValueKey('open-tasks-dialog-btn')), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('二级页 `/tasks` 弹出 AdaptivePopover overlay 时，按系统返回只关闭弹层且留在当前页，再次按返回才回退到首页', (
      tester,
    ) async {
      try {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        final router = createTestRouter(initialLocation: '/tasks');

        await tester.pumpWidget(
          buildBackTestApp(router: router, sessionApi: FakeSessionListApi()),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('open-tasks-popover-btn')), findsOneWidget);
        expect(AdaptivePopover.activeOverlayCount, 0);

        // 点击打开 AdaptivePopover 弹层
        await tester.tap(find.byKey(const ValueKey('open-tasks-popover-btn')));
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('tasks-popover-content')), findsOneWidget);
        expect(AdaptivePopover.activeOverlayCount, 1);

        // 第 1 次按系统返回：应仅关闭 overlay 弹层
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();

        // 弹层已关闭，栈已清空
        expect(find.byKey(const ValueKey('tasks-popover-content')), findsNothing);
        expect(AdaptivePopover.activeOverlayCount, 0);

        // 页面仍保持在二级页 /tasks，未跳回 /
        expect(find.byKey(const ValueKey('open-tasks-popover-btn')), findsOneWidget);
        expect(find.byType(SessionListPage), findsNothing);

        // 第 2 次按系统返回：正常二级分流回退到 /
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();

        expect(find.byType(SessionListPage), findsOneWidget);
        expect(find.byKey(const ValueKey('open-tasks-popover-btn')), findsNothing);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('二级页连续弹出多层 overlay 时，按系统返回按 LIFO 倒序逐层关闭，全部弹层关闭后再次按返回才切页', (
      tester,
    ) async {
      try {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        final router = createTestRouter(initialLocation: '/tasks');

        await tester.pumpWidget(
          buildBackTestApp(router: router, sessionApi: FakeSessionListApi()),
        );
        await tester.pumpAndSettle();

        // 打开第 1 层 Popover
        await tester.tap(find.byKey(const ValueKey('open-tasks-popover-btn')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('tasks-popover-content')), findsOneWidget);
        expect(AdaptivePopover.activeOverlayCount, 1);

        // 打开第 2 层嵌套 Popover
        await tester.tap(find.byKey(const ValueKey('open-nested-popover-btn')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('nested-popover-content')), findsOneWidget);
        expect(find.byKey(const ValueKey('tasks-popover-content')), findsOneWidget);
        expect(AdaptivePopover.activeOverlayCount, 2);

        // 第 1 次返回：关闭最顶层的嵌套 Popover
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('nested-popover-content')), findsNothing);
        expect(find.byKey(const ValueKey('tasks-popover-content')), findsOneWidget);
        expect(AdaptivePopover.activeOverlayCount, 1);
        expect(find.byKey(const ValueKey('open-tasks-popover-btn')), findsOneWidget);

        // 第 2 次返回：关闭第 1 层 Popover
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('tasks-popover-content')), findsNothing);
        expect(AdaptivePopover.activeOverlayCount, 0);
        expect(find.byKey(const ValueKey('open-tasks-popover-btn')), findsOneWidget);

        // 第 3 次返回：切回首页 /
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byType(SessionListPage), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('通过点击弹层内关闭按钮关闭 overlay 时，静态注册栈同步清理，后续按返回直接回退到首页', (
      tester,
    ) async {
      try {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        final router = createTestRouter(initialLocation: '/tasks');

        await tester.pumpWidget(
          buildBackTestApp(router: router, sessionApi: FakeSessionListApi()),
        );
        await tester.pumpAndSettle();

        // 打开弹层
        await tester.tap(find.byKey(const ValueKey('open-tasks-popover-btn')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('tasks-popover-content')), findsOneWidget);
        expect(AdaptivePopover.activeOverlayCount, 1);

        // 点击弹层内的 close 按钮手动关闭
        await tester.tap(find.byKey(const ValueKey('close-popover-item-btn')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('tasks-popover-content')), findsNothing);
        expect(AdaptivePopover.activeOverlayCount, 0);

        // 按系统返回：不应被空幽灵回调拦截，直接回退到首页
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byType(SessionListPage), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('首页 `/` 弹出 AdaptivePopover overlay 时，按系统返回只关闭弹层，不触发退出 Toast', (
      tester,
    ) async {
      try {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        final router = createTestRouter(initialLocation: '/');

        await tester.pumpWidget(
          buildBackTestApp(router: router, sessionApi: FakeSessionListApi()),
        );
        await tester.pumpAndSettle();

        // 打开首页 Popover
        await tester.tap(find.byKey(const ValueKey('open-home-popover-btn')));
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('home-popover-content')), findsOneWidget);
        expect(AdaptivePopover.activeOverlayCount, 1);

        // 首次返回：只关闭 Popover，不弹出 Toast
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('home-popover-content')), findsNothing);
        expect(AdaptivePopover.activeOverlayCount, 0);
        expect(find.byType(SessionListPage), findsOneWidget);
        expect(
          find.byKey(const ValueKey('android-back-exit-toast')),
          findsNothing,
        );

        // 再次按返回：进入正常的首页首次退出提示
        await tester.binding.handlePopRoute();
        await tester.pump();

        expect(
          find.byKey(const ValueKey('android-back-exit-toast')),
          findsOneWidget,
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('防御性：在无 overlay 弹层时 AdaptivePopover.closeTopOverlay() 返回 false 且不抛异常', (
      tester,
    ) async {
      AdaptivePopover.debugReset();
      expect(AdaptivePopover.activeOverlayCount, 0);
      expect(AdaptivePopover.closeTopOverlay(), isFalse);
      expect(AdaptivePopover.closeTopOverlay(), isFalse);
    });
  });

  group('二级分流测试（二级页回退到主页 `/` 与宽屏一致性）', () {
    testWidgets('窄屏下处于二级页 `/tasks`，按系统返回导航回到 `/` 会话列表', (tester) async {
      try {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        final router = createTestRouter(initialLocation: '/tasks');

        await tester.pumpWidget(
          buildBackTestApp(
            router: router,
            size: const Size(390, 844),
            sessionApi: FakeSessionListApi(),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('open-tasks-dialog-btn')), findsOneWidget);

        // 按系统返回
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();

        // 成功回到 SessionListPage
        expect(find.byType(SessionListPage), findsOneWidget);
        expect(find.byKey(const ValueKey('open-tasks-dialog-btn')), findsNothing);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('窄屏下处于二级页 `/chat/c100`，按系统返回导航回到 `/` 会话列表', (tester) async {
      try {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        final router = createTestRouter(initialLocation: '/chat/c100');

        await tester.pumpWidget(
          buildBackTestApp(
            router: router,
            size: const Size(390, 844),
            sessionApi: FakeSessionListApi(),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('chat-page')), findsOneWidget);

        // 按系统返回
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();

        expect(find.byType(SessionListPage), findsOneWidget);
        expect(find.byKey(const ValueKey('chat-page')), findsNothing);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('宽屏下处于二级页 `/settings`，按系统返回右侧切为 EmptyDetailPane，左侧常驻侧栏', (
      tester,
    ) async {
      try {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final router = createTestRouter(initialLocation: '/settings');

        await tester.pumpWidget(
          buildBackTestApp(
            router: router,
            size: const Size(1280, 800),
            sessionApi: FakeSessionListApi(),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const ValueKey('settings-page')), findsOneWidget);
        expect(find.byType(EmptyDetailPane), findsNothing);

        // 按系统返回
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();

        // 右侧展示 EmptyDetailPane，左侧侧栏依然存在
        expect(find.byType(EmptyDetailPane), findsOneWidget);
        expect(find.byKey(const ValueKey('settings-page')), findsNothing);
        expect(
          find.byKey(const ValueKey('adaptive-shell-wide-layout')),
          findsOneWidget,
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  group('三级分流测试（主页 `/` 2 秒内双击退出应用）', () {
    testWidgets('首页首次按系统返回：显示轻提示“再按一次退出应用”，未退出', (tester) async {
      try {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        var systemPopCalls = 0;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'SystemNavigator.pop') {
              systemPopCalls++;
            }
            return null;
          },
        );

        final router = createTestRouter(initialLocation: '/');

        await tester.pumpWidget(
          buildBackTestApp(router: router, sessionApi: FakeSessionListApi()),
        );
        await tester.pumpAndSettle();

        // 首次按返回
        await tester.binding.handlePopRoute();
        await tester.pump();

        // 弹出轻提示
        expect(
          find.byKey(const ValueKey('android-back-exit-toast')),
          findsOneWidget,
        );
        expect(find.text('再按一次退出应用'), findsOneWidget);
        // 未退出
        expect(systemPopCalls, 0);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('首页首次按返回并在 2 秒内再次按返回：调用 SystemNavigator.pop() 退出应用', (
      tester,
    ) async {
      try {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        var systemPopCalls = 0;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'SystemNavigator.pop') {
              systemPopCalls++;
            }
            return null;
          },
        );

        final router = createTestRouter(initialLocation: '/');

        await tester.pumpWidget(
          buildBackTestApp(router: router, sessionApi: FakeSessionListApi()),
        );
        await tester.pumpAndSettle();

        // 首次按返回
        await tester.binding.handlePopRoute();
        await tester.pump();

        expect(
          find.byKey(const ValueKey('android-back-exit-toast')),
          findsOneWidget,
        );
        expect(systemPopCalls, 0);

        // 800ms 后再次按返回（在 2s 窗口内）
        await tester.pump(const Duration(milliseconds: 800));
        await tester.binding.handlePopRoute();
        await tester.pump();

        // 触发退出
        expect(systemPopCalls, 1);
        // Toast 消失
        expect(
          find.byKey(const ValueKey('android-back-exit-toast')),
          findsNothing,
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('首页首次按返回后等待超过 2 秒超时：Toast 自动消失，再次按返回重新进入首次提示', (
      tester,
    ) async {
      try {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        var systemPopCalls = 0;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'SystemNavigator.pop') {
              systemPopCalls++;
            }
            return null;
          },
        );

        final router = createTestRouter(initialLocation: '/');

        await tester.pumpWidget(
          buildBackTestApp(router: router, sessionApi: FakeSessionListApi()),
        );
        await tester.pumpAndSettle();

        // 首次按返回
        await tester.binding.handlePopRoute();
        await tester.pump();

        expect(
          find.byKey(const ValueKey('android-back-exit-toast')),
          findsOneWidget,
        );

        // 推进 2100ms（超时）
        await tester.pump(const Duration(milliseconds: 2100));

        // Toast 已自动消失
        expect(
          find.byKey(const ValueKey('android-back-exit-toast')),
          findsNothing,
        );

        // 再次按返回：作为新的首次按返回，重新显示 Toast，不退出
        await tester.binding.handlePopRoute();
        await tester.pump();

        expect(
          find.byKey(const ValueKey('android-back-exit-toast')),
          findsOneWidget,
        );
        expect(systemPopCalls, 0);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('宽屏下处于首页 `/`：首次按返回显示 Toast，2 秒内再次按返回退出应用', (
      tester,
    ) async {
      try {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        var systemPopCalls = 0;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'SystemNavigator.pop') {
              systemPopCalls++;
            }
            return null;
          },
        );

        final router = createTestRouter(initialLocation: '/');

        await tester.pumpWidget(
          buildBackTestApp(
            router: router,
            size: const Size(1280, 800),
            sessionApi: FakeSessionListApi(),
          ),
        );
        await tester.pumpAndSettle();

        // 宽屏首页首次按返回
        await tester.binding.handlePopRoute();
        await tester.pump();

        expect(
          find.byKey(const ValueKey('android-back-exit-toast')),
          findsOneWidget,
        );
        expect(systemPopCalls, 0);

        // 500ms 后再按返回
        await tester.pump(const Duration(milliseconds: 500));
        await tester.binding.handlePopRoute();
        await tester.pump();

        expect(systemPopCalls, 1);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('首页双击退出流程中若弹出 overlay 弹层：按返回关闭弹层并重置退出计时，后续双击退出保持幂等', (
      tester,
    ) async {
      try {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        var systemPopCalls = 0;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'SystemNavigator.pop') {
              systemPopCalls++;
            }
            return null;
          },
        );

        final router = createTestRouter(initialLocation: '/');

        await tester.pumpWidget(
          buildBackTestApp(router: router, sessionApi: FakeSessionListApi()),
        );
        await tester.pumpAndSettle();

        // 1. 首页按返回，弹出 Toast
        await tester.binding.handlePopRoute();
        await tester.pump();
        expect(
          find.byKey(const ValueKey('android-back-exit-toast')),
          findsOneWidget,
        );
        expect(systemPopCalls, 0);

        // 2. 此时弹出一个 overlay 弹层
        await tester.tap(find.byKey(const ValueKey('open-home-popover-btn')));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('home-popover-content')), findsOneWidget);
        expect(AdaptivePopover.activeOverlayCount, 1);

        // 3. 在 2s 内按返回：优先关闭弹层，重置退出计时，不触发退出
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('home-popover-content')), findsNothing);
        expect(AdaptivePopover.activeOverlayCount, 0);
        expect(systemPopCalls, 0);
        expect(
          find.byKey(const ValueKey('android-back-exit-toast')),
          findsNothing,
        );

        // 4. 再次按返回：重新显示首次退出提示
        await tester.binding.handlePopRoute();
        await tester.pump();
        expect(
          find.byKey(const ValueKey('android-back-exit-toast')),
          findsOneWidget,
        );
        expect(systemPopCalls, 0);

        // 5. 500ms 后再次按返回：正常双击退出
        await tester.pump(const Duration(milliseconds: 500));
        await tester.binding.handlePopRoute();
        await tester.pump();
        expect(systemPopCalls, 1);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  group('跨路由状态重置测试', () {
    testWidgets('从二级页 `/tasks` 按返回跳到 `/` 后，在 `/` 按返回被视为首次返回（显示 Toast 而不直接退出）', (
      tester,
    ) async {
      try {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        var systemPopCalls = 0;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'SystemNavigator.pop') {
              systemPopCalls++;
            }
            return null;
          },
        );

        final router = createTestRouter(initialLocation: '/tasks');

        await tester.pumpWidget(
          buildBackTestApp(router: router, sessionApi: FakeSessionListApi()),
        );
        await tester.pumpAndSettle();

        // 在 /tasks 按返回
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();

        expect(find.byType(SessionListPage), findsOneWidget);
        expect(systemPopCalls, 0);

        // 300ms 后在 / 按返回
        await tester.pump(const Duration(milliseconds: 300));
        await tester.binding.handlePopRoute();
        await tester.pump();

        // 应该是显示 Toast，而不是直接退出
        expect(
          find.byKey(const ValueKey('android-back-exit-toast')),
          findsOneWidget,
        );
        expect(systemPopCalls, 0);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('路由切换时 AdaptiveShell 的 didUpdateWidget 不清空 overlay 栈，按返回仍能优先关闭残留弹层', (
      tester,
    ) async {
      try {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        final router = createTestRouter(initialLocation: '/tasks');

        await tester.pumpWidget(
          buildBackTestApp(router: router, sessionApi: FakeSessionListApi()),
        );
        await tester.pumpAndSettle();

        // 在 /tasks 弹出一个 popover
        await tester.tap(find.byKey(const ValueKey('open-tasks-popover-btn')));
        await tester.pumpAndSettle();
        expect(AdaptivePopover.activeOverlayCount, 1);
        expect(find.byKey(const ValueKey('tasks-popover-content')), findsOneWidget);

        // 代码主动跳转到 /settings（触发 didUpdateWidget）
        router.go('/settings');
        await tester.pumpAndSettle();

        // 验证 didUpdateWidget 没有粗暴清空 overlay 栈（保持现状语义，由自身关闭路径注销）
        expect(AdaptivePopover.activeOverlayCount, 1);

        // 按系统返回：优先关闭残留的 popover
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();

        expect(AdaptivePopover.activeOverlayCount, 0);
        expect(find.byKey(const ValueKey('tasks-popover-content')), findsNothing);
        expect(find.byKey(const ValueKey('settings-page')), findsOneWidget);

        // 再次按系统返回：正常切回首页 /
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();

        expect(find.byType(SessionListPage), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });
}
