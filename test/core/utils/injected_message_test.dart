// ignore_for_file: prefer_const_constructors
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermex_flutter/core/models/chat_message.dart';
import 'package:hermex_flutter/core/utils/injected_message.dart';
import 'package:hermex_flutter/l10n/app_localizations.dart';

ChatMessage _msg(String? content, {String? role = 'user'}) {
  return ChatMessage(role: role, content: content);
}

void main() {
  group('isInjectedNotice — role/content 容错', () {
    test('role null 不崩且返回 false', () {
      expect(
        isInjectedNotice(const ChatMessage(role: null, content: '[IMPORTANT: Background process x completed')),
        isFalse,
      );
    });

    test('content null 不崩且返回 false', () {
      expect(
        isInjectedNotice(const ChatMessage(role: 'user', content: null)),
        isFalse,
      );
    });

    test('空白内容不崩且返回 false', () {
      expect(isInjectedNotice(_msg('   ')), isFalse);
      expect(isInjectedNotice(_msg('')), isFalse);
      expect(isInjectedNotice(_msg('\n\t ')), isFalse);
    });

    test('非 user/system role 不折叠（local_notice/assistant/tool）', () {
      const String c = '[IMPORTANT: Background process proc_1 completed normally (exit code 0).';
      expect(isInjectedNotice(ChatMessage(role: 'assistant', content: c)), isFalse);
      expect(isInjectedNotice(ChatMessage(role: 'local_notice', content: c)), isFalse);
      expect(isInjectedNotice(ChatMessage(role: 'tool', content: c)), isFalse);
      expect(isInjectedNotice(ChatMessage(role: null, content: c)), isFalse);
    });

    test('role 大小写容错', () {
      const String c = '[IMPORTANT: Background process proc_1 completed';
      expect(isInjectedNotice(ChatMessage(role: 'User', content: c)), isTrue);
      expect(isInjectedNotice(ChatMessage(role: 'SYSTEM', content: c)), isTrue);
      expect(isInjectedNotice(ChatMessage(role: ' USER ', content: c)), isTrue);
    });

    test('误伤用例：用户手打 [IMPORTANT: hello] 不折叠', () {
      expect(isInjectedNotice(_msg('[IMPORTANT: hello]')), isFalse);
      expect(isInjectedNotice(_msg('[IMPORTANT: hello world, please help]')), isFalse);
      expect(isInjectedNotice(_msg('[IMPORTANT: Hello, this is my note]')), isFalse);
      expect(classify(_msg('[IMPORTANT: hello]')), InjectedNoticeKind.none);
    });

    test('误伤用例：普通 [SYSTEM: hello] 不折叠', () {
      expect(isInjectedNotice(_msg('[SYSTEM: hello]')), isFalse);
    });

    test('前导空格与大小写容错 — 前导空格仍识别为注入', () {
      expect(isInjectedNotice(_msg('   [IMPORTANT: Background process proc_1 completed')), isTrue);
      expect(isInjectedNotice(_msg('\n  [IMPORTANT: Background process proc_1 completed')), isTrue);
      expect(isInjectedNotice(_msg('\t[IMPORTANT: Background process proc_1 completed')), isTrue);
    });

    test('大小写容错 — 小写前缀仍识别', () {
      expect(isInjectedNotice(_msg('[important: background process proc_1 completed')), isTrue);
      expect(isInjectedNotice(_msg('[IMPORTANT: BACKGROUND PROCESS proc_1 completed')), isTrue);
      expect(isInjectedNotice(_msg('[ImPoRtAnT: Background Process proc_1 completed')), isTrue);
    });
  });

  group('classify — 10 类各 2 条正例', () {
    test('1 backgroundProcess 单条完成 — completed / failed to start', () {
      final ChatMessage a = _msg('[IMPORTANT: Background process proc_abc123 completed normally (exit code 0).');
      final ChatMessage b = _msg('[IMPORTANT: Background process proc_xyz failed to start: spawn error');
      expect(isInjectedNotice(a), isTrue);
      expect(classify(a), InjectedNoticeKind.backgroundProcess);
      expect(isInjectedNotice(b), isTrue);
      expect(classify(b), InjectedNoticeKind.backgroundProcess);
    });

    test('1 backgroundProcess — terminated / exited covers status branch', () {
      final ChatMessage a = _msg('[IMPORTANT: Background process proc_1 terminated by signal 9 (exit code -9).');
      final ChatMessage b = _msg('[IMPORTANT: Background process proc_2 exited with code 1');
      expect(classify(a), InjectedNoticeKind.backgroundProcess);
      expect(classify(b), InjectedNoticeKind.backgroundProcess);
    });

    test('2 backgroundProcessWatch — matched watch pattern x2', () {
      final ChatMessage a = _msg('[IMPORTANT: Background process proc_abc matched watch pattern "error"');
      final ChatMessage b = _msg('[IMPORTANT: Background process proc_xyz matched watch pattern "TODO" -- watch fired');
      expect(classify(a), InjectedNoticeKind.backgroundProcessWatch);
      expect(classify(b), InjectedNoticeKind.backgroundProcessWatch);
    });

    test('3 backgroundProcessAggregated — 聚合完成 x2', () {
      final ChatMessage a = _msg('[IMPORTANT: 3 background processes completed for this session.');
      final ChatMessage b = _msg('[IMPORTANT: 1 background processes completed for this session. See logs.]');
      expect(classify(a), InjectedNoticeKind.backgroundProcessAggregated);
      expect(classify(b), InjectedNoticeKind.backgroundProcessAggregated);
    });

    test('4 subagentAggregated — subagent 聚合 x2', () {
      final ChatMessage a = _msg('[IMPORTANT: 2 background subagent delegations completed — all done');
      final ChatMessage b = _msg('[IMPORTANT: 5 background subagent delegations completed');
      expect(classify(a), InjectedNoticeKind.subagentAggregated);
      expect(classify(b), InjectedNoticeKind.subagentAggregated);
    });

    test('5 overflow / watch_disabled — x2', () {
      final ChatMessage a = _msg('[IMPORTANT: Background process overflow: Too many messages, truncated');
      final ChatMessage b = _msg('[IMPORTANT: Background process watch_disabled: pattern disabled after overflow');
      expect(classify(a), InjectedNoticeKind.overflow);
      expect(classify(b), InjectedNoticeKind.overflow);
    });

    test('6 cron — system role + You are running as a scheduled cron x2', () {
      final ChatMessage a = ChatMessage(
        role: 'system',
        content: '[IMPORTANT: You are running as a scheduled cron job. DELIVERY: push SILENT: true',
      );
      final ChatMessage b = ChatMessage(
        role: 'system',
        content: '[IMPORTANT: You are running as a scheduled cron job. DELIVERY: silent',
      );
      expect(isInjectedNotice(a), isTrue);
      expect(classify(a), InjectedNoticeKind.cron);
      expect(isInjectedNotice(b), isTrue);
      expect(classify(b), InjectedNoticeKind.cron);
    });

    test('7 skill 单体触发 x2', () {
      final ChatMessage a = _msg('[IMPORTANT: The user has invoked the "commit" skill, indicating they want to commit]');
      final ChatMessage b = _msg('[IMPORTANT: The user has invoked the "review" skill, indicating they want code review]');
      expect(classify(a), InjectedNoticeKind.skill);
      expect(classify(b), InjectedNoticeKind.skill);
    });

    test('8 skill bundle x2', () {
      final ChatMessage a = _msg('[IMPORTANT: The user has invoked the "my-bundle" skill bundle, loading 3 skills together]');
      final ChatMessage b = _msg('[IMPORTANT: The user has invoked the "ship" skill bundle, loading 5 skills together ...]');
      expect(classify(a), InjectedNoticeKind.skillBundle);
      expect(classify(b), InjectedNoticeKind.skillBundle);
    });

    test('9 auto-loaded skill x2', () {
      final ChatMessage a = _msg('[IMPORTANT: The "plan" skill is auto-loaded. It helps you plan. ]');
      final ChatMessage b = _msg('[IMPORTANT: The "memory" skill is auto-loaded. Context ready.]');
      expect(classify(a), InjectedNoticeKind.skillAutoLoaded);
      expect(classify(b), InjectedNoticeKind.skillAutoLoaded);
    });

    test('10 MCP 重载通知 x2', () {
      final ChatMessage a = _msg('[IMPORTANT: MCP servers have been reloaded. The tool list has been updated.]');
      final ChatMessage b = _msg('[IMPORTANT: MCP servers have been reloaded. New tools available.]');
      expect(classify(a), InjectedNoticeKind.mcp);
      expect(classify(b), InjectedNoticeKind.mcp);
    });

    test('[SYSTEM: Background process 兼容历史形态', () {
      final ChatMessage a = _msg('[SYSTEM: Background process proc_123 completed normally (exit code 0).');
      expect(isInjectedNotice(a), isTrue);
      expect(classify(a), InjectedNoticeKind.backgroundProcess);
    });

    test('兜底分支 — [IMPORTANT: skill + background process 关键词仍识别', () {
      // 命中泛化兜底：[IMPORTANT: + skill 关键词
      final ChatMessage a = _msg('[IMPORTANT: skill "foo" was loaded due to context]');
      expect(isInjectedNotice(a), isTrue);
    });

    test('大小写与前导空格混合 — 各类仍正确分类', () {
      final ChatMessage cron = ChatMessage(
        role: 'system',
        content: '  [important: you are running as a scheduled cron job. delivery: ...]',
      );
      expect(classify(cron), InjectedNoticeKind.cron);

      final ChatMessage watch = _msg('  [IMPORTANT: Background process proc_1 matched watch pattern "x"');
      expect(classify(watch), InjectedNoticeKind.backgroundProcessWatch);

      final ChatMessage skillLower = _msg('  [important: the user has invoked the "foo" skill, indicating ...]');
      expect(classify(skillLower), InjectedNoticeKind.skill);
    });
  });

  group('extractSummary — sid 截断边界', () {
    test('sid 长度 22 不截断', () {
      // 22 chars: 1234567890123456789012
      const String sid22 = '1234567890123456789012';
      expect(sid22.length, 22);
      final ChatMessage m = _msg('[IMPORTANT: Background process $sid22 completed normally (exit code 0).');
      final String s = extractSummary(m);
      expect(s, contains(sid22));
      expect(s, isNot(contains('…')));
    });

    test('sid 长度 23 截断为 10…8', () {
      const String sid23 = '12345678901234567890123';
      expect(sid23.length, 23);
      final ChatMessage m = _msg('[IMPORTANT: Background process $sid23 completed normally (exit code 0).');
      final String s = extractSummary(m);
      // 期望 10 + … + 8
      const String expected = '1234567890…67890123';
      expect(s, contains(expected));
      expect(s, isNot(contains(sid23)));
    });

    test('sid 超长 proc_xxx 形态截断', () {
      const String longSid = 'proc_abcdefghijklmnopqrstuvwxyz_1234567890';
      final ChatMessage m = _msg('[IMPORTANT: Background process $longSid completed');
      final String s = extractSummary(m);
      expect(s, contains('…'));
      // 首10 末8
      final String expected = '${longSid.substring(0, 10)}…${longSid.substring(longSid.length - 8)}';
      expect(s, contains(expected));
    });

    test('sid 为状态词时不作为 sid（completed 等黑名单）', () {
      final ChatMessage m = _msg('[IMPORTANT: Background process completed normally');
      final String s = extractSummary(m);
      // 不应把 completed 当 sid，标题应为 Background process · completed
      expect(s, contains('Background process'));
      expect(s, contains('completed'));
    });
  });

  group('extractSummary — exit code 三形态', () {
    test('形态1：(exit code 0)', () {
      final ChatMessage m = _msg('[IMPORTANT: Background process proc_1 completed normally (exit code 0).');
      expect(extractSummary(m), contains('(exit 0)'));
    });

    test('形态2：exit code: 1 / exit_code=2', () {
      final ChatMessage a = _msg('[IMPORTANT: Background process proc_1 completed normally exit code: 1');
      final ChatMessage b = _msg('[IMPORTANT: Background process proc_1 failed exit_code=2');
      expect(extractSummary(a), contains('(exit 1)'));
      expect(extractSummary(b), contains('(exit 2)'));
    });

    test('形态3：with code -9', () {
      final ChatMessage m = _msg('[IMPORTANT: Background process proc_1 terminated with code -9');
      expect(extractSummary(m), contains('(exit -9)'));
    });
  });

  group('extractSummary — 状态词映射', () {
    test('completed normally / completed → completed', () {
      expect(extractSummary(_msg('[IMPORTANT: Background process p completed normally')), contains('completed'));
      expect(extractSummary(_msg('[IMPORTANT: Background process p completed')), contains('completed'));
    });

    test('failed to start', () {
      expect(extractSummary(_msg('[IMPORTANT: Background process p failed to start')), contains('failed to start'));
    });

    test('terminated / killed → terminated', () {
      expect(extractSummary(_msg('[IMPORTANT: Background process p terminated by signal')), contains('terminated'));
      expect(extractSummary(_msg('[IMPORTANT: Background process p killed')), contains('terminated'));
    });

    test('marked lost / lost → lost', () {
      expect(extractSummary(_msg('[IMPORTANT: Background process p marked lost')), contains('lost'));
      expect(extractSummary(_msg('[IMPORTANT: Background process p lost')), contains('lost'));
    });

    test('matched watch pattern → matched', () {
      expect(
        extractSummary(_msg('[IMPORTANT: Background process p matched watch pattern "x"')),
        contains('matched'),
      );
    });

    test('exited → exited', () {
      expect(extractSummary(_msg('[IMPORTANT: Background process p exited')), contains('exited'));
    });

    test('中英映射 — 中文 completed/terminated', () {
      final AppLocalizations zh = AppLocalizations(const Locale('zh'));
      final AppLocalizations en = AppLocalizations(const Locale('en'));
      final ChatMessage m = _msg('[IMPORTANT: Background process p completed normally (exit code 0).');
      expect(extractSummary(m, zh), contains('已完成'));
      expect(extractSummary(m, en), contains('completed'));
      final ChatMessage t = _msg('[IMPORTANT: Background process p terminated by signal');
      expect(extractSummary(t, zh), contains('已终止'));
    });
  });

  group('extractSummary — skill/cron/mcp/兜底', () {
    test('Skill：Skill · name 提取', () {
      final ChatMessage m = _msg('[IMPORTANT: The user has invoked the "my-skill" skill, indicating ...]');
      expect(extractSummary(m), 'Skill · my-skill');
      final AppLocalizations zh = AppLocalizations(const Locale('zh'));
      expect(extractSummary(m, zh), '技能 · my-skill');
    });

    test('Skill bundle 追加 bundle', () {
      final ChatMessage m = _msg('[IMPORTANT: The user has invoked the "ship" skill bundle, loading 3 skills]');
      expect(extractSummary(m), 'Skill · ship bundle');
    });

    test('Skill auto-loaded 同样提取', () {
      final ChatMessage m = _msg('[IMPORTANT: The "plan" skill is auto-loaded. ...]');
      expect(extractSummary(m), 'Skill · plan');
    });

    test('Cron：Scheduled task / 定时任务', () {
      final ChatMessage m = ChatMessage(role: 'system', content: '[IMPORTANT: You are running as a scheduled cron job. ...');
      expect(extractSummary(m), 'Scheduled task');
      expect(extractSummary(m, AppLocalizations(const Locale('zh'))), '定时任务');
    });

    test('MCP：MCP servers reloaded', () {
      final ChatMessage m = _msg('[IMPORTANT: MCP servers have been reloaded. ...]');
      expect(extractSummary(m), 'MCP servers reloaded');
    });

    test('聚合卡首行去前缀截断 ≤64', () {
      final ChatMessage m = _msg('[IMPORTANT: 3 background processes completed for this session. Extra long line that should be truncated if exceeds limit.................................................................]');
      final String s = extractSummary(m);
      expect(s.length, lessThanOrEqualTo(65)); // 64 + …
      expect(s, contains('3 background processes completed'));
    });

    test('overflow 兜底首行 ≤48', () {
      final String long = 'a' * 100;
      final ChatMessage m = _msg('[IMPORTANT: Background process overflow: $long');
      // classify 为 overflow 时走 48 限制
      // overflow 的 content 同时命中 background process，故为 overflow 分支 48
      final String s = extractSummary(m);
      expect(s.length, lessThanOrEqualTo(49));
    });

    test('非注入消息 extractSummary 返回空', () {
      expect(extractSummary(_msg('[IMPORTANT: hello]')), '');
      expect(extractSummary(_msg('plain hello')), '');
      expect(extractSummary(const ChatMessage(role: 'assistant', content: '[IMPORTANT: Background process x completed')), '');
    });

    test('超长首行 >300 字符不崩', () {
      final String long = '[IMPORTANT: Background process ${'x' * 400} completed';
      final ChatMessage m = _msg(long);
      expect(() => extractSummary(m), returnsNormally);
      expect(extractSummary(m).isNotEmpty, isTrue);
    });

    test('首行截断 — 去括号后逻辑', () {
      final ChatMessage m = _msg('[IMPORTANT: Background process proc_1 completed normally (exit code 0).\nSecond line ignored\nThird]');
      final String s = extractSummary(m);
      expect(s, isNot(contains('Second line')));
    });
  });

  group('null/空内容不崩', () {
    test('null/空 classify 返回 none 且 summary 空', () {
      const ChatMessage a = ChatMessage(role: null, content: null);
      expect(classify(a), InjectedNoticeKind.none);
      expect(extractSummary(a), '');
      expect(isInjectedNotice(a), isFalse);

      const ChatMessage b = ChatMessage(role: 'user', content: '');
      expect(classify(b), InjectedNoticeKind.none);
      expect(extractSummary(b), '');

      const ChatMessage c = ChatMessage(role: 'user', content: '   ');
      expect(classify(c), InjectedNoticeKind.none);
      expect(extractSummary(c), '');
    });

    test('多行中仅首行参与摘要，第二行不影响分类', () {
      final ChatMessage m = _msg('[IMPORTANT: Background process proc_1 completed\nsome [IMPORTANT: hello] noise');
      expect(classify(m), InjectedNoticeKind.backgroundProcess);
      expect(extractSummary(m), contains('completed'));
    });
  });

  group('displayTitle 中英映射', () {
    test('各种 kind 的 fallback 与中英', () {
      const AppLocalizations en = AppLocalizations(Locale('en'));
      const AppLocalizations zh = AppLocalizations(Locale('zh'));
      expect(InjectedNoticeKind.backgroundProcess.displayTitleWithL10n(en), 'Background process');
      expect(InjectedNoticeKind.backgroundProcess.displayTitleWithL10n(zh), '后台进程');
      expect(InjectedNoticeKind.cron.displayTitleWithL10n(en), 'Scheduled task');
      expect(InjectedNoticeKind.cron.displayTitleWithL10n(zh), '定时任务');
      expect(InjectedNoticeKind.skill.displayTitleWithL10n(en), 'Skill');
      expect(InjectedNoticeKind.skill.displayTitleWithL10n(zh), '技能');
      expect(InjectedNoticeKind.mcp.displayTitleWithL10n(en), 'MCP');
      expect(InjectedNoticeKind.none.displayTitleWithL10n(en), '');
      expect(InjectedNoticeKind.backgroundProcess.displayTitleWithL10n(null), 'Background process');
      expect(InjectedNoticeKind.cron.displayTitleWithL10n(null), 'Scheduled task');
    });
  });

  group('RegExp 预编译 — 多次调用不抛', () {
    test('连续分类 100 次稳定', () {
      final ChatMessage m = _msg('[IMPORTANT: Background process proc_long_12345678901234567890 completed normally (exit code 0).');
      for (int i = 0; i < 100; i++) {
        expect(classify(m), InjectedNoticeKind.backgroundProcess);
        expect(extractSummary(m).isNotEmpty, isTrue);
      }
    });
  });
}
