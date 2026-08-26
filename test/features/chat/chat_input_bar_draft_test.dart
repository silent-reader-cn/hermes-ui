import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermex_flutter/core/models/upload_response.dart';
import 'package:hermex_flutter/features/chat/chat_draft_provider.dart';
import 'package:hermex_flutter/features/chat/chat_page.dart';
import 'package:hermex_flutter/features/chat/chat_providers.dart';
import 'package:hermex_flutter/features/chat/pending_attachments_provider.dart';
import 'package:hermex_flutter/features/settings/chat_send_shortcut_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_chat_api.dart';

/// 会话级草稿 + pending 附件跨会话保留测试：
/// - 输入框文字按 sessionId 隔离持久（切会话/进设置页再返回不丢）；
/// - 发送成功后草稿清空；发送失败回填草稿；
/// - pending 附件按 sessionId 隔离常驻（无 autoDispose）。
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  final attachment = PendingAttachment(
    name: 'a.png',
    path: '/tmp/a.png',
    mime: 'image/png',
    size: 10,
    isImage: true,
    thumbnailData: Uint8List.fromList([1, 2, 3]),
  );

  ProviderContainer makeContainer(FakeChatApi api) {
    // 注意：不定 addTearDown —— 容器生命周期由测试体末尾显式 dispose
    // （ChatController 的 watchdog periodic timer 需随容器销毁取消，
    // 否则 flutter_test 的 timersPending 断言失败）。
    return ProviderContainer(
      overrides: [chatApiProvider.overrideWithValue(api)],
    );
  }

  Future<void> pumpChat(
    WidgetTester tester,
    ProviderContainer container,
    String sessionId,
  ) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: CupertinoApp(home: ChatPage(sessionId: sessionId)),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  Future<void> unmount(WidgetTester tester, ProviderContainer container) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const SizedBox()),
    );
    await tester.pump();
  }

  CupertinoTextField field(WidgetTester tester) =>
      tester.widget<CupertinoTextField>(
        find.byKey(const ValueKey('chat-input-field')),
      );

  FakeChatApi makeApi() {
    final api = FakeChatApi();
    api.sessionResult = {
      'session': {'session_id': 's1', 'messages': const []},
    };
    return api;
  }

  test('草稿按 sessionId 隔离：写入/读取/清空/互不影响', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(chatDraftProvider('s1').notifier).update('在 s1 写的东西');
    container.read(chatDraftProvider('s2').notifier).update('s2 的内容');
    expect(container.read(chatDraftProvider('s1')), '在 s1 写的东西');
    expect(container.read(chatDraftProvider('s2')), 's2 的内容');

    container.read(chatDraftProvider('s1').notifier).clear();
    expect(container.read(chatDraftProvider('s1')), isEmpty);
    expect(container.read(chatDraftProvider('s2')), 's2 的内容');
  });

  testWidgets('输入文字后卸载再挂载，同一会话草稿恢复', (tester) async {
    final api = makeApi();
    final container = makeContainer(api);

    await pumpChat(tester, container, 's1');
    await tester.enterText(
      find.byKey(const ValueKey('chat-input-field')),
      '草稿内容-请保留',
    );
    await tester.pump();
    expect(container.read(chatDraftProvider('s1')), '草稿内容-请保留');

    // 切走（模拟进入设置页/切会话），再挂回 s1。
    await unmount(tester, container);
    await pumpChat(tester, container, 's1');

    expect(field(tester).controller!.text, '草稿内容-请保留');
    container.dispose();
  });

  testWidgets('会话间草稿独立：s1 写草稿，切 s2 为空，切回 s1 恢复', (tester) async {
    final api = makeApi();
    final container = makeContainer(api);

    await pumpChat(tester, container, 's1');
    await tester.enterText(
      find.byKey(const ValueKey('chat-input-field')),
      's1 专属草稿',
    );
    await tester.pump();
    expect(container.read(chatDraftProvider('s1')), 's1 专属草稿');

    // 切到 s2：输入框应空（s2 无草稿）。
    await pumpChat(tester, container, 's2');
    expect(field(tester).controller!.text, isEmpty);

    // s2 输入内容不影响 s1 草稿。
    await tester.enterText(
      find.byKey(const ValueKey('chat-input-field')),
      's2 的临时输入',
    );
    await tester.pump();
    expect(container.read(chatDraftProvider('s1')), 's1 专属草稿');
    expect(container.read(chatDraftProvider('s2')), 's2 的临时输入');

    // 切回 s1：恢复 s1 草稿。
    await pumpChat(tester, container, 's1');
    expect(field(tester).controller!.text, 's1 专属草稿');
    container.dispose();
  });

  testWidgets('发送成功后草稿清空', (tester) async {
    SharedPreferences.setMockInitialValues({
      ChatSendShortcutController.keySendMode: 'ctrlEnter',
    });
    final api = makeApi();
    final container = makeContainer(api);

    await pumpChat(tester, container, 's1');
    await tester.enterText(
      find.byKey(const ValueKey('chat-input-field')),
      '发送这条',
    );
    await tester.pump();
    expect(container.read(chatDraftProvider('s1')), '发送这条');

    // Ctrl+Enter 发送。
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.pump();

    expect(api.startChatCalls, 1);
    expect(container.read(chatDraftProvider('s1')), isEmpty);
    container.dispose();
  });

  test('pending 附件按 sessionId 隔离常驻（切会话/返回不丢）', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(pendingAttachmentsProvider('s1').notifier).add(attachment);
    expect(container.read(pendingAttachmentsProvider('s1')), hasLength(1));

    // 其他会话不受影响。
    expect(container.read(pendingAttachmentsProvider('s2')), isEmpty);

    // 回到 s1 仍在（family 无常驻 autoDispose）。
    expect(container.read(pendingAttachmentsProvider('s1')), hasLength(1));
  });
}