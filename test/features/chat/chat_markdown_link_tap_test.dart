import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/models/chat_message.dart';
import 'package:hermes_ui/features/chat/widgets/chat_media_view.dart';
import 'package:hermes_ui/features/chat/widgets/message_bubble.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import '../../helpers/fake_media_cache.dart';
import 'chat_media_bubble_test.dart' show buildDownloadOverrides;

/// #57：聊天正文 markdown 链接（MEDIA 文件链接 / 网页链接）点击行为。
///
/// 根因回归：`MEDIA:` 转成的 `[📎 name](url)` 链接此前无任何 onTapLink 接线，
/// 渲染可看但点击无反应。本文件锁死：
/// 1. 非图片 MEDIA 链接点击 → 打开附件预览页（内含下载入口）；
/// 2. 图片 MEDIA 链接点击 → 打开 Lightbox；
/// 3. 无扩展名 http(s) 链接点击 → url_launcher 外部打开（mock 取证）；
/// 4. 带扩展名的 https 文件直链 → 应用内预览下载，不走浏览器。

class _MockUrlLauncher extends UrlLauncherPlatform {
  final List<String> launched = [];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launched.add(url);
    return true;
  }
}

Future<void> _pumpBubble(WidgetTester tester, ChatMessage message) async {
  final rig = buildFakeMediaCache();
  addTearDown(rig.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [...buildDownloadOverrides()],
      child: CupertinoApp(
        home: CupertinoPageScaffold(
          child: SingleChildScrollView(child: ChatMessageBubble(message: message)),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group('#57 聊天 markdown 链接点击', () {
    testWidgets('助手消息 MEDIA apk 链接：点击打开附件预览页并露出下载按钮', (
      tester,
    ) async {
      const message = ChatMessage(
        role: 'assistant',
        content: '打包完成：MEDIA:/builds/app-release.apk',
      );

      await _pumpBubble(tester, message);

      // 链接文本渲染
      final linkFinder = find.textContaining('📎 app-release.apk');
      expect(linkFinder, findsOneWidget);

      // 点击前无预览页
      expect(find.text('不支持预览'), findsNothing);

      await tester.tap(linkFinder);
      await tester.pumpAndSettle();

      // 预览页打开：非图片提示 + 下载按钮（测试环境 URL 不可解析 → 可见禁用态，
      // 但入口与文案必须存在，不再是点了没反应）
      expect(find.text('不支持预览'), findsOneWidget);
      expect(find.byType(AttachmentLightbox), findsOneWidget);
      expect(
        find.byKey(const ValueKey('attachment-download-button')),
        findsOneWidget,
      );
    });

    testWidgets('助手消息 MEDIA 图片链接：点击打开 Lightbox 大图', (
      tester,
    ) async {
      const message = ChatMessage(
        role: 'assistant',
        content: '看图：MEDIA:https://example.com/assets/banner.png',
      );

      await _pumpBubble(tester, message);

      // 图片 MEDIA 同时渲染内联图 + 链接文本（imageBuilder 与链接共存）
      final linkFinder = find.textContaining('banner.png').last;
      expect(linkFinder, findsOneWidget);

      await tester.tap(linkFinder);
      await tester.pumpAndSettle();

      expect(find.byType(AttachmentLightbox), findsOneWidget);
      // 图片态不显示「不支持预览」
      expect(find.text('不支持预览'), findsNothing);
    });

    testWidgets('无扩展名 http 链接：点击走 url_launcher 外部打开', (
      tester,
    ) async {
      final mock = _MockUrlLauncher();
      UrlLauncherPlatform.instance = mock;

      const message = ChatMessage(
        role: 'assistant',
        content: '详情见 [example site](https://example.com)。',
      );

      await _pumpBubble(tester, message);

      await tester.tap(find.textContaining('example site'));
      await tester.pumpAndSettle();

      expect(mock.launched, contains('https://example.com'));
      // 不应打开应用内预览页
      expect(find.byType(AttachmentLightbox), findsNothing);
    });

    testWidgets('带扩展名的 https 文件直链：点击走应用内预览下载而非浏览器', (
      tester,
    ) async {
      final mock = _MockUrlLauncher();
      UrlLauncherPlatform.instance = mock;

      const message = ChatMessage(
        role: 'assistant',
        content: '直链：[apk](https://example.com/files/app-release.apk)',
      );

      await _pumpBubble(tester, message);

      await tester.tap(find.textContaining('apk'));
      await tester.pumpAndSettle();

      expect(mock.launched, isEmpty);
      expect(find.byType(AttachmentLightbox), findsOneWidget);
    });
  });
}
