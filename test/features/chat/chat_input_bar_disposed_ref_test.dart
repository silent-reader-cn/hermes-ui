import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/api/api_exception.dart';
import 'package:hermes_ui/core/models/server_catalog.dart';
import 'package:hermes_ui/features/chat/chat_page.dart';
import 'package:hermes_ui/features/chat/chat_providers.dart';

import '../../helpers/fake_chat_api.dart';

/// startChat 挂起在 gate 上，由测试决定何时放行。
class _GatedApi extends FakeChatApi {
  final Completer<void> gate = Completer<void>();

  @override
  Future<ChatStartResponse> startChat({
    required String sessionId,
    required String message,
    String? workspace,
    String? model,
    String? modelProvider,
    String? profile,
    bool explicitModelPick = false,
    List<Map<String, Object?>>? attachments,
  }) async {
    await gate.future;
    return super.startChat(
      sessionId: sessionId,
      message: message,
      workspace: workspace,
      model: model,
      modelProvider: modelProvider,
      profile: profile,
      explicitModelPick: explicitModelPick,
      attachments: attachments,
    );
  }
}

/// 回归：发送途中页面被销毁（切会话/退页）→ `_submit` 的 await 之后不得再
/// 触碰 `ref`（platform_error: Cannot use "ref" after the widget was
/// disposed，chat_input_bar.dart:265）。修复法：await 前捕获全部 notifier，
/// UI 回填路径 mounted 守卫。unhandled StateError 会被测试框架捕获致失败。
void main() {
  Future<ProviderContainer> pumpChat(
    WidgetTester tester,
    _GatedApi api,
  ) async {
    final container = ProviderContainer(
      overrides: [chatApiProvider.overrideWithValue(api)],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const CupertinoApp(home: ChatPage(sessionId: 's1')),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    return container;
  }

  Future<void> unmount(
    WidgetTester tester,
    ProviderContainer container,
  ) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const SizedBox()),
    );
    await tester.pump();
  }

  testWidgets('发送途中退页 → await 后不再用 ref，无 StateError（成功路径）', (
    tester,
  ) async {
    final api = _GatedApi();
    api.sessionResult = {
      'session': {'session_id': 's1', 'messages': const []},
    };
    final container = await pumpChat(tester, api);

    await tester.enterText(
      find.byKey(const ValueKey('chat-input-field')),
      'hello world',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('chat-send-button')));
    await tester.pump();
    expect(api.startChatCalls, 0); // 仍在 gate 上挂起

    // 发送在途：销毁输入栏所在页面 → widget dispose。
    await unmount(tester, container);

    // 放行 startChat → _submit 的 await 在 disposed 状态下恢复。
    api.gate.complete();
    await tester.pump(); // 微任务：send 返回 true → clear 路径（旧代码在此炸 ref）
    await tester.pump(const Duration(milliseconds: 100));

    expect(api.lastSentText, 'hello world');
    container.dispose();
  });

  testWidgets('发送失败 + 页面已销毁 → 回填走 mounted 守卫，不抛 StateError', (
    tester,
  ) async {
    final api = _GatedApi();
    api.sessionResult = {
      'session': {'session_id': 's1', 'messages': const []},
    };
    final container = await pumpChat(tester, api);

    await tester.enterText(
      find.byKey(const ValueKey('chat-input-field')),
      'fallback text',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('chat-send-button')));
    await tester.pump();

    await unmount(tester, container);

    // 放行后 super.startChat 抛 ApiException → send 返回 false → 失败分支
    // （旧代码在此触碰已 dispose 的 _textController 与 ref）。
    api.startChatError = NetworkException(NetworkExceptionKind.cannotConnect);
    api.gate.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    container.dispose();
  });
}
