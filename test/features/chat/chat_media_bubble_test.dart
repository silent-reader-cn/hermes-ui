import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermex_flutter/core/connections/connection_providers.dart';
import 'package:hermex_flutter/core/connections/server_connection.dart';
import 'package:hermex_flutter/core/models/chat_message.dart';
import 'package:hermex_flutter/core/models/message_attachment.dart';
import 'package:hermex_flutter/features/chat/widgets/chat_media_view.dart';
import 'package:hermex_flutter/features/chat/widgets/message_bubble.dart';

// 1x1 像素有效透明 PNG base64 数据
const _k1x1Png =
    'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';

class _FakeActiveConnectionController extends ActiveConnectionController {
  _FakeActiveConnectionController(this._initial);
  final ServerConnection? _initial;
  @override
  ServerConnection? build() => _initial;
}

void main() {
  group('ChatMessageBubble 媒体标记与附件内联渲染 Widget 测试', () {
    testWidgets('助手消息 MEDIA: data:image 渲染为内联 Image.memory', (tester) async {
      const message = ChatMessage(
        role: 'assistant',
        content: '这是渲染好的图片：MEDIA:$_k1x1Png 很好。',
      );

      await tester.pumpWidget(
        const CupertinoApp(
          home: CupertinoPageScaffold(
            child: ChatMessageBubble(message: message),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(ChatInlineMediaWidget), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
      expect(find.textContaining('很好。'), findsOneWidget);
    });

    testWidgets('助手消息 MEDIA: 网络图片 URL 渲染 ChatInlineMediaWidget', (tester) async {
      const message = ChatMessage(
        role: 'assistant',
        content: '请查看：MEDIA:https://example.com/assets/banner.png',
      );

      await tester.pumpWidget(
        const CupertinoApp(
          home: CupertinoPageScaffold(
            child: ChatMessageBubble(
              message: message,
              baseUrl: 'http://localhost:30002',
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(ChatInlineMediaWidget), findsOneWidget);
    });

    testWidgets('ChatInlineMediaWidget 图片加载失败时显示占位符，不白屏且展示 Cupertino 错误提示', (
      tester,
    ) async {
      await tester.pumpWidget(
        const CupertinoApp(
          home: CupertinoPageScaffold(
            child: ChatInlineMediaWidget(
              rawUri: 'data:image/png;base64,INVALID_BASE64_CORRUPTED_DATA',
              alt: 'corrupted.png',
            ),
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
      const message = ChatMessage(
        role: 'assistant',
        content: '音频：MEDIA:/tmp/audio.mp3\n\n文档：MEDIA:/tmp/spec.pdf',
      );

      await tester.pumpWidget(
        const CupertinoApp(
          home: CupertinoPageScaffold(
            child: ChatMessageBubble(message: message),
          ),
        ),
      );
      await tester.pump();

      expect(find.textContaining('🎵 audio.mp3'), findsOneWidget);
      expect(find.textContaining('📎 spec.pdf'), findsOneWidget);
    });

    testWidgets('用户消息附件展示 ChatAttachmentChipView 与图标', (tester) async {
      const message = ChatMessage(
        role: 'user',
        content: '你好',
        attachments: [
          MessageAttachment(name: 'photo.jpg', isImage: true),
          MessageAttachment(name: 'report.pdf', isImage: false),
        ],
      );

      await tester.pumpWidget(
        const CupertinoApp(
          home: CupertinoPageScaffold(
            child: ChatMessageBubble(message: message),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('photo.jpg'), findsOneWidget);
      expect(find.text('report.pdf'), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.photo), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.doc_text), findsOneWidget);
    });

    testWidgets('用户消息尾部 [Attached files: ...] 标记被剥离，附件正常渲染', (tester) async {
      final message = ChatMessage.fromJson(const {
        'role': 'user',
        'content': '发送此文件\n\n[Attached files: /tmp/invoice.pdf]',
      });

      await tester.pumpWidget(
        CupertinoApp(
          home: CupertinoPageScaffold(
            child: ChatMessageBubble(message: message),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('发送此文件'), findsOneWidget);
      expect(find.textContaining('[Attached files:'), findsNothing);
      expect(find.text('invoice.pdf'), findsOneWidget);
    });

    testWidgets('点击内联图片可弹出全屏查看器（Lightbox）且可点击关闭', (tester) async {
      await tester.pumpWidget(
        const CupertinoApp(
          home: CupertinoPageScaffold(
            child: ChatInlineMediaWidget(
              rawUri: _k1x1Png,
              title: 'preview.png',
            ),
          ),
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
  });
}
