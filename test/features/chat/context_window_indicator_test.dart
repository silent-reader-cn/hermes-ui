import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermex_flutter/core/models/context_window_snapshot.dart';
import 'package:hermex_flutter/features/chat/widgets/context_window_indicator.dart';

void main() {
  Widget wrap(Widget child) =>
      CupertinoApp(home: CupertinoPageScaffold(child: child));

  group('ContextWindowIndicator 文本/颜色联动', () {
    testWidgets('无 snapshot -> 中心点且 disabled', (tester) async {
      await tester.pumpWidget(
        wrap(const ContextWindowIndicator(snapshot: null, onTap: null)),
      );
      expect(find.text('\u00b7'), findsOneWidget);
      final btn = tester.widget<CupertinoButton>(
        find.byKey(const ValueKey('chat-context-indicator-button')),
      );
      expect(btn.onPressed, isNull);
    });

    testWidgets('snapshot 无 percentage 仍显示点但可点击', (tester) async {
      var tapped = false;
      final snap =
          ContextWindowSnapshot.fromJson({'threshold_tokens': 1000});
      await tester.pumpWidget(
        wrap(
          ContextWindowIndicator(
            snapshot: snap,
            onTap: () => tapped = true,
          ),
        ),
      );
      expect(find.text('\u00b7'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('chat-context-indicator-button')),
      );
      await tester.pump();
      expect(tapped, isTrue);
    });

    testWidgets('27% 正常显示百分比', (tester) async {
      final snap = ContextWindowSnapshot.fromJson({
        'context_length': 200000,
        'last_prompt_tokens': 54321,
      });
      await tester.pumpWidget(
        wrap(ContextWindowIndicator(snapshot: snap, onTap: () {})),
      );
      expect(find.text('27'), findsOneWidget);
    });

    testWidgets('done 更新后 indicator 即时刷新（重建）', (tester) async {
      final low = ContextWindowSnapshot.fromJson(
        {'context_length': 100, 'last_prompt_tokens': 10},
      );
      final high = ContextWindowSnapshot.fromJson(
        {'context_length': 100, 'last_prompt_tokens': 80},
      );
      await tester.pumpWidget(
        wrap(ContextWindowIndicator(snapshot: low, onTap: () {})),
      );
      expect(find.text('10'), findsOneWidget);
      await tester.pumpWidget(
        wrap(ContextWindowIndicator(snapshot: high, onTap: () {})),
      );
      await tester.pump();
      expect(find.text('80'), findsOneWidget);
    });

    testWidgets('尺寸对齐发送按钮图标 (ringSize=22, tapTargetSize=44, fontSize=7)', (tester) async {
      expect(ContextWindowIndicator.ringSize, 22.0);
      expect(ContextWindowIndicator.tapTargetSize, 44.0);

      final snap = ContextWindowSnapshot.fromJson({
        'context_length': 1000,
        'last_prompt_tokens': 500,
      });
      await tester.pumpWidget(
        wrap(ContextWindowIndicator(snapshot: snap, onTap: () {})),
      );

      final textWidget = tester.widget<Text>(find.text('50'));
      expect(textWidget.style?.fontSize, 7.0);
      expect(textWidget.style?.fontWeight, FontWeight.w600);

      final ringBox = tester.widget<SizedBox>(
        find.ancestor(
          of: find.byType(CustomPaint),
          matching: find.byType(SizedBox),
        ).first,
      );
      expect(ringBox.width, 22.0);
      expect(ringBox.height, 22.0);

      final button = tester.widget<CupertinoButton>(
        find.byKey(const ValueKey('chat-context-indicator-button')),
      );
      expect(button.minimumSize, const Size(44.0, 44.0));
    });
  });
}
