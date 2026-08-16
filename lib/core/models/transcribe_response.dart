import '../utils/lossy_json.dart';

/// 语音转写响应（Swift: TranscribeResponse）。全字段可空：
/// 成功 `{ok, transcript}`，失败 `{error}`（即使非 2xx 也发 JSON body）。
class TranscribeResponse {
  const TranscribeResponse({this.ok, this.transcript, this.error});

  factory TranscribeResponse.fromJson(Map<String, Object?> json) {
    return TranscribeResponse(
      ok: lossyBool(json, 'ok'),
      transcript: lossyString(json, 'transcript'),
      error: lossyString(json, 'error'),
    );
  }

  final bool? ok;
  final String? transcript;
  final String? error;

  @override
  bool operator ==(Object other) {
    return other is TranscribeResponse &&
        other.ok == ok &&
        other.transcript == transcript &&
        other.error == error;
  }

  @override
  int get hashCode => Object.hash(ok, transcript, error);

  @override
  String toString() => 'TranscribeResponse(ok: $ok)';
}
