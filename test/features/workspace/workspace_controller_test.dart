import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/api/api_exception.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/models/workspace.dart';
import 'package:hermes_ui/features/downloads/download_providers.dart';
import 'package:hermes_ui/features/workspace/workspace_providers.dart';

import '../../helpers/fake_download_service.dart';
import '../../helpers/fake_workspace_api.dart';

/// 构造测试条目（path 缺省 = name，适配根目录场景）。
WorkspaceEntry buildEntry(
  String name, {
  String? path,
  bool dir = false,
  int? size,
  double? modified,
  String? type,
}) {
  return WorkspaceEntry(
    name: name,
    path: path ?? name,
    type: type,
    size: size,
    modified: modified,
    isDirectory: dir,
  );
}

/// 组装 ProviderContainer：注入 fake API（apiClientProvider 用占位客户端，
/// 工厂 override 忽略它，不发任何网络请求）。
ProviderContainer makeContainer(FakeWorkspaceApi api) {
  final container = ProviderContainer(
    overrides: [
      apiClientProvider.overrideWithValue(
        ApiClient(baseUrl: 'http://test.local:30002'),
      ),
      workspaceApiFactoryProvider.overrideWithValue((_) => api),
      ...createDownloadTestOverrides(),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('WorkspaceController 状态机', () {
    test('初始加载成功：AsyncData + 根目录条目 + 派生 provider', () async {
      final api = FakeWorkspaceApi(
        directories: {
          '.': [
            buildEntry('src', dir: true),
            buildEntry('readme.md', size: 1536, modified: 1700000000),
          ],
        },
      );
      final container = makeContainer(api);

      await container.read(workspaceControllerProvider('s1').future);
      final state = container
          .read(workspaceControllerProvider('s1'))
          .valueOrNull!;

      expect(api.fetchCalls, ['s1|.']);
      expect(state.entries, hasLength(2));
      expect(state.currentPath, '.');
      expect(state.isAtRoot, isTrue);
      expect(state.isRefreshing, isFalse);
      expect(state.busyPaths, isEmpty);
      expect(state.actionError, isNull);

      // 派生 provider
      expect(
        container.read(workspaceBreadcrumbsProvider('s1')).map((c) => c.path),
        ['.'],
      );
      expect(container.read(workspaceParentPathProvider('s1')), isNull);
      expect(container.read(workspaceDisplayPathProvider('s1')), '根目录');
    });

    test('初始加载失败：AsyncError + 错误信息', () async {
      final api = FakeWorkspaceApi();
      api.fetchError = NetworkException(NetworkExceptionKind.cannotConnect);
      final container = makeContainer(api);

      await expectLater(
        container.read(workspaceControllerProvider('s1').future),
        throwsA(isA<NetworkException>()),
      );
      expect(
        container.read(workspaceControllerProvider('s1')).hasError,
        isTrue,
      );
    });

    test('refresh：重新加载当前目录；失败 → AsyncError', () async {
      final api = FakeWorkspaceApi(
        directories: {
          '.': [buildEntry('a.txt')],
        },
      );
      final container = makeContainer(api);
      await container.read(workspaceControllerProvider('s1').future);

      api.directories['.']!.add(buildEntry('b.txt'));
      final notifier = container.read(
        workspaceControllerProvider('s1').notifier,
      );
      await notifier.refresh();
      final state = container
          .read(workspaceControllerProvider('s1'))
          .valueOrNull!;
      expect(api.fetchCount, 2);
      expect(state.entries.map((e) => e.name), ['a.txt', 'b.txt']);

      api.fetchError = HttpException(500, null, message: '服务不可用');
      await notifier.refresh();
      expect(
        container.read(workspaceControllerProvider('s1')).hasError,
        isTrue,
      );
    });

    test('导航：进入子目录 / 返回父目录 / 跳转根目录，面包屑联动', () async {
      final api = FakeWorkspaceApi(
        directories: {
          '.': [buildEntry('src', dir: true)],
          'src': [
            buildEntry('main.dart', size: 42),
            buildEntry('sub', dir: true, path: 'src/sub'),
          ],
          'src/sub': [buildEntry('deep.txt')],
        },
      );
      final container = makeContainer(api);
      await container.read(workspaceControllerProvider('s1').future);
      final notifier = container.read(
        workspaceControllerProvider('s1').notifier,
      );

      await notifier.navigateTo('src');
      var state = container
          .read(workspaceControllerProvider('s1'))
          .valueOrNull!;
      expect(state.currentPath, 'src');
      expect(state.entries.map((e) => e.name), ['main.dart', 'sub']);
      expect(
        container.read(workspaceBreadcrumbsProvider('s1')).map((c) => c.path),
        ['.', 'src'],
      );
      expect(container.read(workspaceParentPathProvider('s1')), '.');

      await notifier.navigateTo('src/sub');
      state = container.read(workspaceControllerProvider('s1')).valueOrNull!;
      expect(state.currentPath, 'src/sub');
      expect(state.entries.map((e) => e.name), ['deep.txt']);
      expect(
        container.read(workspaceBreadcrumbsProvider('s1')).map((c) => c.path),
        ['.', 'src', 'src/sub'],
      );

      await notifier.navigateUp();
      state = container.read(workspaceControllerProvider('s1')).valueOrNull!;
      expect(state.currentPath, 'src');

      await notifier.navigateToRoot();
      state = container.read(workspaceControllerProvider('s1')).valueOrNull!;
      expect(state.currentPath, '.');
      expect(state.entries.map((e) => e.name), ['src']);
    });

    test('导航失败：保留旧列表 + actionError；retryLastLoad 恢复', () async {
      final api = FakeWorkspaceApi(
        directories: {
          '.': [buildEntry('src', dir: true)],
          'src': [buildEntry('main.dart')],
        },
      );
      final container = makeContainer(api);
      await container.read(workspaceControllerProvider('s1').future);

      api.fetchError = HttpException(403, null, message: '无权访问');
      final notifier = container.read(
        workspaceControllerProvider('s1').notifier,
      );
      await notifier.navigateTo('src');
      var state = container
          .read(workspaceControllerProvider('s1'))
          .valueOrNull!;
      expect(state.currentPath, '.'); // 旧列表保留
      expect(state.entries.map((e) => e.name), ['src']);
      expect(state.isRefreshing, isFalse);
      expect(state.actionError, contains('无权访问'));

      api.fetchError = null;
      await notifier.retryLastLoad();
      state = container.read(workspaceControllerProvider('s1')).valueOrNull!;
      expect(state.currentPath, 'src');
      expect(state.entries.map((e) => e.name), ['main.dart']);
      expect(state.actionError, isNull);
      expect(api.fetchCalls.last, 's1|src');
    });

    test('上传：isUploading 标志 + API 调用 + 成功后刷新当前目录', () async {
      final api = FakeWorkspaceApi(
        directories: {
          '.': [buildEntry('a.txt')],
        },
      );
      final container = makeContainer(api);
      await container.read(workspaceControllerProvider('s1').future);
      final notifier = container.read(
        workspaceControllerProvider('s1').notifier,
      );

      final future = notifier.uploadFile(
        filename: 'new.txt',
        data: Uint8List.fromList([1, 2, 3]),
      );
      // 上传在途标志立即可见
      expect(
        container
            .read(workspaceControllerProvider('s1'))
            .valueOrNull!
            .isUploading,
        isTrue,
      );

      expect(await future, isTrue);
      final state = container
          .read(workspaceControllerProvider('s1'))
          .valueOrNull!;
      expect(api.uploadCalls, ['s1|new.txt|3']);
      expect(state.isUploading, isFalse);
      expect(state.entries.map((e) => e.name), ['a.txt', 'new.txt']);
    });

    test('上传失败：actionError + isUploading 复位 + 列表不变', () async {
      final api = FakeWorkspaceApi(
        directories: {
          '.': [buildEntry('a.txt')],
        },
      );
      api.uploadError = HttpException(413, null, message: '文件过大');
      final container = makeContainer(api);
      await container.read(workspaceControllerProvider('s1').future);

      final ok = await container
          .read(workspaceControllerProvider('s1').notifier)
          .uploadFile(filename: 'big.txt', data: Uint8List.fromList([1]));
      expect(ok, isFalse);
      final state = container
          .read(workspaceControllerProvider('s1'))
          .valueOrNull!;
      expect(state.isUploading, isFalse);
      expect(state.actionError, contains('文件过大'));
      expect(state.entries.map((e) => e.name), ['a.txt']);
      expect(api.uploadCalls, ['s1|big.txt|1']);
    });

    test('删除：API 调用 + 成功后从列表移除 + busyPaths 复位', () async {
      final api = FakeWorkspaceApi(
        directories: {
          '.': [buildEntry('a.txt'), buildEntry('b.txt')],
        },
      );
      final container = makeContainer(api);
      await container.read(workspaceControllerProvider('s1').future);

      final ok = await container
          .read(workspaceControllerProvider('s1').notifier)
          .delete(buildEntry('a.txt'));
      expect(ok, isTrue);
      expect(api.deleteCalls, ['s1|a.txt']);
      final state = container
          .read(workspaceControllerProvider('s1'))
          .valueOrNull!;
      expect(state.entries.map((e) => e.name), ['b.txt']);
      expect(state.busyPaths, isEmpty);
    });

    test('删除失败：actionError + 列表不变', () async {
      final api = FakeWorkspaceApi(
        directories: {
          '.': [buildEntry('a.txt')],
        },
      );
      api.deleteError = HttpException(500, null, message: '删除失败');
      final container = makeContainer(api);
      await container.read(workspaceControllerProvider('s1').future);

      final ok = await container
          .read(workspaceControllerProvider('s1').notifier)
          .delete(buildEntry('a.txt'));
      expect(ok, isFalse);
      final state = container
          .read(workspaceControllerProvider('s1'))
          .valueOrNull!;
      expect(state.actionError, contains('删除失败'));
      expect(state.entries.map((e) => e.name), ['a.txt']);
      expect(state.busyPaths, isEmpty);
    });

    test('重命名：API 调用 + 本地更新该行（根目录与子目录两种场景）', () async {
      final api = FakeWorkspaceApi(
        directories: {
          '.': [buildEntry('a.txt')],
          'src': [buildEntry('old.dart', path: 'src/old.dart')],
        },
      );
      final container = makeContainer(api);
      await container.read(workspaceControllerProvider('s1').future);
      final notifier = container.read(
        workspaceControllerProvider('s1').notifier,
      );

      // 根目录
      final okRoot = await notifier.rename(buildEntry('a.txt'), 'b.txt');
      expect(okRoot, isTrue);
      expect(api.renameCalls, ['s1|a.txt|b.txt']);
      var state = container
          .read(workspaceControllerProvider('s1'))
          .valueOrNull!;
      expect(state.entries.map((e) => e.name), ['b.txt']);
      expect(state.entries.single.path, 'b.txt');

      // 子目录：新路径 = 父路径 + 新名
      await notifier.navigateTo('src');
      final okSub = await notifier.rename(
        buildEntry('old.dart', path: 'src/old.dart'),
        'new.dart',
      );
      expect(okSub, isTrue);
      expect(api.renameCalls.last, 's1|src/old.dart|new.dart');
      state = container.read(workspaceControllerProvider('s1')).valueOrNull!;
      expect(state.entries.map((e) => e.name), ['new.dart']);
      expect(state.entries.single.path, 'src/new.dart');
    });

    test('重命名：名称为空 → actionError 且不调 API', () async {
      final api = FakeWorkspaceApi(
        directories: {
          '.': [buildEntry('a.txt')],
        },
      );
      final container = makeContainer(api);
      await container.read(workspaceControllerProvider('s1').future);

      final ok = await container
          .read(workspaceControllerProvider('s1').notifier)
          .rename(buildEntry('a.txt'), '   ');
      expect(ok, isFalse);
      expect(api.renameCalls, isEmpty);
      expect(
        container
            .read(workspaceControllerProvider('s1'))
            .valueOrNull!
            .actionError,
        contains('名称不能为空'),
      );
    });

    test('下载：构造 Endpoint.rawFile URL 并 enqueue 到下载中心', () async {
      final api = FakeWorkspaceApi(
        directories: {
          '.': [buildEntry('a.txt', size: 2048, type: 'text/plain')],
        },
      );
      final container = makeContainer(api);
      await container.read(workspaceControllerProvider('s1').future);
      final notifier = container.read(
        workspaceControllerProvider('s1').notifier,
      );

      final ok = await notifier.download(
        buildEntry('a.txt', size: 2048, type: 'text/plain'),
      );
      expect(ok, isTrue);

      final tasks = container.read(downloadControllerProvider).tasks;
      expect(tasks, hasLength(1));
      final task = tasks.single;
      expect(task.fileName, 'a.txt');
      expect(task.mimeType, 'text/plain');
      expect(task.expectedBytes, 2048);
      expect(task.sessionId, 's1');
      expect(task.sourceUrl, contains('/api/file/raw?'));
      expect(task.sourceUrl, contains('session_id=s1'));
      expect(task.sourceUrl, contains('path=a.txt'));
    });

    test('打包下载目录：构造 Endpoint.folderDownload URL 并 enqueue 到下载中心', () async {
      final api = FakeWorkspaceApi(
        directories: {
          '.': [buildEntry('a.txt')],
        },
      );
      final container = makeContainer(api);
      await container.read(workspaceControllerProvider('s1').future);
      final notifier = container.read(
        workspaceControllerProvider('s1').notifier,
      );

      final ok = await notifier.downloadFolder();
      expect(ok, isTrue);

      final tasks = container.read(downloadControllerProvider).tasks;
      expect(tasks, hasLength(1));
      final task = tasks.single;
      expect(task.fileName, 'workspace_s1.zip');
      expect(task.mimeType, 'application/zip');
      expect(task.sessionId, 's1');
      expect(task.sourceUrl, contains('/api/folder/download?'));
      expect(task.sourceUrl, contains('session_id=s1'));
    });

    test('条目无路径：删除/下载 → actionError 且不调 API', () async {
      final api = FakeWorkspaceApi(
        directories: {
          '.': [buildEntry('a.txt')],
        },
      );
      final container = makeContainer(api);
      await container.read(workspaceControllerProvider('s1').future);
      final notifier = container.read(
        workspaceControllerProvider('s1').notifier,
      );

      const orphan = WorkspaceEntry(name: 'orphan'); // path 为 null
      expect(await notifier.delete(orphan), isFalse);
      expect(await notifier.download(orphan), isFalse);
      expect(api.deleteCalls, isEmpty);
      expect(api.downloadCalls, isEmpty);
      expect(
        container
            .read(workspaceControllerProvider('s1'))
            .valueOrNull!
            .actionError,
        contains('服务器未提供该条目路径'),
      );
    });

    test('clearActionError：清除行操作错误标记', () async {
      final api = FakeWorkspaceApi(
        directories: {
          '.': [buildEntry('a.txt')],
        },
      );
      api.uploadError = HttpException(500, null, message: '上传失败');
      final container = makeContainer(api);
      await container.read(workspaceControllerProvider('s1').future);
      final notifier = container.read(
        workspaceControllerProvider('s1').notifier,
      );

      await notifier.uploadFile(
        filename: 'x.txt',
        data: Uint8List.fromList([1]),
      );
      expect(
        container
            .read(workspaceControllerProvider('s1'))
            .valueOrNull!
            .actionError,
        isNotNull,
      );

      await notifier.clearActionError();
      expect(
        container
            .read(workspaceControllerProvider('s1'))
            .valueOrNull!
            .actionError,
        isNull,
      );
    });
  });
}
