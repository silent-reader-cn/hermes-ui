import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/models/git_workspace.dart';

void main() {
  group('GitInfoResponse / GitInfo', () {
    test('正常 + 非仓库 + 畸形', () {
      final response = GitInfoResponse.fromJson({
        'git': {
          'branch': 'main',
          'dirty': 2,
          'modified': 1,
          'untracked': 1,
          'ahead': 0,
          'behind': 1,
          'is_git': true,
        },
      });
      expect(response.git!.branch, 'main');
      expect(response.git!.dirty, 2);
      expect(response.git!.isGit, true);
      expect(GitInfoResponse.fromJson({'git': null}).git, isNull);
      final broken = GitInfoResponse.fromJson({'git': 'bad'});
      expect(broken.git, isNull);
      expect(GitInfo.fromJson({'branch': 1, 'is_git': 'yes'}).isGit, true);
    });
  });

  group('GitStatus / GitTotals / GitFile', () {
    test('规格示例正常解析（附录 A.3）', () {
      final response = GitStatusResponse.fromJson({
        'git': {
          'is_git': true,
          'branch': 'main',
          'upstream': 'origin/main',
          'ahead': 0,
          'behind': 1,
          'totals': {'changed': 3, 'staged': 1, 'unstaged': 2, 'untracked': 1, 'conflicts': 0},
          'files': [
            {'path': 'lib/main.dart', 'status': 'M'},
          ],
          'truncated': false,
        },
      });
      final status = response.git!;
      expect(status.isGit, true);
      expect(status.totals!.changed, 3);
      expect(status.files!.single.path, 'lib/main.dart');
      expect(status.truncated, false);
      expect(status.trackedFiles, hasLength(1));
      expect(status.changedCount, 3);
    });

    test('GitFile 派生：changeKind 判定顺序', () {
      expect(
        GitFile.fromJson({'conflict': true, 'status': 'M'}).changeKind,
        GitFileChangeKind.conflict,
      );
      expect(
        GitFile.fromJson({'ignored': true}).changeKind,
        GitFileChangeKind.ignored,
      );
      expect(
        GitFile.fromJson({'status': 'Ignored'}).changeKind,
        GitFileChangeKind.ignored,
      );
      expect(
        GitFile.fromJson({'untracked': true}).changeKind,
        GitFileChangeKind.untracked,
      );
      expect(
        GitFile.fromJson({'status': 'A'}).changeKind,
        GitFileChangeKind.added,
      );
      expect(
        GitFile.fromJson({'status': 'd'}).changeKind,
        GitFileChangeKind.deleted,
      );
      expect(
        GitFile.fromJson({'status': 'R'}).changeKind,
        GitFileChangeKind.renamed,
      );
      expect(
        GitFile.fromJson({'status': 'T'}).changeKind,
        GitFileChangeKind.modified,
      );
      expect(
        GitFile.fromJson({'status': 'M'}).changeKind,
        GitFileChangeKind.modified,
      );
      expect(
        GitFile.fromJson({'staged': true}).changeKind,
        GitFileChangeKind.modified,
      );
      expect(
        GitFile.fromJson(const {}).changeKind,
        GitFileChangeKind.unknown,
      );
    });

    test('GitFile id / displayPath / fileName / parentDirectory / preferredDiffKind', () {
      final file = GitFile.fromJson({
        'path': 'lib/main.dart',
        'old_path': null,
        'workspace_path': 'lib/main.dart',
        'status': 'M',
        'staged': false,
        'unstaged': true,
        'untracked': false,
        'ignored': false,
        'conflict': false,
        'additions': 12,
        'deletions': 3,
        'binary': false,
      });
      expect(file.id, 'lib/main.dart');
      expect(file.displayPath, 'lib/main.dart');
      expect(file.fileName, 'main.dart');
      expect(file.parentDirectory, 'lib');
      expect(file.preferredDiffKind, 'unstaged');
      expect(
        GitFile.fromJson({'path': 'a/b/c.dart', 'staged': true, 'unstaged': false})
            .preferredDiffKind,
        'staged',
      );
      expect(
        GitFile.fromJson({'old_path': 'x'}).id,
        'x',
      );
      expect(GitFile.fromJson(const {}).id, isNotEmpty);
      expect(GitFile.fromJson({'path': 'top.dart'}).parentDirectory, isNull);
    });

    test('GitStatus.trackedFiles / changedCount / totalAdditions / totalDeletions', () {
      final status = GitStatus.fromJson({
        'totals': {'changed': 1},
        'files': [
          {'path': 'a.dart', 'additions': 2, 'deletions': 1},
          {'path': 'b.dart', 'ignored': true, 'additions': 9},
        ],
      });
      expect(status.trackedFiles, hasLength(1));
      expect(status.changedCount, 1);
      expect(status.totalAdditions, 2);
      expect(status.totalDeletions, 1);
      expect(GitStatus.fromJson(const {}).changedCount, 0);
    });

    test('畸形输入：缺失/错型 → 容错', () {
      final file = GitFile.fromJson({
        'path': 1,
        'status': false,
        'additions': '12',
        'staged': 'yes',
      });
      expect(file.path, '1');
      expect(file.status, 'false');
      expect(file.additions, 12);
      expect(file.staged, true);
      expect(GitStatus.fromJson(const {}).isGit, isNull);
    });
  });

  group('Git 信封响应', () {
    test('GitRemoteActionResponse / GitMutationResponse / GitCommitResponse', () {
      final remote = GitRemoteActionResponse.fromJson({
        'ok': true,
        'message': '已推送',
        'status': {'is_git': true, 'branch': 'main'},
      });
      expect(remote.ok, true);
      expect(remote.status!.branch, 'main');

      final mutation = GitMutationResponse.fromJson(
        {'ok': true, 'git': {'is_git': true, 'branch': 'main'}},
      );
      expect(mutation.resolvedStatus!.branch, 'main');

      final commit = GitCommitResponse.fromJson({
        'ok': true,
        'commit': ' abc1234 ',
        'paths': ['lib/main.dart'],
        'status': {'is_git': true, 'branch': 'main'},
      });
      expect(commit.shortSHA, 'abc1234');
      expect(commit.resolvedStatus!.branch, 'main');
      expect(commit.paths, ['lib/main.dart']);
      // git 双键兜底
      expect(
        GitCommitResponse.fromJson({'git': {'branch': 'x'}}).resolvedStatus!.branch,
        'x',
      );
      expect(GitCommitResponse.fromJson(const {}).resolvedStatus, isNull);
    });

    test('GitCommitMessageResponse / GitDiffResponse / GitDiff', () {
      final message = GitCommitMessageResponse.fromJson(
        {'ok': true, 'message': 'feat: …', 'truncated': false},
      );
      expect(message.message, 'feat: …');
      expect(message.truncated, false);

      final diff = GitDiffResponse.fromJson({
        'diff': {
          'path': 'lib/main.dart',
          'kind': 'modified',
          'binary': false,
          'too_large': false,
          'additions': 12,
          'deletions': 3,
          'diff': '@@ -1,3 +1,4 @@…',
        },
      });
      expect(diff.diff!.kind, 'modified');
      expect(diff.diff!.tooLarge, false);
      expect(diff.diff!.additions, 12);
      expect(GitDiffResponse.fromJson(const {}).diff, isNull);
      expect(GitDiff.fromJson({'diff': 1}).diff, '1');
    });
  });

  group('GitBranches 家族', () {
    test('正常解析（附录 A.3）', () {
      final response = GitBranchesResponse.fromJson({
        'branches': {
          'is_git': true,
          'current': 'main',
          'detached': false,
          'head': 'abc1234',
          'local': [
            {
              'name': 'main',
              'sha': 'abc1234',
              'updated': 1723700000,
              'updated_relative': '2 小时前',
              'author': 'me',
              'subject': 'fix',
              'upstream': 'origin/main',
              'ahead': 0,
              'behind': 0,
            },
          ],
          'remote': [],
          'upstream': 'origin/main',
          'ahead': 0,
          'behind': 0,
        },
      });
      final branches = response.branches!;
      expect(branches.current, 'main');
      expect(branches.local!.single.name, 'main');
      expect(branches.local!.single.updated, 1723700000);
      expect(branches.local!.single.subject, 'fix');
      expect(branches.remote, isEmpty);
    });

    test('畸形输入 → 容错', () {
      final branches = GitBranches.fromJson({
        'current': 1,
        'local': 'bad',
        'ahead': 'many',
      });
      expect(branches.current, '1');
      expect(branches.local, isNull);
      expect(branches.ahead, isNull);
      expect(GitBranchesResponse.fromJson(const {}).branches, isNull);
    });
  });

  group('GitCheckoutResponse / GitRestoredStash', () {
    test('正常 + resolvedStatus 优先级', () {
      final response = GitCheckoutResponse.fromJson({
        'ok': true,
        'message': '已切换',
        'status': {'is_git': true, 'branch': 'dev'},
        'current_branch': 'dev',
        'stash_name': null,
        'stashed': false,
        'restored_stash': {'ref': 'stash@{0}', 'branch': 'dev', 'message': 'm'},
        'restore_failed': false,
        'restore_error': null,
      });
      expect(response.resolvedStatus!.branch, 'dev');
      expect(response.currentBranch, 'dev');
      expect(response.restoredStash!.ref, 'stash@{0}');
      expect(response.restoreFailed, false);

      // status 缺失时用 git
      final fallback = GitCheckoutResponse.fromJson({
        'git': {'branch': 'x'},
      });
      expect(fallback.resolvedStatus!.branch, 'x');
      // status 优先于 git
      final priority = GitCheckoutResponse.fromJson({
        'status': {'branch': 's'},
        'git': {'branch': 'g'},
      });
      expect(priority.resolvedStatus!.branch, 's');
    });

    test('畸形输入 → 容错', () {
      final response = GitCheckoutResponse.fromJson({
        'ok': 'yes',
        'restore_error': 1,
        'restored_stash': 'bad',
      });
      expect(response.ok, true);
      expect(response.restoreError, '1');
      expect(response.restoredStash, isNull);
    });
  });

  group('GitCheckoutTarget / GitBranchMode', () {
    test('id = mode:ref:newBranch', () {
      const target = GitCheckoutTarget(
        ref: 'feature/x',
        mode: GitBranchMode.local,
        newBranch: 'nb',
      );
      expect(target.id, 'GitBranchMode.local:feature/x:nb');
    });
  });

  test('== / hashCode / toString', () {
    final a = GitFile.fromJson({'path': 'a.dart'});
    final b = GitFile.fromJson({'path': 'a.dart'});
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a.toString(), contains('GitFile'));
    final status = GitStatus.fromJson({'branch': 'main'});
    expect(status.toString(), contains('GitStatus'));
  });
}
