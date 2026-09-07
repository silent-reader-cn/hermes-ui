import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
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

/// 发送快捷键模式 widget 测试：
/// 1. 经典单行路径：enter 模式 vs ctrlEnter 模式（豁口一修复 + 防双发守卫）
/// 2. 两段式路径：enter 模式 vs ctrlEnter 模式（豁口二修复）
/// 3. 双发探针测试：Shortcuts 与 onSubmitted 触发矩阵实测
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({ComposerTwoPaneController.keyTwoPane: false});
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
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

  /// 模拟按下 Cmd+Enter 组合键（macOS）。
  Future<void> pressCmdEnter(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
    await tester.pump();
  }

  /// 模拟按下 Shift+Enter 组合键。
  Future<void> pressShiftEnter(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    await tester.pump();
  }

  group('经典单行模式（twoPane == false）', () {
    testWidgets('默认 enter 模式：输入框保持单行（maxLines == 4）', (tester) async {
      SharedPreferences.setMockInitialValues({
        ComposerTwoPaneController.keyTwoPane: false,
      });
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

    testWidgets('ctrlEnter 模式：Cmd+Enter 发送并清空输入框', (tester) async {
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
      await tester.enterText(input, 'hello cmd');
      await tester.pump();

      await pressCmdEnter(tester);

      expect(api.startChatCalls, 1);
      expect(api.lastSentText, 'hello cmd');
      expect(field(tester).controller!.text, isEmpty);

      await unmount(tester);
    });

    testWidgets('ctrlEnter 模式（豁口一）：键盘裸 Enter 不发送，保留输入内容', (tester) async {
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
      expect(field(tester).controller!.text, 'hello');

      await unmount(tester);
    });

    testWidgets('ctrlEnter 模式（豁口一主测试）：onSubmitted / IME done 动作不发送，保留输入内容', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
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
        await tester.tap(input);
        await tester.pump();
        await tester.enterText(input, 'hello not submitted');
        await tester.pump();

        // 模拟 Windows 平台桌面 IME 提交 TextInputAction.done（豁口一根因路径）
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();
        await tester.pump();

        // 模式守卫拦截成功，不触发发送且文本完整保留
        expect(api.startChatCalls, 0);
        expect(field(tester).controller!.text, 'hello not submitted');

        await unmount(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('enter 模式：裸 Enter 触发 onSubmitted 发送并清空输入框', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        SharedPreferences.setMockInitialValues({
          ChatSendShortcutController.keySendMode: 'enter',
          ComposerTwoPaneController.keyTwoPane: false,
        });
        final api = FakeChatApi();
        api.sessionResult = {
          'session': {'session_id': 's1', 'messages': const []},
        };
        await pumpPage(tester, api);

        final input = find.byKey(const ValueKey('chat-input-field'));
        await tester.tap(input);
        await tester.pump();
        await tester.enterText(input, 'enter 模式消息');
        await tester.pump();

        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();
        await tester.pump();

        expect(api.startChatCalls, 1);
        expect(api.lastSentText, 'enter 模式消息');
        expect(field(tester).controller!.text, isEmpty);

        await unmount(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('enter 模式：Ctrl+Enter 发送且严格不双发（startChatCalls == 1）', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        SharedPreferences.setMockInitialValues({
          ChatSendShortcutController.keySendMode: 'enter',
          ComposerTwoPaneController.keyTwoPane: false,
        });
        final api = FakeChatApi();
        api.sessionResult = {
          'session': {'session_id': 's1', 'messages': const []},
        };
        await pumpPage(tester, api);

        final input = find.byKey(const ValueKey('chat-input-field'));
        await tester.tap(input);
        await tester.pump();
        await tester.enterText(input, 'single send');
        await tester.pump();

        await pressCtrlEnter(tester);

        expect(api.startChatCalls, 1);
        expect(api.lastSentText, 'single send');
        expect(field(tester).controller!.text, isEmpty);

        await unmount(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('enter 模式：Cmd+Enter 发送且严格不双发（startChatCalls == 1）', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        SharedPreferences.setMockInitialValues({
          ChatSendShortcutController.keySendMode: 'enter',
          ComposerTwoPaneController.keyTwoPane: false,
        });
        final api = FakeChatApi();
        api.sessionResult = {
          'session': {'session_id': 's1', 'messages': const []},
        };
        await pumpPage(tester, api);

        final input = find.byKey(const ValueKey('chat-input-field'));
        await tester.tap(input);
        await tester.pump();
        await tester.enterText(input, 'cmd send');
        await tester.pump();

        await pressCmdEnter(tester);

        expect(api.startChatCalls, 1);
        expect(api.lastSentText, 'cmd send');
        expect(field(tester).controller!.text, isEmpty);

        await unmount(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
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
  });

  group('两段式模式（twoPane == true, isDesktop == true）', () {
    testWidgets('两段式 + ctrlEnter 模式（豁口二）：桌面裸 Enter 插入换行不发送', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        SharedPreferences.setMockInitialValues({
          ComposerTwoPaneController.keyTwoPane: true,
          ChatSendShortcutController.keySendMode: 'ctrlEnter',
        });
        final api = FakeChatApi();
        api.sessionResult = {
          'session': {'session_id': 's1', 'messages': const []},
        };
        await pumpPage(tester, api);

        final input = find.byKey(const ValueKey('chat-input-field'));
        await tester.tap(input);
        await tester.pump();
        await tester.enterText(input, 'line1');
        await tester.pump();

        // 按 Enter 键：映射为 InsertNewlineIntent，不发送
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();

        expect(api.startChatCalls, 0);
        expect(field(tester).controller!.text, 'line1\n');

        await unmount(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('两段式 + ctrlEnter 模式：桌面 Shift+Enter 插入换行不发送', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        SharedPreferences.setMockInitialValues({
          ComposerTwoPaneController.keyTwoPane: true,
          ChatSendShortcutController.keySendMode: 'ctrlEnter',
        });
        final api = FakeChatApi();
        api.sessionResult = {
          'session': {'session_id': 's1', 'messages': const []},
        };
        await pumpPage(tester, api);

        final input = find.byKey(const ValueKey('chat-input-field'));
        await tester.tap(input);
        await tester.pump();
        await tester.enterText(input, 'line1');
        await tester.pump();

        await pressShiftEnter(tester);

        expect(api.startChatCalls, 0);
        expect(field(tester).controller!.text, 'line1\n');

        await unmount(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('两段式 + ctrlEnter 模式：桌面 Ctrl+Enter 发送并清空输入框', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        SharedPreferences.setMockInitialValues({
          ComposerTwoPaneController.keyTwoPane: true,
          ChatSendShortcutController.keySendMode: 'ctrlEnter',
        });
        final api = FakeChatApi();
        api.sessionResult = {
          'session': {'session_id': 's1', 'messages': const []},
        };
        await pumpPage(tester, api);

        final input = find.byKey(const ValueKey('chat-input-field'));
        await tester.tap(input);
        await tester.pump();
        await tester.enterText(input, 'two pane ctrl send');
        await tester.pump();

        await pressCtrlEnter(tester);

        expect(api.startChatCalls, 1);
        expect(api.lastSentText, 'two pane ctrl send');
        expect(field(tester).controller!.text, isEmpty);

        await unmount(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('两段式 + ctrlEnter 模式：桌面 Cmd+Enter 发送并清空输入框', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        SharedPreferences.setMockInitialValues({
          ComposerTwoPaneController.keyTwoPane: true,
          ChatSendShortcutController.keySendMode: 'ctrlEnter',
        });
        final api = FakeChatApi();
        api.sessionResult = {
          'session': {'session_id': 's1', 'messages': const []},
        };
        await pumpPage(tester, api);

        final input = find.byKey(const ValueKey('chat-input-field'));
        await tester.tap(input);
        await tester.pump();
        await tester.enterText(input, 'two pane cmd send');
        await tester.pump();

        await pressCmdEnter(tester);

        expect(api.startChatCalls, 1);
        expect(api.lastSentText, 'two pane cmd send');
        expect(field(tester).controller!.text, isEmpty);

        await unmount(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('两段式 + enter 模式：桌面裸 Enter 发送并清空输入框', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        SharedPreferences.setMockInitialValues({
          ComposerTwoPaneController.keyTwoPane: true,
          ChatSendShortcutController.keySendMode: 'enter',
        });
        final api = FakeChatApi();
        api.sessionResult = {
          'session': {'session_id': 's1', 'messages': const []},
        };
        await pumpPage(tester, api);

        final input = find.byKey(const ValueKey('chat-input-field'));
        await tester.tap(input);
        await tester.pump();
        await tester.enterText(input, 'two pane enter send');
        await tester.pump();

        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        await tester.pump();

        expect(api.startChatCalls, 1);
        expect(api.lastSentText, 'two pane enter send');
        expect(field(tester).controller!.text, isEmpty);

        await unmount(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('两段式 + enter 模式：桌面 Shift+Enter 插入换行不发送', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        SharedPreferences.setMockInitialValues({
          ComposerTwoPaneController.keyTwoPane: true,
          ChatSendShortcutController.keySendMode: 'enter',
        });
        final api = FakeChatApi();
        api.sessionResult = {
          'session': {'session_id': 's1', 'messages': const []},
        };
        await pumpPage(tester, api);

        final input = find.byKey(const ValueKey('chat-input-field'));
        await tester.tap(input);
        await tester.pump();
        await tester.enterText(input, 'line1');
        await tester.pump();

        await pressShiftEnter(tester);

        expect(api.startChatCalls, 0);
        expect(field(tester).controller!.text, 'line1\n');

        await unmount(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('两段式 + enter 模式：桌面 Ctrl+Enter 发送且不双发（startChatCalls == 1）', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        SharedPreferences.setMockInitialValues({
          ComposerTwoPaneController.keyTwoPane: true,
          ChatSendShortcutController.keySendMode: 'enter',
        });
        final api = FakeChatApi();
        api.sessionResult = {
          'session': {'session_id': 's1', 'messages': const []},
        };
        await pumpPage(tester, api);

        final input = find.byKey(const ValueKey('chat-input-field'));
        await tester.tap(input);
        await tester.pump();
        await tester.enterText(input, 'two pane ctrl send');
        await tester.pump();

        await pressCtrlEnter(tester);

        expect(api.startChatCalls, 1);
        expect(api.lastSentText, 'two pane ctrl send');
        expect(field(tester).controller!.text, isEmpty);

        await unmount(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  group('发送快捷键双发探针（Shortcuts 与 onSubmitted 触发矩阵实测）', () {
    testWidgets('探针 1：经典 + enter 模式下 Ctrl+Enter 与 onSubmitted 双路触发实测不双发', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        SharedPreferences.setMockInitialValues({
          ComposerTwoPaneController.keyTwoPane: false,
          ChatSendShortcutController.keySendMode: 'enter',
        });
        final api = FakeChatApi();
        api.sessionResult = {
          'session': {'session_id': 's1', 'messages': const []},
        };
        await pumpPage(tester, api);

        final input = find.byKey(const ValueKey('chat-input-field'));
        await tester.tap(input);
        await tester.pump();
        await tester.enterText(input, 'probe-enter-ctrl');
        await tester.pump();

        // 模拟桌面端用户按下 Ctrl+Enter：Shortcuts 触发 SendMessageIntent
        // 同时注入修饰键有效时的 onSubmitted (TextInputAction.done)，探查是否双发
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pump();
        await tester.pump();

        // 守卫拦截了 onSubmitted，Shortcuts 执行一次发送，计数严格为 1
        expect(api.startChatCalls, 1);
        expect(api.lastSentText, 'probe-enter-ctrl');
        expect(field(tester).controller!.text, isEmpty);

        await unmount(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('探针 2：经典 + ctrlEnter 模式下裸 Enter 触发 onSubmitted 守卫实测不发送', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        SharedPreferences.setMockInitialValues({
          ComposerTwoPaneController.keyTwoPane: false,
          ChatSendShortcutController.keySendMode: 'ctrlEnter',
        });
        final api = FakeChatApi();
        api.sessionResult = {
          'session': {'session_id': 's1', 'messages': const []},
        };
        await pumpPage(tester, api);

        final input = find.byKey(const ValueKey('chat-input-field'));
        await tester.tap(input);
        await tester.pump();
        await tester.enterText(input, 'probe-ctrlenter-bare');
        await tester.pump();

        // 裸 Enter：无修饰键，模拟 Windows 平台 TextInputAction.done
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();
        await tester.pump();

        // 守卫基于模式 (sendMode == ctrlEnter) 彻底拦截 onSubmitted
        expect(api.startChatCalls, 0);
        expect(field(tester).controller!.text, 'probe-ctrlenter-bare');

        await unmount(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('探针 3：经典 + ctrlEnter 模式下 Ctrl+Enter 触发 Shortcuts，onSubmitted 守卫不双发', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        SharedPreferences.setMockInitialValues({
          ComposerTwoPaneController.keyTwoPane: false,
          ChatSendShortcutController.keySendMode: 'ctrlEnter',
        });
        final api = FakeChatApi();
        api.sessionResult = {
          'session': {'session_id': 's1', 'messages': const []},
        };
        await pumpPage(tester, api);

        final input = find.byKey(const ValueKey('chat-input-field'));
        await tester.tap(input);
        await tester.pump();
        await tester.enterText(input, 'probe-ctrlenter-ctrl');
        await tester.pump();

        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pump();
        await tester.pump();

        expect(api.startChatCalls, 1);
        expect(api.lastSentText, 'probe-ctrlenter-ctrl');
        expect(field(tester).controller!.text, isEmpty);

        await unmount(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('探针 4：两段式桌面路径 Shortcuts 表分流实测', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        SharedPreferences.setMockInitialValues({
          ComposerTwoPaneController.keyTwoPane: true,
          ChatSendShortcutController.keySendMode: 'ctrlEnter',
        });
        final api = FakeChatApi();
        api.sessionResult = {
          'session': {'session_id': 's1', 'messages': const []},
        };
        await pumpPage(tester, api);

        final input = find.byKey(const ValueKey('chat-input-field'));
        await tester.tap(input);
        await tester.pump();
        await tester.enterText(input, 'probe-twopane');
        await tester.pump();

        // 裸 Enter -> InsertNewlineIntent，不发送
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(api.startChatCalls, 0);
        expect(field(tester).controller!.text, 'probe-twopane\n');

        // Ctrl+Enter -> SendIntent，发送且调用计数为 1
        await pressCtrlEnter(tester);
        expect(api.startChatCalls, 1);
        expect(api.lastSentText, 'probe-twopane');
        expect(field(tester).controller!.text, isEmpty);

        await unmount(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });
}
