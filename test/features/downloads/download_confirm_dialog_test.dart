import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/features/downloads/download_confirm_dialog.dart';
import 'package:hermes_ui/l10n/app_localizations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const List<LocalizationsDelegate<dynamic>> testDelegates = [
    AppLocalizationsDelegate(),
    DefaultCupertinoLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  Widget buildHostApp({
    required Widget Function(BuildContext) builder,
    Locale locale = const Locale('zh'),
  }) {
    return CupertinoApp(
      locale: locale,
      supportedLocales: const [Locale('zh'), Locale('en')],
      localizationsDelegates: testDelegates,
      home: CupertinoPageScaffold(
        child: Builder(builder: builder),
      ),
    );
  }

  group('showDownloadConfirmationDialog 弹窗改造', () {
    testWidgets('传 modifiedAtSeconds 时显示修改时间，且不显示来源会话', (tester) async {
      bool? result;
      const testEpochSeconds = 1773278400.0; // 2026-03-12T01:20:00.000Z
      final dt = DateTime.fromMillisecondsSinceEpoch(
        (testEpochSeconds * 1000).round(),
      );
      final y = dt.year.toString().padLeft(4, '0');
      final m = dt.month.toString().padLeft(2, '0');
      final d = dt.day.toString().padLeft(2, '0');
      final hh = dt.hour.toString().padLeft(2, '0');
      final mm = dt.minute.toString().padLeft(2, '0');
      final expectedTimeStr = '$y-$m-$d $hh:$mm';

      await tester.pumpWidget(
        buildHostApp(
          builder: (context) => CupertinoButton(
            child: const Text('Open Dialog'),
            onPressed: () async {
              result = await showDownloadConfirmationDialog(
                context,
                fileName: 'report.pdf',
                mimeType: 'application/pdf',
                expectedBytes: 1024 * 1024,
                sessionId: 'sess-abc-123456789',
                modifiedAtSeconds: testEpochSeconds,
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      // 基本信息展示
      expect(find.text('下载文件'), findsOneWidget);
      expect(find.text('名称：report.pdf'), findsOneWidget);
      expect(find.text('信息：文档'), findsOneWidget);
      expect(find.text('值：1.0 MB'), findsOneWidget);

      // 修改时间展示
      expect(find.text('修改时间：$expectedTimeStr'), findsOneWidget);

      // 来源会话不应出现
      expect(find.textContaining('来源'), findsNothing);
      expect(find.textContaining('会话'), findsNothing);
      expect(find.textContaining('sess-abc'), findsNothing);

      // 点击确认
      await tester.tap(find.text('开始下载'));
      await tester.pumpAndSettle();

      expect(result, isTrue);
      expect(find.text('下载文件'), findsNothing);
    });

    testWidgets('未传 modifiedAtSeconds 时不显示修改时间行，点击取消返回 false', (tester) async {
      bool? result;

      await tester.pumpWidget(
        buildHostApp(
          builder: (context) => CupertinoButton(
            child: const Text('Open Dialog'),
            onPressed: () async {
              result = await showDownloadConfirmationDialog(
                context,
                fileName: 'archive.zip',
                mimeType: 'application/zip',
                expectedBytes: 512,
                sessionId: 'session-xyz',
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('下载文件'), findsOneWidget);
      expect(find.text('名称：archive.zip'), findsOneWidget);
      expect(find.text('信息：压缩包'), findsOneWidget);
      expect(find.text('值：512 B'), findsOneWidget);

      // 无修改时间行
      expect(find.textContaining('修改时间'), findsNothing);

      // 无来源会话行
      expect(find.textContaining('来源'), findsNothing);
      expect(find.textContaining('session-xyz'), findsNothing);

      // 点击取消
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      expect(result, isFalse);
      expect(find.text('下载文件'), findsNothing);
    });

    testWidgets('英文环境下展示 Modified 与对应标签', (tester) async {
      const testEpochSeconds = 1773278400.0;
      final dt = DateTime.fromMillisecondsSinceEpoch(
        (testEpochSeconds * 1000).round(),
      );
      final y = dt.year.toString().padLeft(4, '0');
      final m = dt.month.toString().padLeft(2, '0');
      final d = dt.day.toString().padLeft(2, '0');
      final hh = dt.hour.toString().padLeft(2, '0');
      final mm = dt.minute.toString().padLeft(2, '0');
      final expectedTimeStr = '$y-$m-$d $hh:$mm';

      await tester.pumpWidget(
        buildHostApp(
          locale: const Locale('en'),
          builder: (context) => CupertinoButton(
            child: const Text('Open Dialog'),
            onPressed: () async {
              await showDownloadConfirmationDialog(
                context,
                fileName: 'code.dart',
                mimeType: 'text/x-dart',
                sessionId: 'sess-en',
                modifiedAtSeconds: testEpochSeconds,
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Download File'), findsOneWidget);
      expect(find.text('Name：code.dart'), findsOneWidget);
      expect(find.text('Info：Code'), findsOneWidget);
      expect(find.text('Value：Unknown size'), findsOneWidget);
      expect(find.text('Modified：$expectedTimeStr'), findsOneWidget);

      // 来源会话不应出现
      expect(find.textContaining('Source session'), findsNothing);
      expect(find.textContaining('sess-en'), findsNothing);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });
  });
}
