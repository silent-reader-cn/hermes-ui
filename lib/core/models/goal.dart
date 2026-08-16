import '../utils/equality.dart';
import '../utils/lossy_json.dart';
import 'json_value.dart';

/// 目标提交响应（Swift: GoalSubmissionResponse）。
class GoalSubmissionResponse {
  const GoalSubmissionResponse({
    this.ok,
    this.action,
    this.message,
    this.goal,
    this.kickoffPrompt,
    this.decision,
  });

  factory GoalSubmissionResponse.fromJson(Map<String, Object?> json) {
    return GoalSubmissionResponse(
      ok: lossyBool(json, 'ok'),
      action: lossyString(json, 'action'),
      message: lossyString(json, 'message'),
      goal: optModel(json, 'goal', SubmittedGoal.fromJson),
      kickoffPrompt: firstKey(json, ['kickoff_prompt', 'kickoffPrompt'], lossyString),
      decision: optModel(json, 'decision', GoalDecision.fromJson),
    );
  }

  final bool? ok;
  final String? action;
  final String? message;
  final SubmittedGoal? goal;
  final String? kickoffPrompt;
  final GoalDecision? decision;

  /// message trim 空 → null。
  String? get displayMessage {
    final trimmed = message?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }

  /// kickoffPrompt trim 空 → null。
  String? get kickoffPromptText {
    final trimmed = kickoffPrompt?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }

  @override
  bool operator ==(Object other) {
    return other is GoalSubmissionResponse &&
        other.ok == ok &&
        other.action == action &&
        other.message == message &&
        other.goal == goal &&
        other.kickoffPrompt == kickoffPrompt &&
        other.decision == decision;
  }

  @override
  int get hashCode =>
      Object.hash(ok, action, message, goal, kickoffPrompt, decision);

  @override
  String toString() => 'GoalSubmissionResponse(ok: $ok, action: $action)';
}

/// 已提交目标（Swift: SubmittedGoal，全字段 camel/snake 双键）。
class SubmittedGoal {
  const SubmittedGoal({
    this.goal,
    this.status,
    this.turnsUsed,
    this.maxTurns,
    this.lastVerdict,
    this.lastReason,
    this.pausedReason,
  });

  factory SubmittedGoal.fromJson(Map<String, Object?> json) {
    return SubmittedGoal(
      goal: lossyString(json, 'goal'),
      status: lossyString(json, 'status'),
      turnsUsed: firstKey(json, ['turns_used', 'turnsUsed'], lossyInt),
      maxTurns: firstKey(json, ['max_turns', 'maxTurns'], lossyInt),
      lastVerdict: firstKey(json, ['last_verdict', 'lastVerdict'], lossyString),
      lastReason: firstKey(json, ['last_reason', 'lastReason'], lossyString),
      pausedReason: firstKey(json, ['paused_reason', 'pausedReason'], lossyString),
    );
  }

  final String? goal;
  final String? status;
  final int? turnsUsed;
  final int? maxTurns;
  final String? lastVerdict;
  final String? lastReason;
  final String? pausedReason;

  @override
  bool operator ==(Object other) {
    return other is SubmittedGoal &&
        other.goal == goal &&
        other.status == status &&
        other.turnsUsed == turnsUsed &&
        other.maxTurns == maxTurns &&
        other.lastVerdict == lastVerdict &&
        other.lastReason == lastReason &&
        other.pausedReason == pausedReason;
  }

  @override
  int get hashCode => Object.hash(
        goal,
        status,
        turnsUsed,
        maxTurns,
        lastVerdict,
        lastReason,
        pausedReason,
      );

  @override
  String toString() => 'SubmittedGoal(goal: $goal, status: $status)';
}

/// 目标决策（Swift: GoalDecision）。
class GoalDecision {
  const GoalDecision({
    this.status,
    this.shouldContinue,
    this.continuationPrompt,
    this.verdict,
    this.reason,
    this.message,
    this.messageKey,
    this.messageArgs,
  });

  factory GoalDecision.fromJson(Map<String, Object?> json) {
    return GoalDecision(
      status: lossyString(json, 'status'),
      shouldContinue: firstKey(json, ['should_continue', 'shouldContinue'], lossyBool),
      continuationPrompt: firstKey(
        json,
        ['continuation_prompt', 'continuationPrompt'],
        lossyString,
      ),
      verdict: lossyString(json, 'verdict'),
      reason: lossyString(json, 'reason'),
      message: lossyString(json, 'message'),
      messageKey: firstKey(json, ['message_key', 'messageKey'], lossyString),
      messageArgs: firstKeyList(
        json,
        ['message_args', 'messageArgs'],
        optJsonValueList,
      ),
    );
  }

  final String? status;
  final bool? shouldContinue;
  final String? continuationPrompt;
  final String? verdict;
  final String? reason;
  final String? message;
  final String? messageKey;
  final List<JsonValue>? messageArgs;

  static List<JsonValue>? firstKeyList(
    Map<String, Object?> json,
    List<String> keys,
    List<JsonValue>? Function(Map<String, Object?>, String) fn,
  ) {
    for (final key in keys) {
      final value = fn(json, key);
      if (value != null) return value;
    }
    return null;
  }

  @override
  bool operator ==(Object other) {
    return other is GoalDecision &&
        other.status == status &&
        other.shouldContinue == shouldContinue &&
        other.continuationPrompt == continuationPrompt &&
        other.verdict == verdict &&
        other.reason == reason &&
        other.message == message &&
        other.messageKey == messageKey &&
        deepEquals(other.messageArgs, messageArgs);
  }

  @override
  int get hashCode {
    return Object.hash(
      status,
      shouldContinue,
      continuationPrompt,
      verdict,
      reason,
      message,
      messageKey,
      deepHash(messageArgs),
    );
  }

  @override
  String toString() => 'GoalDecision(status: $status, verdict: $verdict)';
}
