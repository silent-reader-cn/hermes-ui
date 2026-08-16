import 'git_workspace.dart';
import 'json_value.dart';
import 'tool_call.dart';

/// 单次 assistant 回合中变更的一个文件（Swift: TurnFileChange）。
/// 纯客户端逻辑，无 JSON。
class TurnFileChange {
  const TurnFileChange({
    required this.path,
    required this.additions,
    required this.deletions,
    required this.action,
    required this.changeKind,
    this.gitFile,
  });

  /// 归一化后的、工作区相对（或绝对）路径。
  final String path;
  final int additions;
  final int deletions;
  final TurnFileChangeAction action;
  final GitFileChangeKind changeKind;
  final GitFile? gitFile;

  String get id => path;

  /// 最后一段路径。
  String get fileName {
    final parts = path.split('/');
    return parts.isEmpty ? path : parts.last;
  }

  @override
  bool operator ==(Object other) {
    return other is TurnFileChange &&
        other.path == path &&
        other.additions == additions &&
        other.deletions == deletions &&
        other.action == action &&
        other.changeKind == changeKind &&
        other.gitFile == gitFile;
  }

  @override
  int get hashCode =>
      Object.hash(path, additions, deletions, action, changeKind, gitFile);

  @override
  String toString() => 'TurnFileChange(path: $path, action: $action)';
}

/// 变更动作（Swift `TurnFileChange.Action`）。
enum TurnFileChangeAction { edited, added, deleted, renamed }

extension TurnFileChangeActionX on TurnFileChangeAction {
  /// 未匹配 git/status 时的兜底 chip 类型。
  GitFileChangeKind get changeKind {
    switch (this) {
      case TurnFileChangeAction.edited:
        return GitFileChangeKind.modified;
      case TurnFileChangeAction.added:
        return GitFileChangeKind.added;
      case TurnFileChangeAction.deleted:
        return GitFileChangeKind.deleted;
      case TurnFileChangeAction.renamed:
        return GitFileChangeKind.renamed;
    }
  }
}

/// 单回合文件变更汇总（Swift: TurnFileChangeSummary）。
class TurnFileChangeSummary {
  const TurnFileChangeSummary({required this.changes});

  static const TurnFileChangeSummary empty = TurnFileChangeSummary(changes: []);

  final List<TurnFileChange> changes;

  int get fileCount => changes.length;

  bool get hasChanges => changes.isNotEmpty;

  int get totalAdditions => changes.fold(0, (sum, c) => sum + c.additions);

  int get totalDeletions => changes.fold(0, (sum, c) => sum + c.deletions);

  /// 支撑 diff sheet 的 git/status 文件。
  List<GitFile> get diffFiles =>
      changes.map((c) => c.gitFile).whereType<GitFile>().toList();

  /// 紧凑胶囊标题，如 "1 change" / "3 changes"。
  String get capsuleTitle => fileCount == 1 ? '1 change' : '$fileCount changes';

  /// 表头标题，如 "1 file changed" / "3 files changed"。
  String get filesChangedTitle =>
      fileCount == 1 ? '1 file changed' : '$fileCount files changed';

  @override
  bool operator ==(Object other) =>
      other is TurnFileChangeSummary && _listEquals(other.changes, changes);

  @override
  int get hashCode => Object.hashAll(changes);

  @override
  String toString() => 'TurnFileChangeSummary(changes: ${changes.length})';
}

/// 工具调用元数据聚合器（Swift `TurnFileChangeAggregator`）。无状态确定性。
class TurnFileChangeAggregator {
  const TurnFileChangeAggregator._();

  /// 工具名 → 动作映射表。
  static TurnFileChangeAction? actionForToolNamed(String name) {
    switch (name) {
      case 'create_file':
        return TurnFileChangeAction.added;
      case 'remove_file':
      case 'delete_file':
      case 'mcp_filesystem_remove_file':
        return TurnFileChangeAction.deleted;
      case 'move_file':
      case 'rename_file':
      case 'mcp_filesystem_move_file':
        return TurnFileChangeAction.renamed;
      case 'write_file':
      case 'patch':
      case 'edit_file':
      case 'mcp_filesystem_write_file':
      case 'mcp_filesystem_edit_file':
        return TurnFileChangeAction.edited;
      default:
        return null;
    }
  }

  /// 构建一个 assistant 回合的文件变更汇总。
  static TurnFileChangeSummary summarize({
    required List<ToolCall> toolCalls,
    GitStatus? status,
  }) {
    final orderedPaths = <String>[];
    final actionByPath = <String, TurnFileChangeAction>{};

    for (final toolCall in toolCalls) {
      for (final candidate in _candidates(from: toolCall)) {
        final path = normalize(candidate.path);
        if (path == null) continue;

        final existing = actionByPath[path];
        if (existing != null) {
          // 同回合内编辑后又创建/删除读作更强的动作；普通 edit 永不降级。
          if (existing == TurnFileChangeAction.edited &&
              candidate.action != TurnFileChangeAction.edited) {
            actionByPath[path] = candidate.action;
          }
        } else {
          orderedPaths.add(path);
          actionByPath[path] = candidate.action;
        }
      }
    }

    final trackedFiles = status?.trackedFiles ?? const <GitFile>[];
    final changes = orderedPaths.map((path) {
      final action = actionByPath[path] ?? TurnFileChangeAction.edited;
      final match = _matchingFile(path, trackedFiles);
      return TurnFileChange(
        path: path,
        additions: match?.additions ?? 0,
        deletions: match?.deletions ?? 0,
        action: action,
        changeKind: match?.changeKind ?? action.changeKind,
        gitFile: match,
      );
    }).toList();

    return TurnFileChangeSummary(changes: changes);
  }

