import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/models/session.dart';
import 'package:hermes_ui/features/session_list/session_list_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_session_list_api.dart';

SessionSummary _session(
  String id,
  String title, {
  bool subagent = false,
  bool archived = false,
  String? sourceLabel,
  String? projectId,
}) {
  return SessionSummary(
    sessionId: id,
    title: title,
    archived: archived,
    sourceLabel: sourceLabel,
    projectId: projectId,
    sourceTag: subagent ? 'subagent' : null,
    rawSource: subagent ? 'subagent' : null,
    createdAt: DateTime.now().millisecondsSinceEpoch / 1000,
  );
}

/// 让非阻塞偏好回填的微任务/事件循环全部执行完（ProviderContainer 无 pump）。
Future<void> _flushMicrotasks() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('SessionListState.displaySessions subagent 全局过滤', () {
    test('默认 showSubagent=false：全部模式隐藏 subagent 会话', () {
      final state = SessionListState(
        sessions: [
          _session('s1', '普通会话'),
          _session('sub1', '子代理会话', subagent: true),
        ],
        visibleCount: 50,
      );
      expect(state.displaySessions.map((s) => s.sessionId).toList(), ['s1']);
    });

    test('showSubagent=true：subagent 会话恢复显示', () {
      final state = SessionListState(
        sessions: [
          _session('s1', '普通会话'),
          _session('sub1', '子代理会话', subagent: true),
        ],
        visibleCount: 50,
      ).copyWith(showSubagent: true);
      expect(state.displaySessions.map((s) => s.sessionId).toSet(), {
        's1',
        'sub1',
      });
    });

    test('归档模式同样隐藏 subagent 归档会话', () {
      final state = SessionListState(
        archivedSessions: [
          _session('a1', '普通归档', archived: true),
          _session('a2', '子代理归档', subagent: true, archived: true),
        ],
        filterMode: SessionListFilterMode.archived,
        visibleCount: 50,
      );
      expect(state.displaySessions.map((s) => s.sessionId).toList(), ['a1']);
    });

    test('来源筛选与项目筛选结果同样应用 subagent 过滤', () {
      final sourceState = SessionListState(
        sessions: [
          _session('s1', '普通电报', sourceLabel: 'telegram'),
          _session('sub1', '子代理电报', subagent: true, sourceLabel: 'telegram'),
        ],
        filterMode: SessionListFilterMode.source,
        filterValue: 'telegram',
        visibleCount: 50,
      );
      expect(sourceState.displaySessions.map((s) => s.sessionId).toList(), [
        's1',
      ]);

      final projectState = SessionListState(
        sessions: [
          _session('s1', '普通项目会话', projectId: 'p1'),
          _session('sub1', '子代理项目会话', subagent: true, projectId: 'p1'),
        ],
        filterMode: SessionListFilterMode.project,
        filterValue: 'p1',
        visibleCount: 50,
      );
      expect(projectState.displaySessions.map((s) => s.sessionId).toList(), [
        's1',
      ]);
    });

    test('搜索命中同样被过滤', () {
      final state = SessionListState(
        sessions: [
          _session('s1', '普通备份', sourceLabel: 'telegram'),
          _session('sub1', '子代理备份', subagent: true, sourceLabel: 'telegram'),
        ],
        searchQuery: '备份',
        searchResults: [
          _session('sub1', '子代理备份', subagent: true, sourceLabel: 'telegram'),
          _session('s1', '普通备份', sourceLabel: 'telegram'),
        ],
        visibleCount: 50,
      );
      expect(state.displaySessions.map((s) => s.sessionId).toList(), ['s1']);
    });

    test('sourceLabels：隐藏时剔除 Subagent，打开后恢复', () {
      final sessions = [
        _session('s1', '普通会话', sourceLabel: 'telegram'),
        _session('sub1', '子代理会话', subagent: true, sourceLabel: 'Subagent'),
      ];
      final hidden = SessionListState(sessions: sessions, visibleCount: 50);
      expect(hidden.sourceLabels, ['telegram']);

      final shown = SessionListState(
        sessions: sessions,
        visibleCount: 50,
      ).copyWith(showSubagent: true);
      expect(shown.sourceLabels.toSet(), {'telegram', 'Subagent'});
    });
  });

  group('SessionListController 开关与持久化', () {
    Future<ProviderContainer> buildContainer(FakeSessionListApi api) async {
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
      return container;
    }

    test('默认关闭：无 prefs 时 showSubagent 为 false', () async {
      final api = FakeSessionListApi(sessions: [_session('s1', '普通会话')]);
      final container = await buildContainer(api);
      expect(
        container.read(sessionListControllerProvider).valueOrNull!.showSubagent,
        isFalse,
      );
    });

    test('初始加载读取 prefs：预置 true → showSubagent 为 true', () async {
      SharedPreferences.setMockInitialValues({
        SessionListController.keyShowSubagent: true,
      });
      final api = FakeSessionListApi(
        sessions: [
          _session('s1', '普通会话'),
          _session('sub1', '子代理会话', subagent: true),
        ],
      );
      final container = await buildContainer(api);
      // build 不阻塞偏好读取：等非阻塞回填微任务执行完再断言。
      await _flushMicrotasks();
      final state = container.read(sessionListControllerProvider).valueOrNull!;
      expect(state.showSubagent, isTrue);
      // 列表视图同步放开 subagent
      expect(state.displaySessions.map((s) => s.sessionId).toSet(), {
        's1',
        'sub1',
      });
    });

    test('setShowSubagent：状态即时更新并持久化到 SharedPreferences', () async {
      final api = FakeSessionListApi(
        sessions: [
          _session('s1', '普通会话'),
          _session('sub1', '子代理会话', subagent: true),
        ],
      );
      final container = await buildContainer(api);

      await container
          .read(sessionListControllerProvider.notifier)
          .setShowSubagent(true);

      var state = container.read(sessionListControllerProvider).valueOrNull!;
      expect(state.showSubagent, isTrue);
      expect(state.displaySessions.map((s) => s.sessionId).toSet(), {
        's1',
        'sub1',
      });

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(SessionListController.keyShowSubagent), isTrue);

      // 再关回：状态与持久化同步回落
      await container
          .read(sessionListControllerProvider.notifier)
          .setShowSubagent(false);
      state = container.read(sessionListControllerProvider).valueOrNull!;
      expect(state.showSubagent, isFalse);
      expect(state.displaySessions.map((s) => s.sessionId).toList(), ['s1']);
      expect(prefs.getBool(SessionListController.keyShowSubagent), isFalse);
    });

    test('刷新保留用户已开启的开关状态', () async {
      final api = FakeSessionListApi(
        sessions: [
          _session('s1', '普通会话'),
          _session('sub1', '子代理会话', subagent: true),
        ],
      );
      final container = await buildContainer(api);
      final notifier = container.read(sessionListControllerProvider.notifier);

      await notifier.setShowSubagent(true);
      await notifier.refresh();

      final state = container.read(sessionListControllerProvider).valueOrNull!;
      expect(state.showSubagent, isTrue);
      expect(state.displaySessions.map((s) => s.sessionId).toSet(), {
        's1',
        'sub1',
      });
    });
  });
}
