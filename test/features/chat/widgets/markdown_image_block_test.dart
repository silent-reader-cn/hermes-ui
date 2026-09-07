import 'package:flutter/cupertino.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/features/chat/widgets/markdown_styles.dart';

Future<void> _pumpMarkdown(
  WidgetTester tester,
  String data, {
  required ValueChanged<Uri> onImage,
}) async {
  var imageIndex = 0;
  await tester.pumpWidget(
    CupertinoApp(
      home: Builder(
        builder: (context) => CupertinoPageScaffold(
          child: MarkdownBody(
            data: data,
            builders: createAssistantMarkdownBuilders(
              context,
              imageBuilder: (uri, title, alt) {
                onImage(uri);
                final index = imageIndex++;
                return Container(
                  key: ValueKey('img-block-$index'),
                  width: 100,
                  height: 50,
                  color: CupertinoColors.activeBlue,
                );
              },
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}


Finder _findImgBlocks() => find.byWidgetPredicate(
      (w) => w.key is ValueKey<String> &&
          (w.key! as ValueKey<String>).value.startsWith('img-block-'),
    );

void main() {
  group('#91 图片块级化渲染（img 不与文字同行镶嵌）', () {
    testWidgets('行中图片独立成块：前后文字成为独立文本块', (tester) async {
      final uris = <Uri>[];
      // 图片嵌在句子中间（无换行）——旧渲染下图片与文字同 Wrap 行。
      await _pumpMarkdown(
        tester,
        '看这张图![图](https://example.com/a.png)很好看',
        onImage: uris.add,
      );

      expect(uris, hasLength(1));
      expect(uris.first.toString(), 'https://example.com/a.png');
      // 图片块存在
      expect(_findImgBlocks(), findsOneWidget);
      // 前后文字被拆为独立块（flush 为匿名块）而非同一段富文本
      expect(find.text('看这张图'), findsOneWidget);
      expect(find.text('很好看'), findsOneWidget);
    });

    testWidgets('行首/独立段落图片不产生重复空行块', (tester) async {
      final uris = <Uri>[];
      // 图片在行首（前面无文字）
      await _pumpMarkdown(
        tester,
        '![图](https://example.com/a.png)',
        onImage: uris.add,
      );

      expect(uris, hasLength(1));
      expect(_findImgBlocks(), findsOneWidget);
      // 无空文本块：页面中不应存在空字符串 Text
      final emptyTexts = tester.widgetList<Text>(
        find.text(''),
      );
      expect(emptyTexts, isEmpty);
    });

    testWidgets('连续两张图片各自独立成块纵向排列', (tester) async {
      final uris = <Uri>[];
      await _pumpMarkdown(
        tester,
        '![一](https://example.com/1.png)\n![二](https://example.com/2.png)',
        onImage: uris.add,
      );

      expect(uris, hasLength(2));
      expect(_findImgBlocks(), findsNWidgets(2));
      // 两图纵向排列（y 不重叠）
      final top = tester.getTopLeft(_findImgBlocks().first);
      final bottom =
          tester.getTopLeft(_findImgBlocks().last);
      expect(bottom.dy, greaterThanOrEqualTo(top.dy + 50));
    });

    testWidgets('未提供 imageBuilder 时不注册 img builder（memory/预览场景保持默认）',
        (tester) async {
      late BuildContext captured;
      await tester.pumpWidget(
        CupertinoApp(
          home: Builder(
            builder: (context) {
              captured = context;
              return const CupertinoPageScaffold(child: SizedBox.shrink());
            },
          ),
        ),
      );

      final builders = createAssistantMarkdownBuilders(captured);
      expect(builders.containsKey('img'), isFalse);
      expect(builders.containsKey('code'), isTrue);

      final withImage = createAssistantMarkdownBuilders(
        captured,
        imageBuilder: (uri, title, alt) => const SizedBox.shrink(),
      );
      expect(withImage.containsKey('img'), isTrue);
    });
  });
}
