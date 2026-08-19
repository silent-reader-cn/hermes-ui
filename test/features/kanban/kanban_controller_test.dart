import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermex_flutter/core/api/api_client.dart';
import 'package:hermex_flutter/core/api/api_exception.dart';
import 'package:hermex_flutter/core/api/ws_client.dart';
import 'package:hermex_flutter/core/connections/connection_providers.dart';
import 'package:hermex_flutter/core/models/kanban.dart';
import 'package:hermex_flutter/features/kanban/kanban_providers.dart';

import '../../helpers/fake_kanban_api.dart';

// ---------------------------------------------------------------------------
// 测试数据构造
// ---------------------------------------------------------------------------

KanbanBoard buildBoard(String slug, {String? name, bool isCurrent = false}) {
  return KanbanBoard(slug: slug, name: name ?? slug, isCurrent: isCurrent);
}

KanbanCard buildCard(
  String id, {
  String? title,
  String? status,
  String? assignee,
  int? commentCount,
  KanbanLinkCounts? linkCounts,
}) {
  return KanbanCard(
    cardID: id,
    title: title ?? '卡片 $id',
    status: status == null ? null : KanbanStatus(status),
    assignee: assignee,
    commentCount: commentCount,
    linkCounts: linkCounts,
  );
}

KanbanColumn buildColumn(String name, List<KanbanCard> cards) {
  return KanbanColumn(name: name, cards: cards);
}

KanbanBoardSnapshot buildSnapshot(
  List<KanbanColumn> columns, {
  int? latestEventId,
}) {
  return KanbanBoardSnapshot(columns: columns, latestEventID: latestEventId);
}

