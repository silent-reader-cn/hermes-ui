import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/features/chat/widgets/chat_media_view.dart';

import '../../helpers/fake_download_service.dart';

/// 1x1 透明 PNG（widget 测试用位图）。
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

Future<void> _pumpLightbox(
  WidgetTester tester, {
  Uint8List? bytes,
  String? resolvedUrl,
  String? name,
  String? altText,
  bool isImage = false,
  String? sessionId,
  int? expectedBytes,
  String? mimeType,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(
          ApiClient(baseUrl: 'http://test.local:30002'),
        ),
        ...createDownloadTestOverrides(),
      ],
      child: CupertinoApp(
        home: AttachmentLightbox(
          bytes: bytes,
          resolvedUrl: resolvedUrl,
          name: name,
          altText: altText,
          isImage: isImage,
          sessionId: sessionId,
          expectedBytes: expectedBytes,
          mimeType: mimeType,
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  group('聊天附件预览复用工作区文件预览', () {
    testWidgets('PDF 附件预览：进入 PDF 分支，不出现不支持预览兜底', (tester) async {
      // pdfrx 依赖 native pdfium 动态链接库，在 flutter_test 环境中无法真实渲染 PDF 页面。
      // 断言正确路由至 PDF 预览分支（而非 previewUnsupported 兜底）：
      // 允许停留在加载状态、preview-pdf 容器或 pdfium 失败兜底，但绝不出现「不支持预览」。
      final pdfHeader = Uint8List.fromList(const [0x25, 0x50, 0x44, 0x46]);
      await _pumpLightbox(tester, name: '报告.pdf', bytes: pdfHeader);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();

      expect(find.text('不支持预览'), findsNothing);
      final hasLoading = find
          .byType(CupertinoActivityIndicator)
          .evaluate()
          .isNotEmpty;
      final hasPdfViewer = find
          .byKey(const ValueKey('preview-pdf'))
          .evaluate()
          .isNotEmpty;
      final hasFallback = find
          .byKey(const ValueKey('preview-download-fallback'))
          .evaluate()
          .isNotEmpty;
      expect(hasLoading || hasPdfViewer || hasFallback, isTrue);
    });

    testWidgets('Office 附件预览：docx 字节渲染富文本与表格，显示 preview-office-docx', (
      tester,
    ) async {
      final bytes = File('test/fixtures/office/sample.docx').readAsBytesSync();
      await _pumpLightbox(tester, name: '纪要.docx', bytes: bytes);

      expect(find.byKey(const ValueKey('preview-office-docx')), findsOneWidget);
      expect(find.textContaining('项目周报 Report 周三'), findsOneWidget);
      expect(find.text('不支持预览'), findsNothing);
    });

    testWidgets('文本附件预览：txt 字节渲染 SelectableText，显示 preview-text', (
      tester,
    ) async {
      final bytes = Uint8List.fromList(utf8.encode('你好'));
      await _pumpLightbox(tester, name: '说明.txt', bytes: bytes);

      expect(find.byKey(const ValueKey('preview-text')), findsOneWidget);
      expect(find.text('你好'), findsOneWidget);
      expect(find.text('不支持预览'), findsNothing);
    });

    testWidgets('归档/不支持格式：维持现状兜底展示「不支持预览」与下载按钮', (tester) async {
      await _pumpLightbox(
        tester,
        name: 'app.zip',
        bytes: Uint8List.fromList([1, 2, 3]),
      );

      expect(find.text('不支持预览'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('attachment-download-button')),
        findsOneWidget,
      );
    });

    testWidgets('图片附件预览：isImage=true 维持 InteractiveViewer 原链路不动', (
      tester,
    ) async {
      await _pumpLightbox(
        tester,
        name: 'photo.png',
        bytes: kPngBytes,
        isImage: true,
      );

      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(find.text('不支持预览'), findsNothing);
      expect(
        find.byKey(const ValueKey('attachment-download-button')),
        findsOneWidget,
      );
    });

    testWidgets('音视频附件预览：mp4 附件进入视频分支非兜底', (tester) async {
      await _pumpLightbox(tester, name: 'movie.mp4', bytes: kPngBytes);
      expect(find.text('不支持预览'), findsNothing);
    });

    testWidgets('回归（真机报障）：预览失败页只有一个重试，下载按钮唯一且钉在导航栏右上角', (tester) async {
      // PDF 附件 + 空字节、无 URL → loadBytes 直接返回空 → pdf 分支
      // bytes.isEmpty 置 _loadError → 失败兜底卡（零网络 IO，确定性）。
      await _pumpLightbox(
        tester,
        name: 'resume_broken.pdf',
        bytes: Uint8List(0),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();

      // 失败卡出现。
      expect(find.text('加载失败'), findsOneWidget);
      // 「重试」文案只允许出现 1 次（曾出现 兜底重试+兜底内下载钮重试态
      // +底部下载钮 = 3 个重试的回归）。
      expect(find.text('重试'), findsOneWidget);
      // 下载按钮全页唯一实例，且位于顶部导航条区域（y < 60）。
      final dl = find.byKey(const ValueKey('attachment-download-button'));
      expect(dl, findsOneWidget);
      expect(tester.getCenter(dl).dy, lessThan(60));
    });
  });
}