  // MARK: - 工具调用元数据提取

  static List<({String path, TurnFileChangeAction action})> _candidates({
    required ToolCall from,
  }) {
    final name = _normalizedToolName(from.name);
    final action = name == null ? null : actionForToolNamed(name);
    final args = from.args;
    if (action == null || args == null) return const [];

    // 重命名/移动只产出目标路径；源路径在 git/status 已不存在。
    if (action == TurnFileChangeAction.renamed) {
      final destination = _firstString(
        args,
        keys: const ['destination', 'path', 'file_path', 'filename'],
      );
      if (destination == null) return const [];
      return [(path: destination, action: action)];
    }

    final results = <({String path, TurnFileChangeAction action})>[];
    for (final key in const ['path', 'file_path', 'filename']) {
      final value = _string(args[key]);
      if (value != null) results.add((path: value, action: action));
    }

    final paths = args['paths'];
    if (paths is JsonArray) {
      for (final item in paths.value) {
        final value = _string(item);
        if (value != null) results.add((path: value, action: action));
      }
    }

    final edits = args['edits'];
    if (edits is JsonArray) {
      for (final edit in edits.value) {
        if (edit is JsonObject) {
          final value = _string(edit.value['path']);
          if (value != null) results.add((path: value, action: action));
        }
      }
    }

    return results;
  }

  static String? _normalizedToolName(String? name) {
    final trimmed = name?.trim().toLowerCase();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  static String? _firstString(
    Map<String, JsonValue> args, {
    required List<String> keys,
  }) {
    for (final key in keys) {
      final value = _string(args[key]);
      if (value != null) return value;
    }
    return null;
  }

  /// 只有字符串参数可作为路径。
  static String? _string(JsonValue? value) {
    if (value is! JsonString) return null;
    final trimmed = value.value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  // MARK: - 路径归一化 & 忽略过滤

  static const String _trimCharacters = '`"\'<>()[]{}';

  static const Set<String> _ignoredComponents = {
    '.git',
    '.hg',
    '.svn',
    'node_modules',
    '.venv',
    'venv',
    '__pycache__',
    'dist',
    'build',
    '.next',
    '.cache',
  };

  /// 归一化工具路径为可比较的工作区路径；不可用 → null。
  /// 去除包裹引号/括号，去掉 `~/` 与 `./` 前缀，拒绝 URL 与超长路径，
  /// 过滤生成/供应商目录。
  static String? normalize(String raw) {
    var path = raw.trim();
    path = _trimWrapping(path);
    path = path.trim();

    if (path.isEmpty || path.length > 240 || path.contains('://')) return null;

    if (path.startsWith('~/')) path = path.substring(2);
    while (path.startsWith('./')) {
      path = path.substring(2);
    }
    path = path.trim();

    if (path.isEmpty || _isIgnored(path)) return null;
    return path;
  }

  static String _trimWrapping(String path) {
    var start = 0;
    var end = path.length;
    while (start < end && _trimCharacters.contains(path[start])) {
      start++;
    }
    while (end > start && _trimCharacters.contains(path[end - 1])) {
      end--;
    }
    return path.substring(start, end);
  }

  static bool _isIgnored(String path) {
    return path.split('/').any(_ignoredComponents.contains);
  }

  // MARK: - git/status 连接

  static GitFile? _matchingFile(String path, List<GitFile> files) {
    for (final file in files) {
      if (_displayPath(file) == path) return file;
    }
    for (final file in files) {
      if (_representsSameFile(_displayPath(file), path)) return file;
    }
    return null;
  }

  static String _displayPath(GitFile file) {
    return normalize(file.displayPath) ?? file.displayPath;
  }

  /// 两个归一化路径指向同一文件：相等，或其中一个是另一个的绝对形式
  /// （`/` 边界后缀匹配）。后缀检查要求较长路径为绝对路径，避免两个
  /// 不同的相对路径因共享尾段而误匹配。
  static bool _representsSameFile(String lhs, String rhs) {
    if (lhs.isEmpty || rhs.isEmpty) return false;
    if (lhs == rhs) return true;
    if (lhs.startsWith('/') && lhs.endsWith('/$rhs')) return true;
    if (rhs.startsWith('/') && rhs.endsWith('/$lhs')) return true;
    return false;
  }
}

bool _listEquals(List<TurnFileChange> a, List<TurnFileChange> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
