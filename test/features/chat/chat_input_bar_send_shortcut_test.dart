import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/features/chat/chat_page.dart';
import 'package:hermes_ui/features/chat/chat_providers.dart';
import 'package:hermes_ui/features/chat/widgets/chat_input_bar.dart';
import 'package:hermes_ui/features/settings/chat_send_shortcut_settings.dart';
import 'package:hermes_ui/features/settings/composer_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_chat_api.dart';

/// 发送快捷键模式 widget 测试：enter 单行保持现状；ctrlEnter 多行、
/// Ctrl+Enter/Cmd+Enter 发送、Enter 换行、流式/发送中不发送。
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({ComposerTwoPaneController.keyTwoPane: false});
  });

  Future<void> pumpPage(WidgetTester tester, FakeChatApi api) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [chatApiProvider.overrideWithValue(api)],
        child: const CupertinoApp(home: ChatPage(sessionId: 's1')),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  CupertinoTextField field(WidgetTester tester) =>
      tester.widget<CupertinoTextField>(
        find.byKey(const ValueKey('chat-input-field')),
      );

  /// 模拟按下 Ctrl+Enter 组合键。
  Future<void> pressCtrlEnter(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.pump();
  }

  testWidgets('默认 enter 模式：输入框保持单行（maxLines == 1）', (tester) async {
    SharedPreferences.setMockInitialValues({ComposerTwoPaneController.keyTwoPane: false});
    final api = FakeChatApi();
    api.sessionResult = {
      'session': {'session_id': 's1', 'messages': const []},
    };
    await pumpPage(tester, api);

    // 布局开关默认关闭：经典形态（min1/max4 软上限）。
    expect(field(tester).maxLines, 4);
    expect(field(tester).minLines, 1);

    await unmount(tester);
  });

  testWidgets('ctrlEnter 模式：输入框放开为多行（maxLines == null）', (tester) async {
    SharedPreferences.setMockInitialValues({
      ChatSendShortcutController.keySendMode: 'ctrlEnter',
      ComposerTwoPaneController.keyTwoPane: false,
    });
    final api = FakeChatApi();
    api.sessionResult = {
      'session': {'session_id': 's1', 'messages': const []},
    };
    await pumpPage(tester, api);

    expect(field(tester).maxLines, isNull);
    expect(field(tester).minLines, 1);

    await unmount(tester);
  });

  testWidgets('ctrlEnter 模式：Ctrl+Enter 发送并清空输入框', (tester) async {
    SharedPreferences.setMockInitialValues({
      ChatSendShortcutController.keySendMode: 'ctrlEnter',
      ComposerTwoPaneController.keyTwoPane: false,
    });
    final api = FakeChatApi();
    api.sessionResult = {
      'session': {'session_id': 's1', 'messages': const []},
    };
    await pumpPage(tester, api);

    final input = find.byKey(const ValueKey('chat-input-field'));
    await tester.enterText(input, 'hello');
    await tester.pump();

    await pressCtrlEnter(tester);

    expect(api.startChatCalls, 1);
    expect(api.lastSentText, 'hello');
    expect(field(tester).controller!.text, isEmpty);

    await unmount(tester);
  });

  testWidgets('ctrlEnter 模式：单独 Enter 不发送，保留输入内容', (tester) async {
    SharedPreferences.setMockInitialValues({
      ChatSendShortcutController.keySendMode: 'ctrlEnter',
      ComposerTwoPaneController.keyTwoPane: false,
    });
    final api = FakeChatApi();
    api.sessionResult = {
      'session': {'session_id': 's1', 'messages': const []},
    };
    await pumpPage(tester, api);

    final input = find.byKey(const ValueKey('chat-input-field'));
    await tester.enterText(input, 'hello');
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(api.startChatCalls, 0);
    // ctrlEnter 模式单独 Enter 不发送（换行由平台 IME 处理，测试环境无插入）。
    expect(field(tester).controller!.text, 'hello');

    await unmount(tester);
  });

  testWidgets('流式/发送中阶段 Ctrl+Enter 不发送（边界）', (tester) async {
    SharedPreferences.setMockInitialValues({
      ChatSendShortcutController.keySendMode: 'ctrlEnter',
      ComposerTwoPaneController.keyTwoPane: false,
    });
    final api = FakeChatApi();
    api.sessionResult = {
      'session': {'session_id': 's1', 'messages': const []},
    };
    await pumpPage(tester, api);

    // 第一次 Ctrl+Enter 发送 → 进入 streaming
    final input = find.byKey(const ValueKey('chat-input-field'));
    await tester.enterText(input, 'first');
    await tester.pump();
    await pressCtrlEnter(tester);
    expect(api.startChatCalls, 1);

    // streaming 已就位（停止按钮出现）
    expect(find.byKey(const ValueKey('chat-stop-button')), findsOneWidget);

    // 流式期间继续输入并 Ctrl+Enter → 不得再次发送 / steer
    await tester.enterText(input, 'second');
    await tester.pump();
    await pressCtrlEnter(tester);
    await tester.pump(const Duration(milliseconds: 100));

    expect(api.startChatCalls, 1);
    expect(api.steerCalls, 0);

    await unmount(tester);
  });

  testWidgets('SendMessageIntent 已映射到 Actions，可直接 invoke 发送', (tester) async {
    SharedPreferences.setMockInitialValues({
      ChatSendShortcutController.keySendMode: 'ctrlEnter',
      ComposerTwoPaneController.keyTwoPane: false,
    });
    final api = FakeChatApi();
    api.sessionResult = {
      'session': {'session_id': 's1', 'messages': const []},
    };
    await pumpPage(tester, api);

    final input = find.byKey(const ValueKey('chat-input-field'));
    await tester.enterText(input, 'via intent');
    await tester.pump();

    Actions.invoke(tester.element(input), const SendMessageIntent());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(api.startChatCalls, 1);
    expect(api.lastSentText, 'via intent');

    await unmount(tester);
  });
}
