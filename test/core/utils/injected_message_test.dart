import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hermes_ui/core/models/chat_message.dart';
import 'package:hermes_ui/core/utils/injected_message.dart';
import 'package:hermes_ui/l10n/app_localizations.dart';

ChatMessage _msg(String content, {String role = 'user'}) =>
    ChatMessage(role: role, content: content);

void main() {
  group('isInjectedNotice', () {
    test('background process 命中', () {
      expect(
        InjectedMessage.isInjectedNotice(
          _msg('[IMPORTANT: Background process proc_abc completed normally'),
        ),
        isTrue,
      );
    });
    test('cron 命中', () {
      expect(
        InjectedMessage.isInjectedNotice(
          _msg(
            '[IMPORTANT: You are running as a scheduled cron job.',
            role: 'system',
          ),
        ),
        isTrue,
      );
    });
    test('skill 命中', () {
      expect(
        InjectedMessage.isInjectedNotice(
          _msg('[IMPORTANT: The user has invoked the "foo" skill'),
        ),
        isTrue,
      );
    });
    test('[System: network cut] 命中', () {
      expect(
        InjectedMessage.isInjectedNotice(
          _msg(
            '[System: The previous response was cut off by a network error mid-stream. Continue exactly where you left off.]',
          ),
        ),
        isTrue,
      );
    });
    test('[System note: gateway recovery] 命中', () {
      expect(
        InjectedMessage.isInjectedNotice(
          _msg(
            '[System note: The previous turn was interrupted by a shutdown; the gateway is now back online. Do NOT re-execute.]',
          ),
        ),
        isTrue,
      );
    });
    test('[System note: new message pending] 命中', () {
      expect(
        InjectedMessage.isInjectedNotice(
          _msg(
            '[System note: A new message has arrived. The conversation history contains pending tool outputs from an interrupted turn. IGNORE those pending results.]',
          ),
        ),
        isTrue,
      );
    });
    test('[System note: suspended] 命中', () {
      expect(
        InjectedMessage.isInjectedNotice(
          _msg(
            "[System note: The user's previous session was stopped and suspended. This is a fresh conversation with no prior context.]",
          ),
        ),
        isTrue,
      );
    });
    test('[System note: first contact] 命中', () {
      expect(
        InjectedMessage.isInjectedNotice(
          _msg(
            "[System note: This is the user's very first message ever. Briefly introduce yourself.]",
          ),
        ),
        isTrue,
      );
    });
    test('[System note: memory recall] 命中', () {
      expect(
        InjectedMessage.isInjectedNotice(
          _msg(
            "[System note: The following is recalled memory context, NOT new user input. Treat as authoritative reference data — this is the agent's persistent memory and should inform all responses.]",
          ),
        ),
        isTrue,
      );
    });
    test('<memory-context> memory recall 命中', () {
      expect(
        InjectedMessage.isInjectedNotice(
          _msg(
            '<memory-context>\n[System note: The following is recalled memory context, NOT new user input.]\nhello\n</memory-context>',
          ),
        ),
        isTrue,
      );
    });
    test('[System: codex reasoning-only] 命中', () {
      expect(
        InjectedMessage.isInjectedNotice(
          _msg(
            '[System: Your previous response contained only internal reasoning and never produced a visible answer or tool call.]',
          ),
        ),
        isTrue,
      );
    });
    test('[System: Continue now] 命中', () {
      expect(
        InjectedMessage.isInjectedNotice(
          _msg(
            '[System: Continue now. Execute the required tool calls and only send your final answer after completing the task.]',
          ),
        ),
        isTrue,
      );
    });
    test('assistant 角色不命中', () {
      expect(
        InjectedMessage.isInjectedNotice(
          _msg('[System: The previous response was cut off by a network error',
              role: 'assistant'),
        ),
        isFalse,
      );
    });
    test('用户手打 [System: hello] 不命中', () {
      expect(
        InjectedMessage.isInjectedNotice(_msg('[System: hello world]')),
        isFalse,
      );
    });
    test('用户手打 [IMPORTANT: hello] 不命中', () {
      expect(
        InjectedMessage.isInjectedNotice(_msg('[IMPORTANT: hello world]')),
        isFalse,
      );
    });
    test('role null 不命中', () {
      expect(
        InjectedMessage.isInjectedNotice(
          const ChatMessage(content: '[System: The previous response was cut off'),
        ),
        isFalse,
      );
    });
    test('大小写/前空白容错', () {
      expect(
        InjectedMessage.isInjectedNotice(
          _msg('  [system: the previous response was cut off by a network error'),
        ),
        isTrue,
      );
    });
  });

  group('classify', () {
    test('network cut', () {
      expect(
        InjectedMessage.classify(
          _msg('[System: The previous response was cut off by a network error mid-stream. Continue exactly where you left off.]'),
        ),
        InjectedNoticeKind.continuationNetworkCut,
      );
    });
    test('output limit', () {
      expect(
        InjectedMessage.classify(
          _msg('[System: Your previous response was truncated by the output length limit. Continue exactly where you left off.]'),
        ),
        InjectedNoticeKind.continuationOutputLimit,
      );
    });
    test('tool too large', () {
      expect(
        InjectedMessage.classify(
          _msg('[System: Your previous tool call (patch) was too large and the stream timed out.]'),
        ),
        InjectedNoticeKind.continuationToolTooLarge,
      );
    });
    test('codex reasoning-only', () {
      expect(
        InjectedMessage.classify(
          _msg('[System: Your previous response contained only internal reasoning and never produced a visible answer.]'),
        ),
        InjectedNoticeKind.codexNudge,
      );
    });
    test('codex Continue now', () {
      expect(
        InjectedMessage.classify(
          _msg('[System: Continue now. Execute the required tool calls and only send your final answer.]'),
        ),
        InjectedNoticeKind.codexNudge,
      );
    });
    test('gateway recovery — interrupted', () {
      expect(
        InjectedMessage.classify(
          _msg('[System note: The previous turn was interrupted by a shutdown; the gateway is now back online.]'),
        ),
        InjectedNoticeKind.gatewayRecovery,
      );
    });
    test('gateway recovery — pending IGNORE', () {
      expect(
        InjectedMessage.classify(
          _msg('[System note: A new message has arrived. The conversation history contains pending tool outputs from an interrupted turn. IGNORE those pending results.]'),
        ),
        InjectedNoticeKind.gatewayRecovery,
      );
    });
    test('session reset — suspended', () {
      expect(
        InjectedMessage.classify(
          _msg("[System note: The user's previous session was stopped and suspended. This is a fresh conversation.]"),
        ),
        InjectedNoticeKind.sessionReset,
      );
    });
    test('session reset — daily', () {
      expect(
        InjectedMessage.classify(
          _msg("[System note: The user's session was automatically reset by the daily schedule.]"),
        ),
        InjectedNoticeKind.sessionReset,
      );
    });
    test('session reset — expired', () {
      expect(
        InjectedMessage.classify(
          _msg("[System note: The user's previous session expired due to inactivity.]"),
        ),
        InjectedNoticeKind.sessionReset,
      );
    });
    test('session reset — first contact', () {
      expect(
        InjectedMessage.classify(
          _msg("[System note: This is the user's very first message ever. Briefly introduce yourself.]"),
        ),
        InjectedNoticeKind.sessionReset,
      );
    });
    test('memory recall', () {
      expect(
        InjectedMessage.classify(
          _msg('[System note: The following is recalled memory context, NOT new user input.]'),
        ),
        InjectedNoticeKind.memoryRecall,
      );
    });
    test('background process 仍正确', () {
      expect(
        InjectedMessage.classify(
          _msg('[IMPORTANT: Background process proc_xxx completed normally (exit code 0).'),
        ),
        InjectedNoticeKind.backgroundProcess,
      );
    });
    test('非注入 → none', () {
      expect(
        InjectedMessage.classify(_msg('hello world')),
        InjectedNoticeKind.none,
      );
    });
    test('裸 dropped-tool nudge → codex', () {
      expect(
        InjectedMessage.classify(
          _msg('Your previous turn indicated a tool call but none was included. Do not narrate a plan'),
        ),
        InjectedNoticeKind.codexNudge,
      );
    });
  });

  group('extractSummary', () {
    test('network cut zh', () {
      final s = InjectedMessage.extractSummary(
        _msg('[System: The previous response was cut off by a network error mid-stream. Continue exactly where you left off.]'),
        const AppLocalizations(Locale('zh')),
      );
      expect(s, '网络中断续写');
    });
    test('network cut en', () {
      final s = InjectedMessage.extractSummary(
        _msg('[System: The previous response was cut off by a network error mid-stream. Continue exactly where you left off.]'),
        const AppLocalizations(Locale('en')),
      );
      expect(s, 'Continue — network error');
    });
    test('output limit zh', () {
      final s = InjectedMessage.extractSummary(
        _msg('[System: Your previous response was truncated by the output length limit. Continue exactly where you left off.]'),
        const AppLocalizations(Locale('zh')),
      );
      expect(s, '输出截断续写');
    });
    test('gateway zh', () {
      final s = InjectedMessage.extractSummary(
        _msg('[System note: The previous turn was interrupted by a shutdown; the gateway is now back online.]'),
        const AppLocalizations(Locale('zh')),
      );
      expect(s, '网关已恢复');
    });
    test('session reset zh', () {
      final s = InjectedMessage.extractSummary(
        _msg("[System note: The user's previous session was stopped and suspended. This is a fresh conversation.]"),
        const AppLocalizations(Locale('zh')),
      );
      expect(s, '会话已重置');
    });
    test('memory zh', () {
      final s = InjectedMessage.extractSummary(
        _msg('[System note: The following is recalled memory context, NOT new user input.]'),
        const AppLocalizations(Locale('zh')),
      );
      expect(s, '记忆上下文');
    });
    test('tool too large zh', () {
      final s = InjectedMessage.extractSummary(
        _msg('[System: Your previous tool call (patch) was too large and the stream timed out.]'),
        const AppLocalizations(Locale('zh')),
      );
      expect(s, '工具调用过大续写');
    });
    test('codex zh', () {
      final s = InjectedMessage.extractSummary(
        _msg('[System: Your previous response contained only internal reasoning and never produced a visible answer.]'),
        const AppLocalizations(Locale('zh')),
      );
      expect(s, '继续执行');
    });
    test('null l10n → en fallback', () {
      final s = InjectedMessage.extractSummary(
        _msg('[System: The previous response was cut off by a network error mid-stream.]'),
      );
      expect(s, 'Continue — network error');
    });
  });
}