/// 组装测试容器（注入 fake API，绕开网络）。
ProviderContainer makeContainer(FakeKanbanApi api) {
  final container = ProviderContainer(
    overrides: [
      apiClientProvider.overrideWithValue(
        ApiClient(baseUrl: 'http://test.local:30002'),
      ),
      kanbanApiFactoryProvider.overrideWithValue((_) => api),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// 等待微任务队列清空（事件流回调 → 刷新 → 状态落定）。
Future<void> settle() => pumpEventQueue();

void main() {
  group('KanbanController 加载', () {
    test('加载看板列表 + 当前看板快照 + 订阅事件流', () async {
      final api = FakeKanbanApi(
        boards: [buildBoard('default', name: '默认看板')],
        currentSlug: 'default',
        snapshots: {
          'default': buildSnapshot(
            [buildColumn('todo', [buildCard('c1', status: 'todo')])],
            latestEventId: 7,
          ),
        },
      );
      final container = makeContainer(api);

      final state = await container.read(kanbanControllerProvider.future);

      expect(state.boards, hasLength(1));
      expect(state.currentBoardSlug, 'default');
      expect(state.currentBoard?.name, '默认看板');
      expect(state.columns, hasLength(1));
      expect(state.columns.first.name, 'todo');
      expect(state.columns.first.cards!.single.cardID, 'c1');
      // 事件流以快照游标订阅。
      expect(api.streamSubscribeCount, 1);
      expect(api.streamSubscriptions, ['default:7']);
    });

    test('无看板：空列表、无快照、不订阅事件流', () async {
      final api = FakeKanbanApi();
      final container = makeContainer(api);

      final state = await container.read(kanbanControllerProvider.future);

      expect(state.boards, isEmpty);
      expect(state.currentBoardSlug, isNull);
      expect(state.snapshot, isNull);
      expect(api.streamSubscribeCount, 0);
    });

    test('服务端未标 current 时默认选第一个看板', () async {
      final api = FakeKanbanApi(
        boards: [buildBoard('a'), buildBoard('b')],
        snapshots: {
          'a': buildSnapshot([buildColumn('todo', [])]),
        },
      );
      final container = makeContainer(api);

      final state = await container.read(kanbanControllerProvider.future);

      expect(state.currentBoardSlug, 'a');
      expect(api.fetchBoardCount, 1);
    });

    test('加载失败 → AsyncError，refresh 恢复', () async {
      final api = FakeKanbanApi(
        boards: [buildBoard('a')],
        currentSlug: 'a',
        snapshots: {
          'a': buildSnapshot([buildColumn('todo', [buildCard('c1', status: 'todo')])]),
        },
      );
      api.fetchBoardsError = NetworkException(NetworkExceptionKind.cannotConnect);
      final container = makeContainer(api);

      // 首次读取触发异步 build；失败时 future 以原始异常完成。
      final future = container.read(kanbanControllerProvider.future);
      await expectLater(future, throwsA(isA<NetworkException>()));
      expect(container.read(kanbanControllerProvider).hasError, isTrue);

      api.fetchBoardsError = null;
      await container.read(kanbanControllerProvider.notifier).refresh();
      final state = container.read(kanbanControllerProvider).valueOrNull!;
      expect(state.boards, hasLength(1));
      expect(state.columns.single.cards!.single.cardID, 'c1');
    });

    test('refresh 重载列表 + 快照并重订事件流', () async {
      final api = FakeKanbanApi(
        boards: [buildBoard('a')],
        currentSlug: 'a',
        snapshots: {
          'a': buildSnapshot([buildColumn('todo', [])]),
        },
      );
      final container = makeContainer(api);
      await container.read(kanbanControllerProvider.future);

      await container.read(kanbanControllerProvider.notifier).refresh();

      expect(api.fetchBoardsCount, 2);
      expect(api.fetchBoardCount, 2);
      expect(api.streamSubscribeCount, 2);
    });
  });

  group('KanbanController 事件流刷新', () {
    test('收到 events 帧 → 重拉快照并更新状态', () async {
      final api = FakeKanbanApi(
        boards: [buildBoard('a')],
        currentSlug: 'a',
        snapshots: {
          'a': buildSnapshot([buildColumn('todo', [buildCard('c1', status: 'todo')])]),
        },
      );
      final container = makeContainer(api);
      await container.read(kanbanControllerProvider.future);
      expect(api.fetchBoardCount, 1);

      // 服务器端变化：c1 变为 done（新快照）。
      api.snapshots['a'] = buildSnapshot([
        buildColumn('todo', []),
        buildColumn('done', [buildCard('c1', status: 'done')]),
      ]);
      api.emitFrame(const KanbanEventsFrame(
        events: [
          KanbanEvent(eventID: 8, cardID: 'c1', kind: 'status_changed'),
        ],
        cursor: 8,
      ));
      await settle();

      expect(api.fetchBoardCount, 2);
      final state = container.read(kanbanControllerProvider).valueOrNull!;
      expect(state.columns, hasLength(2));
      expect(
        state.columns
            .firstWhere((c) => c.name == 'done')
            .cards!
            .single
            .status!
            .rawValue,
        'done',
      );
    });

    test('hello / 空 events / 畸形帧不触发刷新', () async {
      final api = FakeKanbanApi(
        boards: [buildBoard('a')],
        currentSlug: 'a',
        snapshots: {
          'a': buildSnapshot([buildColumn('todo', [])]),
        },
      );
      final container = makeContainer(api);
      await container.read(kanbanControllerProvider.future);

      api.emitFrame(const KanbanHelloFrame(cursor: 0, board: 'a'));
      api.emitFrame(const KanbanEventsFrame(events: [], cursor: 1));
      api.emitFrame(const KanbanIgnoredFrame());
      api.emitFrame(const KanbanMalformedFrame());
      await settle();

      expect(api.fetchBoardCount, 1);
    });

    test('流断开（done）不崩，列表保留', () async {
      final api = FakeKanbanApi(
        boards: [buildBoard('a')],
        currentSlug: 'a',
        snapshots: {
          'a': buildSnapshot([buildColumn('todo', [buildCard('c1', status: 'todo')])]),
        },
      );
      final container = makeContainer(api);
      await container.read(kanbanControllerProvider.future);

      api.closeStream();
      await settle();

      final state = container.read(kanbanControllerProvider).valueOrNull!;
      expect(state.columns.single.cards!.single.cardID, 'c1');
    });
  });

  group('KanbanController 切换看板', () {
    test('selectBoard：激活服务器看板 + 重载列表/快照 + 重订事件流', () async {
      final api = FakeKanbanApi(
        boards: [buildBoard('a'), buildBoard('b')],
        currentSlug: 'a',
        snapshots: {
          'a': buildSnapshot([buildColumn('todo', [buildCard('c1', status: 'todo')])]),
          'b': buildSnapshot([buildColumn('done', [buildCard('c2', status: 'done')])]),
        },
      );
      final container = makeContainer(api);
      await container.read(kanbanControllerProvider.future);

      await container.read(kanbanControllerProvider.notifier).selectBoard('b');

      expect(api.makeBoardActiveCount, 1);
      expect(api.makeBoardActiveCalls, ['b']);
      final state = container.read(kanbanControllerProvider).valueOrNull!;
      expect(state.currentBoardSlug, 'b');
      expect(state.currentBoard?.slug, 'b');
      expect(state.columns.single.name, 'done');
      expect(state.columns.single.cards!.single.cardID, 'c2');
      expect(api.streamSubscriptions.last, startsWith('b:'));
    });

    test('重复选择当前看板 → 不请求', () async {
      final api = FakeKanbanApi(
        boards: [buildBoard('a')],
        currentSlug: 'a',
        snapshots: {
          'a': buildSnapshot([buildColumn('todo', [])]),
        },
      );
      final container = makeContainer(api);
      await container.read(kanbanControllerProvider.future);

      await container.read(kanbanControllerProvider.notifier).selectBoard('a');

      expect(api.makeBoardActiveCount, 0);
      expect(api.fetchBoardsCount, 1);
    });

    test('makeBoardActive 失败不阻断浏览，仅提示', () async {
      final api = FakeKanbanApi(
        boards: [buildBoard('a'), buildBoard('b')],
        currentSlug: 'a',
        snapshots: {
          'a': buildSnapshot([buildColumn('todo', [])]),
          'b': buildSnapshot([buildColumn('done', [])]),
        },
      );
      api.makeBoardActiveError = HttpException(500, 'boom');
      final container = makeContainer(api);

      await container.read(kanbanControllerProvider.future);
      await container.read(kanbanControllerProvider.notifier).selectBoard('b');

      final state = container.read(kanbanControllerProvider).valueOrNull!;
      expect(state.currentBoardSlug, 'b'); // 仍可浏览
      expect(state.actionError, isNotNull);
    });
  });

  group('KanbanController 创建卡片', () {
    test('创建成功：生成 idempotency key 并把卡片插入对应列', () async {
      final api = FakeKanbanApi(
        boards: [buildBoard('a')],
        currentSlug: 'a',
        snapshots: {
          'a': buildSnapshot([
            buildColumn('triage', []),
            buildColumn('todo', [buildCard('c1', status: 'todo')]),
          ]),
        },
      );
      final container = makeContainer(api);
      await container.read(kanbanControllerProvider.future);

      final ok = await container
          .read(kanbanControllerProvider.notifier)
          .createCard(title: '新卡片', status: 'todo', assignee: 'alice');

      expect(ok, isTrue);
      expect(api.createCardCount, 1);
      expect(api.lastIdempotencyKey, isNotNull);
      expect(api.lastIdempotencyKey, isNotEmpty);
      final state = container.read(kanbanControllerProvider).valueOrNull!;
      final todo = state.columns.firstWhere((c) => c.name == 'todo');
      expect(todo.cards, hasLength(2));
      expect(todo.cards!.first.title, '新卡片');
    });

    test('标题为空 → 拒绝且不发请求', () async {
      final api = FakeKanbanApi(
        boards: [buildBoard('a')],
        currentSlug: 'a',
        snapshots: {
          'a': buildSnapshot([buildColumn('todo', [])]),
        },
      );
      final container = makeContainer(api);
      await container.read(kanbanControllerProvider.future);

      final ok = await container
          .read(kanbanControllerProvider.notifier)
          .createCard(title: '   ', status: 'todo');

      expect(ok, isFalse);
      expect(api.createCardCount, 0);
      expect(
        container.read(kanbanControllerProvider).valueOrNull!.actionError,
        contains('标题'),
      );
    });

    test('创建失败 → false + actionError，列表不变', () async {
      final api = FakeKanbanApi(
        boards: [buildBoard('a')],
        currentSlug: 'a',
        snapshots: {
          'a': buildSnapshot([buildColumn('todo', [buildCard('c1', status: 'todo')])]),
        },
      );
      api.createCardError = NetworkException(NetworkExceptionKind.cannotConnect);
      final container = makeContainer(api);
      await container.read(kanbanControllerProvider.future);

      final ok = await container
          .read(kanbanControllerProvider.notifier)
          .createCard(title: '新卡片', status: 'todo');

      expect(ok, isFalse);
      expect(
        container.read(kanbanControllerProvider).valueOrNull!.actionError,
        isNotNull,
      );
      expect(
        container.read(kanbanControllerProvider).valueOrNull!.columns.single
            .cards!
            .single
            .cardID,
        'c1',
      );
    });
  });

  group('KanbanController 状态变更状态机', () {
    test('running 守卫：本地拦截，不发请求，返回错误文案', () async {
      final api = FakeKanbanApi(
        boards: [buildBoard('a')],
        currentSlug: 'a',
        snapshots: {
          'a': buildSnapshot([
            buildColumn('todo', [buildCard('c1', status: 'todo')]),
            buildColumn('done', []),
          ]),
        },
      );
      final container = makeContainer(api);
      await container.read(kanbanControllerProvider.future);

      final error = await container
          .read(kanbanControllerProvider.notifier)
          .setStatus(cardId: 'c1', status: 'running');

      expect(error, contains('running'));
      expect(api.setStatusCount, 0);
      final state = container.read(kanbanControllerProvider).valueOrNull!;
      expect(
        state.columns.firstWhere((c) => c.name == 'todo').cards!.single.cardID,
        'c1',
      );
    });

    test('成功：请求发出，卡片从原列移到目标列', () async {
      final api = FakeKanbanApi(
        boards: [buildBoard('a')],
        currentSlug: 'a',
        snapshots: {
          'a': buildSnapshot([
            buildColumn('todo', [buildCard('c1', status: 'todo')]),
            buildColumn('done', []),
          ]),
        },
      );
      final container = makeContainer(api);
      await container.read(kanbanControllerProvider.future);

      final error = await container
          .read(kanbanControllerProvider.notifier)
          .setStatus(cardId: 'c1', status: 'done');

      expect(error, isNull);
      expect(api.setStatusCount, 1);
      expect(api.lastSetStatusCall, 'c1:done');
      final state = container.read(kanbanControllerProvider).valueOrNull!;
      expect(
        state.columns.firstWhere((c) => c.name == 'todo').cards,
        isEmpty,
      );
      final done = state.columns.firstWhere((c) => c.name == 'done');
      expect(done.cards!.single.cardID, 'c1');
      expect(done.cards!.single.status!.rawValue, 'done');
    });

    test('失败：返回错误文案，本地状态不变', () async {
      final api = FakeKanbanApi(
        boards: [buildBoard('a')],
        currentSlug: 'a',
        snapshots: {
          'a': buildSnapshot([
            buildColumn('todo', [buildCard('c1', status: 'todo')]),
            buildColumn('done', []),
          ]),
        },
      );
      api.setStatusError = HttpException(500, 'server down');
      final container = makeContainer(api);
      await container.read(kanbanControllerProvider.future);

      final error = await container
          .read(kanbanControllerProvider.notifier)
          .setStatus(cardId: 'c1', status: 'done');

      expect(error, isNotNull);
      expect(api.setStatusCount, 1);
      final state = container.read(kanbanControllerProvider).valueOrNull!;
      expect(
        state.columns.firstWhere((c) => c.name == 'todo').cards!.single.cardID,
        'c1',
      );
      expect(
        state.columns.firstWhere((c) => c.name == 'done').cards,
        isEmpty,
      );
    });

    test('目标列不存在 → 卡片从视图移除', () async {
      final api = FakeKanbanApi(
        boards: [buildBoard('a')],
        currentSlug: 'a',
        snapshots: {
          'a': buildSnapshot([
            buildColumn('todo', [buildCard('c1', status: 'todo')]),
          ]),
        },
      );
      final container = makeContainer(api);
      await container.read(kanbanControllerProvider.future);

      final error = await container
          .read(kanbanControllerProvider.notifier)
          .setStatus(cardId: 'c1', status: 'archived');

      expect(error, isNull);
      final state = container.read(kanbanControllerProvider).valueOrNull!;
      expect(state.columns.single.cards, isEmpty);
    });
  });

  group('KanbanController 评论', () {
    test('加评论成功：评论计数 +1', () async {
      final api = FakeKanbanApi(
        boards: [buildBoard('a')],
        currentSlug: 'a',
        snapshots: {
          'a': buildSnapshot([
            buildColumn('todo', [buildCard('c1', status: 'todo', commentCount: 2)]),
          ]),
        },
      );
      final container = makeContainer(api);
      await container.read(kanbanControllerProvider.future);

      final error = await container
          .read(kanbanControllerProvider.notifier)
          .addComment(cardId: 'c1', body: '请补充细节');

      expect(error, isNull);
      expect(api.addCommentCount, 1);
      final state = container.read(kanbanControllerProvider).valueOrNull!;
      final card = state.columns.single.cards!.single;
      expect(card.commentCount, 3);
    });

    test('加评论失败：返回错误文案，计数不变', () async {
      final api = FakeKanbanApi(
        boards: [buildBoard('a')],
        currentSlug: 'a',
        snapshots: {
          'a': buildSnapshot([
            buildColumn('todo', [buildCard('c1', status: 'todo', commentCount: 2)]),
          ]),
        },
      );
      api.addCommentError = NetworkException(NetworkExceptionKind.offline);
      final container = makeContainer(api);
      await container.read(kanbanControllerProvider.future);

      final error = await container
          .read(kanbanControllerProvider.notifier)
          .addComment(cardId: 'c1', body: '请补充细节');

      expect(error, isNotNull);
      expect(
        container.read(kanbanControllerProvider).valueOrNull!.columns.single
            .cards!
            .single
            .commentCount,
        2,
      );
    });
  });

  group('KanbanDetailController', () {
    test('加载卡片详情（卡片 + 评论）', () async {
      final api = FakeKanbanApi(
        boards: [buildBoard('a')],
        currentSlug: 'a',
        snapshots: {
          'a': buildSnapshot([
            buildColumn('todo', [buildCard('c1', status: 'todo')]),
          ]),
        },
        details: {
          'c1': KanbanCardDetailEnvelope(
            card: buildCard('c1', status: 'todo'),
            comments: [
              const KanbanComment(
                commentID: 'c1',
                cardID: 'c1',
                author: 'alice',
                body: '第一条评论',
              ),
            ],
          ),
        },
      );
      final container = makeContainer(api);
      await container.read(kanbanControllerProvider.future);

      final state =
          await container.read(kanbanDetailControllerProvider('c1').future);

      expect(state.card?.cardID, 'c1');
      expect(state.comments.single.body, '第一条评论');
    });

    test('提交评论成功：详情刷新包含新评论', () async {
      final api = FakeKanbanApi(
        boards: [buildBoard('a')],
        currentSlug: 'a',
        snapshots: {
          'a': buildSnapshot([
            buildColumn('todo', [buildCard('c1', status: 'todo')]),
          ]),
        },
        details: {
          'c1': KanbanCardDetailEnvelope(
            card: buildCard('c1', status: 'todo'),
            comments: const [],
          ),
        },
      );
      final container = makeContainer(api);
      await container.read(kanbanControllerProvider.future);
      await container.read(kanbanDetailControllerProvider('c1').future);

      final ok = await container
          .read(kanbanDetailControllerProvider('c1').notifier)
          .submitComment('新评论内容');

      expect(ok, isTrue);
      expect(api.addCommentCount, 1);
      final state = container.read(kanbanDetailControllerProvider('c1')).valueOrNull!;
      expect(state.comments, hasLength(1));
      expect(state.comments.single.body, '新评论内容');
      expect(state.isSubmittingComment, isFalse);
    });

    test('评论失败：返回 false，actionError 置文案', () async {
      final api = FakeKanbanApi(
        boards: [buildBoard('a')],
        currentSlug: 'a',
        snapshots: {
          'a': buildSnapshot([
            buildColumn('todo', [buildCard('c1', status: 'todo')]),
          ]),
        },
        details: {
          'c1': KanbanCardDetailEnvelope(
            card: buildCard('c1', status: 'todo'),
            comments: const [],
          ),
        },
      );
      api.addCommentError = HttpException(500, 'boom');
      final container = makeContainer(api);
      await container.read(kanbanControllerProvider.future);
      await container.read(kanbanDetailControllerProvider('c1').future);

      final ok = await container
          .read(kanbanDetailControllerProvider('c1').notifier)
          .submitComment('新评论内容');

      expect(ok, isFalse);
      final state = container.read(kanbanDetailControllerProvider('c1')).valueOrNull!;
      expect(state.actionError, isNotNull);
      expect(state.comments, isEmpty);
    });
  });
}
