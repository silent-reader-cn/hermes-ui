import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermex_flutter/features/chat/chat_page.dart';
import 'package:hermex_flutter/features/chat/chat_providers.dart';
import 'package:hermex_flutter/features/chat/widgets/chat_message_list.dart';

import '../../helpers/fake_chat_api.dart';

/// 进入长会话时初始滚动位置必须收敛到底部（最新消息）。
///
/// 回归守卫：lazy ListView 首帧 maxScrollExtent 为估算值，单次 jumpTo
/// 会停在随机中间位置；现改为逐帧复核收敛到真实底部。
void main() {
  Future<void> pumpLongChat(WidgetTester tester, {required Size size}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final api = FakeChatApi();
    final messages = List.generate(
      60,
      (i) => {
        'role': i.isEven ? 'user' : 'assistant',
        'content': '第 $i 条消息：${'这是一段较长的消息内容用于撑高消息气泡。' * 3}',
        'message_id': 'm$i',
      },
    );
    api.sessionResult = {
      'session': {
        'session_id': 's1',
        'title': '长会话',
        'messages': messages,
        'message_count': 60,
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
  }

  ScrollPosition positionOf(WidgetTester tester) {
    final scrollableFinder = find
        .descendant(
          of: find.byType(ChatMessageList),
          matching: find.byType(Scrollable),
        )
        .first;
    return tester.state<ScrollableState>(scrollableFinder).position;
  }

  testWidgets('窄屏：进入 60 条长会话后停在底部', (tester) async {
    await pumpLongChat(tester, size: const Size(390, 844));
    // 收敛循环逐帧复核，settle 到稳定。
    await tester.pumpAndSettle();

    final position = positionOf(tester);
    expect(
      position.pixels,
      closeTo(position.maxScrollExtent, 1.0),
      reason: '初始定位应收敛到真实底部（max=${position.maxScrollExtent}',
    );
  });

  testWidgets('宽屏：进入 60 条长会话后停在底部', (tester) async {
    await pumpLongChat(tester, size: const Size(1280, 800));
    await tester.pumpAndSettle();

    final position = positionOf(tester);
    expect(
      position.pixels,
      closeTo(position.maxScrollExtent, 1.0),
      reason: '初始定位应收敛到真实底部（max=${position.maxScrollExtent}',
    );
  });
}
