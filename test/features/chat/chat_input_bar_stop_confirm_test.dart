import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/providers/clipboard_paste_provider.dart';
import 'package:hermes_ui/core/providers/file_picker_provider.dart';
import 'package:hermes_ui/core/utils/clipboard_paste.dart';
import 'package:hermes_ui/core/utils/file_picker.dart';
import 'package:hermes_ui/features/chat/chat_page.dart';
import 'package:hermes_ui/features/chat/chat_providers.dart';
import 'package:hermes_ui/features/prompts/prompts_providers.dart';
import 'package:hermes_ui/features/settings/composer_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_chat_api.dart';
import '../../helpers/fake_prompts_api.dart';

/// 测试环境未挂 AppLocalizationsDelegate，of() 兜底 zh，文案按中文断言。
const kConfirmDialogTitle = '停止生成？';
const kConfirmDialogPrompt = '确定要停止当前回复吗？已生成的内容会保留。';
const kConfirmStopAction = '停止生成';
const kCancelAction = '取消';

Future<void> _pumpComposer(
  WidgetTester tester, {
  required FakeChatApi chatApi,
  String sessionId = 's1',
}) async {
  final prompts = FakePromptsApi(initialPrompts: const []);
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

/// 发送一条消息进入流式（streaming）阶段，工具行出现停止按钮。
Future<void> _enterStreaming(WidgetTester tester) async {
  final inputFinder = find.byKey(const ValueKey('chat-input-field'));
  await tester.enterText(inputFinder, '测试问题');
  await tester.pump();
  await tester.tap(find.byKey(const ValueKey('chat-send-button')));
  await tester.pump();
  await tester.pump();
  expect(find.byKey(const ValueKey('chat-stop-button')), findsOneWidget);
}

/// 点击停止按钮并等待确认框弹出（入场动画走完）。
Future<void> _openStopConfirm(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('chat-stop-button')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  expect(find.byType(CupertinoAlertDialog), findsOneWidget);
}

/// 点击对话框动作按钮并等待关闭动画完全结束（退场约 600ms，
/// 需等足时长让 dialog route 从树中移除）。
Future<void> _tapDialogAction(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pump();
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
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

  group('ChatInputBar 停止生成二次确认框（todo #19）', () {
    testWidgets('分支一：流式点停止 → 弹确认框，确认前不真正停止', (tester) async {
      final chatApi = FakeChatApi();
      chatApi.sessionResult = {
        'session': {'session_id': 's1', 'messages': const []},
      };
      await _pumpComposer(tester, chatApi: chatApi);
      await _enterStreaming(tester);

      await _openStopConfirm(tester);

      // 确认框含标题、提示文案与「取消/停止生成」两个动作
      expect(find.text(kConfirmDialogTitle), findsOneWidget);
      expect(find.text(kConfirmDialogPrompt), findsOneWidget);
      expect(find.text(kCancelAction), findsOneWidget);
      expect(find.text(kConfirmStopAction), findsOneWidget);

      // 未点击确认：controller.stop() 未被调用
      expect(chatApi.cancelCalls, 0);

      await _unmount(tester);
    });

    testWidgets('分支二：确认「停止生成」→ 真正停止并关闭对话框', (tester) async {
      final chatApi = FakeChatApi();
      chatApi.sessionResult = {
        'session': {'session_id': 's1', 'messages': const []},
      };
      await _pumpComposer(tester, chatApi: chatApi);
      await _enterStreaming(tester);

      await _openStopConfirm(tester);
      await _tapDialogAction(tester, kConfirmStopAction);

      // 对话框已关闭，且真正调用了 cancelChat
      expect(find.byType(CupertinoAlertDialog), findsNothing);
      expect(chatApi.cancelCalls, 1);

      await _unmount(tester);
    });

    testWidgets('分支三：点「取消」→ 不停止，对话框关闭、流式继续', (tester) async {
      final chatApi = FakeChatApi();
      chatApi.sessionResult = {
        'session': {'session_id': 's1', 'messages': const []},
      };
      await _pumpComposer(tester, chatApi: chatApi);
      await _enterStreaming(tester);

      await _openStopConfirm(tester);
      await _tapDialogAction(tester, kCancelAction);

      expect(find.byType(CupertinoAlertDialog), findsNothing);
      expect(chatApi.cancelCalls, 0);
      // 流式仍在继续：停止按钮仍在工具行
      expect(find.byKey(const ValueKey('chat-stop-button')), findsOneWidget);

      await _unmount(tester);
    });

    testWidgets('两段式布局：停止按钮同样弹确认框，确认后停止', (tester) async {
      SharedPreferences.setMockInitialValues({
        ComposerTwoPaneController.keyTwoPane: true,
      });
      final chatApi = FakeChatApi();
      chatApi.sessionResult = {
        'session': {'session_id': 's1', 'messages': const []},
      };
      await _pumpComposer(tester, chatApi: chatApi);
      await tester.pump(const Duration(milliseconds: 50));
      await _enterStreaming(tester);

      await _openStopConfirm(tester);
      expect(chatApi.cancelCalls, 0);

      await _tapDialogAction(tester, kConfirmStopAction);

      expect(find.byType(CupertinoAlertDialog), findsNothing);
      expect(chatApi.cancelCalls, 1);

      await _unmount(tester);
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });
  });
}
