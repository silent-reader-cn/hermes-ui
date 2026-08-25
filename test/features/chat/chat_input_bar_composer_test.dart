import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermex_flutter/core/api/api_client.dart';
import 'package:hermex_flutter/core/connections/connection_providers.dart';
import 'package:hermex_flutter/core/providers/clipboard_paste_provider.dart';
import 'package:hermex_flutter/core/providers/file_picker_provider.dart';
import 'package:hermex_flutter/core/utils/accessibility.dart';
import 'package:hermex_flutter/core/utils/clipboard_paste.dart';
import 'package:hermex_flutter/core/utils/file_picker.dart';
import 'package:hermex_flutter/features/chat/chat_page.dart';
import 'package:hermex_flutter/features/chat/chat_providers.dart';
import 'package:hermex_flutter/features/prompts/prompts_providers.dart';

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
        clipboardPasteServiceProvider.overrideWithValue(FakeClipboardPasteService()),
        apiClientProvider.overrideWithValue(client),
      ],
      child: CupertinoApp(
        home: ChatPage(sessionId: sessionId),
      ),
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

  group('ChatInputBar 两段式 Composer 布局与自适应增高', () {
    testWidgets('多行长文本自适应增高且存在上限（minLines: 2, maxLines: 8）', (tester) async {
      final chatApi = FakeChatApi();
      chatApi.sessionResult = {
        'session': {'session_id': 's1', 'messages': const []},
      };
      await _pumpComposer(tester, chatApi: chatApi);

      final inputFinder = find.byKey(const ValueKey('chat-input-field'));
      expect(inputFinder, findsOneWidget);

      final fieldWidget = tester.widget<CupertinoTextField>(inputFinder);
      expect(fieldWidget.minLines, 2);
      expect(fieldWidget.maxLines, 8);
      expect(fieldWidget.keyboardType, TextInputType.multiline);

      // 初始 2 行高度
      final initialHeight = tester.getSize(inputFinder).height;

      // 输入 4 行文本，高度增长
      await tester.enterText(
        inputFinder,
        '第一行\n第二行\n第三行\n第四行',
      );
      await tester.pump();
      final height4Lines = tester.getSize(inputFinder).height;
      expect(height4Lines, greaterThan(initialHeight));

      // 输入 8 行文本，高度进一步增长
      await tester.enterText(
        inputFinder,
        '1\n2\n3\n4\n5\n6\n7\n8',
      );
      await tester.pump();
      final height8Lines = tester.getSize(inputFinder).height;
      expect(height8Lines, greaterThan(height4Lines));

      // 输入 16 行文本（超过 maxLines: 8），高度封顶不再增长
      await tester.enterText(
        inputFinder,
        '1\n2\n3\n4\n5\n6\n7\n8\n9\n10\n11\n12\n13\n14\n15\n16',
      );
      await tester.pump();
      final height16Lines = tester.getSize(inputFinder).height;
      expect(height16Lines, equals(height8Lines));

      await _unmount(tester);
    });

    testWidgets('现有工具栏按键 Key 全部存在（chat-attach-button, chat-saved-prompts-button, chat-send-button）', (
      tester,
    ) async {
      final chatApi = FakeChatApi();
      chatApi.sessionResult = {
        'session': {'session_id': 's1', 'messages': const []},
      };
      await _pumpComposer(tester, chatApi: chatApi);

      expect(find.byKey(const ValueKey('chat-attach-button')), findsOneWidget);
      expect(find.byKey(const ValueKey('chat-saved-prompts-button')), findsOneWidget);
      expect(find.byKey(const ValueKey('chat-send-button')), findsOneWidget);
      expect(find.byKey(const ValueKey('chat-input-field')), findsOneWidget);
      expect(find.byKey(const ValueKey('chat-steer-button')), findsNothing);
      expect(find.byKey(const ValueKey('chat-stop-button')), findsNothing);

      await _unmount(tester);
    });
  });

  group('ChatInputBar 流式状态工具行按钮', () {
    testWidgets('流式期间（streaming）显示 steer 与 stop 按钮，隐藏 send 按钮', (
      tester,
    ) async {
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

      // 点击停止按钮调用 cancelChat
      await tester.tap(stopBtn);
      await tester.pump();
      expect(chatApi.cancelCalls, 1);

      await _unmount(tester);
    });
  });

  group('ChatInputBar 回车语义（桌面 Enter 发送 / Shift+Enter 换行；移动端 Enter 换行）', () {
    testWidgets('桌面端（Windows）：Enter 键触发发送，Shift+Enter 插入换行', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        final chatApi = FakeChatApi();
        chatApi.sessionResult = {
          'session': {'session_id': 's1', 'messages': const []},
        };
        await _pumpComposer(tester, chatApi: chatApi);

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
        expect(freshField.controller!.text, contains('第一行\n'));

        await _unmount(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('移动端（Android）：Enter 键不触发发送（插入换行），需点击发送按钮发送', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        final chatApi = FakeChatApi();
        chatApi.sessionResult = {
          'session': {'session_id': 's1', 'messages': const []},
        };
        await _pumpComposer(tester, chatApi: chatApi);

        final inputFinder = find.byKey(const ValueKey('chat-input-field'));
        await tester.tap(inputFinder);
        await tester.pump();
        await tester.enterText(inputFinder, '移动端消息');
        await tester.pump();

        // 移动端按 Enter 键不发送
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();

        expect(chatApi.startChatCalls, 0);
        final field = tester.widget<CupertinoTextField>(inputFinder);
        expect(field.controller!.text, contains('移动端消息\n'));

        // 点击发送按钮触发发送
        final sendBtn = find.byKey(const ValueKey('chat-send-button'));
        expect(_isButtonEnabled(tester, sendBtn), isTrue);
        await tester.tap(sendBtn);
        await tester.pump();
        await tester.pump();

        expect(chatApi.startChatCalls, 1);
        expect(chatApi.lastSentText, contains('移动端消息'));

        await _unmount(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });
}
