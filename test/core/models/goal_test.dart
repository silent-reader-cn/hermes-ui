import 'package:flutter_test/flutter_test.dart';
import 'package:hermex_flutter/core/models/goal.dart';
import 'package:hermex_flutter/core/models/json_value.dart';

void main() {
  group('GoalSubmissionResponse', () {
    test('规格示例正常解析', () {
      final response = GoalSubmissionResponse.fromJson({
        'ok': true,
        'action': 'accepted',
        'message': '目标已提交',
        'goal': {
          'goal': '修复 bug',
          'status': 'running',
          'turns_used': 3,
          'max_turns': 20,
          'last_verdict': 'continue',
          'last_reason': '正常推进',
        },
        'kickoff_prompt': '开始执行',
        'decision': {
          'status': 'continue',
          'should_continue': true,
          'verdict': 'continue',
          'reason': '…',
          'message': '…',
          'message_key': 'goal.continue',
          'message_args': [],
        },
      });
      expect(response.ok, true);
      expect(response.action, 'accepted');
      expect(response.displayMessage, '目标已提交');
      expect(response.kickoffPromptText, '开始执行');
      expect(response.goal!.turnsUsed, 3);
      expect(response.goal!.maxTurns, 20);
      expect(response.goal!.lastVerdict, 'continue');
      expect(response.decision!.shouldContinue, true);
      expect(response.decision!.messageKey, 'goal.continue');
      expect(response.decision!.messageArgs, isEmpty);
    });

    test('camel 双键', () {
      final response = GoalSubmissionResponse.fromJson({
        'kickoffPrompt': 'K',
        'goal': {
          'turnsUsed': 4,
          'maxTurns': 10,
          'lastVerdict': 'v',
          'lastReason': 'r',
          'pausedReason': 'p',
        },
        'decision': {
          'shouldContinue': false,
          'continuationPrompt': 'c',
          'messageKey': 'k',
          'messageArgs': [1, 'a'],
        },
      });
      expect(response.kickoffPrompt, 'K');
      expect(response.goal!.turnsUsed, 4);
      expect(response.goal!.pausedReason, 'p');
      expect(response.decision!.shouldContinue, false);
      expect(response.decision!.continuationPrompt, 'c');
      expect(response.decision!.messageArgs, [
        const JsonNumber(1),
        const JsonString('a'),
      ]);
    });

    test('畸形输入：缺失/错型 → null 容错', () {
      final response = GoalSubmissionResponse.fromJson({
        'ok': 'yes',
        'action': 1,
        'message': '   ',
        'kickoff_prompt': '  ',
        'goal': 'bad',
        'decision': 'bad',
      });
      expect(response.ok, true);
      expect(response.action, '1');
      expect(response.displayMessage, isNull);
      expect(response.kickoffPromptText, isNull);
      expect(response.goal, isNull);
      expect(response.decision, isNull);

      final goal = SubmittedGoal.fromJson({
        'goal': 2,
        'turns_used': '3',
        'max_turns': 'many',
        'last_verdict': false,
      });
      expect(goal.goal, '2');
      expect(goal.turnsUsed, 3);
      expect(goal.maxTurns, isNull);
      expect(goal.lastVerdict, 'false');
    });
  });

  group('GoalDecision 畸形', () {
    test('类型不符 → 容错，messageArgs 坏数组 → null', () {
      final decision = GoalDecision.fromJson({
        'status': 1,
        'should_continue': 'yes',
        'verdict': 2,
        'message_args': 'bad',
      });
      expect(decision.status, '1');
      expect(decision.shouldContinue, true);
      expect(decision.verdict, '2');
      expect(decision.messageArgs, isNull);
    });
  });

  test('== / hashCode / toString', () {
    final a = GoalSubmissionResponse.fromJson({'ok': true});
    final b = GoalSubmissionResponse.fromJson({'ok': true});
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a.toString(), contains('GoalSubmissionResponse'));
  });
}
