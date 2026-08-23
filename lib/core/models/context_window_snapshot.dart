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
      contextLength: firstKey(json, [
            'context_length',
            'contextLength',
          ], lossyInt) ??
          lossyInt(json, 'context_length'),
      thresholdTokens: firstKey(json, [
            'threshold_tokens',
            'thresholdTokens',
          ], lossyInt) ??
          lossyInt(json, 'threshold_tokens'),
      lastPromptTokens: firstKey(json, [
            'last_prompt_tokens',
            'lastPromptTokens',
          ], lossyInt) ??
          lossyInt(json, 'last_prompt_tokens'),
      inputTokens: firstKey(json, [
            'input_tokens',
            'inputTokens',
          ], lossyInt) ??
          lossyInt(json, 'input_tokens'),
      outputTokens: firstKey(json, [
            'output_tokens',
            'outputTokens',
          ], lossyInt) ??
          lossyInt(json, 'output_tokens'),
      estimatedCost: firstKey(json, [
            'estimated_cost',
            'estimatedCost',
          ], lossyDouble) ??
          lossyDouble(json, 'estimated_cost'),
      // 键是 `tps`（显式 rawValue），同时兼容备用键。
      tokensPerSecond: firstKey(json, [
            'tps',
            'tokens_per_second',
            'tokensPerSecond',
          ], lossyDouble) ??
          lossyDouble(json, 'tps'),
    );
  }

  final int? contextLength;
  final int? thresholdTokens;
  final int? lastPromptTokens;
  final int? inputTokens;
  final int? outputTokens;
  final double? estimatedCost;
  final double? tokensPerSecond;

  /// lastPromptTokens（>0 优先） ?? inputTokens。
  ///
  /// 当 lastPromptTokens 为 0 或 null 时回退到 inputTokens，避免空会话
  /// 的 0 误覆盖真实 input 计数，导致指示器始终 0。
  int? get tokensUsed {
    final last = lastPromptTokens;
    if (last != null && last > 0) return last;
    return inputTokens;
  }

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

  /// 更新 tps 的拷贝。
  ContextWindowSnapshot replacingTokensPerSecond(double? tps) {
    if (tps == null) return this;
    return ContextWindowSnapshot(
      contextLength: contextLength,
      thresholdTokens: thresholdTokens,
      lastPromptTokens: lastPromptTokens,
      inputTokens: inputTokens,
      outputTokens: outputTokens,
      estimatedCost: estimatedCost,
      tokensPerSecond: tps,
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
