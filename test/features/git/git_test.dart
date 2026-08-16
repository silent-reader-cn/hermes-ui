import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hermex_flutter/core/api/api_client.dart';
import 'package:hermex_flutter/core/api/api_exception.dart';
import 'package:hermex_flutter/core/connections/connection_providers.dart';
import 'package:hermex_flutter/core/models/git_workspace.dart';
import 'package:hermex_flutter/features/git/git_api.dart';
import 'package:hermex_flutter/features/git/git_page.dart';
import 'package:hermex_flutter/features/git/git_providers.dart';

import '../../helpers/fake_git_api.dart';

/// 带 3 个变更文件的仓库状态（1 暂存 + 2 未暂存/未跟踪）。
GitStatus sampleStatus() {
  return GitStatus(
    isGit: true,
    branch: 'main',
    upstream: 'origin/main',
    ahead: 1,
    behind: 0,
    totals: const GitTotals(changed: 3, staged: 1, unstaged: 2, untracked: 1),
    files: [
      GitFile(
        path: 'a.txt',
        status: 'M',
        staged: true,
        additions: 3,
        deletions: 1,
      ),
      GitFile(path: 'b.txt', status: 'M', unstaged: true, additions: 1),
      GitFile(path: 'c.txt', untracked: true),
    ],
  );
}

