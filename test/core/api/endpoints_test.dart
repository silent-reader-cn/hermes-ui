import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/api/endpoints.dart';

void main() {
  const base = 'http://hermes.local:8787';

  group('端点表完整性（api_spec.md 第 1 节，125 个）', () {
    test('全部端点按域分组无遗漏', () {
      // 1.1 server — 4
      final server = <Endpoint>[
        Endpoint.health,
        Endpoint.authStatus,
        Endpoint.login,
        Endpoint.logout,
      ];
      // 1.2 sessions — 18
      final sessions = <Endpoint>[
        Endpoint.sessions(),
        Endpoint.sessionsSearch(query: 'q', content: true, depth: 5),
        Endpoint.session(sessionId: 's1', includeMessages: true),
        Endpoint.sessionStatus('s1'),
        Endpoint.newSession,
        Endpoint.renameSession,
        Endpoint.deleteSession,
        Endpoint.pinSession,
        Endpoint.archiveSession,
        Endpoint.branchSession,
        Endpoint.compressSession,
        Endpoint.undoSession,
        Endpoint.retrySession,
        Endpoint.truncateSession,
        Endpoint.updateSession,
        Endpoint.moveSession,
        Endpoint.sessionYolo(),
        Endpoint.exportSession(sessionId: 's1', format: 'html'),
      ];
      // 1.3 projects — 4
      final projects = <Endpoint>[
        Endpoint.projects,
        Endpoint.createProject,
        Endpoint.renameProject,
        Endpoint.deleteProject,
      ];
      // 1.4 chat — 9
      final chat = <Endpoint>[
        Endpoint.chatStart,
        Endpoint.chatStream('st1'),
        Endpoint.chatCancel('st1'),
        Endpoint.chatStreamStatus('st1'),
        Endpoint.chatSteer,
        Endpoint.submitGoal,
        Endpoint.btw,
        Endpoint.background,
        Endpoint.backgroundStatus('s1'),
      ];
      // 1.5 approval — 3
      final approval = <Endpoint>[
        Endpoint.approvalPending('s1'),
        Endpoint.approvalStream('s1'),
        Endpoint.approvalRespond,
      ];
      // 1.6 clarify — 3
      final clarify = <Endpoint>[
        Endpoint.clarifyPending('s1'),
        Endpoint.clarifyStream('s1'),
        Endpoint.clarifyRespond,
      ];
      // 1.7 workspace — 12
      final workspace = <Endpoint>[
        Endpoint.workspaces,
        Endpoint.workspaceSuggestions('pre'),
        Endpoint.workspaceAdd,
        Endpoint.workspaceRemove,
        Endpoint.workspaceRename,
        Endpoint.workspaceReorder,
        Endpoint.fileDelete,
        Endpoint.fileRename,
        Endpoint.directoryList(sessionId: 's1'),
        Endpoint.file(sessionId: 's1', path: 'a.txt'),
        Endpoint.rawFile(sessionId: 's1', path: 'a.txt'),
        Endpoint.media(sessionId: 's1', path: 'a.png'),
      ];
      // 1.8 git — 16
      final git = <Endpoint>[
        Endpoint.gitInfo('s1'),
        Endpoint.gitStatus('s1'),
        Endpoint.gitBranches('s1'),
        Endpoint.gitDiff(sessionId: 's1', path: 'x'),
        Endpoint.gitFetch,
        Endpoint.gitPull,
        Endpoint.gitPush,
        Endpoint.gitCheckout,
        Endpoint.gitStashCheckout,
        Endpoint.gitStage,
        Endpoint.gitUnstage,
        Endpoint.gitDiscard,
        Endpoint.gitCommit,
        Endpoint.gitCommitSelected,
        Endpoint.gitCommitMessage,
        Endpoint.gitCommitMessageSelected,
      ];
      // 1.9 models — 9
      final models = <Endpoint>[
        Endpoint.models,
        Endpoint.modelsLive,
        Endpoint.commands,
        Endpoint.defaultModel,
        Endpoint.reasoning(),
        Endpoint.providers,
        Endpoint.settings,
        Endpoint.updatesCheck,
        Endpoint.updatesApply,
      ];
      // 1.10 profiles — 5
      final profiles = <Endpoint>[
        Endpoint.personalities,
        Endpoint.setPersonality,
        Endpoint.profiles,
        Endpoint.switchProfile,
        Endpoint.createProfile,
      ];
      // 1.11 insights — 1
      final insights = <Endpoint>[Endpoint.insights(7)];
      // 1.12 cron — 10
      final cron = <Endpoint>[
        Endpoint.crons,
        Endpoint.cronCreate,
        Endpoint.cronUpdate,
        Endpoint.cronDelete,
        Endpoint.cronRun,
        Endpoint.cronPause,
        Endpoint.cronResume,
        Endpoint.cronStatus(),
        Endpoint.cronOutput(jobId: 'j1'),
        Endpoint.cronDeliveryOptions,
      ];
      // 1.13 kanban — 23
      final kanban = <Endpoint>[
        Endpoint.kanbanConfig,
        Endpoint.kanbanBoards,
        Endpoint.kanbanCreateBoard,
        Endpoint.kanbanEditBoard('slug'),
        Endpoint.kanbanArchiveBoard('slug'),
        Endpoint.kanbanMakeBoardActive('slug'),
        Endpoint.kanbanDispatch(board: 'b', dryRun: false),
        Endpoint.kanbanBoard(board: 'b'),
        Endpoint.kanbanStats('b'),
        Endpoint.kanbanAssignees('b'),
        Endpoint.kanbanEvents(board: 'b', since: 0),
        Endpoint.kanbanEventsStream(board: 'b', since: 0),
        Endpoint.kanbanCardDetail(board: 'b', cardId: 'c1'),
        Endpoint.kanbanWorkerLog(board: 'b', cardId: 'c1'),
        Endpoint.kanbanAddComment(board: 'b', cardId: 'c1'),
        Endpoint.kanbanCreateCard('b'),
        Endpoint.kanbanBulkAction('b'),
        Endpoint.kanbanEditCard(board: 'b', cardId: 'c1'),
        Endpoint.kanbanCardStatus(board: 'b', cardId: 'c1'),
        Endpoint.kanbanBlockCard(board: 'b', cardId: 'c1'),
        Endpoint.kanbanUnblockCard(board: 'b', cardId: 'c1'),
        Endpoint.kanbanAddDependency('b'),
        Endpoint.kanbanRemoveDependency('b'),
      ];
      // 1.14 memory — 2
      final memory = <Endpoint>[Endpoint.memory, Endpoint.memoryWrite];
      // 1.15 skills — 3
      final skills = <Endpoint>[
        Endpoint.skills,
        Endpoint.skillContent(name: 'n'),
        Endpoint.toggleSkill,
      ];
      // 1.16 upload/transcribe/tts — 3
      final upload = <Endpoint>[
        Endpoint.upload,
        Endpoint.transcribe,
        Endpoint.tts,
      ];

      expect(server, hasLength(4));
      expect(sessions, hasLength(18));
      expect(projects, hasLength(4));
      expect(chat, hasLength(9));
      expect(approval, hasLength(3));
      expect(clarify, hasLength(3));
      expect(workspace, hasLength(12));
      expect(git, hasLength(16));
      expect(models, hasLength(9));
      expect(profiles, hasLength(5));
      expect(insights, hasLength(1));
      expect(cron, hasLength(10));
      expect(kanban, hasLength(23));
      expect(memory, hasLength(2));
      expect(skills, hasLength(3));
      expect(upload, hasLength(3));

      final all = [
        ...server,
        ...sessions,
        ...projects,
        ...chat,
        ...approval,
        ...clarify,
        ...workspace,
        ...git,
        ...models,
        ...profiles,
        ...insights,
        ...cron,
        ...kanban,
        ...memory,
        ...skills,
        ...upload,
      ];
      expect(all, hasLength(125), reason: '端点总数必须为 125');
    });

    test('静态端点路径与规格逐项一致', () {
      const expectations = <String, String>{
        // 1.1
        '/health': '/health',
        '/api/auth/status': '/api/auth/status',
        '/api/auth/login': '/api/auth/login',
        '/api/auth/logout': '/api/auth/logout',
        // 1.2
        '/api/sessions': '/api/sessions',
        '/api/session/new': '/api/session/new',
        '/api/session/rename': '/api/session/rename',
        '/api/session/delete': '/api/session/delete',
        '/api/session/pin': '/api/session/pin',
        '/api/session/archive': '/api/session/archive',
        '/api/session/branch': '/api/session/branch',
        '/api/session/compress': '/api/session/compress',
        '/api/session/undo': '/api/session/undo',
        '/api/session/retry': '/api/session/retry',
        '/api/session/truncate': '/api/session/truncate',
        '/api/session/update': '/api/session/update',
        '/api/session/move': '/api/session/move',
        // 1.3
        '/api/projects': '/api/projects',
        '/api/projects/create': '/api/projects/create',
        '/api/projects/rename': '/api/projects/rename',
        '/api/projects/delete': '/api/projects/delete',
        // 1.4
        '/api/chat/start': '/api/chat/start',
        '/api/chat/steer': '/api/chat/steer',
        '/api/goal': '/api/goal',
        '/api/btw': '/api/btw',
        '/api/background': '/api/background',
        // 1.5 / 1.6
        '/api/approval/respond': '/api/approval/respond',
        '/api/clarify/respond': '/api/clarify/respond',
        // 1.7
        '/api/workspaces': '/api/workspaces',
        '/api/workspaces/add': '/api/workspaces/add',
        '/api/workspaces/remove': '/api/workspaces/remove',
        '/api/workspaces/rename': '/api/workspaces/rename',
        '/api/workspaces/reorder': '/api/workspaces/reorder',
        // 1.8
        '/api/git/fetch': '/api/git/fetch',
        '/api/git/pull': '/api/git/pull',
        '/api/git/push': '/api/git/push',
        '/api/git/checkout': '/api/git/checkout',
        '/api/git/stash-checkout': '/api/git/stash-checkout',
        '/api/git/stage': '/api/git/stage',
        '/api/git/unstage': '/api/git/unstage',
        '/api/git/discard': '/api/git/discard',
        '/api/git/commit': '/api/git/commit',
        '/api/git/commit-selected': '/api/git/commit-selected',
        '/api/git/commit-message': '/api/git/commit-message',
        '/api/git/commit-message-selected': '/api/git/commit-message-selected',
        // 1.9
        '/api/models': '/api/models',
        '/api/models/live': '/api/models/live',
        '/api/commands': '/api/commands',
        '/api/default-model': '/api/default-model',
        '/api/providers': '/api/providers',
        '/api/settings': '/api/settings',
        '/api/updates/check': '/api/updates/check',
        '/api/updates/apply': '/api/updates/apply',
        // 1.10
        '/api/personalities': '/api/personalities',
        '/api/personality/set': '/api/personality/set',
        '/api/profiles': '/api/profiles',
        '/api/profile/switch': '/api/profile/switch',
        '/api/profile/create': '/api/profile/create',
        // 1.12
        '/api/crons': '/api/crons',
        '/api/crons/create': '/api/crons/create',
        '/api/crons/update': '/api/crons/update',
        '/api/crons/delete': '/api/crons/delete',
        '/api/crons/run': '/api/crons/run',
        '/api/crons/pause': '/api/crons/pause',
        '/api/crons/resume': '/api/crons/resume',
        '/api/crons/delivery-options': '/api/crons/delivery-options',
        // 1.13
        '/api/kanban/config': '/api/kanban/config',
        '/api/kanban/boards': '/api/kanban/boards',
        // 1.14
        '/api/memory': '/api/memory',
        '/api/memory/write': '/api/memory/write',
        // 1.15
        '/api/skills': '/api/skills',
        '/api/skills/toggle': '/api/skills/toggle',
        // 1.16
        '/api/upload': '/api/upload',
        '/api/transcribe': '/api/transcribe',
        '/api/tts': '/api/tts',
      };
      final endpointsByPath = <String, Endpoint>{
        for (final e in _staticEndpoints()) e.path: e,
      };
      for (final entry in expectations.entries) {
        expect(
          endpointsByPath[entry.key]?.path,
          entry.value,
          reason: '缺少静态端点 ${entry.key}',
        );
      }
    });
  });

  group('端点 URL 拼装', () {
    test('baseUrl 不带尾斜杠直接拼接，query 正确编码', () {
      expect(Endpoint.health.url(base).toString(), '$base/health');
      expect(
        Endpoint.sessionsSearch(
          query: 'hello world',
          content: true,
          depth: 3,
        ).url(base).toString(),
        '$base/api/sessions/search?q=hello%20world&content=1&depth=3',
      );
      // 尾斜杠容忍
      expect(Endpoint.health.url('$base/').toString(), '$base/health');
    });

    test('sessions：include_archived 为 opt-in，archived_limit 仅随其发送，始终带 sidebar_source=webui', () {
      expect(
        Endpoint.sessions().url(base).toString(),
        '$base/api/sessions?sidebar_source=webui',
      );
      expect(
        Endpoint.sessions(includeArchived: true).url(base).toString(),
        '$base/api/sessions?include_archived=1&sidebar_source=webui',
      );
      expect(
        Endpoint.sessions(
          includeArchived: true,
          archivedLimit: 10,
        ).url(base).toString(),
        '$base/api/sessions?include_archived=1&archived_limit=10&sidebar_source=webui',
      );
      // archivedLimit 单独发送时必须带 include_archived
      expect(
        Endpoint.sessions(
          includeArchived: false,
          archivedLimit: 10,
        ).url(base).toString(),
        '$base/api/sessions?archived_limit=10&sidebar_source=webui',
      );
    });

    test('session：messages/msg_limit/msg_before/expand_renderable', () {
      expect(
        Endpoint.session(
          sessionId: 's1',
          includeMessages: false,
        ).url(base).toString(),
        '$base/api/session?session_id=s1&messages=0',
      );
      expect(
        Endpoint.session(
          sessionId: 's1',
          includeMessages: true,
          messageLimit: 50,
          messageBefore: 100,
          expandRenderable: true,
        ).url(base).toString(),
        '$base/api/session?session_id=s1&messages=1&msg_limit=50&msg_before=100&expand_renderable=1',
      );
    });

    test('chatStream：stream_id query + 重放参数', () {
      expect(
        Endpoint.chatStream('st1').url(base).toString(),
        '$base/api/chat/stream?stream_id=st1',
      );
      expect(
        Endpoint.chatStreamReplay('st1', 42).url(base).toString(),
        '$base/api/chat/stream?stream_id=st1&replay=1&after_seq=42',
      );
      // after_seq 负数 → 0
      expect(
        Endpoint.chatStreamReplay('st1', -3).url(base).toString(),
        '$base/api/chat/stream?stream_id=st1&replay=1&after_seq=0',
      );
    });

    test('chatCancel 是 GET 路径（方法由 ApiClient 决定，路径必须正确）', () {
      expect(
        Endpoint.chatCancel('st1').url(base).toString(),
        '$base/api/chat/cancel?stream_id=st1',
      );
    });

    test('sessionYolo：GET 带 session_id，POST 无 query（同一路径）', () {
      expect(
        Endpoint.sessionYolo().url(base).toString(),
        '$base/api/session/yolo',
      );
      expect(
        Endpoint.sessionYolo('s1').url(base).toString(),
        '$base/api/session/yolo?session_id=s1',
      );
    });

    test('reasoning：model/provider 非空才发', () {
      expect(Endpoint.reasoning().url(base).toString(), '$base/api/reasoning');
      expect(
        Endpoint.reasoning(
          model: 'gpt-4',
          provider: 'openai',
        ).url(base).toString(),
        '$base/api/reasoning?model=gpt-4&provider=openai',
      );
      expect(
        Endpoint.reasoning(model: '', provider: '').url(base).toString(),
        '$base/api/reasoning',
      );
      expect(
        Endpoint.reasoning(model: 'claude', provider: '').url(base).toString(),
        '$base/api/reasoning?model=claude',
      );
    });

    test('gitDiff / cronOutput / skillContent / insights / exportSession', () {
      expect(
        Endpoint.gitDiff(
          sessionId: 's1',
          path: 'a b.txt',
          kind: 'staged',
        ).url(base).toString(),
        '$base/api/git/diff?session_id=s1&path=a%20b.txt&kind=staged',
      );
      expect(
        Endpoint.cronOutput(jobId: 'j1', limit: 3).url(base).toString(),
        '$base/api/crons/output?job_id=j1&limit=3',
      );
      expect(
        Endpoint.cronStatus('j1').url(base).toString(),
        '$base/api/crons/status?job_id=j1',
      );
      expect(
        Endpoint.cronStatus().url(base).toString(),
        '$base/api/crons/status',
      );
      expect(
        Endpoint.skillContent(
          name: 'web',
          file: 'SKILL.md',
        ).url(base).toString(),
        '$base/api/skills/content?name=web&file=SKILL.md',
      );
      expect(
        Endpoint.insights(7).url(base).toString(),
        '$base/api/insights?days=7',
      );
      expect(
        Endpoint.exportSession(
          sessionId: 's1',
          format: 'json',
        ).url(base).toString(),
        '$base/api/session/export?session_id=s1&format=json',
      );
    });

    test('kanban 除路径段外都带 board query', () {
      expect(
        Endpoint.kanbanStats('b1').url(base).toString(),
        '$base/api/kanban/stats?board=b1',
      );
      expect(
        Endpoint.kanbanCardDetail(
          board: 'b1',
          cardId: 'c1',
        ).url(base).toString(),
        '$base/api/kanban/tasks/c1?board=b1',
      );
      expect(
        Endpoint.kanbanCreateCard('b1').url(base).toString(),
        '$base/api/kanban/tasks?board=b1',
      );
      expect(
        Endpoint.kanbanBulkAction('b1').url(base).toString(),
        '$base/api/kanban/tasks/bulk?board=b1',
      );
      expect(
        Endpoint.kanbanAddDependency('b1').url(base).toString(),
        '$base/api/kanban/links?board=b1',
      );
    });

    test('kanbanDispatch：board + dry_run + max=8 固定', () {
      expect(
        Endpoint.kanbanDispatch(board: 'b1', dryRun: true).url(base).toString(),
        '$base/api/kanban/dispatch?board=b1&dry_run=true&max=8',
      );
      expect(
        Endpoint.kanbanDispatch(
          board: 'b1',
          dryRun: false,
        ).url(base).toString(),
        '$base/api/kanban/dispatch?board=b1&dry_run=false&max=8',
      );
    });

    test('kanbanEvents：since max(0)，limit clamp 1–200 默认 200', () {
      expect(
        Endpoint.kanbanEvents(board: 'b1', since: 0).url(base).toString(),
        '$base/api/kanban/events?board=b1&since=0&limit=200',
      );
      expect(
        Endpoint.kanbanEvents(
          board: 'b1',
          since: -5,
          limit: 999,
        ).url(base).toString(),
        '$base/api/kanban/events?board=b1&since=0&limit=200',
      );
      expect(
        Endpoint.kanbanEvents(
          board: 'b1',
          since: 7,
          limit: 0,
        ).url(base).toString(),
        '$base/api/kanban/events?board=b1&since=7&limit=1',
      );
    });

    test('kanbanWorkerLog：tail 默认 65536，clamp 1–2_000_000', () {
      expect(
        Endpoint.kanbanWorkerLog(
          board: 'b1',
          cardId: 'c1',
        ).url(base).toString(),
        '$base/api/kanban/tasks/c1/log?board=b1&tail=65536',
      );
      expect(
        Endpoint.kanbanWorkerLog(
          board: 'b1',
          cardId: 'c1',
          tail: 99999999,
        ).url(base).toString(),
        '$base/api/kanban/tasks/c1/log?board=b1&tail=2000000',
      );
      expect(
        Endpoint.kanbanWorkerLog(
          board: 'b1',
          cardId: 'c1',
          tail: 0,
        ).url(base).toString(),
        '$base/api/kanban/tasks/c1/log?board=b1&tail=1',
      );
    });

    test('kanbanBoard：可选 query 齐全', () {
      expect(
        Endpoint.kanbanBoard(
          board: 'b1',
          tenant: 't',
          assignee: 'a',
          includeArchived: true,
          onlyMine: true,
          since: '123',
        ).url(base).toString(),
        '$base/api/kanban/board?board=b1&tenant=t&assignee=a&include_archived=true&only_mine=true&since=123',
      );
    });
  });

  group('kanban 路径段编码（RFC 3986 unreserved 减掉 `.`）', () {
    test('点号也被编码（防 . / .. 注入）', () {
      expect(Endpoint.encodePathSegment('a.b'), 'a%2Eb');
      expect(Endpoint.encodePathSegment('..'), '%2E%2E');
      expect(Endpoint.encodePathSegment('a.b/c'), 'a%2Eb%2Fc');
    });

    test('unreserved 字符（含 - _ ~）原样保留', () {
      expect(Endpoint.encodePathSegment('ABCabc123-_~'), 'ABCabc123-_~');
    });

    test('非 ASCII / 空格 / 特殊字符按 UTF-8 字节编码', () {
      expect(Endpoint.encodePathSegment('你好'), '%E4%BD%A0%E5%A5%BD');
      expect(Endpoint.encodePathSegment('a b'), 'a%20b');
      expect(Endpoint.encodePathSegment('a#b'), 'a%23b');
    });

    test('URL 拼装时路径段使用该编码（Dart Uri 归一化说明见 endpoints.dart url() 注释）', () {
      // Dart Uri.parse 会把 %2E 归一化解码为字面量 '.'，但 %2F/%20 等 reserved
      // 字符的编码原样保留 → 段完整性保持（cardId 里的 '/' 不会拆出新段）。
      final detail = Endpoint.kanbanCardDetail(
        board: 'b',
        cardId: 'a.b/c',
      ).url(base);
      expect(detail.path, '/api/kanban/tasks/a.b%2Fc');
      expect(detail.pathSegments, ['api', 'kanban', 'tasks', 'a.b/c']);
      expect(detail.toString(), '$base/api/kanban/tasks/a.b%2Fc?board=b');
      expect(Uri.decodeComponent(detail.pathSegments.last), 'a.b/c');

      expect(
        Endpoint.kanbanEditBoard('my.board').url(base).toString(),
        '$base/api/kanban/boards/my.board',
      );
      expect(
        Endpoint.kanbanMakeBoardActive('b.o.a.r.d').url(base).toString(),
        '$base/api/kanban/boards/b.o.a.r.d/switch',
      );
      final unblock = Endpoint.kanbanUnblockCard(
        board: 'b',
        cardId: 'c d',
      ).url(base);
      expect(unblock.path, '/api/kanban/tasks/c%20d/unblock');
      expect(Uri.decodeComponent(unblock.pathSegments[3]), 'c d');
    });

    test('服务端解码后还原原值（编码可逆）', () {
      const raw = 'a.b/你好 c';
      final encoded = Endpoint.encodePathSegment(raw);
      final decoded = Uri.decodeComponent(encoded);
      expect(decoded, raw);
    });
  });

  group('双方法端点同一路径', () {
    test(
      'sessionYolo / reasoning / settings / updatesCheck GET 与 POST 路径相同',
      () {
        expect(Endpoint.sessionYolo('s1').path, '/api/session/yolo');
        expect(Endpoint.reasoning(model: 'm').path, '/api/reasoning');
        expect(Endpoint.settings.path, '/api/settings');
        expect(Endpoint.updatesCheck.path, '/api/updates/check');
      },
    );
  });

  group('设置页三板块新增端点（1.17 / 1.18 / 1.19 — 13 个）', () {
    test('Extensions 端点（6 个）路径与 URL', () {
      expect(
        Endpoint.extensionsStatus.url(base).toString(),
        '$base/api/extensions/status',
      );
      expect(
        Endpoint.extensionsRegistry.url(base).toString(),
        '$base/api/extensions/registry',
      );
      expect(
        Endpoint.extensionToggle.url(base).toString(),
        '$base/api/extensions/toggle',
      );
      expect(
        Endpoint.extensionInstall.url(base).toString(),
        '$base/api/extensions/install',
      );
      expect(
        Endpoint.extensionUninstall.url(base).toString(),
        '$base/api/extensions/uninstall',
      );
      expect(
        Endpoint.extensionSidecarProxyConsent.url(base).toString(),
        '$base/api/extensions/sidecar-proxy-consent',
      );
    });

    test('MCP 端点（5 个）路径、URL 与路径段编码', () {
      expect(Endpoint.mcpServers.url(base).toString(), '$base/api/mcp/servers');
      expect(Endpoint.mcpTools.url(base).toString(), '$base/api/mcp/tools');
      expect(
        Endpoint.mcpServerUpdate('my-server').url(base).toString(),
        '$base/api/mcp/servers/my-server',
      );
      expect(
        Endpoint.mcpServerToggle('my-server').url(base).toString(),
        '$base/api/mcp/servers/my-server',
      );
      expect(
        Endpoint.mcpServerDelete('my-server').url(base).toString(),
        '$base/api/mcp/servers/my-server',
      );

      // 验证特殊字符/空格/斜杠编码
      expect(
        Endpoint.mcpServerUpdate('srv/1 2').url(base).toString(),
        '$base/api/mcp/servers/srv%2F1%202',
      );
      expect(
        Endpoint.mcpServerToggle('srv.name').url(base).toString(),
        '$base/api/mcp/servers/srv.name',
      );
      expect(
        Endpoint.mcpServerDelete('srv/delete').url(base).toString(),
        '$base/api/mcp/servers/srv%2Fdelete',
      );
    });

    test('辅助模型端点（2 个）路径与 URL', () {
      expect(
        Endpoint.auxiliaryModels.url(base).toString(),
        '$base/api/model/auxiliary',
      );
      expect(Endpoint.modelSet.url(base).toString(), '$base/api/model/set');
    });
  });
}

