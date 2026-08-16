import '../models/context_window_snapshot.dart';

/// 上下文窗口格式化（Swift `ContextWindowFormatter`）。纯客户端逻辑，无 JSON。
class ContextWindowFormatter {
  const ContextWindowFormatter._();

  /// 紧凑指示：`27% context`；无数据 → null。
  static String? compactIndicator(ContextWindowSnapshot snapshot) {
    final used = snapshot.tokensUsed;
    final total = snapshot.contextLength;
    if (used == null || total == null || total <= 0) return null;
    final pct = (used / total * 100).truncate();
    return '$pct% context';
  }

  /// `formatTokens(used) / formatTokens(total)`；无数据 → 'Unavailable'。
  static String tokensLabel(ContextWindowSnapshot snapshot) {
    final used = snapshot.tokensUsed;
    final total = snapshot.contextLength;
    if (used == null || total == null) return 'Unavailable';
    return '${formatTokens(used)} / ${formatTokens(total)}';
  }

  static String inputTokensLabel(ContextWindowSnapshot snapshot) {
    final tokens = snapshot.inputTokens;
    if (tokens == null) return 'Unavailable';
    return formatTokens(tokens);
  }

  static String outputTokensLabel(ContextWindowSnapshot snapshot) {
    final tokens = snapshot.outputTokens;
    if (tokens == null) return 'Unavailable';
    return formatTokens(tokens);
  }

  static String thresholdLabel(ContextWindowSnapshot snapshot) {
    final threshold = snapshot.thresholdTokens;
    if (threshold == null || threshold <= 0) return 'Unavailable';
    return formatTokens(threshold);
  }

  static String costLabel(ContextWindowSnapshot snapshot) {
    final cost = snapshot.estimatedCost;
    if (cost == null) return 'Unavailable';
    return formattedCost(cost);
  }

  /// 1_000_000 → `%.1fM`、1_000 → `%.1fK`，否则原数字。
  static String formatTokens(int count) {
    if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(1)}M';
    }
    if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}K';
    }
    return '$count';
  }

  /// `$%.4f`（对应 Swift `formattedCost`）。
  static String formattedCost(double cost) {
    return '\$${cost.toStringAsFixed(4)}';
  }
}
