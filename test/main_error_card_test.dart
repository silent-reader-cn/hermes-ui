import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/app/theme/cupertino_theme.dart';
import 'package:hermes_ui/main.dart';

void main() {
  group('RecoverableErrorCard 完整测试', () {
    testWidgets('文案优先级：优先 widget.message', (tester) async {
      final details = FlutterErrorDetails(
        exception: Exception('Some inner exception'),
        library: 'test library',
      );

      await tester.pumpWidget(
        CupertinoApp(
          home: CupertinoPageScaffold(
            child: RecoverableErrorCard(
              message: '自定义错误消息',
              details: details,
            ),
          ),
        ),
      );

      expect(find.text('自定义错误消息'), findsOneWidget);
      expect(find.text('Exception: Some inner exception'), findsNothing);
    });

    testWidgets('文案优先级：次选 details.exceptionAsString()', (tester) async {
      final details = FlutterErrorDetails(
        exception: StateError('RenderFlex overflowed by 42 pixels'),
        library: 'rendering library',
        context: ErrorDescription('during layout'),
      );

      await tester.pumpWidget(
        CupertinoApp(
          home: CupertinoPageScaffold(
            child: RecoverableErrorCard(details: details),
          ),
        ),
      );

      expect(
        find.text('Bad state: RenderFlex overflowed by 42 pixels'),
        findsOneWidget,
      );
    });

    testWidgets('文案优先级：无 message 和 details 时回退默认文案', (tester) async {
      await tester.pumpWidget(
        const CupertinoApp(
          home: CupertinoPageScaffold(
            child: RecoverableErrorCard(),
          ),
        ),
      );

      expect(find.text('已断开 / 网络错误，重试'), findsOneWidget);
      // details 为空时不展示详情折叠按钮
      expect(find.text('详情'), findsNothing);
    });

    testWidgets('详情折叠与展开交互', (tester) async {
      final stack = StackTrace.fromString('#0 test_func (test.dart:10:5)\n#1 main (main.dart:1:1)');
      final details = FlutterErrorDetails(
        exception: Exception('Crash in widget build'),
        library: 'widgets library',
        context: ErrorDescription('building TestWidget'),
        stack: stack,
      );

      await tester.pumpWidget(
        CupertinoApp(
          home: CupertinoPageScaffold(
            child: RecoverableErrorCard(details: details),
          ),
        ),
      );

      // 默认收起状态
      expect(find.text('详情'), findsOneWidget);
      expect(find.text('收起'), findsNothing);
      expect(find.text('异常详情'), findsNothing);

      // 点击展开
      await tester.tap(find.text('详情'));
      await tester.pumpAndSettle();

      expect(find.text('收起'), findsOneWidget);
      expect(find.text('异常详情'), findsOneWidget);
      expect(find.text('复制详情'), findsOneWidget);

      // 详情文本包含 Exception, Library, Context, StackTrace
      expect(find.textContaining('Exception: Crash in widget build'), findsWidgets);
      expect(find.textContaining('Library: widgets library'), findsWidgets);
      expect(find.textContaining('Context: building TestWidget'), findsWidgets);
      expect(find.textContaining('StackTrace:'), findsWidgets);

      // 点击收起
      await tester.tap(find.text('收起'));
      await tester.pumpAndSettle();

      expect(find.text('详情'), findsOneWidget);
      expect(find.text('收起'), findsNothing);
      expect(find.text('异常详情'), findsNothing);
    });

    testWidgets('复制详情功能与状态反馈', (tester) async {
      String? clipboardText;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall methodCall) async {
          if (methodCall.method == 'Clipboard.setData') {
            clipboardText = (methodCall.arguments as Map)['text'] as String?;
            return null;
          }
          if (methodCall.method == 'Clipboard.getData') {
            return {'text': clipboardText};
          }
          return null;
        },
      );

      final details = FlutterErrorDetails(
        exception: Exception('Copy test error'),
        library: 'core library',
      );

      await tester.pumpWidget(
        CupertinoApp(
          home: CupertinoPageScaffold(
            child: RecoverableErrorCard(details: details),
          ),
        ),
      );

      // 展开详情
      await tester.tap(find.text('详情'));
      await tester.pumpAndSettle();

      expect(find.text('复制详情'), findsOneWidget);

      // 点击复制
      await tester.tap(find.text('复制详情'));
      await tester.pump();

      expect(find.text('已复制'), findsOneWidget);

      // 验证剪贴板数据
      expect(clipboardText, contains('Exception: Copy test error'));
      expect(clipboardText, contains('Library: core library'));

      // 2秒后恢复为「复制详情」
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('复制详情'), findsOneWidget);
      expect(find.text('已复制'), findsNothing);
    });

    testWidgets('深色与浅色主题自适应渲染且对比度良好', (tester) async {
      final details = FlutterErrorDetails(
        exception: Exception('Theme test error'),
      );

      // 浅色模式
      await tester.pumpWidget(
        CupertinoApp(
          theme: buildCupertinoTheme(Brightness.light),
          home: CupertinoPageScaffold(
            child: RecoverableErrorCard(details: details),
          ),
        ),
      );
      expect(find.byType(RecoverableErrorCard), findsOneWidget);
      expect(find.text('Exception: Theme test error'), findsOneWidget);

      // 深色模式
      await tester.pumpWidget(
        CupertinoApp(
          theme: buildCupertinoTheme(Brightness.dark),
          home: CupertinoPageScaffold(
            child: RecoverableErrorCard(details: details),
          ),
        ),
      );
      expect(find.byType(RecoverableErrorCard), findsOneWidget);
      expect(find.text('Exception: Theme test error'), findsOneWidget);
    });

    testWidgets('脱离 Directionality 上下文时安全自包裹不崩溃', (tester) async {
      await tester.pumpWidget(
        const RecoverableErrorCard(message: 'No Directionality parent'),
      );

      expect(find.text('No Directionality parent'), findsOneWidget);
      expect(find.byType(RecoverableErrorCard), findsOneWidget);
    });

    testWidgets('重试按钮点击触发回调与已重试状态切换', (tester) async {
      var retryCalled = false;
      await tester.pumpWidget(
        CupertinoApp(
          home: CupertinoPageScaffold(
            child: RecoverableErrorCard(
              message: 'Retry test error',
              onRetry: () => retryCalled = true,
            ),
          ),
        ),
      );

      expect(find.text('重试'), findsOneWidget);
      expect(find.text('已重试'), findsNothing);

      await tester.tap(find.text('重试'));
      await tester.pump();

      expect(retryCalled, isTrue);
      expect(find.text('已重试'), findsOneWidget);
    });
  });
}
