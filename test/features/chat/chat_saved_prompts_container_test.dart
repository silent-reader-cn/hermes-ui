import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/models/saved_prompt.dart';
import 'package:hermes_ui/features/chat/chat_page.dart';
import 'package:hermes_ui/features/chat/chat_providers.dart';
import 'package:hermes_ui/features/prompts/prompts_providers.dart';
import 'package:hermes_ui/features/prompts/widgets/saved_prompts_sheet.dart';

import '../../helpers/fake_chat_api.dart';
import '../../helpers/fake_prompts_api.dart';

/// 收藏提示词弹层容器分支：
/// - 宽屏（桌面双栏）：图标上方 popover，不再占满底部整宽；
/// - 窄屏（手机）：保持系统底部 Sheet。
void main() {
  Widget buildApp({
    required FakeChatApi chatApi,
    required FakePromptsApi promptsApi,
  }) {
    return ProviderScope(
      overrides: [
        chatApiProvider.overrideWithValue(chatApi),
        promptsApiFactoryProvider.overrideWithValue((_) => promptsApi),
        apiClientProvider.overrideWithValue(
          ApiClient(baseUrl: 'http://test.local:30002'),
        ),
      ],
      child: const CupertinoApp(home: ChatPage(sessionId: 's1')),
    );
  }

  FakePromptsApi buildPromptsApi() {
    return FakePromptsApi(
      initialPrompts: const [
        SavedPrompt(id: 'p1', label: '代码审查模板', text: '请帮我审查以下代码：'),
        SavedPrompt(id: 'p2', label: '周报模板', text: '汇总本周工作：'),
      ],
    );
  }

  Future<void> pumpChat(WidgetTester tester, {required bool wide}) async {
    tester.view.physicalSize = wide
        ? const Size(1280, 800)
        : const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final chatApi = FakeChatApi();
    chatApi.sessionResult = {
      'session': {'session_id': 's1', 'messages': const []},
    };
    await tester.pumpWidget(
      buildApp(chatApi: chatApi, promptsApi: buildPromptsApi()),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  Future<void> openSavedPrompts(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('chat-saved-prompts-button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('宽屏：点击书签在图标上方弹出 popover（非底部 Sheet）', (tester) async {
    await pumpChat(tester, wide: true);
    await openSavedPrompts(tester);

    // popover 卡片出现：内容面板在、底部全宽 Sheet 不在。
    expect(find.byType(SavedPromptsPanel), findsOneWidget);
    expect(find.byType(SavedPromptsSheet), findsNothing);
    expect(find.text('代码审查模板'), findsOneWidget);
    expect(find.text('周报模板'), findsOneWidget);

    // popover 位于输入栏上方区域（不遮蔽输入区）：锚点按钮在屏底，
    // 弹层 top < 锚点 top。
    final anchor = tester.getRect(
      find.byKey(const ValueKey('chat-saved-prompts-button')),
    );
    final panel = tester.getRect(find.byType(SavedPromptsPanel));
    expect(panel.top, lessThan(anchor.top));
    expect(panel.bottom, lessThanOrEqualTo(anchor.top));
  });

  testWidgets('宽屏：点列表项插入输入框并自动关闭 popover', (tester) async {
    await pumpChat(tester, wide: true);
    await openSavedPrompts(tester);

    await tester.tap(find.text('代码审查模板'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(SavedPromptsPanel), findsNothing);
    final field = tester.widget<CupertinoTextField>(
      find.byKey(const ValueKey('chat-input-field')),
    );
    expect(field.controller!.text, '请帮我审查以下代码：');
  });

  testWidgets('宽屏：点击 popover 外区域关闭', (tester) async {
    await pumpChat(tester, wide: true);
    await openSavedPrompts(tester);
    expect(find.byType(SavedPromptsPanel), findsOneWidget);

    // 点击 popover 外的空白（右上内容区，避开输入栏按钮）。
    await tester.tapAt(const Offset(1100, 100));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(SavedPromptsPanel), findsNothing);
  });

  testWidgets('窄屏：保持底部 Sheet 容器', (tester) async {
    await pumpChat(tester, wide: false);
    await openSavedPrompts(tester);

    expect(find.byType(SavedPromptsSheet), findsOneWidget);
    // Sheet 内同样承载列表与「收藏当前输入」按钮。
    expect(
      find.byKey(const ValueKey('saved-prompts-save-current')),
      findsOneWidget,
    );
    expect(find.text('代码审查模板'), findsOneWidget);
  });
}
