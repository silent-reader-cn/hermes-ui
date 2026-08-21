import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermex_flutter/core/api/api_client.dart';
import 'package:hermex_flutter/core/api/api_exception.dart';
import 'package:hermex_flutter/core/connections/connection_providers.dart';
import 'package:hermex_flutter/core/models/workspace.dart';
import 'package:hermex_flutter/features/workspace/workspace_page.dart';
import 'package:hermex_flutter/features/workspace/workspace_providers.dart';

import '../../helpers/fake_workspace_api.dart';

/// 构造测试条目（path 缺省 = name）。
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

/// 组装 WorkspacePage（注入 fake API + 可选 filePicker）。
Future<void> pumpWorkspace(
  WidgetTester tester,
  FakeWorkspaceApi api, {
  WorkspaceFilePicker? picker,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(
          ApiClient(baseUrl: 'http://test.local:30002'),
        ),
        workspaceApiFactoryProvider.overrideWithValue((_) => api),
      ],
      child: CupertinoApp(
        home: WorkspacePage(sessionId: 's1', filePicker: picker),
      ),
    ),
  );
  // 首帧（AsyncLoading）+ 异步 build 完成（AsyncData）
  await tester.pump();
  await tester.pump();
}

void main() {
  group('格式化工具', () {
    test('formatWorkspaceFileSize', () {
      expect(formatWorkspaceFileSize(null), '—');
      expect(formatWorkspaceFileSize(512), '512 B');
      expect(formatWorkspaceFileSize(1536), '1.5 KB');
      expect(formatWorkspaceFileSize(5 * 1024 * 1024), '5.0 MB');
      expect(formatWorkspaceFileSize(2 * 1024 * 1024 * 1024), '2.0 GB');
    });

    test('workspaceEntryDetail：目录显示路径（与名称相同省略），文件显示大小+时间', () {
      expect(
        workspaceEntryDetail(buildEntry('src', dir: true, path: 'src')),
        '',
      );
      expect(
        workspaceEntryDetail(buildEntry('lib', dir: true, path: 'src/lib')),
        'src/lib',
      );
      // 修改时间依赖本地时区，只校验形状
      final detail = workspaceEntryDetail(
        buildEntry('a.txt', size: 1536, modified: 1700000000),
      );
      expect(detail, startsWith('1.5 KB · '));
      expect(
        RegExp(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}$')
            .hasMatch(detail.substring('1.5 KB · '.length)),
        isTrue,
      );
      expect(
        workspaceEntryDetail(buildEntry('b.txt', size: 42, type: 'text')),
        '42 B',
      );
    });
  });

  group('WorkspacePage widget', () {
    testWidgets('列表渲染：目录行 + 文件行（图标/名称/大小/时间）', (tester) async {
      final api = FakeWorkspaceApi(
        directories: {
          '.': [
            buildEntry('src', dir: true),
            buildEntry('readme.md', size: 1536, modified: 1700000000),
            buildEntry('photo.png', size: 2048, type: 'image'),
          ],
        },
      );
      await pumpWorkspace(tester, api);

      expect(find.text('文件'), findsOneWidget);
      expect(find.text('src'), findsOneWidget);
      expect(find.text('readme.md'), findsOneWidget);
      expect(find.text('photo.png'), findsOneWidget);
      // 文件副标题：大小 + 修改时间（时间依赖本地时区，只匹配前缀）
      expect(find.textContaining('1.5 KB · '), findsOneWidget);
      expect(find.text('2.0 KB'), findsOneWidget);
      // 面包屑根目录按钮（当前目录 → 可点击）
      expect(find.byKey(const ValueKey('workspace-root')), findsOneWidget);
      expect(find.byKey(const ValueKey('workspace-up')), findsOneWidget);
      // 目录行有 chevron，文件行有操作按钮
      expect(find.byIcon(CupertinoIcons.chevron_right), findsOneWidget);
      expect(
        find.byKey(const ValueKey('workspace-actions-readme.md')),
        findsOneWidget,
      );
    });

    testWidgets('加载态：目录列表前显示 ActivityIndicator，到达后渲染列表', (tester) async {
      final api = FakeWorkspaceApi(
        directories: {
          '.': [buildEntry('a.txt')],
        },
      );
      api.fetchGate = Completer<void>();
      await pumpWorkspace(tester, api);

      expect(find.byType(CupertinoActivityIndicator), findsWidgets);

      api.fetchGate!.complete();
      await tester.pump();
      await tester.pump();
      expect(find.text('a.txt'), findsOneWidget);
    });

    testWidgets('空态：暂无文件 + 当前路径', (tester) async {
      await pumpWorkspace(tester, FakeWorkspaceApi());

      expect(find.text('暂无文件'), findsOneWidget);
    });

    testWidgets('错误态：加载失败展示错误信息 + 重试恢复', (tester) async {
      final api = FakeWorkspaceApi(
        directories: {
          '.': [buildEntry('a.txt')],
        },
      );
      api.fetchError = NetworkException(NetworkExceptionKind.cannotConnect);
      await pumpWorkspace(tester, api);

      expect(find.text('加载失败'), findsOneWidget);
      expect(find.textContaining('无法连接'), findsOneWidget);

      api.fetchError = null;
      await tester.tap(find.byKey(const ValueKey('workspace-retry')));
      await tester.pump();
      await tester.pump();

      expect(find.text('a.txt'), findsOneWidget);
      expect(find.text('加载失败'), findsNothing);
    });

    testWidgets('目录导航：点击目录行进入，面包屑跳转返回', (tester) async {
      final api = FakeWorkspaceApi(
        directories: {
          '.': [buildEntry('src', dir: true)],
          'src': [buildEntry('main.dart', size: 42)],
        },
      );
      await pumpWorkspace(tester, api);

      await tester.tap(find.text('src'));
      await tester.pump();
      await tester.pump();
      expect(find.text('main.dart'), findsOneWidget);
      // 面包屑出现 src（位置行与面包屑均显示路径文本，用 key 定位）
      expect(find.byKey(const ValueKey('workspace-crumb-src')), findsOneWidget);

      // 点击根目录面包屑返回
      await tester.tap(find.byKey(const ValueKey('workspace-crumb-.')));
      await tester.pump();
      await tester.pump();
      expect(find.text('main.dart'), findsNothing);
      expect(find.byKey(const ValueKey('workspace-crumb-src')), findsNothing);
      expect(find.text('src'), findsOneWidget);
    });

    testWidgets('上一级：进入子目录后点「上一级」返回', (tester) async {
      final api = FakeWorkspaceApi(
        directories: {
          '.': [buildEntry('src', dir: true)],
          'src': [buildEntry('main.dart')],
        },
      );
      await pumpWorkspace(tester, api);

      // 初始在根目录，「上一级」禁用
      var upButton = tester.widget<CupertinoButton>(
        find.byKey(const ValueKey('workspace-up')),
      );
      expect(upButton.onPressed, isNull);

      await tester.tap(find.text('src'));
      await tester.pump();
      await tester.pump();
      upButton = tester.widget<CupertinoButton>(
        find.byKey(const ValueKey('workspace-up')),
      );
      expect(upButton.onPressed, isNotNull);

      await tester.tap(find.byKey(const ValueKey('workspace-up')));
      await tester.pump();
      await tester.pump();
      expect(find.text('main.dart'), findsNothing);
      expect(find.text('src'), findsOneWidget);
    });

    testWidgets('行操作：文件行 ellipsis → 调出行菜单（下载/重命名/删除）', (tester) async {
      final api = FakeWorkspaceApi(
        directories: {
          '.': [buildEntry('a.txt')],
        },
      );
      await pumpWorkspace(tester, api);

      await tester.tap(find.byKey(const ValueKey('workspace-actions-a.txt')));
      await tester.pumpAndSettle();
      expect(find.text('下载'), findsOneWidget);
      expect(find.text('重命名'), findsOneWidget);
      expect(find.text('删除'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('workspace-action-cancel')));
      await tester.pumpAndSettle();
      expect(find.text('下载'), findsNothing);
    });

    testWidgets('下载：行菜单 → 下载 → 调 API → 提示字节数', (tester) async {
      final api = FakeWorkspaceApi(
        directories: {
          '.': [buildEntry('a.txt')],
        },
      );
      api.downloadBytes = Uint8List.fromList(List.filled(1024, 1));
      await pumpWorkspace(tester, api);

      await tester.tap(find.byKey(const ValueKey('workspace-actions-a.txt')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('workspace-action-download')));
      await tester.pumpAndSettle();

      expect(api.downloadCalls, ['s1|a.txt']);
      expect(find.text('提示'), findsOneWidget);
      expect(find.textContaining('1024'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('workspace-dialog-ok')));
      await tester.pumpAndSettle();
      expect(find.text('提示'), findsNothing);
    });

    testWidgets('删除：行菜单 → 删除 → 确认 → 移除行；取消不调 API', (tester) async {
      final api = FakeWorkspaceApi(
        directories: {
          '.': [buildEntry('a.txt'), buildEntry('b.txt')],
        },
      );
      await pumpWorkspace(tester, api);

      await tester.tap(find.byKey(const ValueKey('workspace-actions-a.txt')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('workspace-action-delete')));
      await tester.pumpAndSettle();
      expect(find.text('删除文件'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('workspace-delete-confirm')));
      await tester.pumpAndSettle();
      expect(api.deleteCalls, ['s1|a.txt']);
      expect(find.text('a.txt'), findsNothing);
      expect(find.text('b.txt'), findsOneWidget);
    });

    testWidgets('删除：取消不调 API', (tester) async {
      final api = FakeWorkspaceApi(
        directories: {
          '.': [buildEntry('a.txt')],
        },
      );
      await pumpWorkspace(tester, api);

      await tester.tap(find.byKey(const ValueKey('workspace-actions-a.txt')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('workspace-action-delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('workspace-delete-cancel')));
      await tester.pumpAndSettle();

      expect(api.deleteCalls, isEmpty);
      expect(find.text('a.txt'), findsOneWidget);
    });

    testWidgets('重命名：行菜单 → 重命名 → 输入新名 → 保存 → 调 API 更新行', (tester) async {
      final api = FakeWorkspaceApi(
        directories: {
          '.': [buildEntry('a.txt')],
        },
      );
      await pumpWorkspace(tester, api);

      await tester.tap(find.byKey(const ValueKey('workspace-actions-a.txt')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('workspace-action-rename')));
      await tester.pumpAndSettle();
      expect(find.text('重命名'), findsWidgets);

      await tester.enterText(
        find.byKey(const ValueKey('workspace-rename-field')),
        'b.txt',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('workspace-rename-save')));
      await tester.pumpAndSettle();

      expect(api.renameCalls, ['s1|a.txt|b.txt']);
      expect(find.text('b.txt'), findsOneWidget);
      expect(find.text('a.txt'), findsNothing);
    });

    testWidgets('上传：注入 picker → 点上传 → 调 API → 列表出现新文件', (tester) async {
      final api = FakeWorkspaceApi(
        directories: {
          '.': [buildEntry('a.txt')],
        },
      );
      await pumpWorkspace(
        tester,
        api,
        picker: () async => WorkspacePickedFile(
          name: 'upload.txt',
          bytes: Uint8List.fromList([1, 2, 3]),
        ),
      );

      await tester.tap(find.byKey(const ValueKey('workspace-upload')));
      await tester.pump();
      await tester.pump();

      expect(api.uploadCalls, ['s1|upload.txt|3']);
      expect(find.text('upload.txt'), findsOneWidget);
    });

    testWidgets('上传：picker 为 null → 提示「待接入」且不调 API', (tester) async {
      final api = FakeWorkspaceApi(
        directories: {
          '.': [buildEntry('a.txt')],
        },
      );
      await pumpWorkspace(tester, api);

      await tester.tap(find.byKey(const ValueKey('workspace-upload')));
      await tester.pumpAndSettle();

      expect(api.uploadCalls, isEmpty);
      expect(find.text('文件选择功能待接入'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('workspace-dialog-ok')));
      await tester.pumpAndSettle();
      expect(find.text('文件选择功能待接入'), findsNothing);
    });

    testWidgets('行操作失败：弹窗提示错误，点击「好」后关闭', (tester) async {
      final api = FakeWorkspaceApi(
        directories: {
          '.': [buildEntry('a.txt')],
        },
      );
      api.downloadError = HttpException(500, null, message: '下载服务不可用');
      await pumpWorkspace(tester, api);

      await tester.tap(find.byKey(const ValueKey('workspace-actions-a.txt')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('workspace-action-download')));
      await tester.pumpAndSettle();

      expect(find.text('操作失败'), findsOneWidget);
      // 错误同时显示在路径头横幅与弹窗中（2 处）
      expect(find.textContaining('下载服务不可用'), findsNWidgets(2));
      await tester.tap(find.byKey(const ValueKey('workspace-dialog-ok')));
      await tester.pumpAndSettle();
      expect(find.text('操作失败'), findsNothing);
    });

    testWidgets('预览：文本文件行菜单出现「预览」→ push FilePreviewPage', (tester) async {
      final api = FakeWorkspaceApi(
        directories: {
          '.': [buildEntry('readme.txt', size: 42)],
        },
      );
      api.fileContents['readme.txt'] = const FileResponse(
        content: 'hello preview',
        path: 'readme.txt',
        size: 13,
        lines: 1,
      );
      await pumpWorkspace(tester, api);

      await tester.tap(
        find.byKey(const ValueKey('workspace-actions-readme.txt')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('workspace-action-preview')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('workspace-action-preview')));
      await tester.pumpAndSettle();

      // FilePreviewPage 已进入（文本内容渲染）
      expect(api.fetchFileCalls, ['s1|readme.txt']);
      expect(find.byKey(const ValueKey('preview-scroll')), findsOneWidget);
      expect(find.text('hello preview'), findsOneWidget);
    });

    testWidgets('预览：视频文件行菜单同样出现「预览」', (tester) async {
      final api = FakeWorkspaceApi(
        directories: {
          '.': [const WorkspaceEntry(name: 'clip.mp4', path: 'clip.mp4', size: 12345)],
        },
      );
      api.downloadBytes = Uint8List.fromList(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
      await pumpWorkspace(tester, api);
      await tester.tap(find.byKey(const ValueKey('workspace-actions-clip.mp4')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('workspace-action-preview')),
        findsOneWidget,
      );
    });

    testWidgets('预览：归档文件不出现「预览」动作（直接下载）', (tester) async {
      final api = FakeWorkspaceApi(
        directories: {
          '.': [buildEntry('bundle.zip', size: 1024)],
        },
      );
      await pumpWorkspace(tester, api);

      await tester.tap(
        find.byKey(const ValueKey('workspace-actions-bundle.zip')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('workspace-action-preview')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('workspace-action-download')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('workspace-action-cancel')));
      await tester.pumpAndSettle();
    });

    testWidgets('目录打包下载：头部按钮 → /api/folder/download → 字节数提示', (tester) async {
      final api = FakeWorkspaceApi(
        directories: {
          '.': [buildEntry('a.txt')],
        },
      );
      api.downloadFolderBytes = Uint8List.fromList(List.filled(2048, 2));
      await pumpWorkspace(tester, api);

      await tester.tap(find.byKey(const ValueKey('workspace-download-folder')));
      await tester.pumpAndSettle();

      expect(api.downloadFolderCalls, ['s1|.']);
      expect(find.text('提示'), findsOneWidget);
      expect(find.textContaining('2048'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('workspace-dialog-ok')));
      await tester.pumpAndSettle();
      expect(find.text('提示'), findsNothing);
    });
  });
}
