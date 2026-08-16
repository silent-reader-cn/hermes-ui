import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermex_flutter/core/api/api_client.dart';
import 'package:hermex_flutter/core/api/api_exception.dart';
import 'package:hermex_flutter/core/connections/connection_providers.dart';
import 'package:hermex_flutter/core/models/kanban.dart';
import 'package:hermex_flutter/features/kanban/kanban_page.dart';
import 'package:hermex_flutter/features/kanban/kanban_providers.dart';

import '../../helpers/fake_kanban_api.dart';

// ---------------------------------------------------------------------------
// 测试数据构造
// ---------------------------------------------------------------------------

KanbanBoard buildBoard(String slug, {String? name}) {
  return KanbanBoard(slug: slug, name: name ?? slug);
}

KanbanCard buildCard(
  String id, {
  String? title,
  String? status,
  String? assignee,
  String? body,
  KanbanLinkCounts? linkCounts,
}) {
  return KanbanCard(
    cardID: id,
    title: title ?? '卡片 $id',
    status: status == null ? null : KanbanStatus(status),
    assignee: assignee,
    body: body,
    linkCounts: linkCounts,
  );
}

KanbanBoardSnapshot buildSnapshot(List<KanbanColumn> columns) {
  return KanbanBoardSnapshot(columns: columns);
}

/// 组装 KanbanPage（注入 fake API；页面只用 Navigator push/pop，无需路由表）。
Future<void> pumpKanbanPage(WidgetTester tester, FakeKanbanApi api) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(
          ApiClient(baseUrl: 'http://test.local:30002'),
        ),
        kanbanApiFactoryProvider.overrideWithValue((_) => api),
      ],
      child: const CupertinoApp(home: KanbanPage()),
    ),
  );
  // 首帧（AsyncLoading）+ 异步 build 完成（AsyncData）
  await tester.pump();
  await tester.pump();
}

