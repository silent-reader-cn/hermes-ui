import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hermex_flutter/core/api/api_client.dart';
import 'package:hermex_flutter/core/connections/connection_providers.dart';
import 'package:hermex_flutter/core/models/session.dart';
import 'package:hermex_flutter/features/projects/project_providers.dart';
import 'package:hermex_flutter/features/session_list/scheduled_session_disclosure.dart';
import 'package:hermex_flutter/features/session_list/session_list_page.dart';
import 'package:hermex_flutter/features/session_list/session_list_providers.dart';
import 'package:hermex_flutter/l10n/app_localizations.dart';

import '../../helpers/fake_session_list_api.dart';

/// 秒级时间戳辅助（会话模型时间字段为 epoch 秒）。
double sec(DateTime d) => d.millisecondsSinceEpoch / 1000;

SessionSummary buildSession(
  String id,
  String title, {
  bool pinned = false,
  DateTime? at,
  String? sourceLabel,
}) {
  return SessionSummary(
    sessionId: id,
    title: title,
    pinned: pinned,
    lastMessageAt: sec(at ?? DateTime.now()),
    sourceLabel: sourceLabel,
  );
}

class _StubProjectApi implements ProjectApi {
  @override
  Future<ProjectsResponse> fetchProjects() async =>
      const ProjectsResponse(projects: []);

  @override
  Future<ProjectMutationResponse> createProject({
    required String name,
    String? color,
  }) async => const ProjectMutationResponse(ok: true);

  @override
  Future<ProjectMutationResponse> renameProject({
    required String projectId,
    required String name,
    String? color,
  }) async => const ProjectMutationResponse(ok: true);

  @override
  Future<ProjectMutationResponse> deleteProject(String projectId) async =>
      const ProjectMutationResponse(ok: true);
}

class _ChatStub extends StatelessWidget {
  const _ChatStub({required this.sessionId});
  final String sessionId;

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      child: Center(
        child: Text(
          'ChatPage: $sessionId',
          key: const ValueKey('chat-page-stub'),
        ),
      ),
    );
  }
}

