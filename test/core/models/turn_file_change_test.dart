import 'package:flutter_test/flutter_test.dart';
import 'package:hermex_flutter/core/models/git_workspace.dart';
import 'package:hermex_flutter/core/models/json_value.dart';
import 'package:hermex_flutter/core/models/tool_call.dart';
import 'package:hermex_flutter/core/models/turn_file_change.dart';

void main() {
  group('TurnFileChange 基础', () {
    test('id = path / fileName', () {
      const change = TurnFileChange(
        path: 'lib/main.dart',
        additions: 1,
        deletions: 0,
        action: TurnFileChangeAction.edited,
        changeKind: GitFileChangeKind.modified,
      );
      expect(change.id, 'lib/main.dart');
      expect(change.fileName, 'main.dart');
    });

    test('Action.changeKind 兜底映射', () {
      expect(TurnFileChangeAction.edited.changeKind, GitFileChangeKind.modified);
      expect(TurnFileChangeAction.added.changeKind, GitFileChangeKind.added);
      expect(TurnFileChangeAction.deleted.changeKind, GitFileChangeKind.deleted);
      expect(TurnFileChangeAction.renamed.changeKind, GitFileChangeKind.renamed);
    });
  });

  group('TurnFileChangeSummary', () {
    test('统计派生', () {
      const summary = TurnFileChangeSummary(changes: [
        TurnFileChange(
          path: 'a',
          additions: 2,
          deletions: 1,
          action: TurnFileChangeAction.edited,
          changeKind: GitFileChangeKind.modified,
        ),
        TurnFileChange(
          path: 'b',
          additions: 0,
          deletions: 3,
          action: TurnFileChangeAction.added,
          changeKind: GitFileChangeKind.added,
        ),
      ]);
      expect(summary.fileCount, 2);
      expect(summary.hasChanges, true);
      expect(summary.totalAdditions, 2);
      expect(summary.totalDeletions, 4);
      expect(summary.capsuleTitle, '2 changes');
      expect(summary.filesChangedTitle, '2 files changed');
      expect(
        const TurnFileChangeSummary(changes: []).capsuleTitle,
        '0 changes',
      );
      expect(TurnFileChangeSummary.empty.hasChanges, false);
    });
  });

  group('TurnFileChangeAggregator', () {
    ToolCall toolCall(String name, Map<String, JsonValue> args) {
      return ToolCall(name: name, args: args, isCompleted: true);
    }

    test('actionForToolNamed 映射表', () {
      expect(TurnFileChangeAggregator.actionForToolNamed('create_file'),
          TurnFileChangeAction.added);
      expect(TurnFileChangeAggregator.actionForToolNamed('delete_file'),
          TurnFileChangeAction.deleted);
      expect(TurnFileChangeAggregator.actionForToolNamed('rename_file'),
          TurnFileChangeAction.renamed);
      expect(TurnFileChangeAggregator.actionForToolNamed('write_file'),
          TurnFileChangeAction.edited);
      expect(TurnFileChangeAggregator.actionForToolNamed('read_file'), isNull);
      // actionForToolNamed 精确匹配（大小写归一发生在 summarize 内部）
      expect(TurnFileChangeAggregator.actionForToolNamed('Write_File'), isNull);
    });

    test('summarize：路径提取 + git/status 连接', () {
      final status = GitStatus.fromJson({
        'files': [
          {
            'path': 'lib/main.dart',
            'status': 'M',
            'additions': 5,
            'deletions': 2,
          },
        ],
      });
      final summary = TurnFileChangeAggregator.summarize(
        toolCalls: [
          toolCall('write_file', {
            'path': const JsonString('lib/main.dart'),
          }),
          toolCall('create_file', {
            'paths': const JsonArray([JsonString('new_file.dart')]),
          }),
        ],
        status: status,
      );
      expect(summary.changes, hasLength(2));
      expect(summary.changes[0].path, 'lib/main.dart');
      expect(summary.changes[0].action, TurnFileChangeAction.edited);
      expect(summary.changes[0].changeKind, GitFileChangeKind.modified);
      expect(summary.changes[0].additions, 5);
      expect(summary.changes[0].deletions, 2);
      expect(summary.changes[0].gitFile, isNotNull);
      expect(summary.changes[1].path, 'new_file.dart');
      expect(summary.changes[1].action, TurnFileChangeAction.added);
      expect(summary.changes[1].additions, 0);
      expect(summary.changes[1].gitFile, isNull);
    });

    test('normalize：去引号括号 / ~/ ./ / 拒绝 :// / 超长 / 忽略目录', () {
      expect(TurnFileChangeAggregator.normalize('  "a/b.dart"  '), 'a/b.dart');
      expect(TurnFileChangeAggregator.normalize('~/proj/a.dart'), 'proj/a.dart');
      expect(TurnFileChangeAggregator.normalize('./a.dart'), 'a.dart');
      expect(TurnFileChangeAggregator.normalize('http://x/y'), isNull);
      expect(TurnFileChangeAggregator.normalize(List.filled(241, 'a').join()), isNull);
      expect(TurnFileChangeAggregator.normalize('node_modules/x'), isNull);
      expect(TurnFileChangeAggregator.normalize('src/.git/config'), isNull);
      expect(TurnFileChangeAggregator.normalize('  '), isNull);
      expect(TurnFileChangeAggregator.normalize('build/out.js'), isNull);
    });

    test('renamed 工具只取 destination', () {
      final summary = TurnFileChangeAggregator.summarize(
        toolCalls: [
          toolCall('rename_file', {
            'source': const JsonString('old.dart'),
            'destination': const JsonString('new.dart'),
          }),
        ],
        status: null,
      );
      expect(summary.changes, hasLength(1));
      expect(summary.changes.single.path, 'new.dart');
      expect(summary.changes.single.action, TurnFileChangeAction.renamed);
      expect(summary.changes.single.changeKind, GitFileChangeKind.renamed);
    });

    test('edits 数组路径提取', () {
      final summary = TurnFileChangeAggregator.summarize(
        toolCalls: [
          toolCall('edit_file', {
            'edits': const JsonArray([
              JsonObject({'path': JsonString('a.dart')}),
              JsonObject({'path': JsonString('b.dart')}),
              JsonObject({'type': JsonString('insert')}),
            ]),
          }),
        ],
        status: null,
      );
      expect(summary.changes, hasLength(2));
    });

    test('路径匹配：绝对/相对归一 + 非文件工具忽略', () {
      final status = GitStatus.fromJson({
        'files': [
          {'path': 'lib/main.dart', 'status': 'M', 'additions': 1},
        ],
      });
      final summary = TurnFileChangeAggregator.summarize(
        toolCalls: [
          toolCall('write_file', {
            'path': const JsonString('/workspace/lib/main.dart'),
          }),
          toolCall('bash', {'cmd': const JsonString('ls')}),
        ],
        status: status,
      );
      expect(summary.changes, hasLength(1));
      expect(summary.changes.single.path, '/workspace/lib/main.dart');
      expect(summary.changes.single.additions, 1);
    });

    test('同回合 编辑→创建 升级为更强动作', () {
      final summary = TurnFileChangeAggregator.summarize(
        toolCalls: [
          toolCall('write_file', {'path': const JsonString('a.dart')}),
          toolCall('create_file', {'path': const JsonString('a.dart')}),
        ],
        status: null,
      );
      expect(summary.changes, hasLength(1));
      expect(summary.changes.single.action, TurnFileChangeAction.added);
    });
  });

  test('== / hashCode / toString', () {
    const a = TurnFileChange(
      path: 'a',
      additions: 0,
      deletions: 0,
      action: TurnFileChangeAction.edited,
      changeKind: GitFileChangeKind.modified,
    );
    const b = TurnFileChange(
      path: 'a',
      additions: 0,
      deletions: 0,
      action: TurnFileChangeAction.edited,
      changeKind: GitFileChangeKind.modified,
    );
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a.toString(), contains('TurnFileChange'));
  });
}
