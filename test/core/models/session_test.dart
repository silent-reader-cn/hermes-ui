import 'package:flutter_test/flutter_test.dart';
import 'package:hermex_flutter/core/models/session.dart';

void main() {
  group('SessionsResponse', () {
    test('正常解析（附录 A.1）', () {
      final response = SessionsResponse.fromJson({
        'sessions': [
          {'session_id': 'abc123', 'title': 't'},
        ],
        'cli_count': 2,
        'archived_count': 5,
        'server_time': 1723700000.0,
        'server_tz': 'Asia/Shanghai',
      });
      expect(response.sessions, hasLength(1));
      expect(response.cliCount, 2);
      expect(response.archivedCount, 5);
      expect(response.serverTime, 1723700000.0);
      expect(response.serverTz, 'Asia/Shanghai');
    });

    test('畸形输入：缺失/错型 → null', () {
      final response = SessionsResponse.fromJson({
        'sessions': 'bad',
        'cli_count': 'bad',
        'server_tz': 5,
      });
      expect(response.sessions, isNull);
      expect(response.cliCount, isNull);
      expect(response.serverTz, '5');
      final empty = SessionsResponse.fromJson(const <String, Object?>{});
      expect(empty.sessions, isNull);
    });
  });

  group('SessionSearchResponse / SessionResponse / SessionMutationResponse', () {
    test('正常 + 畸形', () {
      final search = SessionSearchResponse.fromJson(
        {'sessions': [], 'query': 'bug', 'count': 0},
      );
      expect(search.query, 'bug');
      expect(search.count, 0);
      expect(SessionSearchResponse.fromJson(const {}).count, isNull);

      final response = SessionResponse.fromJson(
        {'session': {'session_id': 'abc123'}},
      );
      expect(response.session!.sessionId, 'abc123');
      expect(SessionResponse.fromJson(const {}).session, isNull);
      expect(SessionResponse.fromJson({'session': 'bad'}).session, isNull);

      final mutation = SessionMutationResponse.fromJson(
        {'ok': true, 'session': {'session_id': 'abc123'}, 'error': null},
      );
      expect(mutation.ok, true);
      expect(mutation.session!.sessionId, 'abc123');
      expect(
        SessionMutationResponse.fromJson({'ok': 'nope'}).ok,
        isNull,
      );
    });
  });

  group('ProjectsResponse / ProjectSummary / ProjectMutationResponse', () {
    test('ProjectSummary 正常 + id 派生 + 畸形', () {
      final project = ProjectSummary.fromJson({
        'project_id': 'p1',
        'name': 'hermex',
        'color': '#4f46e5',
        'created_at': 1723700000,
      });
      expect(project.projectId, 'p1');
      expect(project.name, 'hermex');
      expect(project.color, '#4f46e5');
      expect(project.createdAt, 1723700000.0);
      expect(project.id, 'p1');
      expect(ProjectSummary.fromJson({'name': 'x'}).id, 'x');

      final broken = ProjectSummary.fromJson({'project_id': 9});
      expect(broken.projectId, '9');

      final projects = ProjectsResponse.fromJson(
        {'projects': [{'project_id': 'p1', 'name': 'hermex'}]},
      );
      expect(projects.projects, hasLength(1));
      expect(ProjectsResponse.fromJson({'projects': 'bad'}).projects, isNull);

      final mutation = ProjectMutationResponse.fromJson(
        {'ok': true, 'project': {'project_id': 'p1'}, 'error': null},
      );
      expect(mutation.ok, true);
      expect(mutation.project!.projectId, 'p1');
    });
  });

  group('Session 分支/压缩/撤销/重试/状态响应', () {
    test('SessionBranchResponse', () {
      final response = SessionBranchResponse.fromJson({
        'session_id': 'abc123',
        'title': '分支',
        'parent_session_id': 'abc122',
        'error': null,
      });
      expect(response.sessionId, 'abc123');
      expect(response.parentSessionId, 'abc122');
      expect(SessionBranchResponse.fromJson(const {}).title, isNull);
    });

    test('SessionCompressResponse + SessionCompressionSummary.compressedTokenEstimate', () {
      final response = SessionCompressResponse.fromJson({
        'ok': true,
        'session': {'session_id': 'abc123'},
        'summary': {'headline': '已压缩', 'token_line': '128k -> 42k'},
        'focus_topic': 'bug',
        'error': null,
      });
      expect(response.ok, true);
      expect(response.session!.sessionId, 'abc123');
      expect(response.summary!.headline, '已压缩');
      expect(response.summary!.compressedTokenEstimate, 42);
      expect(
        SessionCompressionSummary.fromJson({'token_line': '128k → 42k'})
            .compressedTokenEstimate,
        42,
      );
      expect(
        SessionCompressionSummary.fromJson(const {}).compressedTokenEstimate,
        isNull,
      );
      expect(SessionCompressResponse.fromJson(const {}).summary, isNull);
    });

    test('SessionUndoResponse / SessionRetryResponse / SessionStatusResponse', () {
      final undo = SessionUndoResponse.fromJson({
        'ok': true,
        'removed_count': 2,
        'removed_preview': '…',
        'error': null,
      });
      expect(undo.ok, true);
      expect(undo.removedCount, 2);
      expect(SessionUndoResponse.fromJson({'removed_count': 'bad'}).removedCount, isNull);

      final retry = SessionRetryResponse.fromJson({
        'ok': true,
        'last_user_text': '继续',
        'removed_count': 2,
      });
      expect(retry.lastUserText, '继续');

      final status = SessionStatusResponse.fromJson({
        'session_id': 'abc123',
        'active_stream_id': 's_9',
        'is_streaming': true,
        'pending_user_message': null,
      });
      expect(status.isStreaming, true);
      expect(SessionStatusResponse.fromJson(const {}).sessionId, isNull);
    });
  });

  group('SessionSummary', () {
    test('规格示例正常解析', () {
      final session = SessionSummary.fromJson({
        'session_id': 'abc123',
        'title': '帮我写个脚本',
        'workspace': '/home/u/proj',
        'model': 'gpt-4o',
        'model_provider': 'openai',
        'message_count': 12,
        'created_at': 1723700000.0,
        'updated_at': 1723700100.0,
        'last_message_at': 1723700099.0,
        'pinned': false,
        'archived': false,
        'project_id': null,
        'profile': 'default',
        'input_tokens': 1234,
        'output_tokens': 567,
        'estimated_cost': 0.0123,
        'is_cli_session': false,
        'user_message_count': 5,
        'has_pending_user_message': false,
        'source_label': null,
        'read_only': false,
      });
      expect(session.id, 'abc123');
      expect(session.title, '帮我写个脚本');
      expect(session.inputTokens, 1234);
      expect(session.estimatedCost, 0.0123);
      expect(session.isCliSession, false);
    });

    test('畸形输入：缺失/错型 → null 容错', () {
      final session = SessionSummary.fromJson({
        'session_id': 42,
        'title': false,
        'message_count': '12',
        'pinned': 'yes',
      });
      expect(session.sessionId, '42');
      expect(session.title, 'false');
      expect(session.messageCount, 12);
      expect(session.pinned, true);
      expect(session.id, '42');
      final empty = SessionSummary.fromJson(const {});
      expect(empty.id, startsWith('session-untitled-0'));
    });

    test('id 派生：session-<title>-<timestamp>', () {
      final session = SessionSummary.fromJson({
        'title': ' 我的会话 ',
        'created_at': 100.0,
      });
      expect(session.id, 'session-我的会话-100.0');
    });

    test('派生标记：subagent / claude_code / cron / readOnly', () {
      expect(
        SessionSummary.fromJson({'source_tag': 'subagent'})
            .isDelegatedSubagentSession,
        true,
      );
      expect(
        SessionSummary.fromJson({'session_source': 'SUBAGENT'})
            .isDelegatedSubagentSession,
        true,
      );
      expect(
        SessionSummary.fromJson({'source_tag': 'claude_code'})
            .isClaudeCodeSession,
        true,
      );
      expect(
        SessionSummary.fromJson({'raw_source': 'Claude_Code'})
            .isClaudeCodeSession,
        true,
      );
      expect(
        SessionSummary.fromJson({'source_tag': 'subagent'}).isSessionReadOnly,
        true,
      );
      expect(
        SessionSummary.fromJson({'read_only': true}).isSessionReadOnly,
        true,
      );
      expect(
        SessionSummary.fromJson({'is_read_only': true}).isSessionReadOnly,
        true,
      );
      expect(
        SessionSummary.fromJson({'session_id': 'cron_123'}).isCronSession,
        true,
      );
      expect(
        SessionSummary.fromJson({'session_source': 'cron'}).isCronSession,
        true,
      );
      expect(SessionSummary.fromJson(const {}).isCronSession, false);
      expect(SessionSummary.fromJson(const {}).isClaudeCodeSession, false);
    });

    test('isEmptySidebarPlaceholder / shouldAppearInSessionList', () {
      expect(
        SessionSummary.fromJson({'title': 'untitled'}).isEmptySidebarPlaceholder,
        true,
      );
      expect(
        SessionSummary.fromJson(const {}).isEmptySidebarPlaceholder,
        true,
      );
      expect(
        SessionSummary.fromJson({'title': 'untitled', 'message_count': 3})
            .isEmptySidebarPlaceholder,
        false,
      );
      expect(
        SessionSummary.fromJson({'title': 'untitled', 'is_streaming': true})
            .isEmptySidebarPlaceholder,
        false,
      );
      expect(
        SessionSummary.fromJson({'title': 'untitled'}).shouldAppearInSessionList,
        false,
      );
      expect(
        SessionSummary.fromJson({'title': 'hello'}).shouldAppearInSessionList,
        true,
      );
    });

    test('AutomatedSessionVisibility.shows', () {
      const visibility = AutomatedSessionVisibility(
        showsCron: false,
        showsCli: false,
      );
      expect(
        visibility.shows(SessionSummary.fromJson({'source_tag': 'subagent'})),
        false,
      );
      expect(
        visibility.shows(SessionSummary.fromJson({'session_id': 'cron_1'})),
        false,
      );
      expect(
        visibility.shows(SessionSummary.fromJson({'is_cli_session': true})),
        false,
      );
      expect(
        visibility.shows(SessionSummary.fromJson({'source_tag': 'claude_code'})),
        true,
      );
      expect(
        AutomatedSessionVisibility.showAll
            .shows(SessionSummary.fromJson({'source_tag': 'subagent'})),
        true,
      );
    });

    test('replacingTitle 保留其余字段', () {
      final session = SessionSummary.fromJson(
        {'session_id': 's1', 'title': '旧', 'message_count': 5},
      );
      final renamed = session.replacingTitle('新');
      expect(renamed.title, '新');
      expect(renamed.sessionId, 's1');
      expect(renamed.messageCount, 5);
    });

    test('SessionSummary.fromDetail', () {
      final detail = SessionDetail.fromJson({
        'session_id': 's1',
        'title': 't',
        'messages': [
          {'role': 'user', 'content': 'hi'},
        ],
        'pending_user_message': '待发',
      });
      final summary = SessionSummary.fromDetail(detail);
      expect(summary.sessionId, 's1');
      expect(summary.messageCount, 1);
      expect(summary.hasPendingUserMessage, true);
      expect(summary.isStreaming, isNull);
    });
  });

  group('SessionDetail', () {
    test('规格示例节选正常解析', () {
      final detail = SessionDetail.fromJson({
        'session_id': 'abc123',
        'title': '帮我写个脚本',
        'context_length': 200000,
        'threshold_tokens': 160000,
        'last_prompt_tokens': 54321,
        'messages': [
          {'role': 'user', 'content': '你好', '_ts': 1723700000.0},
        ],
        'tool_calls': [
          {'name': 'write_file', 'snippet': '...', 'tid': 'call_9', 'assistant_msg_idx': 3},
        ],
        '_messages_truncated': false,
        '_messages_offset': 0,
        'compression_anchor_visible_idx': 40,
        'compression_anchor_message_key': {
          'role': 'user',
          'ts': 1723700000.0,
          'text': '摘要...',
          'attachments': 0,
        },
        'compression_anchor_summary': 'summary',
      });
      expect(detail.sessionId, 'abc123');
      expect(detail.contextLength, 200000);
      expect(detail.messages, hasLength(1));
      expect(detail.messages!.single.content, '你好');
      expect(detail.toolCalls, hasLength(1));
      expect(detail.toolCalls!.single.tid, 'call_9');
      expect(detail.messagesTruncated, false);
      expect(detail.messagesOffset, 0);
      expect(detail.compressionAnchorVisibleIdx, 40);
      expect(detail.compressionAnchorMessageKey!.role, 'user');
      expect(detail.compressionAnchorMessageKey!.ts, 1723700000.0);
      expect(detail.compressionAnchorSummary, 'summary');
    });

    test('三键顺序：_messages_* 优先', () {
      final detail = SessionDetail.fromJson({
        '_messages_truncated': true,
        'messages_truncated': false,
      });
      expect(detail.messagesTruncated, true);
      final detail2 = SessionDetail.fromJson({
        '_messagesTruncated': true,
        'messages_truncated': false,
      });
      expect(detail2.messagesTruncated, true);
      final detail3 = SessionDetail.fromJson({'messages_truncated': true});
      expect(detail3.messagesTruncated, true);
      expect(
        SessionDetail.fromJson({'compression_anchor_message_key': 'bad'})
            .compressionAnchorMessageKey,
        isNull,
      );
    });

    test('畸形输入：messages/tool_calls 坏元素兜底', () {
      final detail = SessionDetail.fromJson({
        'messages': [
          {'role': 'user', 'content': 'ok'},
          'bad-element',
          {'role': 'assistant', 'content': 'a', 'message_id': 'm2'},
        ],
        'tool_calls': [
          {'name': 'good'},
          42,
        ],
      });
      expect(detail.messages, hasLength(2));
      expect(detail.messages![1].messageId, 'm2');
      expect(detail.toolCalls, hasLength(1));
      expect(detail.toolCalls!.single.name, 'good');
    });

    test('畸形输入：类型不符 → 容错', () {
      final detail = SessionDetail.fromJson({
        'session_id': 1,
        'context_length': 'big',
        'messages': 'bad',
        'tool_calls': 'bad',
      });
      expect(detail.sessionId, '1');
      expect(detail.contextLength, isNull);
      expect(detail.messages, isNull);
      expect(detail.toolCalls, isNull);
    });
  });

  group('CompressionAnchorMessageKey', () {
    test('正常 + 畸形', () {
      final key = CompressionAnchorMessageKey.fromJson(
        {'role': 'user', 'ts': 1.0, 'text': 't', 'attachments': 0},
      );
      expect(key.role, 'user');
      expect(key.ts, 1.0);
      expect(key.attachments, 0);
      final broken = CompressionAnchorMessageKey.fromJson(
        {'role': 3, 'ts': 'x', 'attachments': 'many'},
      );
      expect(broken.role, '3');
      expect(broken.ts, isNull);
      expect(broken.attachments, isNull);
    });
  });

  test('模型 == / hashCode / toString', () {
    final a = SessionSummary.fromJson({'session_id': 's1', 'title': 't'});
    final b = SessionSummary.fromJson({'session_id': 's1', 'title': 't'});
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a.toString(), contains('SessionSummary'));

    final detail = SessionDetail.fromJson({'session_id': 's1', 'title': 't'});
    expect(detail.id, 's1');
  });
}
