import 'dart:convert';

import 'package:drift/drift.dart';

import '../models/session.dart';
import 'app_database.dart';

/// 最近会话/消息只读缓存。网络成功时写入，断网时由调用方读取。
class CacheService {
  CacheService(this.database);

  final AppDatabase database;
  static const int maxSessions = 50;
  static const Duration ttl = Duration(days: 7);

  Future<void> writeSessions(List<SessionSummary> sessions) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await database.transaction(() async {
      await database.delete(database.cachedSessions).go();
      for (final session in sessions.take(maxSessions)) {
        final id = session.sessionId ?? session.id;
        await database.into(database.cachedSessions).insertOnConflictUpdate(
              CachedSessionsCompanion.insert(
                sessionId: id,
                title: Value(session.title ?? ''),
                payload: jsonEncode(_sessionToJson(session)),
                cachedAt: now,
              ),
            );
      }
    });
  }

  Future<List<SessionSummary>> readSessions() async {
    final cutoff = DateTime.now().subtract(ttl).millisecondsSinceEpoch;
    final rows = await (database.select(database.cachedSessions)
          ..where((row) => row.cachedAt.isBiggerOrEqualValue(cutoff))
          ..orderBy([(row) => OrderingTerm.desc(row.cachedAt)]))
        .get();
    return rows
        .map((row) => SessionSummary.fromJson(
              Map<String, Object?>.from(jsonDecode(row.payload) as Map),
            ))
        .toList(growable: false);
  }

  Future<void> writeMessages({
    required String sessionId,
    required List<Map<String, Object?>> messages,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final message in messages.take(50)) {
      final id = message['id']?.toString();
      if (id == null || id.isEmpty) continue;
      await database.into(database.cachedMessages).insertOnConflictUpdate(
            CachedMessagesCompanion.insert(
              messageId: id,
              sessionId: sessionId,
              payload: jsonEncode(message),
              cachedAt: now,
            ),
          );
    }
  }

  Future<List<Map<String, Object?>>> readMessages(String sessionId) async {
    final rows = await (database.select(database.cachedMessages)
          ..where((row) => row.sessionId.equals(sessionId))
          ..orderBy([(row) => OrderingTerm.desc(row.cachedAt)])
          ..limit(50))
        .get();
    return rows
        .map((row) => Map<String, Object?>.from(jsonDecode(row.payload) as Map))
        .toList(growable: false);
  }

  static Map<String, Object?> _sessionToJson(SessionSummary session) => {
        'session_id': session.sessionId ?? session.id,
        'title': session.title,
        'workspace': session.workspace,
        'model': session.model,
        'message_count': session.messageCount,
        'created_at': session.createdAt,
        'updated_at': session.updatedAt,
        'last_message_at': session.lastMessageAt,
        'pinned': session.pinned,
        'archived': session.archived,
        'profile': session.profile,
      };
}
