import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermex_flutter/core/api/api_client.dart';
import 'package:hermex_flutter/core/connections/connection_providers.dart';
import 'package:hermex_flutter/core/models/session.dart';
import 'package:hermex_flutter/features/session_list/session_list_providers.dart';
import 'package:hermex_flutter/features/settings/cron_visibility_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('buildSessionSections 定时融流与过滤逻辑', () {
    test('showCron = false（默认）：cron 会话被过滤，不进入任何分区', () {
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

      expect(sections.map((s) => s.title).toList(), ['今天']);
      expect(sections.single.sessions.map((s) => s.sessionId).toList(), ['s_today']);
    });

    test('showCron = false：通过 sessionSource/sourceTag/rawSource/sourceLabel 标记的 cron 会话均被过滤', () {
      final now = DateTime(2026, 8, 20, 12);
      final s1 = _buildSession('c1', 'Source=cron', at: now, sessionSource: 'cron');
      final s2 = _buildSession('c2', 'SourceTag=cron', at: now, sourceTag: 'cron');
      final s3 = _buildSession('c3', 'RawSource=cron', at: now, rawSource: 'cron');
      final s4 = _buildSession('c4', 'SourceLabel=cron', at: now, sourceLabel: 'cron');
      final normal = _buildSession('normal_1', '普通会话', at: now);

      final sections = buildSessionSections([s1, s2, s3, s4, normal], now: now);

      expect(sections.map((s) => s.title).toList(), ['今天']);
      expect(sections.single.sessions.map((s) => s.sessionId).toList(), ['normal_1']);
    });

    test('showCron = true：cron 会话融流进时间分区，不再产生「定时」独立分区', () {
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
      ], showCron: true, now: now);

      expect(sections.map((s) => s.title).toList(), ['置顶', '今天', '昨天', '更早']);
      expect(sections[0].sessions.map((s) => s.sessionId).toList(), ['p1']);
      // 今天包含 cron 与 t1，按时间倒序
      expect(sections[1].sessions.map((s) => s.sessionId).toList(), ['cron_1', 't1']);
      expect(sections[2].sessions.map((s) => s.sessionId).toList(), ['y1']);
      expect(sections[3].sessions.map((s) => s.sessionId).toList(), ['e1']);
    });

    test('showCron = true：cron + pinned 会话仍按时间归入时间分区，不进「置顶」分区', () {
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

      final sections = buildSessionSections([cronPinned, normalPinned], showCron: true, now: now);

      expect(sections.map((s) => s.title).toList(), ['置顶', '今天']);
      expect(sections[0].sessions.map((s) => s.sessionId).toList(), ['normal_pinned_1']);
      expect(sections[1].sessions.map((s) => s.sessionId).toList(), ['cron_pinned_1']);
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
    test('普通模式默认不包含 cron 会话，开启 showCron 后融流包含', () async {
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

      // 默认 showCron 为 false
      var sections = container.read(sessionListSectionsProvider);
      expect(sections.map((s) => s.title).toList(), ['今天']);
      expect(sections.single.sessions.map((s) => s.sessionId).toList(), ['s1']);

      // 打开 showCron
      await container.read(cronVisibilityProvider.notifier).setShowCron(true);

      sections = container.read(sessionListSectionsProvider);
      expect(sections.map((s) => s.title).toList(), ['今天']);
      expect(sections.single.sessions.map((s) => s.sessionId).toSet(), {'cron_1', 's1'});
    });

    test('搜索模式派生单一「搜索结果」分区（包含命中结果，不拆分为时间分区）', () async {
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
