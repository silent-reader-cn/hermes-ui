import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/providers/clipboard_paste_provider.dart';
import 'package:hermes_ui/core/providers/file_picker_provider.dart';
import 'package:hermes_ui/core/utils/accessibility.dart';
import 'package:hermes_ui/core/utils/clipboard_paste.dart';
import 'package:hermes_ui/core/utils/file_picker.dart';
import 'package:hermes_ui/features/chat/chat_page.dart';
import 'package:hermes_ui/features/chat/chat_providers.dart';
import 'package:hermes_ui/features/prompts/prompts_providers.dart';
import 'package:hermes_ui/features/settings/composer_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_chat_api.dart';
import '../../helpers/fake_prompts_api.dart';

bool _isButtonEnabled(WidgetTester tester, Finder finder) {
  final widget = tester.widget<AccessibleButton>(finder);
  return widget.onPressed != null;
}

Future<void> _pumpComposer(
  WidgetTester tester, {
  required FakeChatApi chatApi,
  FakePromptsApi? promptsApi,
  String sessionId = 's1',
}) async {
  final prompts = promptsApi ?? FakePromptsApi(initialPrompts: const []);
  final client = ApiClient(baseUrl: 'http://test.local:30002');
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        chatApiProvider.overrideWithValue(chatApi),
        promptsApiFactoryProvider.overrideWithValue((_) => prompts),
        filePickerServiceProvider.overrideWithValue(FakeFilePickerService()),
        clipboardPasteServiceProvider.overrideWithValue(
          FakeClipboardPasteService(),
        ),
        apiClientProvider.overrideWithValue(client),
      ],
      child: CupertinoApp(home: ChatPage(sessionId: sessionId)),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('ChatInputBar 布局开关（默认单行 / 设置开启两段式）', () {
    testWidgets('默认关闭：经典单行布局（min1，无独立工具行），回车即发送', (tester) async {
      final chatApi = FakeChatApi();
      chatApi.sessionResult = {
        'session': {'session_id': 's1', 'messages': const []},
      };
      await _pumpComposer(tester, chatApi: chatApi);

      final inputFinder = find.byKey(const ValueKey('chat-input-field'));
      expect(inputFinder, findsOneWidget);

      // 经典单行：保留自适应（min1/max4 软上限）。
      final field = tester.widget<CupertinoTextField>(inputFinder);
      expect(field.minLines, 1);
      expect(field.maxLines, 4);

      // 回车即发送（经典模式走 onSubmitted：测试里用 IME 提交动作模拟回车）
      await tester.tap(inputFinder);
      await tester.pump();
      await tester.enterText(inputFinder, '经典消息');
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.pump();
      expect(chatApi.startChatCalls, 1);
      expect(chatApi.lastSentText, '经典消息');

      await _unmount(tester);
    });

    testWidgets('开关打开：两段式布局（min2/max8），多行自适应增高且封顶', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        final chatApi = FakeChatApi();
        chatApi.sessionResult = {
          'session': {'session_id': 's1', 'messages': const []},
        };
        // 直接以开启状态注入（模拟设置页已打开开关并持久化）
        SharedPreferences.setMockInitialValues({
          ComposerTwoPaneController.keyTwoPane: true,
        });
        await _pumpComposer(tester, chatApi: chatApi);
        // 等待异步 _load 从 prefs 读到 true
        await tester.pump(const Duration(milliseconds: 50));

        final inputFinder = find.byKey(const ValueKey('chat-input-field'));
        final field = tester.widget<CupertinoTextField>(inputFinder);
        expect(field.minLines, 2);
        expect(field.maxLines, 8);

        final initialHeight = tester.getSize(inputFinder).height;

        // 输入 4 行文本 → 高度增长
        await tester.enterText(inputFinder, '第一行\n第二行\n第三行\n第四行');
        await tester.pump();
        final height4Lines = tester.getSize(inputFinder).height;
        expect(height4Lines, greaterThan(initialHeight));

        // 16 行（超 maxLines: 8）→ 封顶不再增长
        await tester.enterText(
          inputFinder,
          '1\n2\n3\n4\n5\n6\n7\n8\n9\n10\n11\n12\n13\n14\n15\n16',
        );
        await tester.pump();
        final height16 = tester.getSize(inputFinder).height;
        expect(height16, greaterThan(height4Lines));

        await _unmount(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
        SharedPreferences.setMockInitialValues(<String, Object>{});
      }
    });

    testWidgets('两种布局下所有功能 Key 一致且唯一（GlobalKey 不撞车）', (tester) async {
      final chatApi = FakeChatApi();
      chatApi.sessionResult = {
        'session': {'session_id': 's1', 'messages': const []},
      };

      // 经典单行
      await _pumpComposer(tester, chatApi: chatApi);
      for (final key in const [
        'chat-attach-button',
        'chat-saved-prompts-button',
        'chat-context-indicator-button',
        'chat-send-button',
        'chat-input-field',
      ]) {
        expect(
          find.byKey(ValueKey<String>(key)),
          findsOneWidget,
          reason: '经典布局应含 $key 且唯一',
        );
      }
      await _unmount(tester);

      // 两段式
      SharedPreferences.setMockInitialValues({
        ComposerTwoPaneController.keyTwoPane: true,
      });
      await _pumpComposer(tester, chatApi: chatApi);
      await tester.pump(const Duration(milliseconds: 50));
      for (final key in const [
        'chat-attach-button',
        'chat-saved-prompts-button',
        'chat-context-indicator-button',
        'chat-send-button',
        'chat-input-field',
      ]) {
        expect(
          find.byKey(ValueKey<String>(key)),
          findsOneWidget,
          reason: '两段式布局应含 $key 且唯一',
        );
      }
      await _unmount(tester);
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    testWidgets(
      '现有工具栏按键 Key 全部存在（chat-attach-button, chat-saved-prompts-button, chat-send-button）',
      (tester) async {
        final chatApi = FakeChatApi();
        chatApi.sessionResult = {
          'session': {'session_id': 's1', 'messages': const []},
        };
        await _pumpComposer(tester, chatApi: chatApi);

        expect(
          find.byKey(const ValueKey('chat-attach-button')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('chat-saved-prompts-button')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('chat-send-button')), findsOneWidget);
        expect(find.byKey(const ValueKey('chat-input-field')), findsOneWidget);
        expect(find.byKey(const ValueKey('chat-steer-button')), findsNothing);
        expect(find.byKey(const ValueKey('chat-stop-button')), findsNothing);

        await _unmount(tester);
      },
    );
  });

  group('ChatInputBar 流式状态工具行按钮', () {
    testWidgets('流式期间（streaming）显示 steer 与 stop 按钮，隐藏 send 按钮', (tester) async {
      final chatApi = FakeChatApi();
      chatApi.sessionResult = {
        'session': {'session_id': 's1', 'messages': const []},
      };
      await _pumpComposer(tester, chatApi: chatApi);

      // 发送消息进入流式
      final inputFinder = find.byKey(const ValueKey('chat-input-field'));
      await tester.enterText(inputFinder, '测试问题');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('chat-send-button')));
      await tester.pump();
      await tester.pump();

      // 流式状态下工具行出现 steer + 停止按钮，发送按钮消失
      final steerBtn = find.byKey(const ValueKey('chat-steer-button'));
      final stopBtn = find.byKey(const ValueKey('chat-stop-button'));
      final sendBtn = find.byKey(const ValueKey('chat-send-button'));

      expect(steerBtn, findsOneWidget);
      expect(stopBtn, findsOneWidget);
      expect(sendBtn, findsNothing);

      // 未输入 steer 内容时 steer 按钮禁用
      expect(_isButtonEnabled(tester, steerBtn), isFalse);

      // 输入 steer 内容后 steer 按钮可用
      await tester.enterText(inputFinder, '纠偏补充');
      await tester.pump();
      expect(_isButtonEnabled(tester, steerBtn), isTrue);

      // 点击停止按钮 → #19 二次确认框出现，确认后才真正停止
      await tester.tap(stopBtn);
      await tester.pump();
      expect(find.byType(CupertinoAlertDialog), findsOneWidget);
      // 点「停止生成」确认（输入栏 stop 按钮为 icon-only 无文本，
      // 页面上文本「停止生成」唯一，可安全定位）。
      await tester.tap(find.text('停止生成'));
      await tester.pumpAndSettle();
      expect(chatApi.cancelCalls, 1);

      await _unmount(tester);
    });
  });

  group('ChatInputBar 回车语义（桌面 Enter 发送 / Shift+Enter 换行；移动端 Enter 换行）', () {
    testWidgets('桌面端（Windows）两段式：Enter 键触发发送，Shift+Enter 插入换行', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      SharedPreferences.setMockInitialValues({
        ComposerTwoPaneController.keyTwoPane: true,
      });
      try {
        final chatApi = FakeChatApi();
        chatApi.sessionResult = {
          'session': {'session_id': 's1', 'messages': const []},
        };
        await _pumpComposer(tester, chatApi: chatApi);
        await tester.pump(const Duration(milliseconds: 50));

        final inputFinder = find.byKey(const ValueKey('chat-input-field'));

        // 聚焦输入框并输入文本
        await tester.tap(inputFinder);
        await tester.pump();
        await tester.enterText(inputFinder, '桌面消息');
        await tester.pump();

        // 桌面端按 Enter 触发发送
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        await tester.pump();

        expect(chatApi.startChatCalls, 1);
        expect(chatApi.lastSentText, '桌面消息');

        final field = tester.widget<CupertinoTextField>(inputFinder);
        expect(field.controller!.text, isEmpty);

        // 重置调用计数以测试 Shift+Enter
        chatApi.startChatCalls = 0;
        chatApi.sessionResult = {
          'session': {'session_id': 's1', 'messages': const []},
        };
        await _unmount(tester);
        await _pumpComposer(tester, chatApi: chatApi);

        final freshInput = find.byKey(const ValueKey('chat-input-field'));
        await tester.tap(freshInput);
        await tester.pump();
        await tester.enterText(freshInput, '第一行');
        await tester.pump();

        // 按 Shift+Enter 插入换行，不触发发送
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.pump();

        expect(chatApi.startChatCalls, 0);
        final freshField = tester.widget<CupertinoTextField>(freshInput);
        expect(freshField.controller!.text, contains('\n'));

        await _unmount(tester);
        SharedPreferences.setMockInitialValues(<String, Object>{});
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('移动端（Android）两段式：Enter 不发送（插入换行），点发送按钮发送', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      SharedPreferences.setMockInitialValues({
        ComposerTwoPaneController.keyTwoPane: true,
      });
      try {
        final chatApi = FakeChatApi();
        chatApi.sessionResult = {
          'session': {'session_id': 's1', 'messages': const []},
        };
        await _pumpComposer(tester, chatApi: chatApi);
        await tester.pump(const Duration(milliseconds: 50));

        final inputFinder = find.byKey(const ValueKey('chat-input-field'));
        await tester.tap(inputFinder);
        await tester.pump();
        await tester.enterText(inputFinder, '移动端消息');
        await tester.pump();

        // 两段式移动端按 Enter 键插入换行、不发送。
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();

        expect(chatApi.startChatCalls, 0);
        final field = tester.widget<CupertinoTextField>(inputFinder);
        expect(field.controller!.text, contains('\n'));

        // 点击发送按钮触发发送
        final sendBtn = find.byKey(const ValueKey('chat-send-button'));
        expect(_isButtonEnabled(tester, sendBtn), isTrue);
        await tester.tap(sendBtn);
        await tester.pump();
        await tester.pump();

        expect(chatApi.startChatCalls, 1);
        expect(chatApi.lastSentText, contains('移动端消息'));

        await _unmount(tester);
        SharedPreferences.setMockInitialValues(<String, Object>{});
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  group('ChatInputBar 上下文窗口指示器位置与排列顺序（todo #1）', () {
    testWidgets('经典单行布局：[＋] [书签] [上下文圆环] [输入框] [发送] 水平从左到右排列', (tester) async {
      final chatApi = FakeChatApi();
      chatApi.sessionResult = {
        'session': {'session_id': 's1', 'messages': const []},
      };
      await _pumpComposer(tester, chatApi: chatApi);

      final attachX = tester
          .getTopLeft(find.byKey(const ValueKey('chat-attach-button')))
          .dx;
      final bookmarkX = tester
          .getTopLeft(find.byKey(const ValueKey('chat-saved-prompts-button')))
          .dx;
      final indicatorX = tester
          .getTopLeft(
            find.byKey(const ValueKey('chat-context-indicator-button')),
          )
          .dx;
      final inputX = tester
          .getTopLeft(find.byKey(const ValueKey('chat-input-field')))
          .dx;
      final sendX = tester
          .getTopLeft(find.byKey(const ValueKey('chat-send-button')))
          .dx;

      expect(attachX, lessThan(bookmarkX));
      expect(bookmarkX, lessThan(indicatorX));
      expect(indicatorX, lessThan(inputX));
      expect(inputX, lessThan(sendX));

      await _unmount(tester);
    });

    testWidgets('两段式布局：工具行 [附件] [书签] [上下文圆环] | Spacer | [发送] 排列', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        ComposerTwoPaneController.keyTwoPane: true,
      });
      final chatApi = FakeChatApi();
      chatApi.sessionResult = {
        'session': {'session_id': 's1', 'messages': const []},
      };
      await _pumpComposer(tester, chatApi: chatApi);
      await tester.pump(const Duration(milliseconds: 50));

      final attachX = tester
          .getTopLeft(find.byKey(const ValueKey('chat-attach-button')))
          .dx;
      final bookmarkX = tester
          .getTopLeft(find.byKey(const ValueKey('chat-saved-prompts-button')))
          .dx;
      final indicatorX = tester
          .getTopLeft(
            find.byKey(const ValueKey('chat-context-indicator-button')),
          )
          .dx;
      final sendX = tester
          .getTopLeft(find.byKey(const ValueKey('chat-send-button')))
          .dx;

      expect(attachX, lessThan(bookmarkX));
      expect(bookmarkX, lessThan(indicatorX));
      expect(indicatorX, lessThan(sendX));

      await _unmount(tester);
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    testWidgets('只读会话下仍显示上下文圆环指示器', (tester) async {
      final chatApi = FakeChatApi();
      chatApi.sessionResult = {
        'session': {
          'session_id': 's1',
          'messages': const [],
          'is_read_only': true,
        },
      };
      await _pumpComposer(tester, chatApi: chatApi);

      expect(
        find.byKey(const ValueKey('chat-context-indicator-button')),
        findsOneWidget,
      );
      await _unmount(tester);
    });
  });
}
