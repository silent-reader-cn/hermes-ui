// #25 回归测试：消息操作「编辑并重新发送」→ 输入框回填原文。
//
// 覆盖验收 2/3/4：多行长文本回填（光标在末尾）、经典与两段式均生效、
// 连点第二次同一条仍生效；另补「消费后 provider 清除」与「只读会话静默」。
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/features/chat/chat_page.dart';
import 'package:hermes_ui/features/chat/chat_providers.dart';
import 'package:hermes_ui/features/chat/widgets/message_bubble.dart';
import 'package:hermes_ui/features/settings/composer_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_chat_api.dart';

/// 多行长文本消息原文（验收：含多行/长文本）。
const _originalText = '第一行原文\n第二行\n'
    '第三行很长很长很长很长很长很长很长很长很长很长很长很长很长很长';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  FakeChatApi apiWithUserMessage() {
    final api = FakeChatApi();
    api.sessionResult = {
      'session': {
        'session_id': 's1',
        'messages': [
          {'role': 'user', 'content': _originalText, 'message_id': 'm1'},
        ],
      },
    };
    return api;
  }

  /// 长按用户消息气泡 → 菜单点「编辑并重新发送」。
  Future<void> tapEditAndResend(WidgetTester tester) async {
    final bubble = find.byType(ChatMessageBubble).first;
    final rect = tester.getRect(bubble);
    await tester.longPressAt(rect.topLeft + const Offset(8, 8));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.byKey(const ValueKey('msg-action-edit')),
      findsOneWidget,
      reason: 'user 消息长按菜单应含「编辑并重新发送」',
    );
    await tester.tap(find.byKey(const ValueKey('msg-action-edit')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  (String, String) readInput(WidgetTester tester) {
    final field = tester.widget<CupertinoTextField>(
      find.byKey(const ValueKey('chat-input-field')),
    );
    return (field.controller!.text, field.controller!.selection.baseOffset
        .toString());
  }

  group('#25 编辑并重新发送 → 输入框回填', () {
    testWidgets('经典单行：回填消息原文（多行/长文本），光标在末尾', (tester) async {
      final api = apiWithUserMessage();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [chatApiProvider.overrideWithValue(api)],
          child: const CupertinoApp(home: ChatPage(sessionId: 's1')),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      await tapEditAndResend(tester);

      final (text, selection) = readInput(tester);
      expect(text, _originalText);
      expect(int.parse(selection), _originalText.length,
          reason: '光标应置于回填文本末尾');

      // 一次性语义：消费后 provider 值已清除（unawaited 写→消费→clear）。
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ChatPage)),
      );
      expect(
        container.read(chatControllerProvider('s1')).composerPrefill,
        isNull,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('连点第二次同一条仍生效（_appliedPrefill 去重不误吞）', (tester) async {
      final api = apiWithUserMessage();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [chatApiProvider.overrideWithValue(api)],
          child: const CupertinoApp(home: ChatPage(sessionId: 's1')),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // 第一次点编辑。
      await tapEditAndResend(tester);
      final (firstText, _) = readInput(tester);
      expect(firstText, _originalText);

      // 第二次长按同一条 → 再点编辑。
      await tapEditAndResend(tester);
      final (secondText, selection) = readInput(tester);
      expect(secondText, _originalText, reason: '连点第二次仍应回填（去重不吞）');
      expect(int.parse(selection), _originalText.length);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });

    testWidgets('两段式输入模式：同一消费路径同样生效', (tester) async {
      SharedPreferences.setMockInitialValues({
        ComposerTwoPaneController.keyTwoPane: true,
      });
      final api = apiWithUserMessage();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [chatApiProvider.overrideWithValue(api)],
          child: const CupertinoApp(home: ChatPage(sessionId: 's1')),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50)); // 等两段式开关异步读

      // 确认两段式布局生效（多行文本区 minLines 2）。
      final field = tester.widget<CupertinoTextField>(
        find.byKey(const ValueKey('chat-input-field')),
      );
      expect(field.minLines, 2);

      await tapEditAndResend(tester);
      final (text, _) = readInput(tester);
      expect(text, _originalText);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    testWidgets('只读会话：点编辑不回填（静默 return 属预期）', (tester) async {
      final api = FakeChatApi();
      api.sessionResult = {
        'session': {
          'session_id': 's1',
          'read_only': true,
          'messages': [
            {'role': 'user', 'content': _originalText, 'message_id': 'm1'},
          ],
        },
      };
      await tester.pumpWidget(
        ProviderScope(
          overrides: [chatApiProvider.overrideWithValue(api)],
          child: const CupertinoApp(home: ChatPage(sessionId: 's1')),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      await tapEditAndResend(tester);
      final (text, _) = readInput(tester);
      expect(text, isEmpty, reason: '只读会话 prefillComposer 静默 return');

      final container = ProviderScope.containerOf(
        tester.element(find.byType(ChatPage)),
      );
      expect(
        container.read(chatControllerProvider('s1')).composerPrefill,
        isNull,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
  });
}