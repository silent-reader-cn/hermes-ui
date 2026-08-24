import 'package:flutter_test/flutter_test.dart';
import 'package:hermex_flutter/core/models/context_window_snapshot.dart';
import 'package:hermex_flutter/core/utils/context_window_formatter.dart';

void main() {
  group('ContextWindowSnapshot.fromJson', () {
    test('规格示例正常解析（tps 键）', () {
      final snapshot = ContextWindowSnapshot.fromJson({
        'context_length': 200000,
        'threshold_tokens': 160000,
        'last_prompt_tokens': 54321,
        'input_tokens': 60000,
        'output_tokens': 1000,
        'estimated_cost': 0.0123,
        'tps': 24.5,
      });
      expect(snapshot.contextLength, 200000);
      expect(snapshot.thresholdTokens, 160000);
      expect(snapshot.lastPromptTokens, 54321);
      expect(snapshot.inputTokens, 60000);
      expect(snapshot.outputTokens, 1000);
      expect(snapshot.estimatedCost, 0.0123);
      expect(snapshot.tokensPerSecond, 24.5);
    });

    test('畸形输入：缺失/错型 → null 容错', () {
      final snapshot = ContextWindowSnapshot.fromJson({
        'context_length': 'big',
        'threshold_tokens': 'many',
        'tps': 'fast',
      });
      expect(snapshot.contextLength, isNull);
      expect(snapshot.thresholdTokens, isNull);
      expect(snapshot.tokensPerSecond, isNull);
      final empty = ContextWindowSnapshot.fromJson(const {});
      expect(empty.estimatedCost, isNull);
    });
  });

  group('派生属性', () {
    test('tokensUsed / percentage / replacingTokensUsed', () {
      final snapshot = ContextWindowSnapshot.fromJson({
        'context_length': 100,
        'last_prompt_tokens': 25,
        'input_tokens': 50,
      });
      expect(snapshot.tokensUsed, 25);
      expect(snapshot.percentage, 0.25);
      expect(snapshot.replacingTokensUsed(40).lastPromptTokens, 40);
      expect(snapshot.replacingTokensUsed(null), snapshot);
      expect(
        ContextWindowSnapshot.fromJson(const {}).percentage,
        isNull,
      );
      expect(
        ContextWindowSnapshot.fromJson({'context_length': 0, 'last_prompt_tokens': 1})
            .percentage,
        isNull,
      );
    });
  });

  group('ContextWindowFormatter', () {
    final snapshot = ContextWindowSnapshot.fromJson({
      'context_length': 200000,
      'threshold_tokens': 160000,
      'last_prompt_tokens': 54321,
      'input_tokens': 60000,
      'output_tokens': 1000,
      'estimated_cost': 0.0123,
      'tps': 24.5,
    });

    test('compactIndicator', () {
      expect(
        ContextWindowFormatter.compactIndicator(snapshot),
        '27% context',
      );
      expect(
        ContextWindowFormatter.compactIndicator(
          ContextWindowSnapshot.fromJson(const {}),
        ),
        isNull,
      );
    });

    test('tokensLabel / input / output / threshold', () {
      expect(
        ContextWindowFormatter.tokensLabel(snapshot),
        '54.3K / 200.0K',
      );
      expect(
        ContextWindowFormatter.inputTokensLabel(snapshot),
        '60.0K',
      );
      expect(
        ContextWindowFormatter.outputTokensLabel(snapshot),
        '1.0K',
      );
      expect(
        ContextWindowFormatter.thresholdLabel(snapshot),
        '160.0K (80%)',
      );
      expect(
        ContextWindowFormatter.tokensLabel(
          ContextWindowSnapshot.fromJson(const {}),
        ),
        'Unavailable',
      );
    });

    test('formatTokens', () {
      expect(ContextWindowFormatter.formatTokens(1000000), '1.0M');
      expect(ContextWindowFormatter.formatTokens(1500000), '1.5M');
      expect(ContextWindowFormatter.formatTokens(1000), '1.0K');
      expect(ContextWindowFormatter.formatTokens(999), '999');
    });

    test('costLabel', () {
      expect(ContextWindowFormatter.costLabel(snapshot), '\$0.0123');
      expect(
        ContextWindowFormatter.costLabel(
          ContextWindowSnapshot.fromJson(const {}),
        ),
        'Unavailable',
      );
    });
  });

  test('== / hashCode / toString', () {
    final a = ContextWindowSnapshot.fromJson({'context_length': 10});
    final b = ContextWindowSnapshot.fromJson({'context_length': 10});
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a.toString(), contains('ContextWindowSnapshot'));
  });
}
