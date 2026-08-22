import 'package:flutter/widgets.dart';

import '../../l10n/app_localizations.dart';
import '../models/chat_message.dart';

/// Agent 代发注入消息分类器（spec §2）。
///
/// 对齐 `D:\hermes-webui\static\ui.js` 的 `_formatProcessNoticeSummary`
/// 并扩展到全量 10 类注入消息。所有 [RegExp] 均为预编译的 `static const`，
/// 禁止在 `build` 中编译。
enum InjectedNoticeKind {
  backgroundProcess,
  backgroundProcessWatch,
  backgroundProcessAggregated,
  subagentAggregated,
  overflow,
  cron,
  skill,
  skillBundle,
  skillAutoLoaded,
  mcp,
  none,
}

/// 分类器与摘要工具（纯字符串操作）。
class InjectedMessage {
  const InjectedMessage._();

  // ---------------------------------------------------------------------------
  // 预编译正则（spec §2.3，对齐 ui.js _formatProcessNoticeSummary）
  // ---------------------------------------------------------------------------
  static final RegExp _sidRegExp = RegExp(
    r'Background process\s+(\S+)',
    caseSensitive: false,
  );
  static final RegExp _trailingPunctRegExp = RegExp(r'[.:,;)]+$');
  static final RegExp _exitCodeParenRegExp = RegExp(
    r'\(exit[_\s]*code\s*[:=]?\s*(-?\d+)\)',
    caseSensitive: false,
  );
  static final RegExp _exitCodeBareRegExp = RegExp(
    r'exit[_\s]*code\s*[:=]?\s*(-?\d+)',
    caseSensitive: false,
  );
  static final RegExp _withCodeRegExp = RegExp(
    r'with\s+code\s+(-?\d+)',
    caseSensitive: false,
  );
  static final RegExp _skillNameRegExp = RegExp(r'"([^"]+)"');
  static final RegExp _importantPrefixRegExp = RegExp(
    r'^\[IMPORTANT:\s*',
    caseSensitive: false,
  );
  static final RegExp _systemPrefixRegExp = RegExp(
    r'^\[SYSTEM:\s*',
    caseSensitive: false,
  );
  static final RegExp _trailingBracketRegExp = RegExp(r'\]\s*$');
  static final RegExp _fallbackStatusRegExp = RegExp(
    r'Background process(?:\s+\S+)?\s+(.+?)(?:\s*\(.*)?\.?$',
    caseSensitive: false,
  );

  static const Set<String> _sidBlacklist = <String>{
    'completed',
    'failed',
    'terminated',
    'exited',
    'lost',
    'matched',
    'marked',
  };

  // ---------------------------------------------------------------------------
  // 检测入口（spec §2.2）
  // ---------------------------------------------------------------------------

  /// 是否为 agent 代发注入消息。
  ///
  /// 仅当 [ChatMessage.role] 为 `user` 或 `system` 且内容满足白名单前缀时
  /// 返回 `true`，避免误伤用户手打的 `[IMPORTANT: hello]`。
  static bool isInjectedNotice(ChatMessage message) {
    final String? role = message.role;
    if (role == null) return false;
    final String normalizedRole = role.trim().toLowerCase();
    if (normalizedRole != 'user' && normalizedRole != 'system') return false;
    final String? content = message.content;
    if (content == null) return false;
    if (content.trim().isEmpty) return false;
    return _isInjectedNoticeText(content);
  }

  static bool _isInjectedNoticeText(String text) {
    final String t = text.trimLeft();
    if (t.isEmpty) return false;
    if (!t.startsWith('[')) return false;
    final String lower = t.toLowerCase();
    if (lower.startsWith('[important: background process')) return true;
    if (lower.startsWith('[important: you are running as a scheduled cron')) {
      return true;
    }
    if (lower.startsWith('[important: the user has invoked the')) return true;
    if (lower.startsWith('[important: the "')) return true;
    if (lower.contains('background subagent')) return true;
    if (lower.startsWith('[important: mcp servers have been reloaded')) {
      return true;
    }
    if (lower.startsWith('[system: background process')) return true;
    if (lower.startsWith('[important:')) {
      if (_containsAny(lower, const <String>[
        'background process',
        'background subagent',
        'subagent',
        'mcp servers',
        'cron job',
        'skill',
      ])) {
        return true;
      }
      return false;
    }
    return false;
  }

