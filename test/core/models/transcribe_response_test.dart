import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/models/transcribe_response.dart';

void main() {
  group('TranscribeResponse', () {
    test('成功形态（规格示例）', () {
      final response = TranscribeResponse.fromJson(
        {'ok': true, 'transcript': '你好世界'},
      );
      expect(response.ok, true);
      expect(response.transcript, '你好世界');
      expect(response.error, isNull);
    });

    test('失败形态 {error: …}（即使非 2xx）', () {
      final response = TranscribeResponse.fromJson(
        {'error': 'STT not configured'},
      );
      expect(response.ok, isNull);
      expect(response.transcript, isNull);
      expect(response.error, 'STT not configured');
    });

    test('畸形输入：缺失/错型 → null 容错', () {
      final response = TranscribeResponse.fromJson({
        'ok': 'yes',
        'transcript': 42,
        'error': false,
      });
      expect(response.ok, true);
      expect(response.transcript, '42');
      expect(response.error, 'false');
      final empty = TranscribeResponse.fromJson(const {});
      expect(empty.ok, isNull);
      expect(empty.transcript, isNull);
      expect(empty.error, isNull);
    });
  });

  test('== / hashCode', () {
    final a = TranscribeResponse.fromJson({'ok': true});
    final b = TranscribeResponse.fromJson({'ok': true});
    expect(a, b);
    expect(a.hashCode, b.hashCode);
  });
}
