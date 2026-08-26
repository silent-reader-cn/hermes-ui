import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/connections/server_connection.dart';
import 'package:hermes_ui/core/models/chat_message.dart';
import 'package:hermes_ui/core/models/message_attachment.dart';
import 'package:hermes_ui/features/chat/widgets/chat_media_view.dart';
import 'package:hermes_ui/features/chat/widgets/message_bubble.dart';

import '../../helpers/fake_media_cache.dart';

// 1x1 像素有效透明 PNG base64 数据
const _k1x1Png =
    'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';

class _FakeActiveConnectionController extends ActiveConnectionController {
  _FakeActiveConnectionController(this._initial);
  final ServerConnection? _initial;
  @override
  ServerConnection? build() => _initial;
}

/// 包一层 ProviderScope：ChatInlineMediaWidget 已是 ConsumerWidget，且网络图
/// 经 MediaCacheService（provider）取数。构造默认的假媒体缓存（下载抛错
/// → 渲染占位），需要成功场景时传 `rig`。
Widget _testApp(Widget home, {FakeMediaCacheRig? rig}) {
  final service = (rig ?? buildFakeMediaCache()).service;
  return ProviderScope(
    overrides: [mediaCacheOverride(service)],
    child: CupertinoApp(home: CupertinoPageScaffold(child: home)),
  );
}

/// 让真实异步（drift / 文件 IO / 下载回调）在 widget 测试中完成：
/// FakeAsync 下 `pumpAndSettle` 会被无限转圈的加载指示器卡住，且真实 IO
/// 不会推进；用 `tester.runAsync` 放行真实事件循环后 pump 一帧即可。
Future<void> _settleMediaAsync(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 300)),
  );
  await tester.pump();
}