  static bool _containsAny(String lower, List<String> keywords) {
    for (final String k in keywords) {
      if (lower.contains(k)) return true;
    }
    return false;
  }

  // ---------------------------------------------------------------------------
  // 分类（spec §2.2）
  // ---------------------------------------------------------------------------

  /// 分类（未命中注入则返回 [InjectedNoticeKind.none]）。
  static InjectedNoticeKind classify(ChatMessage message) {
    if (!isInjectedNotice(message)) return InjectedNoticeKind.none;
    final String content = message.content ?? '';
    final String lower = content.trimLeft().toLowerCase();

    if (lower.contains('background subagent delegations completed') ||
        lower.contains('background subagent')) {
      return InjectedNoticeKind.subagentAggregated;
    }
    if (lower.contains('background processes completed')) {
      return InjectedNoticeKind.backgroundProcessAggregated;
    }
    if (lower.contains('matched watch pattern')) {
      return InjectedNoticeKind.backgroundProcessWatch;
    }
    if (lower.contains('background process')) {
      if (lower.contains('overflow') ||
          lower.contains('watch_disabled') ||
          lower.contains('watch disabled')) {
        return InjectedNoticeKind.overflow;
      }
      return InjectedNoticeKind.backgroundProcess;
    }
    if (lower.contains('you are running as a scheduled cron')) {
      return InjectedNoticeKind.cron;
    }
    if (lower.contains('skill bundle')) {
      return InjectedNoticeKind.skillBundle;
    }
    if (lower.contains('skill is auto-loaded') ||
        lower.contains('skill is auto loaded')) {
      return InjectedNoticeKind.skillAutoLoaded;
    }
    if (lower.contains('the user has invoked the') &&
        lower.contains('skill')) {
      return InjectedNoticeKind.skill;
    }
    if (lower.contains('mcp servers have been reloaded')) {
      return InjectedNoticeKind.mcp;
    }
    if (lower.contains('mcp servers') || lower.contains('mcp')) {
      if (lower.contains('mcp')) return InjectedNoticeKind.mcp;
    }
    if (lower.contains('cron job')) return InjectedNoticeKind.cron;
    if (lower.contains('skill')) return InjectedNoticeKind.skill;
    if (lower.contains('overflow') ||
        lower.contains('truncated') ||
        lower.contains('watch_disabled')) {
      return InjectedNoticeKind.overflow;
    }
    return InjectedNoticeKind.overflow;
  }

  // ---------------------------------------------------------------------------
  // 摘要（spec §2.3，对齐 ui.js _formatProcessNoticeSummary）
  // ---------------------------------------------------------------------------

  /// 摘要标题提取。
  ///
  /// - Background process 单条/watch：`Background process {sid} · {status} (exit {code})`
  /// - 聚合：首行去前缀后截断 ≤64
  /// - Skill：`Skill · {skillName}`（引号内提取，bundle 追加 `bundle`）
  /// - Cron/MCP：固定标题
  /// - 兜底：首行去 `[IMPORTANT:` 前缀后 ≤48
  static String extractSummary(
    ChatMessage message, [
    AppLocalizations? l10n,
  ]) {
    final InjectedNoticeKind kind = classify(message);
    if (kind == InjectedNoticeKind.none) return '';
    final String raw = message.content ?? '';
    final String firstLine = raw.split('\n').first;
    if (firstLine.trim().isEmpty) return '';

    switch (kind) {
      case InjectedNoticeKind.backgroundProcess:
      case InjectedNoticeKind.backgroundProcessWatch:
        return _backgroundSummary(firstLine, l10n);
      case InjectedNoticeKind.backgroundProcessAggregated:
      case InjectedNoticeKind.subagentAggregated:
        return _firstLineStripped(firstLine, 64);
      case InjectedNoticeKind.cron:
        return _cronTitle(l10n);
      case InjectedNoticeKind.mcp:
        return _mcpTitle(l10n);
      case InjectedNoticeKind.skill:
      case InjectedNoticeKind.skillBundle:
      case InjectedNoticeKind.skillAutoLoaded:
        return _skillSummary(firstLine, kind, l10n);
      case InjectedNoticeKind.overflow:
        return _firstLineStripped(firstLine, 48);
      case InjectedNoticeKind.none:
        return '';
    }
  }

