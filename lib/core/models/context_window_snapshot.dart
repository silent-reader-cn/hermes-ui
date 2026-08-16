import '../utils/lossy_json.dart';

/// 上下文窗口快照（Swift: ContextWindowSnapshot）。
class ContextWindowSnapshot {
  const ContextWindowSnapshot({
    this.contextLength,
    this.thresholdTokens,
    this.lastPromptTokens,
    this.inputTokens,
    this.outputTokens,
    this.estimatedCost,
    this.tokensPerSecond,
  });

  factory ContextWindowSnapshot.fromJson(Map<String, Object?> json) {
    return ContextWindowSnapshot(
      contextLength: lossyInt(json, 'context_length'),
      thresholdTokens: lossyInt(json, 'threshold_tokens'),
      lastPromptTokens: lossyInt(json, 'last_prompt_tokens'),
      inputTokens: lossyInt(json, 'input_tokens'),
      outputTokens: lossyInt(json, 'output_tokens'),
      estimatedCost: lossyDouble(json, 'estimated_cost'),
      // 键是 `tps`（显式 rawValue）。
      tokensPerSecond: lossyDouble(json, 'tps'),
    );
  }

  final int? contextLength;
  final int? thresholdTokens;
  final int? lastPromptTokens;
  final int? inputTokens;
  final int? outputTokens;
  final double? estimatedCost;
  final double? tokensPerSecond;

  /// lastPromptTokens ?? inputTokens。
  int? get tokensUsed => lastPromptTokens ?? inputTokens;

  /// used/contextLength；除数≤0 → null。
  double? get percentage {
    final used = tokensUsed;
    final total = contextLength;
    if (used == null || total == null || total <= 0) return null;
    return used / total;
  }

  /// copyWith：替换 lastPromptTokens。
  ContextWindowSnapshot replacingTokensUsed(int? tokens) {
    if (tokens == null) return this;
    return ContextWindowSnapshot(
      contextLength: contextLength,
      thresholdTokens: thresholdTokens,
      lastPromptTokens: tokens,
      inputTokens: inputTokens,
      outputTokens: outputTokens,
      estimatedCost: estimatedCost,
      tokensPerSecond: tokensPerSecond,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ContextWindowSnapshot &&
        other.contextLength == contextLength &&
        other.thresholdTokens == thresholdTokens &&
        other.lastPromptTokens == lastPromptTokens &&
        other.inputTokens == inputTokens &&
        other.outputTokens == outputTokens &&
        other.estimatedCost == estimatedCost &&
        other.tokensPerSecond == tokensPerSecond;
  }

  @override
  int get hashCode => Object.hash(
        contextLength,
        thresholdTokens,
        lastPromptTokens,
        inputTokens,
        outputTokens,
        estimatedCost,
        tokensPerSecond,
      );

  @override
  String toString() {
    return 'ContextWindowSnapshot(contextLength: $contextLength, '
        'thresholdTokens: $thresholdTokens)';
  }
}
