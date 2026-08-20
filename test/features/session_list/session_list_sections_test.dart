import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermex_flutter/core/api/api_client.dart';
import 'package:hermex_flutter/core/connections/connection_providers.dart';
import 'package:hermex_flutter/core/models/session.dart';
import 'package:hermex_flutter/features/session_list/session_list_providers.dart';

import '../../helpers/fake_session_list_api.dart';

double _sec(DateTime d) => d.millisecondsSinceEpoch / 1000;

SessionSummary _buildSession(
  String id,
  String title, {
  bool pinned = false,
  DateTime? at,
  String? sessionSource,
  String? sourceTag,
  String? rawSource,
  String? sourceLabel,
  double? createdAt,
  double? updatedAt,
}) {
  return SessionSummary(
    sessionId: id,
    title: title,
    pinned: pinned,
    lastMessageAt: at != null ? _sec(at) : null,
    createdAt: createdAt,
    updatedAt: updatedAt,
    sessionSource: sessionSource,
    sourceTag: sourceTag,
    rawSource: rawSource,
    sourceLabel: sourceLabel,
  );
}

void main() {
  group('buildSessionSections 定时分区', () {
    test('cron 会话进「定时」区且不进时间分区（sessionId 以 cron_ 开头）', () {
      final now = DateTime(2026, 8, 20, 12);
      final cronSession = _buildSession(
        'cron_job_1',
        '定时巡检任务',
        at: now.subtract(const Duration(hours: 1)),
      );
      final todaySession = _buildSession(
        's_today',
        '普通今天会话',
        at: now.subtract(const Duration(hours: 2)),
      );

      final sections = buildSessionSections([cronSession, todaySession], now: now);

      expect(sections.map((s) => s.title).toList(), ['定时', '今天']);
      expect(sections[0].sessions.map((s) => s.sessionId).toList(), ['cron_job_1']);
      expect(sections[1].sessions.map((s) => s.sessionId).toList(), ['s_today']);
    });

    test('通过 sessionSource/sourceTag/rawSource/sourceLabel 标记的 cron 会话均归入「定时」区', () {
      final now = DateTime(2026, 8, 20, 12);
      final s1 = _buildSession('c1', 'Source=cron', at: now, sessionSource: 'cron');
      final s2 = _buildSession('c2', 'SourceTag=cron', at: now, sourceTag: 'cron');
      final s3 = _buildSession('c3', 'RawSource=cron', at: now, rawSource: 'cron');
      final s4 = _buildSession('c4', 'SourceLabel=cron', at: now, sourceLabel: 'cron');
      final normal = _buildSession('normal_1', '普通会话', at: now);

      final sections = buildSessionSections([s1, s2, s3, s4, normal], now: now);

      expect(sections.map((s) => s.title).toList(), ['定时', '今天']);
      expect(
        sections[0].sessions.map((s) => s.sessionId).toSet(),
        {'c1', 'c2', 'c3', 'c4'},
      );
      expect(sections[1].sessions.map((s) => s.sessionId).toList(), ['normal_1']);
    });

    test('定时区排在置顶之前，分区顺序为 [定时, 置顶, 今天, 昨天, 更早]', () {
      final now = DateTime(2026, 8, 20, 12);
      final cron = _buildSession('cron_1', '定时会话', at: now);
      final pinned = _buildSession('p1', '置顶会话', pinned: true, at: now);
      final today = _buildSession(
        't1',
        '今天会话',
        at: now.subtract(const Duration(hours: 1)),
      );
      final yesterday = _buildSession(
        'y1',
        '昨天会话',
        at: now.subtract(const Duration(days: 1)),
      );
      final earlier = _buildSession(
        'e1',
        '更早会话',
        at: now.subtract(const Duration(days: 5)),
      );

      final sections = buildSessionSections([
        earlier,
        yesterday,
        today,
        pinned,
        cron,
      ], now: now);

      expect(sections.map((s) => s.title).toList(), ['定时', '置顶', '今天', '昨天', '更早']);
      expect(sections[0].sessions.map((s) => s.sessionId).toList(), ['cron_1']);
      expect(sections[1].sessions.map((s) => s.sessionId).toList(), ['p1']);
      expect(sections[2].sessions.map((s) => s.sessionId).toList(), ['t1']);
      expect(sections[3].sessions.map((s) => s.sessionId).toList(), ['y1']);
      expect(sections[4].sessions.map((s) => s.sessionId).toList(), ['e1']);
    });

    test('无定时会话时，空定时区不出现（空组剔除）', () {
      final now = DateTime(2026, 8, 20, 12);
      final pinned = _buildSession('p1', '置顶会话', pinned: true, at: now);
      final today = _buildSession('t1', '今天会话', at: now);

      final sections = buildSessionSections([pinned, today], now: now);

      expect(sections.map((s) => s.title).toList(), ['置顶', '今天']);
    });

    test('cron + pinned 会话仍进「定时」区而非「置顶」区（置顶互斥决策）', () {
      final now = DateTime(2026, 8, 20, 12);
      final cronPinned = _buildSession(
        'cron_pinned_1',
        '定时且置顶会话',
        pinned: true,
        at: now,
      );
      final normalPinned = _buildSession(
        'normal_pinned_1',
        '普通置顶会话',
        pinned: true,
        at: now,
      );

      final sections = buildSessionSections([cronPinned, normalPinned], now: now);

      expect(sections.map((s) => s.title).toList(), ['定时', '置顶']);
      expect(sections[0].sessions.map((s) => s.sessionId).toList(), ['cron_pinned_1']);
      expect(sections[1].sessions.map((s) => s.sessionId).toList(), ['normal_pinned_1']);
    });

    test('定时区内多个会话按时间倒序排列', () {
      final now = DateTime(2026, 8, 20, 12);
      final cronNewer = _buildSession(
        'cron_new',
        '较新定时任务',
        at: now.subtract(const Duration(minutes: 10)),
      );
      final cronOlder = _buildSession(
        'cron_old',
        '较旧定时任务',
        at: now.subtract(const Duration(hours: 3)),
      );
      final cronFallback = _buildSession(
        'cron_fallback',
        '无 lastMessageAt 回退 updatedAt',
        updatedAt: _sec(now.subtract(const Duration(minutes: 30))),
      );

      final sections = buildSessionSections([
        cronOlder,
        cronNewer,
        cronFallback,
      ], now: now);

      expect(sections.single.title, '定时');
      // 时间顺序：cronNewer (10m ago) > cronFallback (30m ago) > cronOlder (3h ago)
      expect(
        sections.single.sessions.map((s) => s.sessionId).toList(),
        ['cron_new', 'cron_fallback', 'cron_old'],
      );
    });

    test('非 cron 会话分组与现有行为完全一致', () {
      final now = DateTime(2026, 8, 16, 12);
      final pinned = _buildSession('p1', '置顶会话', pinned: true, at: now);
      final today = _buildSession(
        't1',
        '今天会话',
        at: now.subtract(const Duration(hours: 1)),
      );
      final yesterday = _buildSession(
        'y1',
        '昨天会话',
        at: now.subtract(const Duration(days: 1)),
      );
      final earlier = _buildSession(
        'e1',
        '更早会话',
        at: now.subtract(const Duration(days: 10)),
      );
      final noTimestamp = _buildSession(
        'n1',
        '无时间戳',
        at: DateTime.fromMillisecondsSinceEpoch(0),
      );

      final sections = buildSessionSections([
        noTimestamp,
        earlier,
        yesterday,
        today,
        pinned,
      ], now: now);

      expect(sections.map((s) => s.title).toList(), ['置顶', '今天', '昨天', '更早']);
      expect(sections[0].sessions.map((s) => s.sessionId).toList(), ['p1']);
      expect(sections[1].sessions.map((s) => s.sessionId).toList(), ['t1']);
      expect(sections[2].sessions.map((s) => s.sessionId).toList(), ['y1']);
      expect(sections[3].sessions.map((s) => s.sessionId).toList(), ['e1', 'n1']);
    });

    test('全空输入 → 无分区', () {
      expect(
        buildSessionSections(const [], now: DateTime(2026, 1, 1)),
        isEmpty,
      );
    });
  });

  group('sessionListSectionsProvider 派生状态', () {
    test('普通模式派生含定时分区的结构', () async {
      final now = DateTime.now();
      final cron = _buildSession('cron_1', '定时会话', at: now);
      final normal = _buildSession('s1', '普通会话', at: now);
      final api = FakeSessionListApi(sessions: [cron, normal]);

      final container = ProviderContainer(
        overrides: [
          apiClientProvider.overrideWithValue(
            ApiClient(baseUrl: 'http://test.local:30002'),
          ),
          sessionListApiFactoryProvider.overrideWithValue((_) => api),
        ],
      );
      addTearDown(container.dispose);

      await container.read(sessionListControllerProvider.future);
      final sections = container.read(sessionListSectionsProvider);

      expect(sections.map((s) => s.title).toList(), ['定时', '今天']);
      expect(sections[0].sessions.map((s) => s.sessionId).toList(), ['cron_1']);
      expect(sections[1].sessions.map((s) => s.sessionId).toList(), ['s1']);
    });

    test('搜索模式派生单一「搜索结果」分区（包含命中结果，不拆分为定时/时间分区）', () async {
      final cronHit = _buildSession('cron_hit', '定时备份任务');
      final normalHit = _buildSession('s_hit', '普通备份任务');
      final api = FakeSessionListApi(sessions: [cronHit, normalHit]);
      api.searchResults['备份'] = [cronHit, normalHit];

      final container = ProviderContainer(
        overrides: [
          apiClientProvider.overrideWithValue(
            ApiClient(baseUrl: 'http://test.local:30002'),
          ),
          sessionListApiFactoryProvider.overrideWithValue((_) => api),
        ],
      );
      addTearDown(container.dispose);

      await container.read(sessionListControllerProvider.future);
      await container.read(sessionListControllerProvider.notifier).search('备份');

      final sections = container.read(sessionListSectionsProvider);

      expect(sections, hasLength(1));
      expect(sections.first.title, '搜索结果');
      expect(
        sections.first.sessions.map((s) => s.sessionId).toList(),
        ['cron_hit', 's_hit'],
      );
    });
  });
}