  static String _backgroundSummary(String firstLine, AppLocalizations? l10n) {
    final String firstLineNoBracket = firstLine
        .replaceFirst(_importantPrefixRegExp, '')
        .replaceFirst(_trailingBracketRegExp, '');
    String sid = '';
    final RegExpMatch? sidMatch = _sidRegExp.firstMatch(firstLineNoBracket);
    if (sidMatch != null) {
      String rawSid = sidMatch.group(1) ?? '';
      rawSid = rawSid.replaceFirst(_trailingPunctRegExp, '');
      final String lowerToken = rawSid.toLowerCase();
      if (!_sidBlacklist.contains(lowerToken)) {
        sid = rawSid;
        if (sid.length > 22) {
          sid = '${sid.substring(0, 10)}…${sid.substring(sid.length - 8)}';
        }
      }
    }

    String? exitCode;
    RegExpMatch? m = _exitCodeParenRegExp.firstMatch(firstLine);
    m ??= _exitCodeBareRegExp.firstMatch(firstLine);
    m ??= _withCodeRegExp.firstMatch(firstLine);
    if (m != null) exitCode = m.group(1);

    final String lower = firstLine.toLowerCase();
    late final String statusText;
    if (lower.contains('completed normally') || lower.contains('completed')) {
      statusText = _statusCompleted(l10n);
    } else if (lower.contains('failed to start')) {
      statusText = _statusFailedToStart(l10n);
    } else if (lower.contains('terminated by') ||
        lower.contains('terminated') ||
        lower.contains('killed')) {
      statusText = _statusTerminated(l10n);
    } else if (lower.contains('marked lost') || lower.contains('lost')) {
      statusText = _statusLost(l10n);
    } else if (lower.contains('matched watch pattern')) {
      statusText = _statusMatched(l10n);
    } else if (lower.contains('exited')) {
      statusText = _statusExited(l10n);
    } else {
      final RegExpMatch? sm = _fallbackStatusRegExp.firstMatch(
        firstLineNoBracket,
      );
      if (sm != null) {
        final String raw = (sm.group(1) ?? 'completed').trim();
        statusText = raw.isEmpty ? _statusCompleted(l10n) : raw;
      } else {
        statusText = _statusCompleted(l10n);
      }
    }

    final String baseTitle = _backgroundTitle(l10n);
    final String sidPart = sid.isEmpty ? '' : ' $sid';
    final String exitPart = exitCode == null ? '' : ' (exit $exitCode)';
    return '$baseTitle$sidPart · $statusText$exitPart';
  }

  static String _skillSummary(
    String firstLine,
    InjectedNoticeKind kind,
    AppLocalizations? l10n,
  ) {
    final RegExpMatch? m = _skillNameRegExp.firstMatch(firstLine);
    final String? name = m?.group(1)?.trim();
    final String skillLabel = _skillLabel(l10n);
    if (name != null && name.isNotEmpty) {
      final String suffix =
          kind == InjectedNoticeKind.skillBundle ? ' bundle' : '';
      return '$skillLabel · $name$suffix';
    }
    return _firstLineStripped(firstLine, 64);
  }

  static String _firstLineStripped(String firstLine, int limit) {
    String t = firstLine.trimLeft();
    t = t.replaceFirst(_importantPrefixRegExp, '');
    t = t.replaceFirst(_systemPrefixRegExp, '');
    t = t.replaceFirst(_trailingBracketRegExp, '');
    t = t.trim();
    if (t.length > limit) {
      t = '${t.substring(0, limit).trimRight()}…';
    }
    return t;
  }

