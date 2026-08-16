import '../utils/equality.dart';
import '../utils/lossy_json.dart';
import '../utils/uuid.dart';

/// git-info 响应信封（Swift: GitInfoResponse）。
class GitInfoResponse {
  const GitInfoResponse({this.git});

  factory GitInfoResponse.fromJson(Map<String, Object?> json) {
    return GitInfoResponse(git: optModel(json, 'git', GitInfo.fromJson));
  }

  final GitInfo? git;

  @override
  bool operator ==(Object other) => other is GitInfoResponse && other.git == git;

  @override
  int get hashCode => Object.hashAll([git]);

  @override
  String toString() => 'GitInfoResponse(git: $git)';
}

/// git 信息（Swift: GitInfo）。
class GitInfo {
  const GitInfo({
    this.branch,
    this.dirty,
    this.modified,
    this.untracked,
    this.ahead,
    this.behind,
    this.isGit,
  });

  factory GitInfo.fromJson(Map<String, Object?> json) {
    return GitInfo(
      branch: lossyString(json, 'branch'),
      dirty: lossyInt(json, 'dirty'),
      modified: lossyInt(json, 'modified'),
      untracked: lossyInt(json, 'untracked'),
      ahead: lossyInt(json, 'ahead'),
      behind: lossyInt(json, 'behind'),
      isGit: lossyBool(json, 'is_git'),
    );
  }

  final String? branch;
  final int? dirty;
  final int? modified;
  final int? untracked;
  final int? ahead;
  final int? behind;
  final bool? isGit;

  @override
  bool operator ==(Object other) {
    return other is GitInfo &&
        other.branch == branch &&
        other.dirty == dirty &&
        other.modified == modified &&
        other.untracked == untracked &&
        other.ahead == ahead &&
        other.behind == behind &&
        other.isGit == isGit;
  }

  @override
  int get hashCode =>
      Object.hash(branch, dirty, modified, untracked, ahead, behind, isGit);

  @override
  String toString() => 'GitInfo(branch: $branch, isGit: $isGit)';
}

/// git/status 响应信封（Swift: GitStatusResponse）。
class GitStatusResponse {
  const GitStatusResponse({this.git});

  factory GitStatusResponse.fromJson(Map<String, Object?> json) {
    return GitStatusResponse(git: optModel(json, 'git', GitStatus.fromJson));
  }

  final GitStatus? git;

  @override
  bool operator ==(Object other) =>
      other is GitStatusResponse && other.git == git;

  @override
  int get hashCode => Object.hashAll([git]);

  @override
  String toString() => 'GitStatusResponse(git: $git)';
}

/// git 状态（Swift: GitStatus）。
class GitStatus {
  const GitStatus({
    this.isGit,
    this.branch,
    this.upstream,
    this.ahead,
    this.behind,
    this.totals,
    this.files,
    this.truncated,
  });

  factory GitStatus.fromJson(Map<String, Object?> json) {
    return GitStatus(
      isGit: lossyBool(json, 'is_git'),
      branch: lossyString(json, 'branch'),
      upstream: lossyString(json, 'upstream'),
      ahead: lossyInt(json, 'ahead'),
      behind: lossyInt(json, 'behind'),
      totals: optModel(json, 'totals', GitTotals.fromJson),
      files: optModelList(json, 'files', GitFile.fromJson),
      truncated: lossyBool(json, 'truncated'),
    );
  }

  final bool? isGit;
  final String? branch;
  final String? upstream;
  final int? ahead;
  final int? behind;
  final GitTotals? totals;
  final List<GitFile>? files;
  final bool? truncated;

  /// 排除 ignored 条目的文件列表。
  List<GitFile> get trackedFiles =>
      (files ?? const []).where((f) => !f.isIgnoredFile).toList();

  /// 变更文件数：优先 totals.changed，否则 trackedFiles 数量。
  int get changedCount => totals?.changed ?? trackedFiles.length;

  int get totalAdditions =>
      trackedFiles.fold(0, (sum, f) => sum + (f.additions ?? 0));

  int get totalDeletions =>
      trackedFiles.fold(0, (sum, f) => sum + (f.deletions ?? 0));