/// 组装 ProviderContainer：注入 fake API（apiClientProvider 用占位客户端，
/// 工厂 override 忽略它，不发任何网络请求）。
ProviderContainer makeContainer(FakeGitApi api) {
  final container = ProviderContainer(
    overrides: [
      apiClientProvider.overrideWithValue(
        ApiClient(baseUrl: 'http://test.local:30002'),
      ),
      gitApiFactoryProvider.overrideWithValue((_) => api),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('GitController 状态机', () {
    test('初始加载成功：status + 分支加载', () async {
      final api = FakeGitApi(status: sampleStatus());
      final container = makeContainer(api);

      final state = await container.read(gitControllerProvider('s1').future);
      expect(api.statusCount, 1);
      expect(api.branchesCount, 1);
      expect(state.status!.branch, 'main');
      expect(state.branches!.current, 'main');
      expect(state.isGitRepository, isTrue);
      expect(state.stagedFiles, hasLength(1));
      expect(state.unstagedFiles, hasLength(2));
      expect(state.stagedFiles.single.path, 'a.txt');
    });

    test('非 git 仓库：不请求分支', () async {
      final api = FakeGitApi(status: const GitStatus(isGit: false));
      final container = makeContainer(api);

      final state = await container.read(gitControllerProvider('s1').future);
      expect(state.isNonRepository, isTrue);
      expect(state.branches, isNull);
      expect(api.branchesCount, 0);
    });

    test('status 加载失败 → AsyncError；refresh 重试成功', () async {
      final api = FakeGitApi(status: sampleStatus());
      api.statusError = NetworkException(NetworkExceptionKind.cannotConnect);
      final container = makeContainer(api);

      await expectLater(
        container.read(gitControllerProvider('s1').future),
        throwsA(isA<ApiException>()),
      );
      expect(container.read(gitControllerProvider('s1')).hasError, isTrue);

      api.statusError = null;
      await container.read(gitControllerProvider('s1').notifier).refresh();
      final state = container.read(gitControllerProvider('s1')).valueOrNull!;
      expect(state.status!.branch, 'main');
      expect(api.statusCount, 2);
    });

    test('分支加载失败：主状态保留 + branchesError', () async {
      final api = FakeGitApi(status: sampleStatus());
      api.branchesError = NetworkException(NetworkExceptionKind.timedOut);
      final container = makeContainer(api);

      final state = await container.read(gitControllerProvider('s1').future);
      expect(state.status!.branch, 'main');
      expect(state.branches, isNull);
      expect(state.branchesError, isNotNull);
    });

    test('stage 成功：status 用响应更新', () async {
      final api = FakeGitApi(status: sampleStatus());
      // 响应返回「a.txt、b.txt 均已暂存」的新状态。
      api.mutationResponse = GitMutationResponse(
        ok: true,
        git: GitStatus(
          isGit: true,
          branch: 'main',
          totals: const GitTotals(changed: 3, staged: 2, unstaged: 1),
          files: [
            GitFile(
              path: 'a.txt',
              status: 'M',
              staged: true,
              additions: 3,
              deletions: 1,
            ),
            GitFile(path: 'b.txt', status: 'M', staged: true, additions: 1),
            GitFile(path: 'c.txt', untracked: true),
          ],
        ),
      );
      final container = makeContainer(api);
      await container.read(gitControllerProvider('s1').future);

      final ok = await container
          .read(gitControllerProvider('s1').notifier)
          .stage(['b.txt']);
      expect(ok, isTrue);
      expect(api.stageCalls, ['b.txt']);
      final state = container.read(gitControllerProvider('s1')).valueOrNull!;
      expect(state.stagedFiles, hasLength(2));
      expect(state.isActionRunning, isFalse);
      expect(state.actionError, isNull);
    });

    test('stage 失败 → actionError，状态不变', () async {
      final api = FakeGitApi(status: sampleStatus());
      api.stageError = NetworkException(NetworkExceptionKind.cannotConnect);
      final container = makeContainer(api);
      await container.read(gitControllerProvider('s1').future);

      final ok = await container
          .read(gitControllerProvider('s1').notifier)
          .stage(['b.txt']);
      expect(ok, isFalse);
      final state = container.read(gitControllerProvider('s1')).valueOrNull!;
      expect(state.actionError, contains('无法连接'));
      expect(state.stagedFiles, hasLength(1));
      expect(state.isActionRunning, isFalse);

      await container
          .read(gitControllerProvider('s1').notifier)
          .clearActionError();
      expect(
        container.read(gitControllerProvider('s1')).valueOrNull!.actionError,
        isNull,
      );
    });

    test('unstage / discard：调用 API 并更新状态', () async {
      final api = FakeGitApi(status: sampleStatus());
      final container = makeContainer(api);
      await container.read(gitControllerProvider('s1').future);

      final okUnstage = await container
          .read(gitControllerProvider('s1').notifier)
          .unstage(['a.txt']);
      expect(okUnstage, isTrue);
      expect(api.unstageCalls, ['a.txt']);

      final okDiscard = await container
          .read(gitControllerProvider('s1').notifier)
          .discard(['c.txt']);
      expect(okDiscard, isTrue);
      expect(api.discardCalls, ['c.txt']);
      final state = container.read(gitControllerProvider('s1')).valueOrNull!;
      expect(state.selectedFile, isNull);
    });

    test('commit 成功：提示短 SHA + 状态更新', () async {
      final api = FakeGitApi(status: sampleStatus());
      api.commitResponse = const GitCommitResponse(
        ok: true,
        commit: 'abc1234',
        git: GitStatus(isGit: true, branch: 'main'),
      );
      final container = makeContainer(api);
      await container.read(gitControllerProvider('s1').future);

      final ok = await container
          .read(gitControllerProvider('s1').notifier)
          .commit('feat: 提交测试');
      expect(ok, isTrue);
      expect(api.commitCalls, ['feat: 提交测试']);
      final state = container.read(gitControllerProvider('s1')).valueOrNull!;
      expect(state.actionMessage, '已提交 abc1234');
      expect(state.status!.isGit, isTrue);
    });

    test('commit 空消息：不发请求，actionError', () async {
      final api = FakeGitApi(status: sampleStatus());
      final container = makeContainer(api);
      await container.read(gitControllerProvider('s1').future);

      final ok = await container
          .read(gitControllerProvider('s1').notifier)
          .commit('   ');
      expect(ok, isFalse);
      expect(api.commitCalls, isEmpty);
      expect(
        container.read(gitControllerProvider('s1')).valueOrNull!.actionError,
        '提交信息不能为空。',
      );
    });

    test('commit 失败 → actionError', () async {
      final api = FakeGitApi(status: sampleStatus());
      api.commitError = NetworkException(NetworkExceptionKind.timedOut);
      final container = makeContainer(api);
      await container.read(gitControllerProvider('s1').future);

      final ok = await container
          .read(gitControllerProvider('s1').notifier)
          .commit('feat: x');
      expect(ok, isFalse);
      expect(
        container.read(gitControllerProvider('s1')).valueOrNull!.actionError,
        contains('超时'),
      );
    });

    test('checkout 成功：调用 + 刷新 status/分支 + 提示', () async {
      final api = FakeGitApi(status: sampleStatus());
      final container = makeContainer(api);
      await container.read(gitControllerProvider('s1').future);

      final ok = await container
          .read(gitControllerProvider('s1').notifier)
          .checkout('dev');
      expect(ok, isTrue);
      expect(api.checkoutCalls, ['dev:local']);
      // 初始 1 次 + checkout 后刷新 1 次
      expect(api.statusCount, 2);
      expect(api.branchesCount, 2);
      final state = container.read(gitControllerProvider('s1')).valueOrNull!;
      expect(state.actionMessage, isNotNull);
      expect(state.isActionRunning, isFalse);
    });

    test('checkout 当前分支：直接返回，不发请求', () async {
      final api = FakeGitApi(status: sampleStatus());
      final container = makeContainer(api);
      await container.read(gitControllerProvider('s1').future);

      final ok = await container
          .read(gitControllerProvider('s1').notifier)
          .checkout('main');
      expect(ok, isFalse);
      expect(api.checkoutCalls, isEmpty);
    });

    test('checkout dirty_worktree：友好错误提示', () async {
      final api = FakeGitApi(status: sampleStatus());
      api.checkoutError = HttpException(
        409,
        '{"code":"dirty_worktree","error":"worktree dirty"}',
        serverCode: 'dirty_worktree',
        serverMessage: 'worktree dirty',
      );
      final container = makeContainer(api);
      await container.read(gitControllerProvider('s1').future);

      final ok = await container
          .read(gitControllerProvider('s1').notifier)
          .checkout('dev');
      expect(ok, isFalse);
      expect(
        container.read(gitControllerProvider('s1')).valueOrNull!.actionError,
        '工作区有未提交的更改，无法切换分支。',
      );
    });

    test('fetch / pull / push：调用 + 刷新 status + 提示', () async {
      final api = FakeGitApi(status: sampleStatus());
      final container = makeContainer(api);
      await container.read(gitControllerProvider('s1').future);
      final statusBefore = api.statusCount;

      expect(
        await container
            .read(gitControllerProvider('s1').notifier)
            .fetchRemote(),
        isTrue,
      );
      expect(api.fetchCalls, ['s1']);
      expect(
        container.read(gitControllerProvider('s1')).valueOrNull!.actionMessage,
        '完成',
      );

      expect(
        await container.read(gitControllerProvider('s1').notifier).pullRemote(),
        isTrue,
      );
      expect(api.pullCalls, ['s1']);

      expect(
        await container.read(gitControllerProvider('s1').notifier).pushRemote(),
        isTrue,
      );
      expect(api.pushCalls, ['s1']);

      // 每个远程操作后都刷新 status + 分支
      expect(api.statusCount, statusBefore + 3);
      expect(api.branchesCount, 1 + 3);
    });

    test('push 失败 → actionError', () async {
      final api = FakeGitApi(status: sampleStatus());
      api.pushError = NetworkException(NetworkExceptionKind.cannotConnect);
      final container = makeContainer(api);
      await container.read(gitControllerProvider('s1').future);

      final ok = await container
          .read(gitControllerProvider('s1').notifier)
          .pushRemote();
      expect(ok, isFalse);
      expect(
        container.read(gitControllerProvider('s1')).valueOrNull!.actionError,
        contains('无法连接'),
      );
    });

    test('selectFile：加载 diff（staged 文件用 staged kind），再点折叠', () async {
      final api = FakeGitApi(status: sampleStatus());
      final container = makeContainer(api);
      await container.read(gitControllerProvider('s1').future);

      final aFile = sampleStatus().files!.first; // a.txt（staged-only）
      await container
          .read(gitControllerProvider('s1').notifier)
          .selectFile(aFile);
      var state = container.read(gitControllerProvider('s1')).valueOrNull!;
      expect(api.diffCalls, ['a.txt:staged']);
      expect(state.diff!.diff, contains('diff --git'));
      expect(state.isDiffLoading, isFalse);

      await container
          .read(gitControllerProvider('s1').notifier)
          .selectFile(aFile);
      state = container.read(gitControllerProvider('s1')).valueOrNull!;
      expect(state.selectedFile, isNull);
      expect(state.diff, isNull);
    });

    test('selectFile：diff 加载失败 → actionError', () async {
      final api = FakeGitApi(status: sampleStatus());
      api.diffError = NetworkException(NetworkExceptionKind.timedOut);
      final container = makeContainer(api);
      await container.read(gitControllerProvider('s1').future);

      final bFile = sampleStatus().files![1]; // b.txt
      await container
          .read(gitControllerProvider('s1').notifier)
          .selectFile(bFile);
      final state = container.read(gitControllerProvider('s1')).valueOrNull!;
      expect(state.diff, isNull);
      expect(state.actionError, contains('超时'));
    });

    test('selectFile：路径为空 → actionError，不发请求', () async {
      final api = FakeGitApi(status: sampleStatus());
      final container = makeContainer(api);
      await container.read(gitControllerProvider('s1').future);

      await container
          .read(gitControllerProvider('s1').notifier)
          .selectFile(GitFile(untracked: true));
      expect(api.diffCount, 0);
      expect(
        container.read(gitControllerProvider('s1')).valueOrNull!.actionError,
        '服务器未提供文件路径。',
      );
    });
  });

  group('GitPage widget', () {
    Future<void> pumpGitPage(WidgetTester tester, FakeGitApi api) async {
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const GitPage(sessionId: 's1'),
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(
              ApiClient(baseUrl: 'http://test.local:30002'),
            ),
            gitApiFactoryProvider.overrideWithValue((_) => api),
          ],
          child: CupertinoApp.router(routerConfig: router),
        ),
      );
      // 首帧（AsyncLoading）+ 异步 build 完成（AsyncData）
      await tester.pump();
      await tester.pump();
    }

    testWidgets('渲染：分支摘要 + 状态分区 + 文件行 + 提交表单 + 远程按钮', (tester) async {
      final api = FakeGitApi(status: sampleStatus());
      await pumpGitPage(tester, api);

      expect(find.text('Git 面板'), findsOneWidget);
      expect(find.text('main'), findsOneWidget);
      expect(find.textContaining('领先 1'), findsOneWidget);
      expect(find.text('+4 −1 · 共 3 个文件'), findsOneWidget);
      expect(find.text('已暂存'), findsOneWidget);
      expect(find.text('未暂存'), findsOneWidget);
      expect(find.text('a.txt'), findsOneWidget);
      expect(find.text('b.txt'), findsOneWidget);
      expect(find.text('c.txt'), findsOneWidget);
      expect(find.text('暂存'), findsNWidgets(2));
      expect(find.text('取消暂存'), findsOneWidget);
      // 提交表单（分区标题 + 按钮）
      expect(find.byKey(const ValueKey('git-commit-message')), findsOneWidget);
      expect(find.text('提交'), findsNWidgets(2));
      expect(find.byKey(const ValueKey('git-fetch')), findsOneWidget);
      expect(find.byKey(const ValueKey('git-pull')), findsOneWidget);
      expect(find.byKey(const ValueKey('git-push')), findsOneWidget);
    });

    testWidgets('暂存 / 取消暂存 / 丢弃按钮调用 API', (tester) async {
      final api = FakeGitApi(status: sampleStatus());
      await pumpGitPage(tester, api);

      await tester.tap(find.byKey(const ValueKey('git-stage-b.txt')));
      await tester.pump();
      await tester.pump();
      expect(api.stageCalls, ['b.txt']);

      await tester.tap(find.byKey(const ValueKey('git-unstage-a.txt')));
      await tester.pump();
      await tester.pump();
      expect(api.unstageCalls, ['a.txt']);

      await tester.tap(find.byKey(const ValueKey('git-discard-c.txt')));
      await tester.pump();
      await tester.pump();
      expect(api.discardCalls, ['c.txt']);
    });

    testWidgets('点击文件行展开 diff，再次点击折叠', (tester) async {
      final api = FakeGitApi(status: sampleStatus());
      await pumpGitPage(tester, api);

      await tester.tap(find.text('b.txt'));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('git-diff')), findsOneWidget);
      expect(find.textContaining('diff --git'), findsOneWidget);
      expect(api.diffCalls, ['b.txt:unstaged']);

      await tester.tap(find.text('b.txt'));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('git-diff')), findsNothing);
    });

    testWidgets('提交表单：输入消息提交，成功后清空并提示 SHA', (tester) async {
      final api = FakeGitApi(status: sampleStatus());
      await pumpGitPage(tester, api);

      await tester.ensureVisible(
        find.byKey(const ValueKey('git-commit-message')),
      );
      await tester.enterText(
        find.byKey(const ValueKey('git-commit-message')),
        'feat: 提交测试',
      );
      await tester.tap(find.byKey(const ValueKey('git-commit-button')));
      await tester.pump();
      await tester.pump();

      expect(api.commitCalls, ['feat: 提交测试']);
      // 成功横幅固定在导航栏底部（任何滚动位置可见）。
      expect(find.text('已提交 abc1234'), findsOneWidget);
      final field = tester.widget<CupertinoTextField>(
        find.byKey(const ValueKey('git-commit-message')),
      );
      expect(field.controller!.text, isEmpty);
    });

    testWidgets('提交信息为空：按钮无效，不发请求', (tester) async {
      final api = FakeGitApi(status: sampleStatus());
      await pumpGitPage(tester, api);

      await tester.ensureVisible(
        find.byKey(const ValueKey('git-commit-button')),
      );
      await tester.tap(find.byKey(const ValueKey('git-commit-button')));
      await tester.pump();
      expect(api.commitCalls, isEmpty);
    });

    testWidgets('分支选择器：ActionSheet 切换分支', (tester) async {
      final api = FakeGitApi(status: sampleStatus());
      await pumpGitPage(tester, api);

      await tester.tap(find.byKey(const ValueKey('git-branch-picker')));
      await tester.pumpAndSettle();
      expect(find.text('dev'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('git-branch-dev')));
      await tester.pumpAndSettle();
      expect(api.checkoutCalls, ['dev:local']);
    });

    testWidgets('fetch / pull / push 按钮调用 API', (tester) async {
      final api = FakeGitApi(status: sampleStatus());
      await pumpGitPage(tester, api);

      await tester.ensureVisible(find.byKey(const ValueKey('git-fetch')));
      // 确保完全滚入可视区（按钮中心可能仍在视口边缘）。
      await tester.drag(
        find.byKey(const ValueKey('git-scroll')),
        const Offset(0, -120),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('git-fetch')));
      await tester.pump();
      await tester.pump();
      expect(api.fetchCalls, ['s1']);
      // 成功横幅固定在导航栏底部（任何滚动位置可见）。
      expect(find.text('完成'), findsOneWidget);

      // 横幅出现后内容下移 52px，重新滚动后再点 pull。
      await tester.drag(
        find.byKey(const ValueKey('git-scroll')),
        const Offset(0, -120),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('git-pull')));
      await tester.pump();
      await tester.pump();
      expect(api.pullCalls, ['s1']);

      await tester.tap(find.byKey(const ValueKey('git-push')));
      await tester.pump();
      await tester.pump();
      expect(api.pushCalls, ['s1']);
    });

    testWidgets('加载态：数据到达前显示 ActivityIndicator', (tester) async {
      final api = FakeGitApi(status: sampleStatus());
      api.statusGate = Completer<void>();
      await pumpGitPage(tester, api);

      expect(find.byType(CupertinoActivityIndicator), findsOneWidget);

      api.statusGate!.complete();
      await tester.pump();
      await tester.pump();
      expect(find.text('main'), findsOneWidget);
      expect(find.byType(CupertinoActivityIndicator), findsNothing);
    });

    testWidgets('错误态：加载失败展示错误信息，重试恢复', (tester) async {
      final api = FakeGitApi(status: sampleStatus());
      api.statusError = NetworkException(NetworkExceptionKind.cannotConnect);
      await pumpGitPage(tester, api);

      expect(find.text('加载失败'), findsOneWidget);
      expect(find.textContaining('无法连接'), findsOneWidget);

      api.statusError = null;
      await tester.tap(find.byKey(const ValueKey('git-retry')));
      await tester.pump();
      await tester.pump();

      expect(find.text('main'), findsOneWidget);
      expect(find.text('加载失败'), findsNothing);
    });

    testWidgets('非 git 仓库 → 空态', (tester) async {
      final api = FakeGitApi(status: const GitStatus(isGit: false));
      await pumpGitPage(tester, api);

      expect(find.text('不是 Git 仓库'), findsOneWidget);
      expect(find.text('该工作区不是 git 仓库，无法使用 Git 功能。'), findsOneWidget);
    });

    testWidgets('工作区干净 → 空态', (tester) async {
      final api = FakeGitApi(
        status: const GitStatus(isGit: true, branch: 'main'),
      );
      await pumpGitPage(tester, api);

      expect(find.text('工作区干净'), findsOneWidget);
      expect(find.text('没有待提交的变更。'), findsOneWidget);
    });

    testWidgets('操作失败 → 红色横幅，可关闭', (tester) async {
      final api = FakeGitApi(status: sampleStatus());
      api.stageError = NetworkException(NetworkExceptionKind.cannotConnect);
      await pumpGitPage(tester, api);

      await tester.tap(find.byKey(const ValueKey('git-stage-b.txt')));
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const ValueKey('git-action-error')), findsOneWidget);
      expect(find.textContaining('无法连接'), findsWidgets);

      await tester.tap(find.byKey(const ValueKey('git-banner-dismiss')));
      await tester.pump();
      expect(find.byKey(const ValueKey('git-action-error')), findsNothing);
    });
  });

  group('gitFriendlyError', () {
    test('服务器错误码映射中文提示；未知错误回退服务器消息', () {
      HttpException http(String code, String message) => HttpException(
        409,
        '{"code":"$code","error":"$message"}',
        serverCode: code,
        serverMessage: message,
      );
      expect(
        gitFriendlyError(http('dirty_worktree', 'x')),
        '工作区有未提交的更改，无法切换分支。',
      );
      expect(gitFriendlyError(http('active_stream', 'x')), '请等待当前响应完成后再操作仓库。');
      expect(
        gitFriendlyError(http('destructive_git_disabled', 'x')),
        contains('HERMES_WEBUI_WORKSPACE_GIT_DESTRUCTIVE=1'),
      );
      expect(gitFriendlyError(http('unknown_code', '服务器说不行')), '服务器说不行');
      expect(
        gitFriendlyError(NetworkException(NetworkExceptionKind.offline)),
        contains('离线'),
      );
      expect(gitFriendlyError(StateError('boom')), 'Bad state: boom');
    });
  });
}
