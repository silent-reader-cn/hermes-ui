// ignore_for_file: prefer_const_constructors
import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Scaffold;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/models/saved_prompt.dart';
import 'package:hermes_ui/features/prompts/prompts_providers.dart';
import 'package:hermes_ui/features/prompts/widgets/saved_prompts_sheet.dart';

import '../../helpers/fake_prompts_api.dart';

ProviderScope wrap(
  Widget child,
  FakePromptsApi api, {
  List<Override> extra = const [],
}) {
  return ProviderScope(
    overrides: [
      // Minimal apiClient to satisfy provider factory dep (build not used when
      // promptsApiFactory overridden, but required by some code paths).
      // Use test local base.
      apiClientProvider.overrideWithValue(
        ApiClient(baseUrl: 'http://test.local:30002'),
      ),
      promptsApiFactoryProvider.overrideWithValue((_) => api),
      ...extra,
    ],
    child: CupertinoApp(home: child),
  );
}

Widget sheetFor({
  required FakePromptsApi api,
  ValueChanged<String>? onInsert,
  String? currentInput,
  String Function()? getCurrentInput,
  List<String> inserted = const [],
}) {
  final inserts = <String>[];
  inserts.addAll(inserted);
  return wrap(
    SavedPromptsSheet(
      onInsert: onInsert ?? inserts.add,
      currentInput: currentInput,
      getCurrentInput: getCurrentInput,
    ),
    api,
  );
}

SavedPrompt p(String id, String text, {String? label}) =>
    SavedPrompt(id: id, label: label, text: text, createdAt: 1700000000);

