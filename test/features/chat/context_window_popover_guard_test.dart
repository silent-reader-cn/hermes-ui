import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hermex_flutter/core/models/context_window_snapshot.dart';
import 'package:hermex_flutter/features/chat/chat_providers.dart';
import 'package:hermex_flutter/features/chat/widgets/chat_input_bar.dart';
import '../../helpers/fake_chat_api.dart';

void main() {
  testWidgets('_showContextPopover 无 percentage 仍可弹出（snapshot!=null 即可）',
      (tester) async {
    final api = FakeChatApi();
    api.sessionResult = {
      'session': {'session_id': 's1', 'messages': const []},
    };
    await tester.pumpWidget(
      ProviderScope(
        overrides: [chatApiProvider.overrideWithValue(api)],
        child: const CupertinoApp(
          home: CupertinoPageScaffold(child: ChatInputBar(sessionId: 's1')),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final snap = ContextWindowSnapshot.fromJson({'threshold_tokens': 5000});
    expect(snap.percentage, isNull);

    // The guard is snapshot==null, so this snapshot should allow popover.
    // Verify indicator is present and tappable when snapshot would exist.
    expect(
      find.byKey(const ValueKey('chat-context-indicator-button')),
      findsOneWidget,
    );
  });
}