void main() {
  group('kanbanStatusTitle 状态文案', () {
    test('全部状态映射', () {
      expect(kanbanStatusTitle('triage'), '待分类');
      expect(kanbanStatusTitle('todo'), '待办');
      expect(kanbanStatusTitle('ready'), '就绪');
      expect(kanbanStatusTitle('running'), '运行中');
      expect(kanbanStatusTitle('blocked'), '受阻');
      expect(kanbanStatusTitle('done'), '完成');
      expect(kanbanStatusTitle('archived'), '已归档');
      expect(kanbanStatusTitle(null), '未知状态');
      expect(kanbanStatusTitle('weird'), '不支持: weird');
    });
  });

  group('KanbanPage widget', () {
    testWidgets('看板渲染：切换条 + 分列卡片（标题/负责人/依赖标记）', (tester) async {
      final api = FakeKanbanApi(
        boards: [buildBoard('default', name: '主看板')],
        currentSlug: 'default',
        snapshots: {
          'default': buildSnapshot([
            KanbanColumn(name: 'todo', cards: [
              buildCard(
                'c1',
                title: '实现登录',
                status: 'todo',
                assignee: 'alice',
                linkCounts: const KanbanLinkCounts(parents: 2),
              ),
              buildCard('c2', title: '实现注册', status: 'todo'),
            ]),
            KanbanColumn(name: 'done', cards: [
              buildCard('c3', title: '搭建脚手架', status: 'done', assignee: 'bob'),
            ]),
          ]),
        },
      );
      await pumpKanbanPage(tester, api);

      expect(find.text('看板'), findsOneWidget);
      expect(find.text('主看板'), findsOneWidget);
      expect(find.text('待办'), findsOneWidget);
      expect(find.text('完成'), findsOneWidget);
      expect(find.text('实现登录'), findsOneWidget);
      expect(find.text('实现注册'), findsOneWidget);
      expect(find.text('搭建脚手架'), findsOneWidget);
      expect(find.text('alice'), findsOneWidget);
      expect(find.text('bob'), findsOneWidget);
      expect(find.text('未指派'), findsOneWidget);
      expect(find.text('前驱 2'), findsOneWidget);
      expect(find.byKey(const ValueKey('kanban-create')), findsOneWidget);
      expect(find.byKey(const ValueKey('kanban-board-default')), findsOneWidget);
    });

    testWidgets('加载态：数据到达前显示 ActivityIndicator，到达后渲染', (tester) async {
      final api = FakeKanbanApi(
        boards: [buildBoard('a')],
        currentSlug: 'a',
        snapshots: {
          'a': buildSnapshot([
            KanbanColumn(name: 'todo', cards: [buildCard('c1', title: '到了', status: 'todo')]),
          ]),
        },
      );
      api.fetchGate = Completer<void>();
      await pumpKanbanPage(tester, api);

      expect(find.byType(CupertinoActivityIndicator), findsWidgets);

      api.fetchGate!.complete();
      await tester.pump();
      await tester.pump();
      expect(find.text('到了'), findsOneWidget);
      expect(find.byType(CupertinoActivityIndicator), findsNothing);
    });

    testWidgets('空态：无看板', (tester) async {
      await pumpKanbanPage(tester, FakeKanbanApi());

      expect(find.text('暂无看板'), findsOneWidget);
    });

    testWidgets('错误态：加载失败展示错误信息，重试恢复', (tester) async {
      final api = FakeKanbanApi(
        boards: [buildBoard('a')],
        currentSlug: 'a',
        snapshots: {
          'a': buildSnapshot([
            KanbanColumn(name: 'todo', cards: [buildCard('c1', title: '恢复的卡片', status: 'todo')]),
          ]),
        },
      );
      api.fetchBoardsError = NetworkException(NetworkExceptionKind.cannotConnect);
      await pumpKanbanPage(tester, api);

      expect(find.text('加载失败'), findsOneWidget);
      expect(find.textContaining('无法连接'), findsOneWidget);

      api.fetchBoardsError = null;
      await tester.tap(find.byKey(const ValueKey('kanban-retry')));
      await tester.pump();
      await tester.pump();
      expect(find.text('恢复的卡片'), findsOneWidget);
    });

    testWidgets('切换看板：点击另一看板 chip 后渲染该看板卡片', (tester) async {
      final api = FakeKanbanApi(
        boards: [buildBoard('a', name: '看板A'), buildBoard('b', name: '看板B')],
        currentSlug: 'a',
        snapshots: {
          'a': buildSnapshot([
            KanbanColumn(name: 'todo', cards: [buildCard('c1', title: 'A的卡片', status: 'todo')]),
          ]),
          'b': buildSnapshot([
            KanbanColumn(name: 'done', cards: [buildCard('c2', title: 'B的卡片', status: 'done')]),
          ]),
        },
      );
      await pumpKanbanPage(tester, api);

      expect(find.text('A的卡片'), findsOneWidget);
      expect(find.text('B的卡片'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('kanban-board-b')));
      await tester.pump();
      await tester.pump();

      expect(api.makeBoardActiveCount, 1);
      expect(find.text('B的卡片'), findsOneWidget);
      expect(find.text('A的卡片'), findsNothing);
    });

    testWidgets('创建卡片表单：标题必填，提交后卡片出现在对应列', (tester) async {
      final api = FakeKanbanApi(
        boards: [buildBoard('a')],
        currentSlug: 'a',
        snapshots: {
          'a': buildSnapshot([
            const KanbanColumn(name: 'triage', cards: []),
            KanbanColumn(name: 'todo', cards: [buildCard('c1', title: '旧卡片', status: 'todo')]),
          ]),
        },
      );
      await pumpKanbanPage(tester, api);

      await tester.tap(find.byKey(const ValueKey('kanban-create')));
      await tester.pumpAndSettle();

      // 标题为空时创建按钮禁用。
      final saveButton = tester.widget<CupertinoButton>(
        find.byKey(const ValueKey('kanban-form-save')),
      );
      expect(saveButton.onPressed, isNull);

      await tester.enterText(
        find.byKey(const ValueKey('kanban-form-title')),
        '新功能卡片',
      );
      await tester.enterText(
        find.byKey(const ValueKey('kanban-form-body')),
        '实现一个很棒的功能',
      );
      await tester.enterText(
        find.byKey(const ValueKey('kanban-form-assignee')),
        'carol',
      );
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('kanban-form-save')));
      await tester.pumpAndSettle();

      expect(api.createCardCount, 1);
      expect(find.text('新功能卡片'), findsOneWidget);
      expect(find.text('carol'), findsOneWidget);
      // 表单已关闭。
      expect(find.byKey(const ValueKey('kanban-form-title')), findsNothing);
    });

    testWidgets('创建卡片失败：弹窗提示操作失败', (tester) async {
      final api = FakeKanbanApi(
        boards: [buildBoard('a')],
        currentSlug: 'a',
        snapshots: {
          'a': buildSnapshot([
            const KanbanColumn(name: 'triage', cards: []),
          ]),
        },
      );
      api.createCardError = NetworkException(NetworkExceptionKind.offline);
      await pumpKanbanPage(tester, api);

      await tester.tap(find.byKey(const ValueKey('kanban-create')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('kanban-form-title')),
        '会失败的卡片',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('kanban-form-save')));
      await tester.pumpAndSettle();

      expect(find.text('操作失败'), findsOneWidget);
      await tester.tap(find.text('好'));
      await tester.pumpAndSettle();
    });
  });

  group('KanbanCardDetailPage widget', () {
    testWidgets('卡片详情：描述 + 元信息 + 评论列表 + 状态按钮', (tester) async {
      final api = FakeKanbanApi(
        boards: [buildBoard('a')],
        currentSlug: 'a',
        snapshots: {
          'a': buildSnapshot([
            KanbanColumn(name: 'todo', cards: [buildCard('c1', title: '详情卡片', status: 'todo')]),
          ]),
        },
        details: {
          'c1': KanbanCardDetailEnvelope(
            card: buildCard(
              'c1',
              title: '详情卡片',
              status: 'todo',
              assignee: 'alice',
              body: '这是卡片的详细描述',
            ),
            comments: const [
              KanbanComment(
                commentID: 'k1',
                cardID: 'c1',
                author: 'bob',
                body: '进展如何？',
              ),
            ],
          ),
        },
      );
      await pumpKanbanPage(tester, api);

      await tester.tap(find.byKey(const ValueKey('kanban-card-c1')));
      await tester.pumpAndSettle();

      expect(find.text('这是卡片的详细描述'), findsOneWidget);
      expect(find.text('alice'), findsOneWidget);
      expect(find.text('进展如何？'), findsOneWidget);
      expect(find.text('bob'), findsOneWidget);
      // 状态按钮：待分类/待办(当前)/就绪/完成/受阻 → 除当前外 4 个。
      expect(find.byKey(const ValueKey('kanban-status-triage')), findsOneWidget);
      expect(find.byKey(const ValueKey('kanban-status-todo')), findsNothing);
      expect(find.byKey(const ValueKey('kanban-status-ready')), findsOneWidget);
      expect(find.byKey(const ValueKey('kanban-status-done')), findsOneWidget);
      expect(find.byKey(const ValueKey('kanban-status-blocked')), findsOneWidget);
      expect(find.byKey(const ValueKey('kanban-comment-input')), findsOneWidget);
    });

    testWidgets('状态变更：点完成按钮后详情刷新为新状态', (tester) async {
      final api = FakeKanbanApi(
        boards: [buildBoard('a')],
        currentSlug: 'a',
        snapshots: {
          'a': buildSnapshot([
            KanbanColumn(name: 'todo', cards: [buildCard('c1', title: '变更卡片', status: 'todo')]),
            const KanbanColumn(name: 'done', cards: []),
          ]),
        },
        details: {
          'c1': KanbanCardDetailEnvelope(
            card: buildCard('c1', title: '变更卡片', status: 'todo'),
            comments: const [],
          ),
        },
      );
      await pumpKanbanPage(tester, api);
      await tester.tap(find.byKey(const ValueKey('kanban-card-c1')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('kanban-status-done')));
      await tester.pumpAndSettle();

      expect(api.setStatusCount, 1);
      expect(api.lastSetStatusCall, 'c1:done');
      expect(find.text('完成'), findsWidgets);
    });

    testWidgets('评论：输入并发送后新评论出现在列表', (tester) async {
      final api = FakeKanbanApi(
        boards: [buildBoard('a')],
        currentSlug: 'a',
        snapshots: {
          'a': buildSnapshot([
            KanbanColumn(name: 'todo', cards: [buildCard('c1', title: '评论卡片', status: 'todo')]),
          ]),
        },
        details: {
          'c1': KanbanCardDetailEnvelope(
            card: buildCard('c1', title: '评论卡片', status: 'todo'),
            comments: const [],
          ),
        },
      );
      await pumpKanbanPage(tester, api);
      await tester.tap(find.byKey(const ValueKey('kanban-card-c1')));
      await tester.pumpAndSettle();

      expect(find.text('暂无评论'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('kanban-comment-input')),
        '我来跟进这个问题',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('kanban-comment-send')));
      await tester.pumpAndSettle();

      expect(api.addCommentCount, 1);
      expect(find.text('我来跟进这个问题'), findsOneWidget);
      expect(find.text('暂无评论'), findsNothing);
    });
  });
}
