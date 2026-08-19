import '../utils/lossy_json.dart';

/// 待澄清请求/响应类型别名（兼容 TASK W3 强类型命名）。
typedef ClarificationRequest = ClarificationPendingResponse;

/// 待澄清响应信封（Swift: ClarificationPendingResponse）。
class ClarificationPendingResponse {
  const ClarificationPendingResponse({this.pending, this.pendingCount});

  factory ClarificationPendingResponse.fromJson(Map<String, Object?> json) {
    return ClarificationPendingResponse(
      pending: optModel(json, 'pending', PendingClarification.fromJson),
      pendingCount: firstKey(json, ['pending_count', 'pendingCount'], lossyInt),
    );
  }

  /// SSE 流载荷解析（对齐 Swift `streamPayload`，同 ApprovalPendingResponse 模式）。
  static ClarificationPendingResponse streamPayload(Map<String, Object?> json) {
    final wrapped = ClarificationPendingResponse.fromJson(json);
    if (wrapped.pending != null || wrapped.pendingCount != null) {
      return wrapped;
    }
    final direct = PendingClarification.fromJson(json);
    if (!direct.isEmpty) {
      return ClarificationPendingResponse(pending: direct, pendingCount: 1);
    }
    return const ClarificationPendingResponse();
  }

  /// 数据中是否含澄清标记（question / choices_offered / choicesOffered）。
  static bool containsClarificationMarkers(Map<String, Object?> json) {
    final candidate = json['pending'];
    final Map<String, Object?> map;
    if (candidate is Map) {
      map = Map<String, Object?>.from(candidate);
    } else {
      map = json;
    }
    return map.containsKey('question') ||
        map.containsKey('choices_offered') ||
        map.containsKey('choicesOffered');
  }

  final PendingClarification? pending;
  final int? pendingCount;

  @override
  bool operator ==(Object other) {
    return other is ClarificationPendingResponse &&
        other.pending == pending &&
        other.pendingCount == pendingCount;
  }

  @override
  int get hashCode => Object.hash(pending, pendingCount);

  @override
  String toString() => 'ClarificationPendingResponse(pendingCount: $pendingCount)';
}

/// 待澄清（Swift: PendingClarification）。`id` = clarifyId 非空 ? clarifyId :
/// `$sessionId-$question-$requestedAt`。
class PendingClarification {
  const PendingClarification({
    this.clarifyId,
    this.question,
    this.choicesOffered,
    this.sessionId,
    this.kind,
    this.requestedAt,
    this.timeoutSeconds,
    this.expiresAt,
  });

  factory PendingClarification.fromJson(Map<String, Object?> json) {
    return PendingClarification(
      clarifyId: firstKey(json, ['clarify_id', 'clarifyId', 'id'], lossyString),
      question: lossyString(json, 'question'),
      choicesOffered: lossyStringArray(json, ['choices_offered', 'choicesOffered']),
      sessionId: firstKey(json, ['session_id', 'sessionId'], lossyString),
      kind: lossyString(json, 'kind'),
      requestedAt: firstKey(json, ['requested_at', 'requestedAt'], lossyDouble),
      timeoutSeconds: firstKey(json, ['timeout_seconds', 'timeoutSeconds'], lossyInt),
      expiresAt: firstKey(json, ['expires_at', 'expiresAt'], lossyDouble),
    );
  }

  final String? clarifyId;
  final String? question;
  final List<String>? choicesOffered;
  final String? sessionId;
  final String? kind;
  final double? requestedAt;
  final int? timeoutSeconds;
  final double? expiresAt;

  String get id {
    final cid = clarifyId;
    if (cid != null && cid.isNotEmpty) return cid;
    return '${sessionId ?? ''}-${question ?? ''}-${requestedAt ?? 0}';
  }

  /// trim 过滤空后的选项。
  List<String> get displayChoices {
    return choicesOffered
            ?.map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList() ??
        const [];
  }

  /// 空则默认文案。
  String get displayQuestion {
    final trimmed = question?.trim() ?? '';
    return trimmed.isEmpty
        ? 'The agent needs more information before continuing.'
        : trimmed;
  }

  /// 8 字段全空。
  bool get isEmpty {
    return clarifyId == null &&
        question == null &&
        (choicesOffered?.isEmpty ?? true) &&
        sessionId == null &&
        kind == null &&
        requestedAt == null &&
        timeoutSeconds == null &&
        expiresAt == null;
  }

  @override
  bool operator ==(Object other) {
    return other is PendingClarification &&
        other.clarifyId == clarifyId &&
        other.question == question &&
        _listEquals(other.choicesOffered, choicesOffered) &&
        other.sessionId == sessionId &&
        other.kind == kind &&
        other.requestedAt == requestedAt &&
        other.timeoutSeconds == timeoutSeconds &&
        other.expiresAt == expiresAt;
  }

  @override
  int get hashCode {
    return Object.hash(
      clarifyId,
      question,
      _hashList(choicesOffered),
      sessionId,
      kind,
      requestedAt,
      timeoutSeconds,
      expiresAt,
    );
  }

  @override
  String toString() => 'PendingClarification(clarifyId: $clarifyId, question: $question)';
}

/// 澄清响应（Swift: ClarificationRespondResponse）。
class ClarificationRespondResponse {
  const ClarificationRespondResponse({
    this.ok,
    this.response,
    this.stale,
    this.staleCleared,
    this.relayed,
  });

  factory ClarificationRespondResponse.fromJson(Map<String, Object?> json) {
    return ClarificationRespondResponse(
      ok: lossyBool(json, 'ok'),
      response: lossyString(json, 'response'),
      stale: lossyBool(json, 'stale'),
      staleCleared: firstKey(json, ['stale_cleared', 'staleCleared'], lossyBool),
      relayed: lossyBool(json, 'relayed'),
    );
  }

  final bool? ok;
  final String? response;
  final bool? stale;
  final bool? staleCleared;
  final bool? relayed;

  @override
  bool operator ==(Object other) {
    return other is ClarificationRespondResponse &&
        other.ok == ok &&
        other.response == response &&
        other.stale == stale &&
        other.staleCleared == staleCleared &&
        other.relayed == relayed;
  }

  @override
  int get hashCode => Object.hash(ok, response, stale, staleCleared, relayed);

  @override
  String toString() => 'ClarificationRespondResponse(ok: $ok)';
}

bool _listEquals(List<String>? a, List<String>? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return false;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

int _hashList(List<String>? list) => Object.hashAll(list ?? const []);
