import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/features/git/git_api.dart';
import 'package:hermes_ui/features/insights/insights_api.dart';
import 'package:hermes_ui/features/kanban/kanban_api.dart';
import 'package:hermes_ui/features/memory/memory_api.dart';
import 'package:hermes_ui/features/projects/project_providers.dart';
import 'package:hermes_ui/features/session_list/session_list_providers.dart';
import 'package:hermes_ui/features/skills/skills_api.dart';
import 'package:hermes_ui/features/tasks/tasks_api.dart';
import 'package:hermes_ui/features/workspace/workspace_api.dart';

/// 各 feature 生产包装层（*ApiClient）回归测试。
///
/// 背景（2026-08 实锤 bug）：这些包装类把 ApiClient 扩展**已解码好的**
/// typed 响应再 `fromJson(_asMap(...))` 二次解析——_asMap 对非 Map 兜底成
/// 空 map → 字段全丢。表现：会话列表空、金板配置空、git 状态空、模型列表空等，
/// 接口全 200 无报错（容错解码不 throw），且全部被 Fake 注入测试绕过。
///
/// 本文件用真实 Dio + 假 adapter 走全链路（HTTP → ApiClient 扩展解码 →
/// 包装层），是这些包装层的唯一生产路径覆盖。修复后 false 的断言即失败。
void main() {
  const base = 'http://hermes.local:8787';

  (ApiClient, _JsonAdapter) buildClient(String responseBody) {
    final adapter = _JsonAdapter(responseBody);
    final dio = Dio(
      BaseOptions(validateStatus: (_) => true, followRedirects: false),
    );
    dio.httpClientAdapter = adapter;
    final publicDio = Dio(
      BaseOptions(validateStatus: (_) => true, followRedirects: false),
    );
    publicDio.httpClientAdapter = adapter;
    return (ApiClient(baseUrl: base, dio: dio, publicMediaDio: publicDio),
        adapter);
  }

  group('SessionListApiClient（会话列表）', () {
    test('fetchSessions 透传解码 sessions 列表', () async {
      final (client, adapter) = buildClient(jsonEncode({
        'sessions': [
          {'session_id': 's1', 'title': 'Hello'},
          {'session_id': 's2', 'title': 'World'},
        ],
      }));
      final response = await SessionListApiClient(client).fetchSessions();

      expect(adapter.requests.single.uri.path, '/api/sessions');
      expect(response.sessions, hasLength(2));
      expect(response.sessions!.first.sessionId, 's1');
      expect(response.sessions!.first.title, 'Hello');
    });

    test('createSession 返回新建会话 id（不再恒为空）', () async {
      final (client, adapter) = buildClient(jsonEncode({
        'session': {'session_id': 's9', 'title': 'New'},
      }));
      final summary = await SessionListApiClient(client).createSession();

      expect(adapter.requests.single.method, 'POST');
      expect(summary.sessionId, 's9');
    });
  });

  group('GitApiClient（git 面板）', () {
    test('fetchStatus 透传解码分支状态', () async {
      final (client, adapter) = buildClient(jsonEncode({
        'git': {
          'is_git': true,
          'branch': 'feat/settings-fix',
          'ahead': 2,
          'behind': 0,
        },
      }));
      final response =
          await GitApiClient(client).fetchStatus('s1');

      expect(adapter.requests.single.uri.path, '/api/git/status');
      expect(response.git?.isGit, isTrue);
      expect(response.git?.branch, 'feat/settings-fix');
    });
  });

  group('TasksApiClient（定时任务）', () {
    test('fetchJobs 透传解码任务列表', () async {
      final (client, adapter) = buildClient(jsonEncode({
        'jobs': [
          {'job_id': 'j1'},
          {'job_id': 'j2'},
        ],
      }));
      final response = await TasksApiClient(client).fetchJobs();

      expect(adapter.requests.single.uri.path, '/api/crons');
      expect(response.jobs, hasLength(2));
    });
  });

  group('InsightsApiClient（用量统计）', () {
    test('fetchInsights 透传解码统计字段', () async {
      final (client, adapter) = buildClient(jsonEncode({
        'total_sessions': 5,
        'total_messages': 120,
      }));
      final response =
          await InsightsApiClient(client).fetchInsights(days: 7);

      expect(adapter.requests.single.uri.path, '/api/insights');
      expect(adapter.requests.single.uri.queryParameters['days'], '7');
      expect(response.totalSessions, 5);
      expect(response.totalMessages, 120);
    });
  });

  group('MemoryApiClient（记忆）', () {
    test('fetchMemory 透传解码记忆正文', () async {
      final (client, adapter) = buildClient(jsonEncode({
        'memory': 'remember this',
      }));
      final response = await MemoryApiClient(client).fetchMemory();

      expect(adapter.requests.single.uri.path, '/api/memory');
      expect(response.memory, 'remember this');
    });
  });

  group('SkillsApiClient（技能）', () {
    test('fetchSkills 透传解码技能列表', () async {
      final (client, adapter) = buildClient(jsonEncode({
        'skills': [
          {'name': 'hermes-ui-codebase'},
        ],
      }));
      final response = await SkillsApiClient(client).fetchSkills();

      expect(adapter.requests.single.uri.path, '/api/skills');
      expect(response.skills, hasLength(1));
      expect(response.skills!.first.name, 'hermes-ui-codebase');
    });
  });

  group('ProjectApiClient（项目）', () {
    test('fetchProjects 透传解码项目列表', () async {
      final (client, adapter) = buildClient(jsonEncode({
        'projects': [
          {'id': 'p1', 'name': 'hermes-ui'},
        ],
      }));
      final response = await ProjectApiClient(client).fetchProjects();

      expect(adapter.requests.single.uri.path, '/api/projects');
      expect(response.projects, hasLength(1));
    });
  });

  group('KanbanApiClient（看板）', () {
    test('fetchConfiguration 透传解码列配置', () async {
      final (client, adapter) = buildClient(jsonEncode({
        'columns': ['todo', 'done'],
      }));
      final response = await KanbanApiClient(client).fetchConfiguration();

      expect(adapter.requests.single.uri.path, '/api/kanban/config');
      expect(response.columns, hasLength(2));
    });
  });

  group('WorkspaceApiClient（工作区）', () {
    test('fetchDirectory 透传解码文件列表', () async {
      final (client, adapter) = buildClient(jsonEncode({
        'path': '/src',
        'entries': [
          {'name': 'main.dart'},
        ],
      }));
      final response = await WorkspaceApiClient(client)
          .fetchDirectory(sessionId: 's1', path: '/src');

      expect(adapter.requests.single.uri.path, '/api/list');
      expect(response.path, '/src');
      expect(response.entries, hasLength(1));
    });
  });
}

/// 记录请求并回放固定 JSON 的假 HttpClientAdapter。
class _JsonAdapter implements HttpClientAdapter {
  _JsonAdapter(this.body);

  final String body;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      body,
      200,
      headers: {
        'content-type': ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}