void main() {
  group('ChatMessageBubble 媒体标记与附件内联渲染 Widget 测试', () {
    testWidgets('助手消息 MEDIA: data:image 渲染为内联 Image.memory', (tester) async {
      final rig = buildFakeMediaCache();
      addTearDown(rig.dispose);
      const message = ChatMessage(
        role: 'assistant',
        content: '这是渲染好的图片：MEDIA:$_k1x1Png 很好。',
      );

      await tester.pumpWidget(
        _testApp(const ChatMessageBubble(message: message)),
      );
      await tester.pump();

      expect(find.byType(ChatInlineMediaWidget), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
      expect(
        tester.widget<Image>(find.byType(Image)).image,
        isA<MemoryImage>(),
      );
      expect(find.textContaining('很好。'), findsOneWidget);
    });

    testWidgets('助手消息 MEDIA: 网络图片 URL 渲染 ChatInlineMediaWidget', (
      tester,
    ) async {
      final rig = buildFakeMediaCache();
      addTearDown(rig.dispose);
      const message = ChatMessage(
        role: 'assistant',
        content: '请查看：MEDIA:https://example.com/assets/banner.png',
      );

      await tester.pumpWidget(
        _testApp(
          const ChatMessageBubble(
            message: message,
            baseUrl: 'http://localhost:30002',
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(ChatInlineMediaWidget), findsOneWidget);
    });

    testWidgets('ChatInlineMediaWidget 图片加载失败时显示占位符，不白屏且展示 Cupertino 错误提示', (
      tester,
    ) async {
      final rig = buildFakeMediaCache();
      addTearDown(rig.dispose);
      await tester.pumpWidget(
        _testApp(
          const ChatInlineMediaWidget(
            rawUri: 'data:image/png;base64,INVALID_BASE64_CORRUPTED_DATA',
            alt: 'corrupted.png',
          ),
        ),
      );
      await tester.pump();

      expect(find.text('图片加载失败'), findsOneWidget);
      expect(find.text('corrupted.png'), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.photo), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('助手消息音频/视频/文档 MEDIA: 标记转换为对应链接芯片', (tester) async {
      final rig = buildFakeMediaCache();
      addTearDown(rig.dispose);
      const message = ChatMessage(
        role: 'assistant',
        content: '音频：MEDIA:/tmp/audio.mp3\n\n文档：MEDIA:/tmp/spec.pdf',
      );

      await tester.pumpWidget(
        _testApp(const ChatMessageBubble(message: message)),
      );
      await tester.pump();

      expect(find.textContaining('🎵 audio.mp3'), findsOneWidget);
      expect(find.textContaining('📎 spec.pdf'), findsOneWidget);
    });

    testWidgets('用户消息附件展示 ChatAttachmentChipView 与图标', (tester) async {
      final rig = buildFakeMediaCache();
      addTearDown(rig.dispose);
      const message = ChatMessage(
        role: 'user',
        content: '你好',
        attachments: [
          MessageAttachment(name: 'photo.jpg', isImage: true),
          MessageAttachment(name: 'report.pdf', isImage: false),
        ],
      );

      await tester.pumpWidget(
        _testApp(const ChatMessageBubble(message: message)),
      );
      await tester.pump();

      expect(find.text('photo.jpg'), findsOneWidget);
      expect(find.text('report.pdf'), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.photo), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.doc_text), findsOneWidget);
    });

    testWidgets('用户消息尾部 [Attached files: ...] 标记被剥离，附件正常渲染', (tester) async {
      final rig = buildFakeMediaCache();
      addTearDown(rig.dispose);
      final message = ChatMessage.fromJson(const {
        'role': 'user',
        'content': '发送此文件\n\n[Attached files: /tmp/invoice.pdf]',
      });

      await tester.pumpWidget(_testApp(ChatMessageBubble(message: message)));
      await tester.pump();

      expect(find.text('发送此文件'), findsOneWidget);
      expect(find.textContaining('[Attached files:'), findsNothing);
      expect(find.text('invoice.pdf'), findsOneWidget);
    });

    testWidgets('点击内联图片可弹出全屏查看器（Lightbox）且可点击关闭', (tester) async {
      final rig = buildFakeMediaCache();
      addTearDown(rig.dispose);
      await tester.pumpWidget(
        _testApp(
          const ChatInlineMediaWidget(rawUri: _k1x1Png, title: 'preview.png'),
        ),
      );
      await tester.pump();

      final imgFinder = find.byType(ChatInlineMediaWidget);
      expect(imgFinder, findsOneWidget);

      await tester.tap(imgFinder);
      await tester.pumpAndSettle();

      // 验证弹出全屏 Lightbox
      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.clear_thick), findsOneWidget);

      // 点击关闭
      await tester.tap(find.byIcon(CupertinoIcons.clear_thick));
      await tester.pumpAndSettle();

      expect(find.byType(InteractiveViewer), findsNothing);
    });

    testWidgets('ProviderScope 激活连接 baseUrl 正确注入到媒体组件', (tester) async {
      final rig = buildFakeMediaCache();
      addTearDown(rig.dispose);
      final conn = ServerConnection(
        id: 'conn_1',
        name: 'Dev Server',
        baseUrl: 'http://hermes.example.com:30002',
        createdAt: DateTime(2026),
      );

      const message = ChatMessage(
        role: 'assistant',
        content: 'MEDIA:/var/data/output.png',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            activeConnectionProvider.overrideWith(
              () => _FakeActiveConnectionController(conn),
            ),
            mediaCacheOverride(rig.service),
          ],
          child: const CupertinoApp(
            home: CupertinoPageScaffold(
              child: ChatMessageBubble(message: message),
            ),
          ),
        ),
      );
      await tester.pump();

      final widgetFinder = find.byType(ChatInlineMediaWidget);
      expect(widgetFinder, findsOneWidget);
      final inlineWidget = tester.widget<ChatInlineMediaWidget>(widgetFinder);
      expect(inlineWidget.baseUrl, 'http://hermes.example.com:30002');
    });

    // ── P2 媒体缓存渲染切换：网络图经 MediaCacheService 落盘 → Image.file ──
    // 说明：MediaCacheService 的命中/下载/淘汰逻辑已在单测全覆盖；此处直接
    // override mediaFileProvider 验证渲染切换（成功→Image.file / 失败→占位），
    // 避免 FakeAsync 下真实 drift+文件 IO 的不确定性。
    testWidgets('网络图片成功下载后渲染为 Image.file', (tester) async {
      // 真实 PNG 临时文件，供 Image.file 解码。
      final pngFile = File(
        '${Directory.systemTemp.path}${Platform.pathSeparator}hermex_net_success.png',
      );
      await tester.runAsync(
        () => pngFile.writeAsBytes(base64Decode(_k1x1Png.split(',').last)),
      );
      addTearDown(() async {
        try {
          await pngFile.delete();
        } on FileSystemException {
          // ignore
        }
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            mediaFileProvider.overrideWith((ref, url) async => pngFile),
          ],
          child: const CupertinoApp(
            home: CupertinoPageScaffold(
              child: ChatInlineMediaWidget(
                rawUri: 'https://example.com/assets/banner.png',
                alt: 'banner.png',
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      final image = tester.widget<Image>(find.byType(Image));
      expect(image.image, isA<FileImage>());
      expect((image.image as FileImage).file.path, pngFile.path);
      expect(find.text('图片加载失败'), findsNothing);
    });

    testWidgets('网络图片下载失败（非 2xx/网络错）渲染为失败占位符', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            mediaFileProvider.overrideWith(
              (ref, url) async => throw StateError('401 for test'),
            ),
          ],
          child: const CupertinoApp(
            home: CupertinoPageScaffold(
              child: ChatInlineMediaWidget(
                rawUri: 'https://example.com/assets/secret.png',
                alt: 'secret.png',
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('图片加载失败'), findsOneWidget);
      expect(find.text('secret.png'), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.photo), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('本地 file:// 路径分支仍走 Image.file（不经媒体缓存）', (tester) async {
      final rig = buildFakeMediaCache();
      addTearDown(rig.dispose);
      // 构造一个真实存在的临时 PNG 文件，作为本地 file:// 引用。
      // 真实文件 IO 在 FakeAsync 下不会推进，须经 runAsync 完成。
      final tmpFile = File(
        '${Directory.systemTemp.path}${Platform.pathSeparator}hermex_local_test.png',
      );
      await tester.runAsync(
        () => tmpFile.writeAsBytes(base64Decode(_k1x1Png.split(',').last)),
      );
      addTearDown(() async {
        try {
          await tmpFile.delete();
        } on FileSystemException {
          // ignore
        }
      });

      await tester.pumpWidget(
        _testApp(ChatInlineMediaWidget(rawUri: tmpFile.path)),
      );
      await _settleMediaAsync(tester);

      final image = tester.widget<Image>(find.byType(Image));
      expect(image.image, isA<FileImage>());
    });
  });
}
