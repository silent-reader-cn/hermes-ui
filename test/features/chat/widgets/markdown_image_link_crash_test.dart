// Regression tests for the vendored flutter_markdown patch
// (third_party/flutter_markdown, see PATCH_NOTES.md).
//
// Reproduces the "Bad state: Too many elements" crash reported when
// opening README files whose badges use [![alt](src)](href) — a
// link-wrapped block-level image leaves two inline elements on the
// builder stack when the package flushes at the block boundary.
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hermes_ui/features/chat/widgets/markdown_styles.dart';

const String _badgeMd =
    'Intro text\n\n[![CI](https://example.com/badge.svg)](https://example.com) '
    'tail text\n';

Widget _wrapMarkdown(
  String data, {
  // ignore: deprecated_member_use
  Widget Function(Uri, String?, String?)? imageBuilder,
}) {
  return CupertinoApp(
    home: CupertinoPageScaffold(
      child: SingleChildScrollView(
        child: Builder(
          builder: (BuildContext context) => MarkdownBody(
            data: data,
            selectable: true,
            styleSheet: buildAssistantMarkdownStyleSheet(context),
            builders: createAssistantMarkdownBuilders(
              context,
              imageBuilder: imageBuilder,
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('badge link [![alt](src)](href) renders without crash (chat config)',
      (WidgetTester tester) async {
    await tester.pumpWidget(_wrapMarkdown(
      _badgeMd,
      imageBuilder: (Uri uri, String? alt, String? title) =>
          const SizedBox(height: 40, child: FlutterLogo()),
    ));
    await tester.pump();
    expect(find.byType(MarkdownBody), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('full README.md renders without crash (chat config)',
      (WidgetTester tester) async {
    final readme = File('README.md').readAsStringSync();
    await tester.pumpWidget(_wrapMarkdown(
      readme,
      imageBuilder: (Uri uri, String? alt, String? title) =>
          const SizedBox(height: 40, child: FlutterLogo()),
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('bold-then-image paragraph renders without crash (chat config)',
      (WidgetTester tester) async {
    await tester.pumpWidget(_wrapMarkdown(
      '**Bold** intro ![pic](https://example.com/pic.png) tail\n',
      imageBuilder: (Uri uri, String? alt, String? title) =>
          const SizedBox(height: 40, child: FlutterLogo()),
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('package-default img path (no imageBuilder) stays intact',
      (WidgetTester tester) async {
    // File preview / memory use createAssistantMarkdownBuilders without an
    // imageBuilder — the patch must not disturb the default inline path.
    await tester.pumpWidget(_wrapMarkdown(
      '![alt](https://example.com/i.png) inline after image\n\n[![b](https://e.com/b.svg)](https://e.com)\n',
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byType(Image), findsWidgets);
  });

  testWidgets('plain text and badges degrade to readable output, not error UI',
      (WidgetTester tester) async {
    // Belt-and-braces: even if a future AST shape re-trips the builder,
    // the widget-layer fallback must render plain text instead of
    // propagating to the global error dialog.
    await tester.pumpWidget(_wrapMarkdown(
      _badgeMd,
      imageBuilder: (Uri uri, String? alt, String? title) =>
          const SizedBox(height: 40, child: FlutterLogo()),
    ));
    await tester.pump();
    final exception = tester.takeException();
    if (exception != null) {
      // Fallback path active: the crash must not escape the widget.
      fail('builder crash escaped MarkdownBody: $exception');
    }
    expect(find.byType(MarkdownBody), findsOneWidget);
  });
}