void main() {
  group('ScheduledSessionDisclosure 独立组件测试', () {
    testWidgets('默认状态收起（对齐蓝本）：展示标题、数量与折叠 chevron，不展示子项', (
      tester,
    ) async {
      await tester.pumpWidget(
        const CupertinoApp(
          home: CupertinoPageScaffold(
            child: ScheduledSessionDisclosure(
              title: '定时',
              count: 3,
              children: [
                Text('会话 1'),
                Text('会话 2'),
                Text('会话 3'),
              ],
            ),
          ),
        ),
      );

      // 标题与数量展示
      expect(find.text('定时'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      // 折叠图标 chevron_right
      expect(find.byIcon(CupertinoIcons.chevron_right), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.chevron_down), findsNothing);
      // 子项收起不展示
      expect(find.text('会话 1'), findsNothing);
      expect(find.text('会话 2'), findsNothing);
      expect(find.text('会话 3'), findsNothing);
      expect(
        find.byKey(const ValueKey('scheduled-disclosure-collapsed')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('scheduled-disclosure-section')),
        findsNothing,
      );
    });

    testWidgets('点击标题行 → 展开展示子项；再次点击 → 收起', (tester) async {
      final expansionEvents = <bool>[];

      await tester.pumpWidget(
        CupertinoApp(
          home: CupertinoPageScaffold(
            child: ScheduledSessionDisclosure(
              title: '定时',
              count: 2,
              onExpansionChanged: expansionEvents.add,
              children: const [
                Text('会话 A'),
                Text('会话 B'),
              ],
            ),
          ),
        ),
      );

      // 初始收起
      expect(find.text('会话 A'), findsNothing);
      expect(find.text('会话 B'), findsNothing);

      // 点击展开
      await tester.tap(
        find.byKey(const ValueKey('scheduled-disclosure-header')),
      );
      await tester.pumpAndSettle();

      expect(expansionEvents, [true]);
      expect(find.byIcon(CupertinoIcons.chevron_down), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.chevron_right), findsNothing);
      expect(find.text('会话 A'), findsOneWidget);
      expect(find.text('会话 B'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('scheduled-disclosure-section')),
        findsOneWidget,
      );

      // 再次点击收起
      await tester.tap(
        find.byKey(const ValueKey('scheduled-disclosure-header')),
      );
      await tester.pumpAndSettle();

      expect(expansionEvents, [true, false]);
      expect(find.byIcon(CupertinoIcons.chevron_right), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.chevron_down), findsNothing);
      expect(find.text('会话 A'), findsNothing);
      expect(find.text('会话 B'), findsNothing);
    });

    testWidgets('支持 initialExpanded = true 初始化展开', (tester) async {
      await tester.pumpWidget(
        const CupertinoApp(
          home: CupertinoPageScaffold(
            child: ScheduledSessionDisclosure(
              title: '定时',
              initialExpanded: true,
              children: [
                Text('直接可见会话'),
              ],
            ),
          ),
        ),
      );

      expect(find.byIcon(CupertinoIcons.chevron_down), findsOneWidget);
      expect(find.text('直接可见会话'), findsOneWidget);
    });
  });

  group('SessionListPage 定时分区与折叠集成测试', () {
    Future<void> pumpSessionListPage(
      WidgetTester tester,
      FakeSessionListApi api, {
      Locale locale = const Locale('zh'),
    }) async {
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) =>
                const SessionListPage(showUtilityRows: false),
          ),
          GoRoute(
            path: '/chat/:sessionId',
            builder: (_, state) => _ChatStub(
              sessionId: state.pathParameters['sessionId'] ?? '',
            ),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(
              ApiClient(baseUrl: 'http://test.local:30002'),
            ),
            sessionListApiFactoryProvider.overrideWithValue((_) => api),
            projectApiFactoryProvider.overrideWithValue(
              (_) => _StubProjectApi(),
            ),
          ],
          child: CupertinoApp.router(
            routerConfig: router,
            locale: locale,
            supportedLocales: const [Locale('zh'), Locale('en')],
            localizationsDelegates: const [
              AppLocalizationsDelegate(),
              DefaultCupertinoLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
          ),
        ),
      );
      // 首帧（AsyncLoading）+ 异步 build 完成（AsyncData）
      await tester.pump();
      await tester.pump();
    }

    testWidgets('含 cron 会话列表：页面出现「定时」标题行，默认收起；其他分区正常渲染', (
      tester,
    ) async {
      final now = DateTime.now();
      final noon = DateTime(now.year, now.month, now.day, 12);
      final api = FakeSessionListApi(
        sessions: [
          // 定时会话 1（cron_ 前缀）
          buildSession('cron_1', '每日自动同步', at: noon),
          // 定时会话 2（sourceLabel=cron）
          buildSession('s_cron_2', '定时备份任务', sourceLabel: 'cron', at: noon),
          // 普通置顶会话
          buildSession('p1', '置顶重要会话', pinned: true, at: noon),
          // 今天会话
          buildSession(
            't1',
            '今天普通会话',
            at: noon.subtract(const Duration(hours: 2)),
          ),
          // 更早会话
          buildSession(
            'e1',
            '更早普通会话',
            at: noon.subtract(const Duration(days: 5)),
          ),
        ],
      );

      await pumpSessionListPage(tester, api);

      // 分区标题断言
      expect(find.text('定时'), findsOneWidget);
      expect(find.text('置顶'), findsOneWidget);
      expect(find.text('今天'), findsOneWidget);
      expect(find.text('更早'), findsOneWidget);

      // 非定时分区的普通会话行正常显示
      expect(find.text('置顶重要会话'), findsOneWidget);
      expect(find.text('今天普通会话'), findsOneWidget);
      expect(find.text('更早普通会话'), findsOneWidget);

      // 定时会话由于默认折叠，行内容不显示
      expect(find.text('每日自动同步'), findsNothing);
      expect(find.text('定时备份任务'), findsNothing);
      expect(find.byIcon(CupertinoIcons.chevron_right), findsOneWidget);
    });

    testWidgets('点击「定时」标题行 → 展开显示定时会话；再点击 → 收起', (tester) async {
      final now = DateTime.now();
      final noon = DateTime(now.year, now.month, now.day, 12);
      final api = FakeSessionListApi(
        sessions: [
          buildSession('cron_1', '每日自动同步', at: noon),
          buildSession('t1', '今天普通会话', at: noon),
        ],
      );

      await pumpSessionListPage(tester, api);

      expect(find.text('定时'), findsOneWidget);
      expect(find.text('每日自动同步'), findsNothing);

      // 点击展开
      await tester.tap(find.text('定时'));
      await tester.pumpAndSettle();

      // 展开后显示定时会话
      expect(find.text('每日自动同步'), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.chevron_down), findsOneWidget);

      // 再次点击收起
      await tester.tap(find.text('定时'));
      await tester.pumpAndSettle();

      // 收起后隐藏
      expect(find.text('每日自动同步'), findsNothing);
      expect(find.byIcon(CupertinoIcons.chevron_right), findsOneWidget);
    });

    testWidgets('展开定时分区后点击会话行 → 跳转 /chat/:sessionId', (tester) async {
      final now = DateTime.now();
      final noon = DateTime(now.year, now.month, now.day, 12);
      final api = FakeSessionListApi(
        sessions: [
          buildSession('cron_1', '每日自动同步', at: noon),
        ],
      );

      await pumpSessionListPage(tester, api);

      // 展开
      await tester.tap(find.text('定时'));
      await tester.pumpAndSettle();

      // 点击会话行
      await tester.tap(find.text('每日自动同步'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('chat-page-stub')), findsOneWidget);
      expect(find.text('ChatPage: cron_1'), findsOneWidget);
    });

    testWidgets('展开定时分区后行快捷操作 ellipsis 菜单正常工作', (tester) async {
      final now = DateTime.now();
      final noon = DateTime(now.year, now.month, now.day, 12);
      final api = FakeSessionListApi(
        sessions: [
          buildSession('cron_1', '每日自动同步', at: noon),
        ],
      );

      await pumpSessionListPage(tester, api);

      // 展开
      await tester.tap(find.text('定时'));
      await tester.pumpAndSettle();

      // 点击 ellipsis 按钮
      await tester.tap(
        find.byKey(const ValueKey('session-actions-cron_1')),
      );
      await tester.pumpAndSettle();

      // 确认弹出了 CupertinoActionSheet
      expect(find.byType(CupertinoActionSheet), findsOneWidget);
      expect(
        find.byKey(const ValueKey('session-action-pin')),
        findsOneWidget,
      );
    });

    testWidgets('英文语言环境下标题映射为「Scheduled」', (tester) async {
      final now = DateTime.now();
      final noon = DateTime(now.year, now.month, now.day, 12);
      final api = FakeSessionListApi(
        sessions: [
          buildSession('cron_1', 'Daily Sync Job', at: noon),
          buildSession('p1', 'Pinned Session', pinned: true, at: noon),
        ],
      );

      await pumpSessionListPage(tester, api, locale: const Locale('en'));

      expect(find.text('Scheduled'), findsOneWidget);
      expect(find.text('Pinned'), findsOneWidget);
      expect(find.text('定时'), findsNothing);
      expect(find.text('置顶'), findsNothing);
    });

    testWidgets('无定时会话时页面不渲染「定时」分区', (tester) async {
      final now = DateTime.now();
      final noon = DateTime(now.year, now.month, now.day, 12);
      final api = FakeSessionListApi(
        sessions: [
          buildSession('p1', '置顶会话', pinned: true, at: noon),
          buildSession('t1', '今天会话', at: noon),
        ],
      );

      await pumpSessionListPage(tester, api);

      expect(find.text('定时'), findsNothing);
      expect(find.text('置顶'), findsOneWidget);
      expect(find.text('今天'), findsOneWidget);
    });

    testWidgets('搜索模式下定时会话直接进入「搜索结果」，无独立定时折叠分区', (tester) async {
      final now = DateTime.now();
      final noon = DateTime(now.year, now.month, now.day, 12);
      final api = FakeSessionListApi(
        sessions: [
          buildSession('cron_1', '自动备份同步', at: noon),
          buildSession('t1', '备份相关讨论', at: noon),
        ],
      );
      api.searchResults['备份'] = [
        buildSession('cron_1', '自动备份同步', at: noon),
        buildSession('t1', '备份相关讨论', at: noon),
      ];

      await pumpSessionListPage(tester, api);

      // 输入搜索词
      await tester.enterText(
        find.byKey(const ValueKey('session-list-search')),
        '备份',
      );
      // 350ms 防抖 + 异步搜索响应
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      await tester.pump();

      // 搜索模式下展示「搜索结果」单一分区，无「定时」折叠分区
      expect(find.text('搜索结果'), findsOneWidget);
      expect(find.text('定时'), findsNothing);
      expect(find.text('自动备份同步'), findsOneWidget);
      expect(find.text('备份相关讨论'), findsOneWidget);
    });
  });
}
