import 'package:flutter/cupertino.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermex_flutter/app/theme/status_colors.dart';

void main() {
  group('secondaryText 暗黑与浅色模式解析回归测试', () {
    testWidgets('dark: Text widget secondaryText resolveFrom painted color == 0x99EBEBF5', (
      tester,
    ) async {
      await tester.pumpWidget(
        CupertinoApp(
          theme: const CupertinoThemeData(brightness: Brightness.dark),
          home: Builder(
            builder: (context) => Center(
              child: Text(
                'x',
                style: TextStyle(color: secondaryText.resolveFrom(context)),
              ),
            ),
          ),
        ),
      );
      final renderParagraph = tester.renderObject<RenderParagraph>(
        find.text('x'),
      );
      expect(renderParagraph.text.style!.color!.toARGB32(), 0x99EBEBF5);
    });

    testWidgets('light: Text widget secondaryText resolveFrom painted color == 0x993C3C43', (
      tester,
    ) async {
      await tester.pumpWidget(
        CupertinoApp(
          theme: const CupertinoThemeData(brightness: Brightness.light),
          home: Builder(
            builder: (context) => Center(
              child: Text(
                'x',
                style: TextStyle(color: secondaryText.resolveFrom(context)),
              ),
            ),
          ),
        ),
      );
      final renderParagraph = tester.renderObject<RenderParagraph>(
        find.text('x'),
      );
      expect(renderParagraph.text.style!.color!.toARGB32(), 0x993C3C43);
    });

    test('secondaryText darkColor and darkHighContrastColor 对齐 secondaryLabel', () {
      expect(
        secondaryText.darkColor.toARGB32(),
        CupertinoColors.secondaryLabel.darkColor.toARGB32(),
      );
      expect(
        secondaryText.darkHighContrastColor.toARGB32(),
        CupertinoColors.secondaryLabel.darkHighContrastColor.toARGB32(),
      );
      expect(secondaryText.darkColor.toARGB32(), 0x99EBEBF5);
      expect(secondaryText.darkHighContrastColor.toARGB32(), 0xADEBEBF5);
    });
  });
}
