import 'package:flutter_test/flutter_test.dart';
import 'package:hermex_flutter/core/models/kanban.dart';

void main() {
  group('KanbanConfiguration', () {
    test('正常解析 + assignees 多形态', () {
      final config = KanbanConfiguration.fromJson({
        'columns': ['todo', 'done'],
        'assignees': ['alice', {'name': 'bob'}],
        'default_tenant': 't1',
        'lane_by_profile': true,
        'include_archived_by_default': false,
        'render_markdown': true,
        'read_only': false,
      });
      expect(config.columns, ['todo', 'done']);
      expect(config.assignees, ['alice', 'bob']);
      expect(config.defaultTenant, 't1');
      expect(config.renderMarkdown, true);
    });

    test('assignees 任一元素非字符串非对象 → 整数组 null（对齐 Swift）', () {
      final config = KanbanConfiguration.fromJson({
        'assignees': ['alice', 42],
      });
      expect(config.assignees, isNull);
    });

    test('畸形输入：缺失/错型 → 容错', () {
      final config = KanbanConfiguration.fromJson({
        'columns': 'bad',
        'assignees': 'bad',
        'default_tenant': 1,
        'read_only': 'yes',
      });
      expect(config.columns, isNull);
      expect(config.assignees, isNull);
      expect(config.defaultTenant, '1');
      expect(config.readOnly, true);
    });
  });

  group('KanbanBoardsResponse / KanbanBoard', () {
    test('规格示例正常解析', () {
      final response = KanbanBoardsResponse.fromJson({
        'boards': [
          {
            'slug': 'dev',
            'name': '开发',
            'description': '…',
            'icon': '🛠️',
            'color': '#4f46e5',
            'is_current': true,
            'total': 42,
            'counts': {'todo': 10, 'running': 3},
            'read_only': false,
          },
        ],
        'current': 'dev',
        'read_only': false,
      });
      final board = response.boards!.single;
      expect(board.slug, 'dev');
      expect(board.name, '开发');
      expect(board.isCurrent, true);
      expect(board.total, 42);
      expect(board.counts, {'todo': 10, 'running': 3});
      expect(response.current, 'dev');
    });

    test('畸形输入：counts 错型 → null', () {
      final board = KanbanBoard.fromJson({
        'slug': 1,
        'total': 'bad',
        'counts': 'bad',
        'is_current': 'yes',
      });
      expect(board.slug, '1');
      expect(board.total, isNull);
      expect(board.counts, isNull);
      expect(board.isCurrent, true);
      expect(KanbanBoardsResponse.fromJson({'boards': 'bad'}).boards, isNull);
    });

    test('KanbanBoardMutationEnvelope', () {
      final envelope = KanbanBoardMutationEnvelope.fromJson(
        {'board': {'slug': 'dev'}, 'current': 'dev', 'read_only': false},
      );
      expect(envelope.board!.slug, 'dev');
      expect(envelope.current, 'dev');
      expect(envelope.readOnly, false);
    });
  });

  group('KanbanBoardSnapshot / KanbanColumn / KanbanAppliedFilters', () {
    test('规格示例正常解析（latestEventId 显式键）', () {
      final snapshot = KanbanBoardSnapshot.fromJson({
        'columns': [
          {'name': 'todo', 'tasks': []},
        ],
        'tenants': ['t1'],
        'assignees': ['alice'],
        'filters': {
          'tenant': null,
          'assignee': 'alice',
          'include_archived': false,
          'only_mine': false,
          'profile': null,
        },
        'changed': true,
        'latestEventId': 99,
        'read_only': false,
      });
      expect(snapshot.columns!.single.name, 'todo');
      expect(snapshot.columns!.single.cards, isEmpty);
      expect(snapshot.tenants, ['t1']);
      expect(snapshot.filters!.assignee, 'alice');
      expect(snapshot.latestEventID, 99);
      expect(snapshot.changed, true);
    });

    test('畸形输入 → 容错', () {
      final snapshot = KanbanBoardSnapshot.fromJson({
        'columns': 'bad',
        'filters': 'bad',
        'latestEventId': 'bad',
      });
      expect(snapshot.columns, isNull);
      expect(snapshot.filters, isNull);
      expect(snapshot.latestEventID, isNull);
    });
  });

  group('KanbanCard / KanbanStatus / staleness', () {
    test('规格示例正常解析（显式键 id/currentRunId/workerPid）', () {
      final card = KanbanCard.fromJson({
        'id': 'card_1',
        'title': '实现登录页',
        'status': 'ready',
        'assignee': 'alice',
        'body': '…',
        'tenant': 't1',
        'priority': 1,
        'comment_count': 2,
        'link_counts': {'parents': 1, 'children': 0},
        'age_seconds': 1200.0,
        'created_at': '2026-08-15T10:00:00Z',
        'updated_at': '2026-08-15T10:20:00Z',
        'workspace_kind': 'hermes',
        'workspace_path': '/home/u/proj',
        'skills': ['dart'],
        'max_runtime_seconds': 600,
        'currentRunId': null,
        'claim_lock': null,
        'claim_expires': null,
        'workerPid': null,
      });
      expect(card.cardID, 'card_1');
      expect(card.title, '实现登录页');
      expect(card.status!.rawValue, 'ready');
      expect(card.status!.isSupported, true);
      expect(card.linkCounts!.parents, 1);
      expect(card.ageSeconds, 1200.0);
      expect(card.skills, ['dart']);
    });

    test('KanbanStatus 保留未知值（类而非枚举）', () {
      final card = KanbanCard.fromJson({'status': 'mystery'});
      expect(card.status!.rawValue, 'mystery');
      expect(card.status!.isSupported, false);
      expect(const KanbanStatus('RUNNING').isSupported, true);
    });

    test('staleness 判定', () {
      expect(KanbanCard.fromJson({'status': 'running', 'age_seconds': 7200}).staleness,
          KanbanStaleness.critical);
      expect(KanbanCard.fromJson({'status': 'running', 'age_seconds': 900}).staleness,
          KanbanStaleness.warning);
      expect(KanbanCard.fromJson({'status': 'running', 'age_seconds': 60}).staleness,
          KanbanStaleness.none);
      expect(KanbanCard.fromJson({'status': 'ready', 'age_seconds': 7200}).staleness,
          KanbanStaleness.warning);
      expect(KanbanCard.fromJson({'status': 'blocked', 'age_seconds': 90000}).staleness,
          KanbanStaleness.critical);
      expect(KanbanCard.fromJson({'status': 'blocked', 'age_seconds': 7200}).staleness,
          KanbanStaleness.warning);
      expect(KanbanCard.fromJson(const {}).staleness, KanbanStaleness.none);
      expect(KanbanCard.fromJson({'status': 'todo', 'age_seconds': 999999}).staleness,
          KanbanStaleness.none);
    });

    test('replacingStatus：非 running 清空运行字段', () {
      final card = KanbanCard.fromJson({
        'id': 'c1',
        'status': 'running',
        'currentRunId': 'r1',
        'claim_lock': 'l',
        'claim_expires': 'e',
        'workerPid': 'w',
      });
      final moved = card.replacingStatus('done');
      expect(moved.status!.rawValue, 'done');
      expect(moved.currentRunID, isNull);
      expect(moved.claimLock, isNull);
      expect(moved.workerID, isNull);
      final running = card.replacingStatus('running');
      expect(running.currentRunID, 'r1');
    });

    test('畸形输入 → 容错', () {
      final card = KanbanCard.fromJson({
        'title': 1,
        'priority': 'high',
        'age_seconds': 'old',
        'link_counts': 'bad',
        'skills': 'bad',
      });
      expect(card.title, '1');
      expect(card.priority, isNull);
      expect(card.ageSeconds, isNull);
      expect(card.linkCounts, isNull);
      expect(card.skills, isNull);
    });
  });

  group('卡片详情家族', () {
    test('KanbanCardDetailEnvelope 规格示例（task 键）', () {
      final envelope = KanbanCardDetailEnvelope.fromJson({
        'task': {'id': 'card_1', 'title': '实现登录页', 'status': 'ready'},
        'comments': [
          {'id': 'c1', 'taskId': 'card_1', 'author': 'alice', 'body': '看看', 'created_at': '…'},
        ],
        'events': [
          {
            'id': 'e1',
            'taskId': 'card_1',
            'run_id': 'run_2',
            'kind': 'status_change',
            'created_at': '…',
            'payload': {'status': 'ready', 'reason': '…', 'summary': '…', 'fields': ['a']},
          },
        ],
        'links': {'parents': ['card_0'], 'children': []},
        'runs': [
          {
            'id': 'run_2',
            'status': 'completed',
            'outcome': 'success',
            'summary': '…',
            'started_at': '…',
            'endedAt': '…',
            'workerPid': '1234',
            'log_tail': '…',
          },
        ],
        'read_only': false,
      });
      expect(envelope.card!.cardID, 'card_1');
      expect(envelope.comments!.single.commentID, 'c1');
      expect(envelope.comments!.single.cardID, 'card_1');
      expect(envelope.comments!.single.presentationID, 'c1');
      expect(envelope.events!.single.kind, 'status_change');
      expect(envelope.events!.single.payload!.fields, ['a']);
      expect(envelope.links!.prerequisites, ['card_0']);
      expect(envelope.links!.dependents, isEmpty);
      expect(envelope.runs!.single.runID, 'run_2');
      expect(envelope.runs!.single.finishedAt, '…');
      expect(envelope.runs!.single.workerID, '1234');
      expect(envelope.readOnly, false);
    });

    test('KanbanDispatchRun 双键兜底', () {
      expect(KanbanDispatchRun.fromJson({'runId': 'r'}).runID, 'r');
      expect(KanbanDispatchRun.fromJson({'finished_at': 'f'}).finishedAt, 'f');
      expect(KanbanDispatchRun.fromJson({'worker': 'w'}).workerID, 'w');
      expect(KanbanDispatchRun.fromJson(const {}).presentationID, '');
    });

    test('KanbanComment / KanbanDetailEvent presentationID 派生', () {
      expect(
        KanbanComment.fromJson({
          'taskId': 'c',
          'author': 'a',
          'created_at': 't',
          'body': 'b',
        }).presentationID,
        'c|a|t|b',
      );
      expect(
        KanbanDetailEvent.fromJson({
          'taskId': 'c',
          'run_id': 'r',
          'kind': 'k',
          'created_at': 't',
        }).presentationID,
        'c|r|k|t',
      );
    });

    test('KanbanWorkerLog / KanbanAddCommentResponse / KanbanStats / KanbanAssigneeHistory', () {
      final log = KanbanWorkerLog.fromJson({
        'taskId': 'card_1',
        'exists': true,
        'size_bytes': 1024,
        'content': '…',
        'truncated': false,
      });
      expect(log.cardID, 'card_1');
      expect(log.sizeBytes, 1024);
      expect(KanbanWorkerLog.fromJson(const {}).content, isNull);

      final addComment = KanbanAddCommentResponse.fromJson(
        {'ok': true, 'commentId': 'c2', 'read_only': false},
      );
      expect(addComment.commentID, 'c2');

      final stats = KanbanStats.fromJson({
        'total': 42,
        'by_status': {'todo': 10},
        'by_assignee': {'alice': 3},
      });
      expect(stats.total, 42);
      expect(stats.byStatus, {'todo': 10});

      final history = KanbanAssigneeHistory.fromJson(
        {'assignees': ['alice', {'name': 'bob'}]},
      );
      expect(history.assignees, ['alice', 'bob']);
    });
  });

  group('事件流 / 批量 / 依赖 / dispatch', () {
    test('KanbanEventsEnvelope + KanbanEvent（id 为 int）', () {
      final envelope = KanbanEventsEnvelope.fromJson({
        'events': [
          {'id': 1, 'taskId': 'card_1', 'runId': 'run_2', 'kind': 'created', 'created_at': 1723700000},
        ],
        'cursor': 5,
        'latestEventId': 5,
        'read_only': false,
      });
      expect(envelope.events!.single.eventID, 1);
      expect(envelope.events!.single.createdAt, 1723700000);
      expect(envelope.cursor, 5);
      expect(envelope.latestEventID, 5);
    });

    test('KanbanBulkActionEnvelope / KanbanBulkActionResult（非对象元素三字段全 null）', () {
      final envelope = KanbanBulkActionEnvelope.fromJson({
        'results': [
          {'id': 'card_1', 'ok': true, 'error': null},
          {'id': 'card_2', 'ok': false, 'error': 'boom'},
        ],
        'read_only': false,
      });
      expect(envelope.results, hasLength(2));
      expect(envelope.results![0].cardID, 'card_1');
      expect(envelope.results![0].ok, true);
      expect(envelope.results![1].error, 'boom');
      // 整元素非对象 → 三字段全 null
      final bare = KanbanBulkActionResult.fromJson('bare-string');
      expect(bare.cardID, isNull);
      expect(bare.ok, isNull);
      expect(bare.error, isNull);
      // 数组含非对象元素 → 整数组 null（optModelList 语义）
      expect(
        KanbanBulkActionEnvelope.fromJson({'results': [{'id': 'c'}, 42]})
            .results,
        isNull,
      );
    });

    test('KanbanDependencyMutationEnvelope（parentId/childId 显式键）', () {
      final envelope = KanbanDependencyMutationEnvelope.fromJson({
        'ok': true,
        'changed': true,
        'parentId': 'card_0',
        'childId': 'card_1',
        'read_only': false,
      });
      expect(envelope.ok, true);
      expect(envelope.prerequisiteID, 'card_0');
      expect(envelope.dependentID, 'card_1');
    });

    test('KanbanDispatchResult 计数特殊解析', () {
      final result = KanbanDispatchResult.fromJson({
        'spawned': 2,
        'promoted': 1,
        'reclaimed': 0,
        'skipped_unassigned': ['a', 'b', 'c'],
        'skipped_nonspawnable': '3',
        'auto_blocked': 4.9,
        'timed_out': true,
        'crashed': {'x': 1},
      });
      expect(result.spawned, 2);
      expect(result.promoted, 1);
      expect(result.reclaimed, 0);
      expect(result.skippedUnassigned, 3); // 数组长度
      expect(result.skippedNonspawnable, 3); // 字符串解析
      expect(result.autoBlocked, 4); // 数字截断
      expect(result.timedOut, isNull); // bool → null
      expect(result.crashed, isNull); // object → null
      expect(result.hasKnownCategory, true);
      expect(
        KanbanDispatchResult.fromJson(const {}).hasKnownCategory,
        false,
      );
    });
  });

  group('请求 DTO', () {
    test('queryParameters 生成', () {
      expect(
        const KanbanBoardRequest(board: 'dev', tenant: 't', since: 5).queryParameters,
        {'board': 'dev', 'tenant': 't', 'since': '5'},
      );
      expect(
        const KanbanBoardRequest(board: 'dev', includeArchived: true, onlyMine: true)
            .queryParameters,
        {'board': 'dev', 'include_archived': 'true', 'only_mine': 'true'},
      );
      expect(
        const KanbanEventsRequest(board: 'dev', since: 3, limit: 999).queryParameters,
        {'board': 'dev', 'since': '3', 'limit': '200'},
      );
      expect(
        const KanbanEventsRequest(board: 'dev', since: -1, limit: 0).queryParameters,
        {'board': 'dev', 'since': '0', 'limit': '1'},
      );
      expect(
        const KanbanWorkerLogRequest(cardID: 'c', board: 'dev').queryParameters,
        {'board': 'dev', 'tail': '65536'},
      );
      expect(
        const KanbanWorkerLogRequest(cardID: 'c', board: 'dev', tailBytes: 99999999)
            .queryParameters,
        {'board': 'dev', 'tail': '2000000'},
      );
      expect(
        const KanbanDispatchRequest(board: 'dev', dryRun: true).queryParameters,
        {'board': 'dev', 'dry_run': 'true', 'max': '8'},
      );
    });

    test('body toJson 输出 snake_case', () {
      final create = const KanbanCreateCardRequest(
        board: 'dev',
        title: 't',
        status: 'todo',
        workspaceKind: 'hermes',
        idempotencyKey: 'k',
      );
      expect(create.queryParameters, {'board': 'dev'});
      expect(create.toJson(), {
        'title': 't',
        'status': 'todo',
        'workspace_kind': 'hermes',
        'idempotency_key': 'k',
      });

      expect(
        const KanbanDependencyMutationRequest(
          board: 'dev',
          prerequisiteID: 'p',
          dependentID: 'd',
        ).toJson(),
        {'prerequisite_id': 'p', 'dependent_id': 'd'},
      );

      expect(
        const KanbanCreateBoardRequest(
          slug: 's',
          name: 'n',
          description: 'd',
          icon: 'i',
          color: 'c',
        ).toJson(),
        {'slug': 's', 'name': 'n', 'description': 'd', 'icon': 'i', 'color': 'c'},
      );
    });

    test('KanbanBulkAction sealed 子类', () {
      const change = KanbanBulkActionChangeStatus('todo');
      const assign = KanbanBulkActionAssignProfile('work');
      const priority = KanbanBulkActionSetPriority(1);
      const archive = KanbanBulkActionArchiveCards();
      expect(change.status, 'todo');
      expect(assign.profile, 'work');
      expect(priority.priority, 1);
      expect(archive, const KanbanBulkActionArchiveCards());
      expect(change, isNot(archive));
    });
  });

  test('== / hashCode / toString', () {
    final a = KanbanCard.fromJson({'id': 'c1', 'title': 't'});
    final b = KanbanCard.fromJson({'id': 'c1', 'title': 't'});
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a.toString(), contains('KanbanCard'));
  });
}