  @override
  bool operator ==(Object other) {
    return other is GitStatus &&
        other.isGit == isGit &&
        other.branch == branch &&
        other.upstream == upstream &&
        other.ahead == ahead &&
        other.behind == behind &&
        other.totals == totals &&
        deepEquals(other.files, files) &&
        other.truncated == truncated;
  }

  @override
  int get hashCode => Object.hash(
        isGit,
        branch,
        upstream,
        ahead,
        behind,
        totals,
        deepHash(files),
        truncated,
      );

  @override
  String toString() => 'GitStatus(branch: $branch, isGit: $isGit)';
}

/// git 总计（Swift: GitTotals）。
class GitTotals {
  const GitTotals({
    this.changed,
    this.staged,
    this.unstaged,
    this.untracked,
    this.conflicts,
  });

  factory GitTotals.fromJson(Map<String, Object?> json) {
    return GitTotals(
      changed: lossyInt(json, 'changed'),
      staged: lossyInt(json, 'staged'),
      unstaged: lossyInt(json, 'unstaged'),
      untracked: lossyInt(json, 'untracked'),
      conflicts: lossyInt(json, 'conflicts'),
    );
  }

  final int? changed;
  final int? staged;
  final int? unstaged;
  final int? untracked;
  final int? conflicts;

  @override
  bool operator ==(Object other) {
    return other is GitTotals &&
        other.changed == changed &&
        other.staged == staged &&
        other.unstaged == unstaged &&
        other.untracked == untracked &&
        other.conflicts == conflicts;
  }

  @override
  int get hashCode =>
      Object.hash(changed, staged, unstaged, untracked, conflicts);

  @override
  String toString() => 'GitTotals(changed: $changed)';
}

/// git 文件（Swift: GitFile）。`id` = 第一个非空（path ?? workspacePath ??
/// oldPath，trim 后非空）否则 uuid（init 时计算）。
class GitFile {
  GitFile({
    this.path,
    this.oldPath,
    this.workspacePath,
    this.status,
    this.staged,
    this.unstaged,
    this.untracked,
    this.ignored,
    this.conflict,
    this.additions,
    this.deletions,
    this.binary,
  }) : id = _stablePath(path, workspacePath, oldPath) ?? uuidV4();

  factory GitFile.fromJson(Map<String, Object?> json) {
    final path = lossyString(json, 'path');
    final oldPath = lossyString(json, 'old_path');
    final workspacePath = lossyString(json, 'workspace_path');
    return GitFile(
      path: path,
      oldPath: oldPath,
      workspacePath: workspacePath,
      status: lossyString(json, 'status'),
      staged: lossyBool(json, 'staged'),
      unstaged: lossyBool(json, 'unstaged'),
      untracked: lossyBool(json, 'untracked'),
      ignored: lossyBool(json, 'ignored'),
      conflict: lossyBool(json, 'conflict'),
      additions: lossyInt(json, 'additions'),
      deletions: lossyInt(json, 'deletions'),
      binary: lossyBool(json, 'binary'),
    );
  }

  final String id;
  final String? path;
  final String? oldPath;
  final String? workspacePath;
  final String? status;
  final bool? staged;
  final bool? unstaged;
  final bool? untracked;
  final bool? ignored;
  final bool? conflict;
  final int? additions;
  final int? deletions;
  final bool? binary;

  static String? _stablePath(
    String? path,
    String? workspacePath,
    String? oldPath,
  ) {
    for (final candidate in [path, workspacePath, oldPath]) {
      final trimmed = candidate?.trim();
      if (trimmed != null && trimmed.isNotEmpty) return trimmed;
    }
    return null;
  }

  /// 变更类型判定顺序照抄 Swift：conflict → ignored → untracked →
  /// status 首字符 A/D/R/M/T → staged||unstaged → modified，否则 unknown。
  GitFileChangeKind get changeKind {
    if (conflict == true) return GitFileChangeKind.conflict;
    if (isIgnoredFile) return GitFileChangeKind.ignored;
    if (untracked == true) return GitFileChangeKind.untracked;

    final upper = (status ?? '').toUpperCase();
    final firstChar = upper.isEmpty ? '' : upper[0];
    switch (firstChar) {
      case 'A':
        return GitFileChangeKind.added;
      case 'D':
        return GitFileChangeKind.deleted;
      case 'R':
        return GitFileChangeKind.renamed;
      case 'M':
      case 'T':
        return GitFileChangeKind.modified;
      default:
        return (staged == true || unstaged == true)
            ? GitFileChangeKind.modified
            : GitFileChangeKind.unknown;
    }
  }

