import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/app/theme/cupertino_theme.dart';
import 'package:hermes_ui/features/onboarding/widgets/onboarding_hero_motion.dart';
import 'package:hermes_ui/features/onboarding/widgets/wide_dual_pane.dart';

const _slogan = '随时随地的自建 AI 智能体助手';
const _form = ColoredBox(
  key: ValueKey('form-probe'),
  color: Color(0xFFF8F8FA),
  child: Center(child: Text('Form')),
);

Future<void> _pumpPane(
  WidgetTester tester, {
  Brightness brightness = Brightness.light,
  bool disableAnimations = false,
  bool ticking = true,
  double textScale = 1,
  Size size = const Size(1280, 800),
  bool useDualPane = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    CupertinoApp(
      theme: buildCupertinoTheme(brightness),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations: disableAnimations,
          textScaler: TextScaler.linear(textScale),
        ),
        child: TickerMode(enabled: ticking, child: child!),
      ),
      home: RepaintBoundary(
        key: const ValueKey('pane-capture'),
        child: CupertinoPageScaffold(
          child: useDualPane ? const WideDualPane(child: _form) : _form,
        ),
      ),
    ),
  );
}

double _opacity(WidgetTester tester, String element) => tester
    .widget<FadeTransition>(
      find.byKey(ValueKey('onboarding-hero-$element-opacity')),
    )
    .opacity
    .value;

double _breathScale(WidgetTester tester) => tester
    .widget<ScaleTransition>(
      find.byKey(const ValueKey('onboarding-hero-logo-breath')),
    )
    .scale
    .value;

void _expectSettledBrand(WidgetTester tester) {
  expect(_opacity(tester, 'logo'), 1);
  expect(_opacity(tester, 'title'), 1);
  expect(_opacity(tester, 'slogan'), 1);
  expect(tester.widget<Text>(find.text('Hermes')).style!.letterSpacing, -0.5);
  expect(find.text(_slogan), findsOneWidget);
  expect(tester.takeException(), isNull);
}

Future<Uint8List> _pixels(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('pane-capture')),
  );
  return (await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      return data!.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }))!;
}

