import 'package:flutter_test/flutter_test.dart';
import 'package:hermex_flutter/core/models/clarification.dart';

void main() {
  group('PendingClarification', () {
    test('规格示例正常解析', () {
      final pending = PendingClarification.fromJson({
        'clarify_id': 'cl_3',
        'question': '选哪个方案？',
        'choices_offered': ['方案A', '方案B'],
        'session_id': 'abc123',
        'kind': 'choice',
        'requested_at': 1723700000.0,
        'timeout_seconds': 300,
        'expires_at': 1723700300.0,
      });
      expect(pending.clarifyId, 'cl_3');
      expect(pending.question, '选哪个方案？');
      expect(pending.choicesOffered, ['方案A', '方案B']);
      expect(pending.sessionId, 'abc123');
      expect(pending.kind, 'choice');
      expect(pending.requestedAt, 1723700000.0);
      expect(pending.timeoutSeconds, 300);
      expect(pending.expiresAt, 1723700300.0);
      expect(pending.id, 'cl_3');
    });

    test('camel 双键', () {
      final pending = PendingClarification.fromJson({
        'clarifyId': 'c1',
        'choicesOffered': ['a'],
        'sessionId': 's1',
        'requestedAt': 1.0,
        'timeoutSeconds': 5,
        'expiresAt': 2.0,
      });
      expect(pending.clarifyId, 'c1');
      expect(pending.sessionId, 's1');
      expect(pending.timeoutSeconds, 5);
    });

    test('畸形输入：缺失/错型 → null 容错', () {
      final pending = PendingClarification.fromJson({
        'clarify_id': 9,
        'question': false,
        'choices_offered': 'bad',
        'session_id': null,
        'requested_at': 'x',
        'timeout_seconds': 'y',
        'expires_at': 'z',
      });
      expect(pending.clarifyId, '9');
      expect(pending.question, 'false');
      // 单字符串 → 包装成单元素数组（对齐 Swift decodeStringArray）
      expect(pending.choicesOffered, ['bad']);
      expect(pending.requestedAt, isNull);
      expect(pending.timeoutSeconds, isNull);
      expect(pending.expiresAt, isNull);
      expect(PendingClarification.fromJson(const {}).isEmpty, true);
    });

    test('displayChoices / displayQuestion / id 派生', () {
      expect(
        PendingClarification.fromJson({'choices_offered': [' a ', '', 'b']})
            .displayChoices,
        ['a', 'b'],
      );
      expect(
        PendingClarification.fromJson(const {}).displayQuestion,
        'The agent needs more information before continuing.',
      );
      expect(
        PendingClarification.fromJson({'question': '  hi  '}).displayQuestion,
        'hi',
      );
      final derived = PendingClarification.fromJson({
        'session_id': 's1',
        'question': 'q',
        'requested_at': 5.0,
      });
      expect(derived.id, 's1-q-5.0');
    });

    test('choices_offered 支持 JSONValue 数组 / 单字符串', () {
      // Dart 数字统一为 double，JsonNumber(1.0).lossyString → '1.0'
      expect(
        PendingClarification.fromJson({'choices_offered': [1, 'a', true]})
            .choicesOffered,
        ['1.0', 'a', 'true'],
      );
      expect(
        PendingClarification.fromJson({'choices_offered': 'single'})
            .choicesOffered,
        ['single'],
      );
    });
  });

  group('ClarificationPendingResponse', () {
    test('正常 + pending_count 双键 + streamPayload', () {
      final response = ClarificationPendingResponse.fromJson({
        'pending': {'clarify_id': 'cl_3', 'question': '…'},
        'pending_count': 1,
      });
      expect(response.pending!.clarifyId, 'cl_3');
      expect(response.pendingCount, 1);
      expect(
        ClarificationPendingResponse.fromJson({'pendingCount': 2}).pendingCount,
        2,
      );

      final direct = ClarificationPendingResponse.streamPayload({
        'clarify_id': 'cl_9',
        'question': 'q',
      });
      expect(direct.pending!.clarifyId, 'cl_9');
      expect(direct.pendingCount, 1);

      final empty = ClarificationPendingResponse.streamPayload(const {});
      expect(empty.pending, isNull);
      expect(empty.pendingCount, isNull);
    });

    test('containsClarificationMarkers', () {
      expect(
        ClarificationPendingResponse.containsClarificationMarkers(
          {'pending': {'question': 'q'}},
        ),
        true,
      );
      expect(
        ClarificationPendingResponse.containsClarificationMarkers(
          {'choices_offered': ['a']},
        ),
        true,
      );
      expect(
        ClarificationPendingResponse.containsClarificationMarkers(
          {'other': 1},
        ),
        false,
      );
    });
  });

  group('ClarificationRespondResponse', () {
    test('正常解析（附录 A.5）', () {
      final response = ClarificationRespondResponse.fromJson({
        'ok': true,
        'response': '方案A',
        'stale': false,
        'stale_cleared': false,
        'relayed': false,
      });
      expect(response.ok, true);
      expect(response.response, '方案A');
      expect(response.stale, false);
      expect(response.staleCleared, false);
    });

    test('畸形输入：stale_cleared 双键 + 错型容错', () {
      expect(
        ClarificationRespondResponse.fromJson({'staleCleared': true})
            .staleCleared,
        true,
      );
      final broken = ClarificationRespondResponse.fromJson({
        'ok': 'maybe',
        'response': 42,
      });
      expect(broken.ok, isNull);
      expect(broken.response, '42');
    });
  });

  test('== / hashCode', () {
    final a = PendingClarification.fromJson({'clarify_id': 'c1', 'question': 'q'});
    final b = PendingClarification.fromJson({'clarify_id': 'c1', 'question': 'q'});
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });
}