  /// ignored==true || status 大小写不敏感 == 'Ignored'。
  bool get isIgnoredFile {
    return ignored == true ||
        (status?.toLowerCase() == 'ignored');
  }

  /// (path ?? workspacePath ?? '').trim 非空 ? 它 : (oldPath ?? '')。
  String get displayPath {
    final trimmed = (path ?? workspacePath ?? '').trim();
    return trimmed.isEmpty ? (oldPath ?? '') : trimmed;
  }

  /// 最后一段路径。
  String get fileName {
    final value = displayPath;
    final parts = value.split('/');
    return parts.isEmpty ? value : parts.last;
  }

  /// 父目录；仓库根 → null。
  String? get parentDirectory {
    final parts = displayPath.split('/');
    if (parts.length <= 1) return null;
    return parts.sublist(0, parts.length - 1).join('/');
  }

  /// staged-only 变更用 'staged'，否则 'unstaged'。
  String get preferredDiffKind =>
      (staged == true && unstaged != true) ? 'staged' : 'unstaged';

  @override
  bool operator ==(Object other) {
    return other is GitFile &&
        other.path == path &&
        other.oldPath == oldPath &&
        other.workspacePath == workspacePath &&
        other.status == status &&
        other.staged == staged &&
        other.unstaged == unstaged &&
        other.untracked == untracked &&
        other.ignored == ignored &&
        other.conflict == conflict &&
        other.additions == additions &&
        other.deletions == deletions &&
        other.binary == binary;
  }

  @override
  int get hashCode => Object.hash(
        path,
        oldPath,
        workspacePath,
        status,
        staged,
        unstaged,
        untracked,
        ignored,
        conflict,
        additions,
        deletions,
        binary,
      );

  @override
  String toString() => 'GitFile(path: $path, status: $status)';
}

/// git 文件变更类型（Swift `GitFile.ChangeKind`）。
enum GitFileChangeKind {
  conflict,
  untracked,
  added,
  deleted,
  renamed,
  modified,
  ignored,
  unknown,
}

/// git 远程操作响应（Swift: GitRemoteActionResponse）。
class GitRemoteActionResponse {
  const GitRemoteActionResponse({this.ok, this.message, this.status});

  factory GitRemoteActionResponse.fromJson(Map<String, Object?> json) {
    return GitRemoteActionResponse(
      ok: lossyBool(json, 'ok'),
      message: lossyString(json, 'message'),
      status: optModel(json, 'status', GitStatus.fromJson),
    );
  }

  final bool? ok;
  final String? message;
  final GitStatus? status;

  @override
  bool operator ==(Object other) {
    return other is GitRemoteActionResponse &&
        other.ok == ok &&
        other.message == message &&
        other.status == status;
  }

  @override
  int get hashCode => Object.hash(ok, message, status);

  @override
  String toString() => 'GitRemoteActionResponse(ok: $ok)';
}

/// git 变更响应（Swift: GitMutationResponse）。派生 `resolvedStatus` = git。
class GitMutationResponse {
  const GitMutationResponse({this.ok, this.git});

  factory GitMutationResponse.fromJson(Map<String, Object?> json) {
    return GitMutationResponse(
      ok: lossyBool(json, 'ok'),
      git: optModel(json, 'git', GitStatus.fromJson),
    );
  }

  final bool? ok;
  final GitStatus? git;

  GitStatus? get resolvedStatus => git;

  @override
  bool operator ==(Object other) =>
      other is GitMutationResponse && other.ok == ok && other.git == git;

  @override
  int get hashCode => Object.hash(ok, git);

  @override
  String toString() => 'GitMutationResponse(ok: $ok)';
}