void main() {
  testWidgets('Reduce Motion shows the final brand with no active ticker', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await _pumpPane(tester, disableAnimations: true);
      await tester.pumpAndSettle();

      _expectSettledBrand(tester);
      expect(_breathScale(tester), 1);
      expect(tester.hasRunningAnimations, isFalse);
      expect(tester.binding.transientCallbackCount, 0);
      expect(find.bySemanticsLabel('Hermes'), findsOneWidget);
      expect(
        tester.getSemantics(find.text('Hermes')),
        matchesSemantics(label: 'Hermes', isHeader: true),
      );
      expect(find.bySemanticsLabel(_slogan), findsOneWidget);

      await tester.pump(const Duration(seconds: 24));
      _expectSettledBrand(tester);
      expect(_breathScale(tester), 1);
      expect(tester.binding.transientCallbackCount, 0);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets(
    'entrance reveals the icon, title and slogan in order within 1.2s',
    (tester) async {
      await _pumpPane(tester);
      expect(_opacity(tester, 'logo'), 0);
      expect(_opacity(tester, 'title'), 0);
      expect(_opacity(tester, 'slogan'), 0);

      await tester.pump(const Duration(milliseconds: 200));
      expect(_opacity(tester, 'logo'), greaterThan(0));
      expect(_opacity(tester, 'title'), 0);
      expect(_opacity(tester, 'slogan'), 0);
      await tester.pump(const Duration(milliseconds: 300));
      expect(_opacity(tester, 'title'), greaterThan(0));
      expect(_opacity(tester, 'slogan'), 0);

      await tester.pump(const Duration(milliseconds: 700));
      _expectSettledBrand(tester);
      expect(tester.hasRunningAnimations, isTrue);
    },
  );

  testWidgets('ambient breath keeps running without rebuilding brand text', (
    tester,
  ) async {
    await _pumpPane(tester);
    await tester.pump(const Duration(milliseconds: 1200));
    // Flutter reports completion on the first frame strictly after duration.
    await tester.pump(const Duration(milliseconds: 16));
    final title = tester.widget<Text>(find.text('Hermes'));
    final slogan = tester.widget<Text>(find.text(_slogan));
    final titleRect = tester.getRect(find.text('Hermes'));
    final sloganRect = tester.getRect(find.text(_slogan));

    for (var cycle = 0; cycle < 3; cycle++) {
      await tester.pump(const Duration(seconds: 6));
      expect(_breathScale(tester), closeTo(1.01, 0.000001));
      await tester.pump(const Duration(seconds: 6));
      expect(_breathScale(tester), closeTo(1, 0.000001));
      expect(tester.hasRunningAnimations, isTrue);
      expect(tester.widget<Text>(find.text('Hermes')), same(title));
      expect(tester.widget<Text>(find.text(_slogan)), same(slogan));
      expect(tester.getRect(find.text('Hermes')), titleRect);
      expect(tester.getRect(find.text(_slogan)), sloganRect);
      expect(tester.takeException(), isNull);
    }

    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    testWidgets('${brightness.name} brand fits every window boundary', (
      tester,
    ) async {
      for (final size in const [
        Size(900, 600),
        Size(900, 1440),
        Size(2560, 600),
        Size(2560, 1440),
      ]) {
        // An intentional infinite loop cannot settle; static layout checks use
        // the real accessibility setting, while the test above exercises motion.
        await _pumpPane(
          tester,
          brightness: brightness,
          size: size,
          disableAnimations: true,
        );
        await tester.pumpAndSettle();
        _expectSettledBrand(tester);
        final paneRect = tester.getRect(
          find.byKey(const ValueKey('onboarding-brand-pane')),
        );
        expect(paneRect.width, closeTo((size.width - 0.5) * 0.45, 0.01));
        expect(
          paneRect.contains(tester.getCenter(find.text('Hermes'))),
          isTrue,
        );
        expect(
          paneRect.contains(tester.getBottomRight(find.text(_slogan))),
          isTrue,
        );
        expect(
          tester
              .getSize(
                find.byKey(const ValueKey('wide-dual-pane-form-container')),
              )
              .width,
          lessThanOrEqualTo(460),
        );
        expect(tester.hasRunningAnimations, isFalse);
      }
    });
  }

  testWidgets('large text retains the scroll fallback at the smallest window', (
    tester,
  ) async {
    await _pumpPane(
      tester,
      size: const Size(900, 600),
      textScale: 3.2,
      disableAnimations: true,
    );
    await tester.pumpAndSettle();
    final scrollable = find.descendant(
      of: find.byType(OnboardingHeroMotion),
      matching: find.byType(Scrollable),
    );
    final position = tester.state<ScrollableState>(scrollable).position;
    expect(position.maxScrollExtent, greaterThan(0));
    await tester.drag(scrollable, const Offset(0, -800));
    await tester.pumpAndSettle();
    expect(position.pixels, greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('changing Reduce Motion settles immediately and resumes gently', (
    tester,
  ) async {
    await _pumpPane(tester);
    await tester.pump(const Duration(milliseconds: 400));
    expect(_opacity(tester, 'slogan'), 0);

    await _pumpPane(tester, disableAnimations: true);
    await tester.pumpAndSettle();
    _expectSettledBrand(tester);
    expect(_breathScale(tester), 1);
    expect(tester.binding.transientCallbackCount, 0);

    await _pumpPane(tester);
    _expectSettledBrand(tester);
    await tester.pump(const Duration(seconds: 6));
    expect(_breathScale(tester), closeTo(1.01, 0.000001));
    await _pumpPane(tester, brightness: Brightness.dark);
    _expectSettledBrand(tester);
    expect(_breathScale(tester), closeTo(1.01, 0.000001));

    await _pumpPane(
      tester,
      brightness: Brightness.dark,
      disableAnimations: true,
    );
    await tester.pumpAndSettle();
    expect(_breathScale(tester), 1);
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('TickerMode mutes an obscured brand and unmount cancels motion', (
    tester,
  ) async {
    await _pumpPane(tester);
    await tester.pump(const Duration(milliseconds: 1216));
    await _pumpPane(tester, ticking: false);
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);

    await _pumpPane(tester);
    await tester.pump(const Duration(seconds: 3));
    expect(tester.hasRunningAnimations, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'narrow fallback is pixel-identical to rendering child directly',
    (tester) async {
      await _pumpPane(tester, size: const Size(899, 600));
      await tester.pumpAndSettle();
      expect(find.byType(OnboardingBrandPane), findsNothing);
      expect(find.byType(OnboardingHeroMotion), findsNothing);
      expect(tester.binding.transientCallbackCount, 0);
      final wrappedPixels = await _pixels(tester);

      await _pumpPane(tester, size: const Size(899, 600), useDualPane: false);
      await tester.pumpAndSettle();
      expect(await _pixels(tester), orderedEquals(wrappedPixels));
      expect(tester.takeException(), isNull);
    },
  );
}
