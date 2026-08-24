import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermex_flutter/features/chat/chat_providers.dart';
import 'package:hermex_flutter/features/chat/widgets/chat_message_list.dart';
import '../../helpers/fake_chat_api.dart';

void main() {
  testWidgets('同 content 无 messageId 以 renderId 去重', (tester) async {
    final api = FakeChatApi();
    api.sessionResult = {
      'session': {
        'session_id': 's-dup',
        'messages': [
          {'role': 'user', 'content': '重复文本'},
          {'role': 'assistant', 'content': '重复文本'},
        ],
      },
    };
    await tester.pumpWidget(
      ProviderScope(
        overrides: [chatApiProvider.overrideWithValue(api)],
        child: const CupertinoApp(home: CupertinoPageScaffold(child: ChatMessageList(sessionId: 's-dup'))),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
    expect(find.text('重复文本'), findsNWidgets(2));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('同 messageId 仍以 renderId 区分', (tester) async {
    final api = FakeChatApi();
    api.sessionResult = {
      'session': {
        'session_id': 's-dup2',
        'messages': [
          {'role': 'user', 'content': 'A', 'message_id': 'dup-id'},
          {'role': 'assistant', 'content': 'B', 'message_id': 'dup-id'},
        ],
      },
    };
    await tester.pumpWidget(
      ProviderScope(
        overrides: [chatApiProvider.overrideWithValue(api)],
        child: const CupertinoApp(home: CupertinoPageScaffold(child: ChatMessageList(sessionId: 's-dup2'))),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
    expect(find.text('A'), findsOneWidget);
    expect(find.text('B'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