/// git 提交响应（Swift: GitCommitResponse）。status / git 双键。
class GitCommitResponse {
  const GitCommitResponse({
    this.ok,
    this.commit,
    this.paths,
    this.status,
    this.git,
  });

  factory GitCommitResponse.fromJson(Map<String, Object?> json) {
    return GitCommitResponse(
      ok: lossyBool(json, 'ok'),
      commit: lossyString(json, 'commit'),
      paths: optStringList(json, 'paths'),
      status: optModel(json, 'status', GitStatus.fromJson),
      git: optModel(json, 'git', GitStatus.fromJson),
    );
  }

  final bool? ok;
  final String? commit;
  final List<String>? paths;
  final GitStatus? status;
  final GitStatus? git;

  GitStatus? get resolvedStatus => status ?? git;

  /// commit trim 后的短 SHA。
  String? get shortSHA {
    final trimmed = commit?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  @override
  bool operator ==(Object other) {
    return other is GitCommitResponse &&
        other.ok == ok &&
        other.commit == commit &&
        _listEquals(other.paths, paths) &&
        other.status == status &&
        other.git == git;
  }

  @override
  int get hashCode => Object.hash(
        ok,
        commit,
        Object.hashAll(paths ?? const []),
        status,
        git,
      );

  @override
  String toString() => 'GitCommitResponse(ok: $ok, commit: $commit)';
}

/// git 提交信息响应（Swift: GitCommitMessageResponse）。
class GitCommitMessageResponse {
  const GitCommitMessageResponse({this.ok, this.message, this.truncated});

  factory GitCommitMessageResponse.fromJson(Map<String, Object?> json) {
    return GitCommitMessageResponse(
      ok: lossyBool(json, 'ok'),
      message: lossyString(json, 'message'),
      truncated: lossyBool(json, 'truncated'),
    );
  }

  final bool? ok;
  final String? message;
  final bool? truncated;

  @override
  bool operator ==(Object other) {
    return other is GitCommitMessageResponse &&
        other.ok == ok &&
        other.message == message &&
        other.truncated == truncated;
  }

  @override
  int get hashCode => Object.hash(ok, message, truncated);

  @override
  String toString() => 'GitCommitMessageResponse(ok: $ok)';
}

/// git 分支列表响应信封（Swift: GitBranchesResponse）。
class GitBranchesResponse {
  const GitBranchesResponse({this.branches});

  factory GitBranchesResponse.fromJson(Map<String, Object?> json) {
    return GitBranchesResponse(
      branches: optModel(json, 'branches', GitBranches.fromJson),
    );
  }

  final GitBranches? branches;

  @override
  bool operator ==(Object other) =>
      other is GitBranchesResponse && other.branches == branches;

  @override
  int get hashCode => Object.hashAll([branches]);

  @override
  String toString() => 'GitBranchesResponse(branches: $branches)';
}

/// git 分支（Swift: GitBranches）。
class GitBranches {
  const GitBranches({
    this.isGit,
    this.current,
    this.detached,
    this.head,
    this.local,
    this.remote,
    this.upstream,
    this.ahead,
    this.behind,
  });

  factory GitBranches.fromJson(Map<String, Object?> json) {
    return GitBranches(
      isGit: lossyBool(json, 'is_git'),
      current: lossyString(json, 'current'),
      detached: lossyBool(json, 'detached'),
      head: lossyString(json, 'head'),
      local: optModelList(json, 'local', GitBranchRef.fromJson),
      remote: optModelList(json, 'remote', GitBranchRef.fromJson),
      upstream: lossyString(json, 'upstream'),
      ahead: lossyInt(json, 'ahead'),
      behind: lossyInt(json, 'behind'),
    );
  }

  final bool? isGit;
  final String? current;
  final bool? detached;
  final String? head;
  final List<GitBranchRef>? local;
  final List<GitBranchRef>? remote;
  final String? upstream;
  final int? ahead;
  final int? behind;

  @override
  bool operator ==(Object other) {
    return other is GitBranches &&
        other.isGit == isGit &&
        other.current == current &&
        other.detached == detached &&
        other.head == head &&
        deepEquals(other.local, local) &&
        deepEquals(other.remote, remote) &&
        other.upstream == upstream &&
        other.ahead == ahead &&
        other.behind == behind;
  }

