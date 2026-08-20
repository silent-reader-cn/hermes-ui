import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermex_flutter/core/cache/app_database.dart';
import 'package:hermex_flutter/core/cache/cache_service.dart';
import 'package:hermex_flutter/core/models/session.dart';

void main() {
  late AppDatabase db;
  late CacheService service;

  setUp(() {
    db = AppDatabase.memory();
    service = CacheService(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('CacheService - Sessions', () {
    test('writeSessions / readSessions 往返一致，SessionSummary 字段完整保留', () async {
      const session = SessionSummary(
        sessionId: 'sess-001',
        title: '测试会话标题',
        workspace: 'my-workspace',
        model: 'gemini-pro',
        messageCount: 42,
        createdAt: 1771500000.0,
        updatedAt: 1771501800.0,
        lastMessageAt: 1771501790.0,
        pinned: true,
        archived: false,
        profile: 'coding-agent',
      );

      await service.writeSessions([session]);
      final loaded = await service.readSessions();

      expect(loaded, hasLength(1));
      final item = loaded.first;
      expect(item.sessionId, 'sess-001');
      expect(item.title, '测试会话标题');
      expect(item.workspace, 'my-workspace');
      expect(item.model, 'gemini-pro');
      expect(item.messageCount, 42);
      expect(item.createdAt, 1771500000.0);
      expect(item.updatedAt, 1771501800.0);
      expect(item.lastMessageAt, 1771501790.0);
      expect(item.pinned, isTrue);
      expect(item.archived, isFalse);
      expect(item.profile, 'coding-agent');
    });

    test('maxSessions 上限截断为 50 条', () async {
      final sessions = List.generate(
        60,
        (i) => SessionSummary(
          sessionId: 'sess-$i',
          title: 'Session $i',
        ),
      );

      await service.writeSessions(sessions);
      final loaded = await service.readSessions();

      expect(loaded, hasLength(50));
      expect(loaded.first.sessionId, 'sess-0');
      expect(loaded.last.sessionId, 'sess-49');
    });

    test('TTL 7天过期自动剔除注入的历史会话', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final pastExpired = DateTime.now().subtract(const Duration(days: 8)).millisecondsSinceEpoch;
      final pastValid = DateTime.now().subtract(const Duration(days: 6)).millisecondsSinceEpoch;

      // 直接向底层表注入过去时间模拟过期
      await db.into(db.cachedSessions).insert(
            CachedSessionsCompanion.insert(
              sessionId: 'expired-1',
              title: const Value('Expired Session'),
              payload: jsonEncode({
                'session_id': 'expired-1',
                'title': 'Expired Session',
              }),
              cachedAt: pastExpired,
            ),
          );

      await db.into(db.cachedSessions).insert(
            CachedSessionsCompanion.insert(
              sessionId: 'valid-old-1',
              title: const Value('Valid Old Session'),
              payload: jsonEncode({
                'session_id': 'valid-old-1',
                'title': 'Valid Old Session',
              }),
              cachedAt: pastValid,
            ),
          );

      await db.into(db.cachedSessions).insert(
            CachedSessionsCompanion.insert(
              sessionId: 'fresh-1',
              title: const Value('Fresh Session'),
              payload: jsonEncode({
                'session_id': 'fresh-1',
                'title': 'Fresh Session',
              }),
              cachedAt: now,
            ),
          );

      final loaded = await service.readSessions();
      final ids = loaded.map((s) => s.sessionId).toList();

      expect(ids, contains('fresh-1'));
      expect(ids, contains('valid-old-1'));
      expect(ids, isNot(contains('expired-1')));
    });

    test('writeSessions 会清空旧全量并重写', () async {
      await service.writeSessions([
        const SessionSummary(sessionId: 's-old', title: 'Old'),
      ]);
      expect(await service.readSessions(), hasLength(1));

      await service.writeSessions([
        const SessionSummary(sessionId: 's-new-1', title: 'New 1'),
        const SessionSummary(sessionId: 's-new-2', title: 'New 2'),
      ]);

      final loaded = await service.readSessions();
      expect(loaded, hasLength(2));
      expect(loaded.map((s) => s.sessionId), ['s-new-1', 's-new-2']);
    });
  });

  group('CacheService - Messages', () {
    test('writeMessages upsert 语义（同 messageId 重复写覆盖）', () async {
      await service.writeMessages(
        sessionId: 'sess-1',
        messages: [
          {'id': 'msg-1', 'role': 'user', 'content': '原始内容'},
          {'id': 'msg-2', 'role': 'assistant', 'content': '助手回复'},
        ],
      );

      var loaded = await service.readMessages('sess-1');
      expect(loaded, hasLength(2));
      final msg1 = loaded.firstWhere((m) => m['id'] == 'msg-1');
      expect(msg1['content'], '原始内容');

      // 覆盖写 msg-1
      await service.writeMessages(
        sessionId: 'sess-1',
        messages: [
          {'id': 'msg-1', 'role': 'user', 'content': '更新后的内容'},
        ],
      );

      loaded = await service.readMessages('sess-1');
      expect(loaded, hasLength(2));
      final updatedMsg1 = loaded.firstWhere((m) => m['id'] == 'msg-1');
      expect(updatedMsg1['content'], '更新后的内容');
    });

    test('50 条上限与按 sessionId 过滤', () async {
      final sess1Messages = List.generate(
        60,
        (i) => {'id': 's1-msg-$i', 'role': 'user', 'content': 'Text $i'},
      );
      final sess2Messages = List.generate(
        10,
        (i) => {'id': 's2-msg-$i', 'role': 'user', 'content': 'Sess2 Text $i'},
      );

      await service.writeMessages(sessionId: 'sess-1', messages: sess1Messages);
      await service.writeMessages(sessionId: 'sess-2', messages: sess2Messages);

      final s1Loaded = await service.readMessages('sess-1');
      final s2Loaded = await service.readMessages('sess-2');

      expect(s1Loaded, hasLength(50));
      expect(s1Loaded.every((m) => m['id'].toString().startsWith('s1-msg-')), isTrue);

      expect(s2Loaded, hasLength(10));
      expect(s2Loaded.every((m) => m['id'].toString().startsWith('s2-msg-')), isTrue);
    });

    test('readMessages 返回顺序按 cachedAt 倒序（契约验证：调用方需自行反转）', () async {
      // 模拟先后不同时间写入消息
      final t1 = 100000;
      final t2 = 200000;
      final t3 = 300000;

      await db.into(db.cachedMessages).insert(
            CachedMessagesCompanion.insert(
              messageId: 'msg-old',
              sessionId: 'sess-order',
              payload: jsonEncode({'id': 'msg-old', 'content': 'first'}),
              cachedAt: t1,
            ),
          );

      await db.into(db.cachedMessages).insert(
            CachedMessagesCompanion.insert(
              messageId: 'msg-mid',
              sessionId: 'sess-order',
              payload: jsonEncode({'id': 'msg-mid', 'content': 'second'}),
              cachedAt: t2,
            ),
          );

      await db.into(db.cachedMessages).insert(
            CachedMessagesCompanion.insert(
              messageId: 'msg-new',
              sessionId: 'sess-order',
              payload: jsonEncode({'id': 'msg-new', 'content': 'third'}),
              cachedAt: t3,
            ),
          );

      final result = await service.readMessages('sess-order');

      // 契约断言：readMessages 严格返回 [msg-new, msg-mid, msg-old]（cachedAt 倒序）
      expect(result.map((m) => m['id']).toList(), ['msg-new', 'msg-mid', 'msg-old']);

      // 验证调用方反转后为正序 [msg-old, msg-mid, msg-new]
      final chronological = result.reversed.map((m) => m['id']).toList();
      expect(chronological, ['msg-old', 'msg-mid', 'msg-new']);
    });

    test('空 sessionId 或无数据返回空列表', () async {
      expect(await service.readMessages(''), isEmpty);
      expect(await service.readMessages('non-existent-session'), isEmpty);
    });

    test('忽略无 id 或空 id 的消息 Map', () async {
      await service.writeMessages(
        sessionId: 'sess-invalid-id',
        messages: [
          {'role': 'user', 'content': 'no id'},
          {'id': '', 'role': 'user', 'content': 'empty id'},
          {'id': 'valid-id', 'role': 'user', 'content': 'valid'},
        ],
      );

      final loaded = await service.readMessages('sess-invalid-id');
      expect(loaded, hasLength(1));
      expect(loaded.first['id'], 'valid-id');
    });
  });
}
