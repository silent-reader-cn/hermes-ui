import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/api/api_exception.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/models/workspace.dart';
import 'package:hermes_ui/features/workspace_manager/file_preview_page.dart';
import 'package:hermes_ui/features/workspace/workspace_providers.dart';

import '../../helpers/fake_download_service.dart';
import '../../helpers/fake_workspace_api.dart';

/// 1x1 透明 PNG（widget 测试用可解码位图）。
final Uint8List kPngBytes = Uint8List.fromList(const [
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0D,
  0x0A,
  0x2D,
  0xB4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
]);

WorkspaceEntry entry(String name) => WorkspaceEntry(name: name, path: name);

/// 组装 FilePreviewPage（注入 fake workspace API）。
Future<void> pumpPreview(
  WidgetTester tester,
  FakeWorkspaceApi api,
  WorkspaceEntry file,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(
          ApiClient(baseUrl: 'http://test.local:30002'),
        ),
        workspaceApiFactoryProvider.overrideWithValue((_) => api),
        ...createDownloadTestOverrides(),
      ],
      child: CupertinoApp(
        home: FilePreviewPage(sessionId: 's1', entry: file),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  group('文件类型判定', () {
    test('扩展名白名单路由', () {
      expect(workspaceFileKindOf(entry('a.dart')), WorkspaceFileKind.text);
      expect(workspaceFileKindOf(entry('README.md')), WorkspaceFileKind.text);
      expect(workspaceFileKindOf(entry('pic.png')), WorkspaceFileKind.image);
      expect(workspaceFileKindOf(entry('movie.mp4')), WorkspaceFileKind.video);
      expect(workspaceFileKindOf(entry('song.mp3')), WorkspaceFileKind.audio);
      expect(workspaceFileKindOf(entry('book.pdf')), WorkspaceFileKind.pdf);
      expect(workspaceFileKindOf(entry('app.zip')), WorkspaceFileKind.archive);
      expect(workspaceFileKindOf(entry('noext')), WorkspaceFileKind.other);
      expect(workspaceFileIsPreviewable(entry('a.dart')), isTrue);
      expect(workspaceFileIsPreviewable(entry('pic.png')), isTrue);
      expect(workspaceFileIsPreviewable(entry('movie.mp4')), isTrue);
      expect(workspaceFileIsPreviewable(entry('song.mp3')), isTrue);
      expect(workspaceFileIsPreviewable(entry('app.zip')), isFalse);
    });
  });

  group('FilePreviewPage widget', () {
    testWidgets('文本预览：渲染内容 + 大小/行数元信息', (tester) async {
      final api = FakeWorkspaceApi();
      api.fileContents['pubspec.yaml'] = const FileResponse(
        content: 'name: hermes_ui\nversion: 1.0.0',
        path: 'pubspec.yaml',
        size: 36,
        lines: 2,
      );
      await pumpPreview(tester, api, entry('pubspec.yaml'));

      expect(api.fetchFileCalls, ['s1|pubspec.yaml']);
      expect(find.textContaining('name: hermes_ui'), findsOneWidget);
      expect(find.textContaining('36 B'), findsOneWidget);
      expect(find.textContaining('2 行'), findsOneWidget);
    });

    testWidgets('文本预览（空文件）：显示空文件占位', (tester) async {
      final api = FakeWorkspaceApi();
      api.fileContents['empty.txt'] = const FileResponse(content: '');
      await pumpPreview(tester, api, entry('empty.txt'));

      expect(find.text('（空文件）'), findsOneWidget);
    });

    testWidgets('Markdown 富渲染：.md 走 MarkdownBody', (tester) async {
      final api = FakeWorkspaceApi();
      api.fileContents['README.md'] = const FileResponse(
        content: '# Title\n\nsome **bold** text',
        size: 30,
        lines: 3,
      );
      await pumpPreview(tester, api, entry('README.md'));

      expect(find.byKey(const ValueKey('preview-markdown')), findsOneWidget);
      expect(find.byType(MarkdownBody), findsOneWidget);
    });

    testWidgets('图片预览：raw 字节 → Image.memory', (tester) async {
      final api = FakeWorkspaceApi()..downloadBytes = kPngBytes;
      await pumpPreview(tester, api, entry('pic.png'));

      expect(
        find.byKey(const ValueKey('preview-image'), skipOffstage: false),
        findsOneWidget,
      );
      final image = tester.widget<Image>(
        find.byKey(const ValueKey('preview-image'), skipOffstage: false),
      );
      expect(image.image, isA<MemoryImage>());
      expect((image.image as MemoryImage).bytes, same(kPngBytes));
      // 回归（真机反馈 bug）：InteractiveViewer 视口必须铺满剩余空间，
      // 不能被小图收缩（否则放大内容被内部 ClipRect 裁回小框）。
      final viewerSize = tester.getSize(
        find.byKey(const ValueKey('preview-image-viewer')),
      );
      expect(viewerSize.width, 800);
      expect(viewerSize.height, greaterThan(400));
    });

    testWidgets('归档/未知类型：无法预览提示 + 下载兜底按钮', (tester) async {
      final api = FakeWorkspaceApi();
      await pumpPreview(tester, api, entry('bundle.zip'));

      expect(find.text('无法预览该文件'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('preview-download-fallback')),
        findsOneWidget,
      );
    });

    testWidgets('加载失败：错误详情 + 重试恢复', (tester) async {
      final api = FakeWorkspaceApi()
        ..fetchFileError = HttpException(404, null, message: 'Not a file');
      await pumpPreview(tester, api, entry('missing.txt'));

      expect(find.text('加载失败'), findsOneWidget);
      expect(find.text('Not a file'), findsOneWidget);

      api.fetchFileError = null;
      api.fileContents['missing.txt'] = const FileResponse(
        content: 'recovered',
        size: 8,
        lines: 1,
      );
      await tester.tap(find.byKey(const ValueKey('preview-retry')));
      await tester.pumpAndSettle();
      expect(find.text('recovered'), findsOneWidget);
    });

    testWidgets('下载：导航栏下载按钮 → 确认后入队下载中心', (tester) async {
      final api = FakeWorkspaceApi()..downloadBytes = kPngBytes;
      await pumpPreview(tester, api, entry('pic.png'));

      await tester.tap(find.byKey(const ValueKey('preview-download')));
      await tester.pumpAndSettle();

      expect(find.text('下载文件'), findsOneWidget);
      expect(find.text('pic.png'), findsWidgets);
      expect(find.text('开始下载'), findsOneWidget);

      await tester.tap(find.text('开始下载'));
      await tester.pumpAndSettle();

      expect(find.text('下载文件'), findsNothing);
    });

    testWidgets('音视频预览：video/audio 进入可预览分支（非兜底）', (tester) async {
      final api = FakeWorkspaceApi()..downloadBytes = kPngBytes;
      await pumpPreview(tester, api, entry('movie.mp4'));
      expect(find.byKey(const ValueKey('preview-scroll')), findsOneWidget);
      expect(find.text('无法预览该文件'), findsNothing);
    });

    testWidgets('不可预览文件兜底：下载按钮弹出确认框并入队下载中心', (tester) async {
      final api = FakeWorkspaceApi()
        ..fetchFileError = HttpException(404, null, message: 'gone');
      await pumpPreview(tester, api, entry('x.bin'));

      await tester.tap(find.byKey(const ValueKey('preview-download-fallback')));
      await tester.pumpAndSettle();

      expect(find.text('下载文件'), findsOneWidget);
      expect(find.text('x.bin'), findsWidgets);
      expect(find.text('开始下载'), findsOneWidget);

      await tester.tap(find.text('开始下载'));
      await tester.pumpAndSettle();

      expect(find.text('下载文件'), findsNothing);
    });
  });
}