  @override
  int get hashCode => Object.hash(
        isGit,
        current,
        detached,
        head,
        deepHash(local),
        deepHash(remote),
        upstream,
        ahead,
        behind,
      );

  @override
  String toString() => 'GitBranches(current: $current, isGit: $isGit)';
}

/// git 分支引用（Swift: GitBranchRef）。
class GitBranchRef {
  const GitBranchRef({
    this.name,
    this.sha,
    this.updated,
    this.updatedRelative,
    this.author,
    this.subject,
    this.upstream,
    this.ahead,
    this.behind,
  });

  factory GitBranchRef.fromJson(Map<String, Object?> json) {
    return GitBranchRef(
      name: lossyString(json, 'name'),
      sha: lossyString(json, 'sha'),
      updated: lossyInt(json, 'updated'),
      updatedRelative: lossyString(json, 'updated_relative'),
      author: lossyString(json, 'author'),
      subject: lossyString(json, 'subject'),
      upstream: lossyString(json, 'upstream'),
      ahead: lossyInt(json, 'ahead'),
      behind: lossyInt(json, 'behind'),
    );
  }

  final String? name;
  final String? sha;
  final int? updated;
  final String? updatedRelative;
  final String? author;
  final String? subject;
  final String? upstream;
  final int? ahead;
  final int? behind;

  @override
  bool operator ==(Object other) {
    return other is GitBranchRef &&
        other.name == name &&
        other.sha == sha &&
        other.updated == updated &&
        other.updatedRelative == updatedRelative &&
        other.author == author &&
        other.subject == subject &&
        other.upstream == upstream &&
        other.ahead == ahead &&
        other.behind == behind;
  }

  @override
  int get hashCode => Object.hash(
        name,
        sha,
        updated,
        updatedRelative,
        author,
        subject,
        upstream,
        ahead,
        behind,
      );

  @override
  String toString() => 'GitBranchRef(name: $name, sha: $sha)';
}

/// git 检出响应（Swift: GitCheckoutResponse）。`resolvedStatus` = status ?? git。
class GitCheckoutResponse {
  const GitCheckoutResponse({
    this.ok,
    this.message,
    this.status,
    this.git,
    this.branches,
    this.currentBranch,
    this.stashName,
    this.stashed,
    this.restoredStash,
    this.restoreFailed,
    this.restoreError,
    this.restoreStash,
  });

  factory GitCheckoutResponse.fromJson(Map<String, Object?> json) {
    return GitCheckoutResponse(
      ok: lossyBool(json, 'ok'),
      message: lossyString(json, 'message'),
      status: optModel(json, 'status', GitStatus.fromJson),
      git: optModel(json, 'git', GitStatus.fromJson),
      branches: optModel(json, 'branches', GitBranches.fromJson),
      currentBranch: lossyString(json, 'current_branch'),
      stashName: lossyString(json, 'stash_name'),
      stashed: lossyBool(json, 'stashed'),
      restoredStash: optModel(json, 'restored_stash', GitRestoredStash.fromJson),
      restoreFailed: lossyBool(json, 'restore_failed'),
      restoreError: lossyString(json, 'restore_error'),
      restoreStash: optModel(json, 'restore_stash', GitRestoredStash.fromJson),
    );
  }

  final bool? ok;
  final String? message;
  final GitStatus? status;
  final GitStatus? git;
  final GitBranches? branches;
  final String? currentBranch;
  final String? stashName;
  final bool? stashed;
  final GitRestoredStash? restoredStash;
  final bool? restoreFailed;
  final String? restoreError;
  final GitRestoredStash? restoreStash;

  GitStatus? get resolvedStatus => status ?? git;

  @override
  bool operator ==(Object other) {
    return other is GitCheckoutResponse &&
        other.ok == ok &&
        other.message == message &&
        other.status == status &&
        other.git == git &&
        other.branches == branches &&
        other.currentBranch == currentBranch &&
        other.stashName == stashName &&
        other.stashed == stashed &&
        other.restoredStash == restoredStash &&
        other.restoreFailed == restoreFailed &&
        other.restoreError == restoreError &&
        other.restoreStash == restoreStash;
  }

