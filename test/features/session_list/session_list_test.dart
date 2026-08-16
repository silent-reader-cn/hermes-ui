import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show debugDefaultTargetPlatformOverride;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hermex_flutter/core/api/api_client.dart';
import 'package:hermex_flutter/core/api/api_exception.dart';
import 'package:hermex_flutter/core/connections/connection_providers.dart';
import 'package:hermex_flutter/core/models/session.dart';
import 'package:hermex_flutter/features/session_list/session_list_page.dart';
import 'package:hermex_flutter/features/session_list/session_list_providers.dart';

import '../../helpers/fake_session_list_api.dart';

/// 秒级时间戳辅助（会话模型时间字段为 epoch 秒）。
double sec(DateTime d) => d.millisecondsSinceEpoch / 1000;

SessionSummary buildSession(
  String id,
  String title, {
  bool pinned = false,
  DateTime? at,
}) {
  return SessionSummary(
    sessionId: id,
    title: title,
    pinned: pinned,
    lastMessageAt: sec(at ?? DateTime.now()),
  );
}

/// 组装 ProviderContainer：注入 fake API（apiClientProvider 用占位客户端，
/// 工厂 override 忽略它，不发任何网络请求）。
ProviderContainer makeContainer(FakeSessionListApi api) {
  final container = ProviderContainer(
    overrides: [
      apiClientProvider.overrideWithValue(
        ApiClient(baseUrl: 'http://test.local:30002'),
      ),
      sessionListApiFactoryProvider.overrideWithValue((_) => api),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('buildSessionSections 分区', () {
    test('置顶 / 今天 / 昨天 / 更早 分组，组内时间倒序，空组剔除', () {
      final now = DateTime(2026, 8, 16, 12);
      final pinned = buildSession('p1', '置顶会话', pinned: true, at: now);
      final today = buildSession('t1', '今天会话', at: now.subtract(const Duration(hours: 1)));
      final yesterday = buildSession('y1', '昨天会话', at: now.subtract(const Duration(days: 1)));
      final earlier = buildSession('e1', '更早会话', at: now.subtract(const Duration(days: 10)));
      final noTimestamp = buildSession('n1', '无时间戳', at: DateTime.fromMillisecondsSinceEpoch(0));

      final sections = buildSessionSections(
        [noTimestamp, earlier, yesterday, today, pinned],
        now: now,
      );

      expect(sections.map((s) => s.title).toList(), ['置顶', '今天', '昨天', '更早']);
      expect(sections[0].sessions.map((s) => s.sessionId), ['p1']);
      expect(sections[1].sessions.map((s) => s.sessionId), ['t1']);
      expect(sections[2].sessions.map((s) => s.sessionId), ['y1']);
      // 更早：e1（10 天前）在前，无时间戳（0）在后
      expect(sections[3].sessions.map((s) => s.sessionId), ['e1', 'n1']);
    });

    test('全空输入 → 无分区', () {
      expect(buildSessionSections(const [], now: DateTime(2026, 1, 1)), isEmpty);
    });
  });

  group('SessionListController 状态机', () {
    test('初始加载成功：AsyncData + 首屏分页窗口 + 派生可见列表', () async {
      final api = FakeSessionListApi(
        sessions: [
          buildSession('s1', 'A'),
          buildSession('s2', 'B'),
        ],
      );
      final container = makeContainer(api);

      await container.read(sessionListControllerProvider.future);
      final state = container.read(sessionListControllerProvider).valueOrNull!;

      expect(api.fetchCount, 1);
      expect(state.sessions, hasLength(2));
      expect(state.visibleCount, 2);
      expect(state.hasMore, isFalse);
      expect(state.searchQuery, isNull);
      expect(
        container
            .read(sessionListVisibleSessionsProvider)
            .map((s) => s.sessionId),
        ['s1', 's2'],
      );
    });

    test('初始加载失败 → AsyncError；refresh 重试成功', () async {
      final api = FakeSessionListApi(sessions: [buildSession('s1', 'A')]);
      api.fetchError = NetworkException(NetworkExceptionKind.cannotConnect);
      final container = makeContainer(api);

      await expectLater(
        container.read(sessionListControllerProvider.future),
        throwsA(isA<ApiException>()),
      );
      expect(container.read(sessionListControllerProvider).hasError, isTrue);
      expect(container.read(sessionListControllerProvider).valueOrNull, isNull);

      api.fetchError = null;
      await container.read(sessionListControllerProvider.notifier).refresh();

      final state = container.read(sessionListControllerProvider).valueOrNull!;
      expect(state.sessions, hasLength(1));
      expect(state.visibleCount, 1);
    });

    test('分页：loadMore 每页 +50 展开窗口，耗尽后幂等', () async {
      final api = FakeSessionListApi(
        sessions: [
          for (var i = 0; i < 120; i++)
            SessionSummary(sessionId: 's$i', title: '会话 $i', createdAt: 1000.0 + i),
        ],
      );
      final container = makeContainer(api);
      await container.read(sessionListControllerProvider.future);
      final controller = container.read(sessionListControllerProvider.notifier);

      var state = container.read(sessionListControllerProvider).valueOrNull!;
      expect(state.visibleCount, 50);
      expect(state.hasMore, isTrue);

      await controller.loadMore();
      state = container.read(sessionListControllerProvider).valueOrNull!;
      expect(state.visibleCount, 100);
      expect(state.hasMore, isTrue);

      await controller.loadMore();
      state = container.read(sessionListControllerProvider).valueOrNull!;
      expect(state.visibleCount, 120);
      expect(state.hasMore, isFalse);

      await controller.loadMore();
      expect(
        container.read(sessionListControllerProvider).valueOrNull!.visibleCount,
        120,
      );

      expect(
        container.read(sessionListVisibleSessionsProvider),
        hasLength(120),
      );
    });

    test('搜索：命中 → 搜索模式展示命中；清空 → 恢复普通列表', () async {
      final api = FakeSessionListApi(
        sessions: [buildSession('s1', 'A'), buildSession('s2', 'B')],
      );
      api.searchResults['bug'] = [buildSession('r1', '修复 bug')];
      final container = makeContainer(api);
      await container.read(sessionListControllerProvider.future);
      final controller = container.read(sessionListControllerProvider.notifier);

      await controller.search('bug');
      var state = container.read(sessionListControllerProvider).valueOrNull!;
      expect(api.searchQueries, ['bug']);
      expect(state.searchQuery, 'bug');
      expect(state.isSearching, isFalse);
      expect(state.searchResults!.map((s) => s.sessionId), ['r1']);
      expect(
        container
            .read(sessionListVisibleSessionsProvider)
            .map((s) => s.sessionId),
        ['r1'],
      );

      await controller.search('');
      state = container.read(sessionListControllerProvider).valueOrNull!;
      expect(state.searchQuery, isNull);
      expect(state.searchResults, isNull);
      expect(
        container.read(sessionListVisibleSessionsProvider),
        hasLength(2),
      );
    });

    test('搜索失败：actionError + 空结果；clearActionError 清除', () async {
      final api = FakeSessionListApi(sessions: [buildSession('s1', 'A')]);
      api.searchError = HttpException(500, null, message: '搜索服务不可用');
      final container = makeContainer(api);
      await container.read(sessionListControllerProvider.future);
      final controller = container.read(sessionListControllerProvider.notifier);

      await controller.search('bug');
      final state = container.read(sessionListControllerProvider).valueOrNull!;
      expect(state.searchQuery, 'bug');
      expect(state.isSearching, isFalse);
      expect(state.searchResults, isEmpty);
      expect(state.actionError, contains('搜索服务不可用'));

      await controller.clearActionError();
      expect(
        container.read(sessionListControllerProvider).valueOrNull!.actionError,
        isNull,
      );
    });

    test('置顶：调 pin API 并本地更新 → 归入「置顶」分区', () async {
      final s1 = buildSession('s1', 'A');
      final api = FakeSessionListApi(sessions: [s1]);
      final container = makeContainer(api);
      await container.read(sessionListControllerProvider.future);
      final controller = container.read(sessionListControllerProvider.notifier);

      final ok = await controller.setPinned(s1, true);
      expect(ok, isTrue);
      expect(api.pinCalls, ['s1:true']);
      final updated =
          container.read(sessionListControllerProvider).valueOrNull!.sessions.single;
      expect(updated.pinned, isTrue);
      final sections = container.read(sessionListSectionsProvider);
      expect(sections.single.title, '置顶');
    });

    test('归档：调 archive API 并从列表移除', () async {
      final api = FakeSessionListApi(
        sessions: [buildSession('s1', 'A'), buildSession('s2', 'B')],
      );
      final container = makeContainer(api);
      await container.read(sessionListControllerProvider.future);
      final controller = container.read(sessionListControllerProvider.notifier);

      final ok = await controller.setArchived(
        container.read(sessionListControllerProvider).valueOrNull!.sessions.first,
        true,
      );
      expect(ok, isTrue);
      expect(api.archiveCalls, ['s1:true']);
      expect(
        container
            .read(sessionListControllerProvider)
            .valueOrNull!
            .sessions
            .map((s) => s.sessionId),
        ['s2'],
      );
    });

    test('删除：调 delete API 并从列表移除', () async {
      final api = FakeSessionListApi(
        sessions: [buildSession('s1', 'A'), buildSession('s2', 'B')],
      );
      final container = makeContainer(api);
      await container.read(sessionListControllerProvider.future);
      final controller = container.read(sessionListControllerProvider.notifier);

      final ok = await controller.delete(
        container.read(sessionListControllerProvider).valueOrNull!.sessions.first,
      );
      expect(ok, isTrue);
      expect(api.deleteCalls, ['s1']);
      expect(
        container
            .read(sessionListControllerProvider)
            .valueOrNull!
            .sessions
            .map((s) => s.sessionId),
        ['s2'],
      );
    });

    test('分支：调 branch API，返回新 ID 并插入列表顶部', () async {
      final api = FakeSessionListApi(sessions: [buildSession('s1', 'A')]);
      api.branchResponse = const SessionBranchResponse(
        sessionId: 'b1',
        title: '分支副本',
      );
      final container = makeContainer(api);
      await container.read(sessionListControllerProvider.future);
      final controller = container.read(sessionListControllerProvider.notifier);

      final id = await controller.branch(
        container.read(sessionListControllerProvider).valueOrNull!.sessions.single,
      );
      expect(id, 'b1');
      expect(api.branchCalls, ['s1']);
      final sessions =
          container.read(sessionListControllerProvider).valueOrNull!.sessions;
      expect(sessions.first.sessionId, 'b1');
      expect(sessions.first.title, '分支副本');
    });

    test('分支失败（服务器未返回 ID）：actionError，列表不变', () async {
      final api = FakeSessionListApi(sessions: [buildSession('s1', 'A')]);
      api.branchResponse = const SessionBranchResponse();
      final container = makeContainer(api);
      await container.read(sessionListControllerProvider.future);
      final controller = container.read(sessionListControllerProvider.notifier);

      final id = await controller.branch(
        container.read(sessionListControllerProvider).valueOrNull!.sessions.single,
      );
      expect(id, isNull);
      final state = container.read(sessionListControllerProvider).valueOrNull!;
      expect(state.actionError, isNotNull);
      expect(state.sessions, hasLength(1));
    });

    test('新建会话：调 create API，返回新 ID 并插入顶部', () async {
      final api = FakeSessionListApi(sessions: [buildSession('s1', 'A')]);
      api.createdSession = const SessionSummary(sessionId: 'n1', title: '新会话');
      final container = makeContainer(api);
      await container.read(sessionListControllerProvider.future);
      final controller = container.read(sessionListControllerProvider.notifier);

      final id = await controller.createSession();
      expect(id, 'n1');
      expect(api.createCount, 1);
      final sessions =
          container.read(sessionListControllerProvider).valueOrNull!.sessions;
      expect(sessions.first.sessionId, 'n1');
    });

    test('行操作失败：actionError 提示，列表不变', () async {
      final api = FakeSessionListApi(sessions: [buildSession('s1', 'A')]);
      api.pinError = HttpException(500, null, message: '置顶服务不可用');
      final container = makeContainer(api);
      await container.read(sessionListControllerProvider.future);
      final controller = container.read(sessionListControllerProvider.notifier);

      final ok = await controller.setPinned(
        container.read(sessionListControllerProvider).valueOrNull!.sessions.single,
        true,
      );
      expect(ok, isFalse);
      final state = container.read(sessionListControllerProvider).valueOrNull!;
      expect(state.actionError, contains('置顶服务不可用'));
      expect(state.sessions, hasLength(1));
      expect(api.pinCalls, ['s1:true']);
    });
  });

  group('SessionListPage widget', () {
    Future<void> pumpSessionList(
      WidgetTester tester,
      FakeSessionListApi api,
    ) async {
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(path: '/', builder: (_, _) => const SessionListPage()),
          GoRoute(
            path: '/chat',
            builder: (_, _) => const _ChatStub(sessionId: ''),
          ),
          GoRoute(
            path: '/chat/:sessionId',
            builder: (_, state) =>
                _ChatStub(sessionId: state.pathParameters['sessionId'] ?? ''),
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
          ],
          child: CupertinoApp.router(routerConfig: router),
        ),
      );
      // 首帧（AsyncLoading）+ 异步 build 完成（AsyncData）
      await tester.pump();
      await tester.pump();
    }

    testWidgets('列表渲染：分区标题 + 会话行 + 置顶图标 + 悬浮按钮', (tester) async {
      // 用当天中午作基准，避免凌晨运行时「now - 2h」跨天落到昨天导致分区断言失败
      final now = DateTime.now();
      final noon = DateTime(now.year, now.month, now.day, 12);
      final api = FakeSessionListApi(
        sessions: [
          buildSession('p1', '置顶会话', pinned: true, at: noon),
          buildSession(
            't1',
            '今天会话',
            at: noon.subtract(const Duration(hours: 2)),
          ),
          buildSession(
            'e1',
            '更早会话',
            at: noon.subtract(const Duration(days: 5)),
          ),
        ],
      );
      await pumpSessionList(tester, api);

      expect(find.text('置顶'), findsOneWidget);
      expect(find.text('今天'), findsOneWidget);
      expect(find.text('更早'), findsOneWidget);
      expect(find.text('置顶会话'), findsOneWidget);
      expect(find.text('今天会话'), findsOneWidget);
      expect(find.text('更早会话'), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.pin_fill), findsOneWidget);
      expect(find.byKey(const ValueKey('session-list-new')), findsOneWidget);
    });

    testWidgets('加载态：数据到达前显示 ActivityIndicator，到达后渲染列表', (tester) async {
      final api = FakeSessionListApi(sessions: [buildSession('s1', '到了')]);
      api.fetchGate = Completer<void>();
      await pumpSessionList(tester, api);

      expect(find.byType(CupertinoActivityIndicator), findsOneWidget);

      api.fetchGate!.complete();
      await tester.pump();
      await tester.pump();
      expect(find.text('到了'), findsOneWidget);
      expect(find.byType(CupertinoActivityIndicator), findsNothing);
    });

    testWidgets('空态：暂无会话 + 新建会话入口', (tester) async {
      await pumpSessionList(tester, FakeSessionListApi());

      expect(find.text('暂无会话'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('session-list-empty-new')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('session-list-new')), findsOneWidget);
    });

    testWidgets('错误态：加载失败展示错误信息，重试恢复', (tester) async {
      final api = FakeSessionListApi(sessions: [buildSession('s1', '恢复的会话')]);
      api.fetchError = NetworkException(NetworkExceptionKind.cannotConnect);
      await pumpSessionList(tester, api);

      expect(find.text('加载失败'), findsOneWidget);
      expect(find.textContaining('无法连接'), findsOneWidget);

      api.fetchError = null;
      await tester.tap(find.byKey(const ValueKey('session-list-retry')));
      await tester.pump();
      await tester.pump();

      expect(find.text('恢复的会话'), findsOneWidget);
      expect(find.text('加载失败'), findsNothing);
    });

    testWidgets('点击会话行 → 跳转 /chat/:sessionId', (tester) async {
      final api = FakeSessionListApi(sessions: [buildSession('s1', '第一个会话')]);
      await pumpSessionList(tester, api);

      await tester.tap(find.byKey(const ValueKey('session-row-s1')));
      await tester.pumpAndSettle();

      expect(find.text('chat-s1'), findsOneWidget);
    });

    testWidgets('新建会话：悬浮 + 按钮创建并跳转 /chat/:id', (tester) async {
      final api = FakeSessionListApi(sessions: [buildSession('s1', '已有会话')]);
      api.createdSession = const SessionSummary(sessionId: 'n1', title: '新建的会话');
      await pumpSessionList(tester, api);

      await tester.tap(find.byKey(const ValueKey('session-list-new')));
      await tester.pumpAndSettle();

      expect(api.createCount, 1);
      expect(find.text('chat-n1'), findsOneWidget);
    });

    testWidgets('搜索：350ms 防抖后远程搜索并展示命中', (tester) async {
      final now = DateTime.now();
      final api = FakeSessionListApi(
        sessions: [
          buildSession('s1', '第一个会话', at: now),
          buildSession('s2', '第二个会话', at: now),
        ],
      );
      api.searchResults['bug'] = [buildSession('r1', '修复 bug 的会话')];
      await pumpSessionList(tester, api);

      await tester.enterText(
        find.byKey(const ValueKey('session-list-search')),
        'bug',
      );
      // 防抖窗口内不触发
      await tester.pump(const Duration(milliseconds: 200));
      expect(api.searchCount, 0);

      // 防抖到期 → 远程搜索 → 展示命中、隐藏普通列表
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump();
      await tester.pump();
      expect(api.searchCount, 1);
      expect(api.searchQueries, ['bug']);
      expect(find.text('搜索结果'), findsOneWidget);
      expect(find.text('修复 bug 的会话'), findsOneWidget);
      expect(find.text('第一个会话'), findsNothing);
    });

    testWidgets('下拉刷新：重新拉取列表', (tester) async {
      // CupertinoSliverRefreshControl 需要弹跳式（iOS）滚动物理才会上抛负偏移，
      // 测试默认 Android 平台（钳制物理）不会触发 —— 显式切到 iOS。
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

      final api = FakeSessionListApi(sessions: [buildSession('s1', '会话一')]);
      await pumpSessionList(tester, api);
      expect(api.fetchCount, 1);

      // 分步拖拽 + 每次 pump（让刷新指示器完成布局、越过触发阈值）。
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('session-list-scroll'))),
      );
      await gesture.moveBy(const Offset(0, 300));
      await tester.pump();
      await gesture.moveBy(const Offset(0, 150));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      // 测试结束前还原平台（框架会在 teardown 前校验 foundation 变量已复位）。
      debugDefaultTargetPlatformOverride = null;
      expect(api.fetchCount, 2);
    });

    testWidgets('行操作：ellipsis 弹菜单 → 置顶生效', (tester) async {
      final api = FakeSessionListApi(sessions: [buildSession('s1', '会话一')]);
      await pumpSessionList(tester, api);

      await tester.tap(find.byKey(const ValueKey('session-actions-s1')));
      await tester.pumpAndSettle();
      expect(find.text('归档'), findsOneWidget);
      expect(find.text('分支'), findsOneWidget);
      expect(find.text('删除'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('session-action-pin')));
      await tester.pumpAndSettle();

      expect(api.pinCalls, ['s1:true']);
      // 菜单关闭（归档文本消失），置顶后分区标题出现
      expect(find.text('归档'), findsNothing);
      expect(find.text('置顶'), findsOneWidget);
    });

    testWidgets('删除：确认弹窗 → 确认后移除行并显示空态', (tester) async {
      final api = FakeSessionListApi(sessions: [buildSession('s1', '会话一')]);
      await pumpSessionList(tester, api);

      await tester.tap(find.byKey(const ValueKey('session-actions-s1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('session-action-delete')));
      await tester.pumpAndSettle();

      expect(find.text('删除会话'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('session-delete-confirm')));
      await tester.pumpAndSettle();

      expect(api.deleteCalls, ['s1']);
      expect(find.text('暂无会话'), findsOneWidget);
    });

    testWidgets('行操作失败：弹窗展示错误并可在点击「好」后关闭', (tester) async {
      final api = FakeSessionListApi(sessions: [buildSession('s1', '会话一')]);
      api.pinError = HttpException(500, null, message: '置顶服务不可用');
      await pumpSessionList(tester, api);

      await tester.tap(find.byKey(const ValueKey('session-actions-s1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('session-action-pin')));
      await tester.pumpAndSettle();

      expect(find.text('操作失败'), findsOneWidget);
      expect(find.textContaining('置顶服务不可用'), findsOneWidget);

      await tester.tap(find.text('好'));
      await tester.pumpAndSettle();
      expect(find.text('操作失败'), findsNothing);
    });
  });
}

/// 聊天页占位（widget 测试用，显示收到的 sessionId 以断言跳转目标）。
class _ChatStub extends StatelessWidget {
  const _ChatStub({required this.sessionId});

  final String sessionId;

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text('chat-$sessionId'),
      ),
      child: const Center(child: Text('聊天占位')),
    );
  }
}