/// 全部静态（无参）端点，供路径完整性校验。
List<Endpoint> _staticEndpoints() {
  return [
    Endpoint.health,
    Endpoint.authStatus,
    Endpoint.login,
    Endpoint.logout,
    Endpoint.sessions(),
    Endpoint.newSession,
    Endpoint.renameSession,
    Endpoint.deleteSession,
    Endpoint.pinSession,
    Endpoint.archiveSession,
    Endpoint.branchSession,
    Endpoint.compressSession,
    Endpoint.undoSession,
    Endpoint.retrySession,
    Endpoint.truncateSession,
    Endpoint.updateSession,
    Endpoint.moveSession,
    Endpoint.projects,
    Endpoint.createProject,
    Endpoint.renameProject,
    Endpoint.deleteProject,
    Endpoint.chatStart,
    Endpoint.chatSteer,
    Endpoint.submitGoal,
    Endpoint.btw,
    Endpoint.background,
    Endpoint.approvalRespond,
    Endpoint.clarifyRespond,
    Endpoint.workspaces,
    Endpoint.workspaceAdd,
    Endpoint.workspaceRemove,
    Endpoint.workspaceRename,
    Endpoint.workspaceReorder,
    Endpoint.gitFetch,
    Endpoint.gitPull,
    Endpoint.gitPush,
    Endpoint.gitCheckout,
    Endpoint.gitStashCheckout,
    Endpoint.gitStage,
    Endpoint.gitUnstage,
    Endpoint.gitDiscard,
    Endpoint.gitCommit,
    Endpoint.gitCommitSelected,
    Endpoint.gitCommitMessage,
    Endpoint.gitCommitMessageSelected,
    Endpoint.models,
    Endpoint.modelsLive,
    Endpoint.commands,
    Endpoint.defaultModel,
    Endpoint.providers,
    Endpoint.settings,
    Endpoint.updatesCheck,
    Endpoint.updatesApply,
    Endpoint.personalities,
    Endpoint.setPersonality,
    Endpoint.profiles,
    Endpoint.switchProfile,
    Endpoint.createProfile,
    Endpoint.crons,
    Endpoint.cronCreate,
    Endpoint.cronUpdate,
    Endpoint.cronDelete,
    Endpoint.cronRun,
    Endpoint.cronPause,
    Endpoint.cronResume,
    Endpoint.cronDeliveryOptions,
    Endpoint.kanbanConfig,
    Endpoint.kanbanBoards,
    Endpoint.kanbanCreateBoard,
    Endpoint.memory,
    Endpoint.memoryWrite,
    Endpoint.skills,
    Endpoint.toggleSkill,
    Endpoint.upload,
    Endpoint.transcribe,
    Endpoint.tts,
  ];
}