void main() {
  group('SavedPromptsSheet 空态/加载态/列表渲染', () {
    testWidgets('空列表 -> 显示 savedPromptsEmpty', (tester) async {
      final api = FakePromptsApi(initialPrompts: const []);
      await tester.pumpWidget(sheetFor(api: api));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('暂无收藏提示词'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('saved-prompts-save-current')),
        findsOneWidget,
      );
      expect(find.text('收藏提示词'), findsOneWidget);
    });

    testWidgets('loading 时显示 CupertinoActivityIndicator', (tester) async {
      final api = FakePromptsApi(initialPrompts: const []);
      api.fetchGate = Completer<void>(); // block fetch -> loading
      await tester.pumpWidget(sheetFor(api: api));
      await tester.pump();
      expect(find.byType(CupertinoActivityIndicator), findsWidgets);
      api.fetchGate!.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    });

    testWidgets('error 态 -> 红字 + 重试按钮', (tester) async {
      // Force error by injecting failing api wrapper
      final failing = _FailingFetchApi();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(
              ApiClient(baseUrl: 'http://test.local:30002'),
            ),
            promptsApiFactoryProvider.overrideWithValue((_) => failing),
          ],
          child: const CupertinoApp(home: SavedPromptsSheet(onInsert: _noop)),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      // Error text present and retry button
      expect(find.byKey(const ValueKey('saved-prompts-retry')), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
      // Retry re-invokes fetch
      failing.shouldFail = false;
      failing.fallback.addAll([p('x', 'hi')]);
      await tester.tap(find.byKey(const ValueKey('saved-prompts-retry')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('hi'), findsWidgets);
    });

    testWidgets('列表渲染：label 优先，副标题 text，删除按钮存在', (tester) async {
      final api = FakePromptsApi(
        initialPrompts: [
          p('a1', 'hello world long text here', label: 'My label'),
          p(
            'a2',
            'fallback only text that is longer than sixty chars to test truncation behaviour xxxxx',
          ),
        ],
      );
      await tester.pumpWidget(sheetFor(api: api));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('My label'), findsOneWidget);
      // second row title truncated to 60 and subtitle full both contain prefix -> findsWidgets
      expect(find.textContaining('fallback only text'), findsWidgets);
      expect(
        find.byKey(const ValueKey('saved-prompt-delete-a1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('saved-prompt-delete-a2')),
        findsOneWidget,
      );
      expect(find.byIcon(CupertinoIcons.delete), findsNWidgets(2));
    });

    testWidgets('label 为空时 title 回落 text 前60（helper 验证）', (tester) async {
      final long = List.filled(100, 'a').join();
      final api = FakePromptsApi(initialPrompts: [p('x', long)]);
      await tester.pumpWidget(sheetFor(api: api));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final tileTitle = find.widgetWithText(CupertinoListTile, 'a' * 60);
      expect(tileTitle, findsOneWidget);
      // subtitle still full text
      expect(find.text(long), findsOneWidget);
    });
  });

  group('SavedPromptsSheet 交互：插入/删除', () {
    testWidgets('点击行 -> onInsert(text) + pop', (tester) async {
      final api = FakePromptsApi(initialPrompts: [p('a1', 'insert me')]);
      final inserts = <String>[];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(
              ApiClient(baseUrl: 'http://test.local:30002'),
            ),
            promptsApiFactoryProvider.overrideWithValue((_) => api),
          ],
          child: CupertinoApp(
            home: Builder(
              builder: (context) => CupertinoButton(
                onPressed: () => showCupertinoModalPopup<void>(
                  context: context,
                  builder: (_) => SavedPromptsSheet(onInsert: inserts.add),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      // Tile visible in popup
      expect(find.byKey(const ValueKey('saved-prompt-a1-0')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('saved-prompt-a1-0')));
      await tester.pumpAndSettle();
      expect(inserts, ['insert me']);
      // Sheet closed: popup dismissed (tile offstage)
      expect(find.byKey(const ValueKey('saved-prompt-a1-0')), findsNothing);
    });

    testWidgets('点击删除 -> 调用 remove + 列表刷新', (tester) async {
      final api = FakePromptsApi(
        initialPrompts: [p('a1', 'hello'), p('a2', 'world')],
      );
      await tester.pumpWidget(sheetFor(api: api));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const ValueKey('saved-prompt-a1-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('saved-prompt-a1-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('saved-prompt-a2-1')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('saved-prompt-delete-a1')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(api.deleteCount, 1);
      expect(api.lastDeleteId, 'a1');
      expect(find.byKey(const ValueKey('saved-prompt-a1-0')), findsNothing);
      // a2 now at index 0 after re-render (single item)
      expect(find.byKey(const ValueKey('saved-prompt-a2-0')), findsOneWidget);
    });

    testWidgets('saveCurrentInput 空 -> 弹 savedPromptsEmptyInput 提示', (
      tester,
    ) async {
      final api = FakePromptsApi(initialPrompts: const []);
      await tester.pumpWidget(sheetFor(api: api, currentInput: '   '));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(
        find.byKey(const ValueKey('saved-prompts-save-current')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('请先输入提示词'), findsOneWidget);
      expect(api.createCount, 0);
      await tester.tap(find.text('好'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    });

    testWidgets('saveCurrentInput 成功 -> promptSaved toast 并刷新列表', (
      tester,
    ) async {
      final api = FakePromptsApi(initialPrompts: const []);
      await tester.pumpWidget(
        sheetFor(api: api, getCurrentInput: () => '  new text  '),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(
        find.byKey(const ValueKey('saved-prompts-save-current')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(api.createCount, 1);
      expect(api.lastCreateText, 'new text');
      expect(find.text('已收藏'), findsWidgets);
      await tester.tap(find.text('好'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('saved-prompt-id_1-0')), findsOneWidget);
    });

    testWidgets('top inset 不应推开第一项', (tester) async {
      final api = FakePromptsApi(
        initialPrompts: [p('inset', '首项内容', label: '首项')],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(
              ApiClient(baseUrl: 'http://test.local:30002'),
            ),
            promptsApiFactoryProvider.overrideWithValue((_) => api),
          ],
          child: MediaQuery(
            data: const MediaQueryData(padding: EdgeInsets.only(top: 51)),
            child: const CupertinoApp(home: SavedPromptsSheet(onInsert: _noop)),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final sheet = tester.getRect(find.byType(SavedPromptsSheet));
      final tile = tester.getRect(
        find.byKey(const ValueKey('saved-prompt-inset-0')),
      );
      // The ListView must not inherit the Android status-bar inset.
      // With the inset bug this gap is about 100 logical px; the fixed list
      // starts immediately after the sheet handle/title area.
      expect(tile.top - sheet.top, lessThan(60));
    });
    testWidgets('systemGrey6 resolveFrom 不抛异常（暗黑模式 smoke）', (tester) async {
      final api = FakePromptsApi(initialPrompts: const []);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(
              ApiClient(baseUrl: 'http://test.local:30002'),
            ),
            promptsApiFactoryProvider.overrideWithValue((_) => api),
          ],
          child: MediaQuery(
            data: const MediaQueryData(platformBrightness: Brightness.dark),
            child: CupertinoApp(
              theme: const CupertinoThemeData(brightness: Brightness.dark),
              home: SavedPromptsSheet(onInsert: _noop),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);
    });
  });

  group('Cupertino 约束', () {
    testWidgets('无 Material 混入：仅 Cupertino widgets', (tester) async {
      final api = FakePromptsApi(initialPrompts: [p('a1', 'hello')]);
      await tester.pumpWidget(sheetFor(api: api));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(CupertinoListTile), findsWidgets);
      expect(
        find.byType(CupertinoActivityIndicator),
        findsNothing,
      ); // not loading
      // Material Scaffold/AppBar etc should not appear
      expect(find.byType(Scaffold), findsNothing);
    });
  });
}

void _noop(String _) {}

class _FailingFetchApi implements PromptsApi {
  bool shouldFail = true;
  List<SavedPrompt> fallback = [];
  int fetchCount = 0;
  @override
  Future<SavedPromptsResponse> fetchPrompts() async {
    fetchCount++;
    if (shouldFail) throw Exception('network fail');
    return SavedPromptsResponse(prompts: [...fallback]);
  }

  @override
  Future<SavePromptResponse> createPrompt({
    required String text,
    String? label,
  }) => throw UnimplementedError();
  @override
  Future<DeletePromptResponse> deletePrompt(String id) =>
      throw UnimplementedError();
}