  @override
  int get hashCode => Object.hash(
        ok,
        message,
        status,
        git,
        branches,
        currentBranch,
        stashName,
        stashed,
        restoredStash,
        restoreFailed,
        restoreError,
        restoreStash,
      );

  @override
  String toString() => 'GitCheckoutResponse(ok: $ok, currentBranch: $currentBranch)';
}

/// git 恢复的 stash（Swift: GitRestoredStash）。
class GitRestoredStash {
  const GitRestoredStash({this.ref, this.branch, this.message});

  factory GitRestoredStash.fromJson(Map<String, Object?> json) {
    return GitRestoredStash(
      ref: lossyString(json, 'ref'),
      branch: lossyString(json, 'branch'),
      message: lossyString(json, 'message'),
    );
  }

  final String? ref;
  final String? branch;
  final String? message;

  @override
  bool operator ==(Object other) {
    return other is GitRestoredStash &&
        other.ref == ref &&
        other.branch == branch &&
        other.message == message;
  }

  @override
  int get hashCode => Object.hash(ref, branch, message);

  @override
  String toString() => 'GitRestoredStash(ref: $ref, branch: $branch)';
}

/// git diff 响应信封（Swift: GitDiffResponse）。
class GitDiffResponse {
  const GitDiffResponse({this.diff});

  factory GitDiffResponse.fromJson(Map<String, Object?> json) {
    return GitDiffResponse(diff: optModel(json, 'diff', GitDiff.fromJson));
  }

  final GitDiff? diff;

  @override
  bool operator ==(Object other) => other is GitDiffResponse && other.diff == diff;

  @override
  int get hashCode => Object.hashAll([diff]);

  @override
  String toString() => 'GitDiffResponse(diff: $diff)';
}

/// git diff（Swift: GitDiff）。
class GitDiff {
  const GitDiff({
    this.path,
    this.kind,
    this.binary,
    this.tooLarge,
    this.additions,
    this.deletions,
    this.diff,
  });

  factory GitDiff.fromJson(Map<String, Object?> json) {
    return GitDiff(
      path: lossyString(json, 'path'),
      kind: lossyString(json, 'kind'),
      binary: lossyBool(json, 'binary'),
      tooLarge: lossyBool(json, 'too_large'),
      additions: lossyInt(json, 'additions'),
      deletions: lossyInt(json, 'deletions'),
      diff: lossyString(json, 'diff'),
    );
  }

  final String? path;
  final String? kind;
  final bool? binary;
  final bool? tooLarge;
  final int? additions;
  final int? deletions;
  final String? diff;

  @override
  bool operator ==(Object other) {
    return other is GitDiff &&
        other.path == path &&
        other.kind == kind &&
        other.binary == binary &&
        other.tooLarge == tooLarge &&
        other.additions == additions &&
        other.deletions == deletions &&
        other.diff == diff;
  }

  @override
  int get hashCode => Object.hash(
        path,
        kind,
        binary,
        tooLarge,
        additions,
        deletions,
        diff,
      );

  @override
  String toString() => 'GitDiff(path: $path, kind: $kind)';
}

/// 分支模式（Swift `GitBranchMode`）。纯客户端，无 JSON。
enum GitBranchMode { local, remote }

/// git 检出目标（Swift `GitCheckoutTarget`）。纯客户端，无 JSON。
/// `id` = `mode:ref:newBranch`。
class GitCheckoutTarget {
  const GitCheckoutTarget({
    required this.ref,
    required this.mode,
    this.newBranch,
    this.track,
  });

  final String ref;
  final GitBranchMode mode;
  final String? newBranch;
  final bool? track;

  String get id => '$mode:$ref:$newBranch';

  @override
  bool operator ==(Object other) {
    return other is GitCheckoutTarget &&
        other.ref == ref &&
        other.mode == mode &&
        other.newBranch == newBranch &&
        other.track == track;
  }

  @override
  int get hashCode => Object.hash(ref, mode, newBranch, track);

  @override
  String toString() => 'GitCheckoutTarget(ref: $ref, mode: $mode)';
}

bool _listEquals(List<String>? a, List<String>? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return false;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
