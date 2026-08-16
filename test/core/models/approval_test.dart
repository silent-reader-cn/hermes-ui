import 'package:flutter_test/flutter_test.dart';
import 'package:hermex_flutter/core/models/approval.dart';

void main() {
  group('ApprovalChoice', () {
    test('4 个 rawValue 解析，未知 → null', () {
      expect(approvalChoiceFromJson('once'), ApprovalChoice.once);
      expect(approvalChoiceFromJson('session'), ApprovalChoice.session);
      expect(approvalChoiceFromJson('always'), ApprovalChoice.always);
      expect(approvalChoiceFromJson('deny'), ApprovalChoice.deny);
      expect(approvalChoiceFromJson('unknown'), isNull);
      expect(approvalChoiceFromJson(5), isNull);
    });
  });

  group('PendingApproval', () {
    test('规格示例正常解析', () {
      final pending = PendingApproval.fromJson({
        'approval_id': 'ap_7',
        'command': 'bash',
        'description': 'Run destructive command?',
        'pattern_key': 'rm -rf',
        'pattern_keys': ['rm -rf', 'git push --force'],
      });
      expect(pending.approvalId, 'ap_7');
      expect(pending.command, 'bash');
      expect(pending.patternKey, 'rm -rf');
      expect(pending.patternKeys, ['rm -rf', 'git push --force']);
      expect(pending.displayPatternKeys, ['rm -rf', 'git push --force']);
      expect(pending.id, 'ap_7');
    });

    test('三键 approval_id：approval_id → approvalId → id，trim 归一', () {
      expect(PendingApproval.fromJson({'approvalId': 'x'}).approvalId, 'x');
      expect(PendingApproval.fromJson({'id': 'y'}).approvalId, 'y');
      expect(PendingApproval.fromJson({'approval_id': '  z  '}).approvalId, 'z');
    });

    test('畸形输入：缺失/错型 → null 容错', () {
      final pending = PendingApproval.fromJson({
        'approval_id': '',
        'command': 3,
        'description': false,
        'pattern_key': 9,
        'pattern_keys': 'not-a-list',
      });
      expect(pending.approvalId, isNull);
      expect(pending.command, '3');
      expect(pending.description, 'false');
      expect(pending.patternKey, '9');
      // 单字符串 → 包装成单元素数组（对齐 Swift decodeStringArray）
      expect(pending.patternKeys, ['not-a-list']);
      expect(PendingApproval.fromJson(const {}).isEmpty, true);
    });

    test('displayPatternKeys：patternKeys 过滤空后优先，否则 patternKey 单元素', () {
      // 过滤保留原字符串（Swift 只按 trim 非空过滤，不重写元素）
      expect(
        PendingApproval.fromJson({'pattern_keys': [' a ', '']})
            .displayPatternKeys,
        [' a '],
      );
      expect(
        PendingApproval.fromJson({'pattern_key': '  x  '}).displayPatternKeys,
        ['x'],
      );
      expect(PendingApproval.fromJson(const {}).displayPatternKeys, isEmpty);
    });

    test('id 派生：command-description-patternKeys', () {
      final pending = PendingApproval.fromJson({
        'command': 'bash',
        'description': 'desc',
        'pattern_keys': ['a', 'b'],
      });
      expect(pending.id, 'bash-desc-a,b');
    });

    test('pattern_keys 支持 JSONValue 数组 / 单字符串包装', () {
      // Dart 数字统一为 double，JsonNumber(1.0).lossyString → '1.0'
      expect(
        PendingApproval.fromJson({'pattern_keys': [1, 'two', true]})
            .patternKeys,
        ['1.0', 'two', 'true'],
      );
      expect(
        PendingApproval.fromJson({'pattern_keys': 'solo'}).patternKeys,
        ['solo'],
      );
    });
  });

  group('ApprovalPendingResponse', () {
    test('正常解析 + pending_count 双键', () {
      final response = ApprovalPendingResponse.fromJson({
        'pending': {'approval_id': 'ap_7', 'command': 'bash'},
        'pending_count': 1,
      });
      expect(response.pending!.approvalId, 'ap_7');
      expect(response.pendingCount, 1);
      expect(
        ApprovalPendingResponse.fromJson({'pendingCount': 2}).pendingCount,
        2,
      );
      expect(
        ApprovalPendingResponse.fromJson(const {}).pending,
        isNull,
      );
    });

    test('streamPayload：自身优先 / 直接 pending 包装 / 空', () {
      final wrapped = ApprovalPendingResponse.streamPayload({
        'pending': {'approval_id': 'ap_1'},
        'pending_count': 1,
      });
      expect(wrapped.pending!.approvalId, 'ap_1');
      expect(wrapped.pendingCount, 1);

      final direct = ApprovalPendingResponse.streamPayload({
        'approval_id': 'ap_2',
        'command': 'ls',
      });
      expect(direct.pending!.approvalId, 'ap_2');
      expect(direct.pendingCount, 1);

      final empty = ApprovalPendingResponse.streamPayload(const {});
      expect(empty.pending, isNull);
      expect(empty.pendingCount, isNull);
    });
  });

  group('ApprovalRespondResponse', () {
    test('规格示例正常解析', () {
      final response = ApprovalRespondResponse.fromJson({
        'ok': true,
        'choice': 'always',
        'stale_cleared': false,
        'relayed': false,
        'stale': false,
      });
      expect(response.ok, true);
      expect(response.choice, ApprovalChoice.always);
      expect(response.staleCleared, false);
      expect(response.relayed, false);
      expect(response.stale, false);
    });

    test('畸形输入：choice 未知 → null，其余容错', () {
      final response = ApprovalRespondResponse.fromJson({
        'ok': 'yes',
        'choice': 'maybe',
        'stale_cleared': 1,
      });
      expect(response.ok, true);
      expect(response.choice, isNull);
      expect(response.staleCleared, true);
    });
  });

  group('SessionYoloResponse', () {
    test('正常 + yolo_enabled/yoloEnabled 双键 + 畸形', () {
      expect(
        SessionYoloResponse.fromJson({'ok': true, 'yolo_enabled': true})
            .yoloEnabled,
        true,
      );
      expect(
        SessionYoloResponse.fromJson({'yoloEnabled': true}).yoloEnabled,
        true,
      );
      expect(
        SessionYoloResponse.fromJson({'yolo_enabled': 'garbage'}).yoloEnabled,
        isNull,
      );
      expect(SessionYoloResponse.fromJson(const {}).ok, isNull);
    });
  });

  test('== / hashCode', () {
    final a = ApprovalRespondResponse.fromJson({'ok': true, 'choice': 'once'});
    final b = ApprovalRespondResponse.fromJson({'ok': true, 'choice': 'once'});
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });
}
