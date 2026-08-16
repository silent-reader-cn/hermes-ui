import 'package:flutter_test/flutter_test.dart';
import 'package:hermex_flutter/core/models/workspace.dart';

void main() {
  group('WorkspacesResponse / WorkspaceRoot', () {
    test('正常解析（含裸字符串形态）', () {
      final response = WorkspacesResponse.fromJson({
        'workspaces': [
          {'path': '/home/u/proj', 'name': 'proj'},
        ],
        'last': '/home/u/proj',
      });
      expect(response.workspaces!.single.path, '/home/u/proj');
      expect(response.workspaces!.single.name, 'proj');
      expect(response.last, '/home/u/proj');

      // 裸字符串 → path，name null
      final bare = WorkspaceRoot.fromJson('/home/u/proj');
      expect(bare.path, '/home/u/proj');
      expect(bare.name, isNull);
    });

    test('畸形输入：缺失/错型 → null 容错', () {
      // 数组含非对象元素 → 整数组 null（Swift try? 语义）
      final response = WorkspacesResponse.fromJson({
        'workspaces': ['/a', 42, {'path': 5}],
        'last': 7,
      });
      expect(response.workspaces, isNull);
      expect(response.last, isNull);
      expect(WorkspacesResponse.fromJson(const {}).workspaces, isNull);
      expect(WorkspaceRoot.fromJson(42).path, isNull);
      // 纯对象数组但字段错型 → 字段容错
      final mixed = WorkspacesResponse.fromJson({
        'workspaces': [
          {'path': 5},
        ],
      });
      expect(mixed.workspaces, hasLength(1));
      expect(mixed.workspaces!.single.path, isNull);
    });
  });

  group('WorkspaceSuggestionsResponse / WorkspaceMutationResponse', () {
    test('正常 + 畸形', () {
      final suggestions = WorkspaceSuggestionsResponse.fromJson({
        'suggestions': ['/home/u/proj', '/home/u/other'],
        'prefix': '/home/u',
      });
      expect(suggestions.suggestions, hasLength(2));
      expect(suggestions.prefix, '/home/u');
      expect(
        WorkspaceSuggestionsResponse.fromJson({'suggestions': [1]}).suggestions,
        isNull,
      );

      final mutation = WorkspaceMutationResponse.fromJson({
        'ok': true,
        'workspaces': [{'path': '/home/u/proj'}],
        'error': null,
      });
      expect(mutation.ok, true);
      expect(mutation.workspaces!.single.path, '/home/u/proj');
      // lossyBool：'no' → false
      expect(
        WorkspaceMutationResponse.fromJson({'ok': 'no'}).ok,
        false,
      );
    });

    test('WorkspaceMutationRejection 错误描述', () {
      const rejection = WorkspaceMutationRejection(serverMessage: 'bad path');
      expect(
        rejection.errorDescription,
        'The server rejected the request: bad path',
      );
      expect(
        const WorkspaceMutationRejection().errorDescription,
        'The server rejected the request.',
      );
    });
  });

  group('请求 DTO 编码', () {
    test('toJson 输出 snake_case', () {
      expect(
        const AddWorkspaceRequest(path: '/a', name: 'n', create: true).toJson(),
        {'path': '/a', 'name': 'n', 'create': true},
      );
      expect(
        const RemoveWorkspaceRequest(path: '/a').toJson(),
        {'path': '/a'},
      );
      expect(
        const RenameWorkspaceRequest(path: '/a', name: 'b').toJson(),
        {'path': '/a', 'name': 'b'},
      );
      expect(
        const ReorderWorkspacesRequest(paths: ['/a', '/b']).toJson(),
        {'paths': ['/a', '/b']},
      );
    });
  });

  group('DirectoryListResponse / WorkspaceEntry', () {
    test('规格示例正常解析', () {
      final response = DirectoryListResponse.fromJson({
        'entries': [
          {
            'name': 'src',
            'path': '/home/u/proj/src',
            'type': 'dir',
            'size': null,
            'modified': 1723700000.0,
            'is_directory': true,
          },
        ],
        'path': '/home/u/proj',
        'workspace': 'proj',
        'error': null,
      });
      final entry = response.entries!.single;
      expect(entry.name, 'src');
      expect(entry.type, 'dir');
      expect(entry.modified, 1723700000.0);
      expect(entry.isDirectory, true);
      expect(entry.isBrowsableDirectory, true);
      expect(entry.id, '/home/u/proj/src');
    });

    test('is_directory/is_dir 双键 + type 兜底', () {
      expect(
        WorkspaceEntry.fromJson({'is_dir': true}).isDirectory,
        true,
      );
      expect(
        WorkspaceEntry.fromJson({'type': 'dir'}).isBrowsableDirectory,
        true,
      );
      expect(
        WorkspaceEntry.fromJson(const {}).isBrowsableDirectory,
        false,
      );
      expect(WorkspaceEntry.fromJson(const {}).id, isNotEmpty);
    });

    test('畸形输入：缺失/错型 → null 容错', () {
      final entry = WorkspaceEntry.fromJson({
        'name': 1,
        'size': 'big',
        'modified': 'x',
        'is_directory': 'yes',
      });
      expect(entry.name, isNull);
      expect(entry.size, isNull);
      expect(entry.modified, isNull);
      expect(entry.isDirectory, isNull);
    });
  });

  group('FileResponse', () {
    test('规格示例正常解析 + 畸形', () {
      final response = FileResponse.fromJson({
        'content': 'void main() {}',
        'path': '/home/u/proj/lib/main.dart',
        'name': 'main.dart',
        'language': 'dart',
        'size': 1024,
        'lines': 42,
        'error': null,
      });
      expect(response.content, 'void main() {}');
      expect(response.language, 'dart');
      expect(response.size, 1024);
      expect(response.lines, 42);
      final broken = FileResponse.fromJson({
        'content': 1,
        'size': 'big',
        'lines': 'many',
      });
      expect(broken.content, isNull);
      expect(broken.size, isNull);
      expect(broken.lines, isNull);
    });
  });

  test('== / hashCode', () {
    final a = WorkspaceRoot.fromJson('/x');
    final b = WorkspaceRoot.fromJson('/x');
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });
}
