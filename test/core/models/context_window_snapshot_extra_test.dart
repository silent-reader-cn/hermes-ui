import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/models/context_window_snapshot.dart';

void main() {
  group('ContextWindowSnapshot.fromJson 容错补充', () {
    test('字符串数字与超大 double 容错', () {
      final s = ContextWindowSnapshot.fromJson({
        'context_length': '200000',
        'last_prompt_tokens': '54321',
        'input_tokens': 1e20,
        'tps': '24.5',
      });
      expect(s.contextLength, 200000);
      expect(s.lastPromptTokens, 54321);
      expect(s.inputTokens, isNull);
      expect(s.tokensPerSecond, 24.5);
    });

    test('percentage = (lastPromptTokens??inputTokens)/contextLength', () {
      expect(
        ContextWindowSnapshot.fromJson({
          'context_length': 100,
          'last_prompt_tokens': 25,
        }).percentage,
        0.25,
      );
      expect(
        ContextWindowSnapshot.fromJson({
          'context_length': 100,
          'input_tokens': 40,
        }).percentage,
        0.40,
      );
      expect(
        ContextWindowSnapshot.fromJson({
          'context_length': 100,
          'last_prompt_tokens': 25,
          'input_tokens': 40,
        }).percentage,
        0.25,
      );
      expect(
        ContextWindowSnapshot.fromJson({
          'context_length': 0,
          'last_prompt_tokens': 10,
        }).percentage,
        isNull,
      );
      expect(
        ContextWindowSnapshot.fromJson(const {}).percentage,
        isNull,
      );
    });

    test('replacingTokensUsed 保持其他字段', () {
      final a = ContextWindowSnapshot.fromJson({
        'context_length': 200000,
        'threshold_tokens': 160000,
        'input_tokens': 60000,
        'output_tokens': 1000,
      });
      final b = a.replacingTokensUsed(54321);
      expect(b.lastPromptTokens, 54321);
      expect(b.contextLength, 200000);
      expect(b.thresholdTokens, 160000);
      expect(b.inputTokens, 60000);
    });
  });
}