  static String _backgroundTitle(AppLocalizations? l10n) {
    if (l10n == null) return 'Background process';
    return l10n.isEnglish ? 'Background process' : '后台进程';
  }

  static String _skillLabel(AppLocalizations? l10n) {
    if (l10n == null) return 'Skill';
    return l10n.isEnglish ? 'Skill' : '技能';
  }

  static String _cronTitle(AppLocalizations? l10n) {
    if (l10n == null) return 'Scheduled task';
    return l10n.isEnglish ? 'Scheduled task' : '定时任务';
  }

  static String _mcpTitle(AppLocalizations? l10n) {
    if (l10n == null) return 'MCP servers reloaded';
    return l10n.isEnglish ? 'MCP servers reloaded' : 'MCP 服务已重载';
  }

  static String _statusCompleted(AppLocalizations? l10n) {
    if (l10n == null) return 'completed';
    return l10n.isEnglish ? 'completed' : '已完成';
  }

  static String _statusFailedToStart(AppLocalizations? l10n) {
    if (l10n == null) return 'failed to start';
    return l10n.isEnglish ? 'failed to start' : '启动失败';
  }

  static String _statusTerminated(AppLocalizations? l10n) {
    if (l10n == null) return 'terminated';
    return l10n.isEnglish ? 'terminated' : '已终止';
  }

  static String _statusLost(AppLocalizations? l10n) {
    if (l10n == null) return 'lost';
    return l10n.isEnglish ? 'lost' : '已丢失';
  }

  static String _statusMatched(AppLocalizations? l10n) {
    if (l10n == null) return 'matched';
    return l10n.isEnglish ? 'matched' : '已匹配';
  }

  static String _statusExited(AppLocalizations? l10n) {
    if (l10n == null) return 'exited';
    return l10n.isEnglish ? 'exited' : '已退出';
  }
}

/// 是否为注入通知（转发至 [InjectedMessage.isInjectedNotice]）。
bool isInjectedNotice(ChatMessage message) =>
    InjectedMessage.isInjectedNotice(message);

/// 分类（转发至 [InjectedMessage.classify]）。
InjectedNoticeKind classify(ChatMessage message) =>
    InjectedMessage.classify(message);

/// 摘要（转发至 [InjectedMessage.extractSummary]）。
String extractSummary(ChatMessage message, [AppLocalizations? l10n]) =>
    InjectedMessage.extractSummary(message, l10n);

/// [InjectedNoticeKind] 展示标题扩展。
extension InjectedNoticeKindDisplay on InjectedNoticeKind {
  /// 基于 [BuildContext] 的本地化标题（优先走 [AppLocalizations]）。
  String displayTitle(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return displayTitleWithL10n(l10n);
  }

  /// 基于可选 [AppLocalizations] 的标题（便于测试与非 Widget 调用）。
  String displayTitleWithL10n([AppLocalizations? l10n]) {
    switch (this) {
      case InjectedNoticeKind.backgroundProcess:
      case InjectedNoticeKind.backgroundProcessWatch:
      case InjectedNoticeKind.backgroundProcessAggregated:
      case InjectedNoticeKind.subagentAggregated:
        if (l10n == null) return 'Background process';
        return l10n.isEnglish ? 'Background process' : '后台进程';
      case InjectedNoticeKind.cron:
        if (l10n == null) return 'Scheduled task';
        return l10n.isEnglish ? 'Scheduled task' : '定时任务';
      case InjectedNoticeKind.skill:
      case InjectedNoticeKind.skillBundle:
      case InjectedNoticeKind.skillAutoLoaded:
        if (l10n == null) return 'Skill';
        return l10n.isEnglish ? 'Skill' : '技能';
      case InjectedNoticeKind.mcp:
        if (l10n == null) return 'MCP';
        return l10n.isEnglish ? 'MCP' : 'MCP';
      case InjectedNoticeKind.overflow:
        if (l10n == null) return 'Notice';
        return l10n.isEnglish ? 'Notice' : '提示';
      case InjectedNoticeKind.none:
        return '';
    }
  }
}
