import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermex_flutter/core/api/api_client.dart';
import 'package:hermex_flutter/features/settings/settings_providers.dart';

/// SettingsApiClient（生产包装层）回归测试。
///
/// 背景（2026-08 实锤 bug）：SettingsApiClient 曾把 [ApiClient] 扩展
/// （ApiClientServerPanels）**已经解码好的** ModelsResponse / 响应模型
/// 再 `fromJson(_asMap(...))` 二次解析——_asMap 遇到非 Map 兜底成空 map，
/// groups / default_model 全部丢失 → 设置页默认模型列表永远为空、推理项隐藏。
/// 本文件用真实 Dio + 假 adapter 走全链路（HTTP → sendJson → 扩展解码 →
/// SettingsApiClient），保证该包装层行为被测试覆盖，不再被 FakeSettingsApi
/// 注入绕过。
void main() {
  const base = 'http://hermes.local:8787';

  (ApiClient, _JsonAdapter) buildClient(String responseBody,
      {int status = 200}) {
    final adapter = _JsonAdapter(responseBody, status: status);
    final dio = Dio(
      BaseOptions(validateStatus: (_) => true, followRedirects: false),
    );
    dio.httpClientAdapter = adapter;
    final publicDio = Dio(
      BaseOptions(validateStatus: (_) => true, followRedirects: false),
    );
    publicDio.httpClientAdapter = adapter;
    final client = ApiClient(baseUrl: base, dio: dio, publicMediaDio: publicDio);
    return (client, adapter);
  }

  group('SettingsApiClient.models()', () {
    test('GET /api/models → 正确解码 groups / default_model / active_provider',
        () async {
      final (client, adapter) = buildClient(jsonEncode({
        'default_model': 'deepseek-v4-flash',
        'active_provider': 'custom:cpa',
        'groups': [
          {
            'provider_id': 'custom:cpa',
            'provider': 'CPA',
            'models': [
              {'id': 'grok-4.5', 'label': 'Grok 4.5'},
              {'id': 'deepseek-v4-flash', 'label': 'DeepSeek V4 Flash'},
            ],
            'extra_models': [
              {'id': 'gpt-5.6-sol', 'label': 'GPT 5.6 SOL'},
            ],
          },
        ],
      }));
      final api = SettingsApiClient(client);

      final response = await api.models();

      // 请求路径正确。
      final request = adapter.requests.single;
      expect(request.method, 'GET');
      expect(request.uri.toString(), '$base/api/models');

      // 字段不再丢失（回归核心：修复前这里全部为 null / 空）。
      expect(response.defaultModel, 'deepseek-v4-flash');
      expect(response.activeProvider, 'custom:cpa');
      final groups = response.catalogGroups;
      expect(groups, hasLength(1));
      expect(groups.single.providerID, 'custom:cpa');
      expect(groups.single.models, hasLength(2));
      expect(groups.single.models.first.id, 'grok-4.5');
      expect(groups.single.models.first.displayName, 'Grok 4.5');
      expect(groups.single.extraModels.single.id, 'gpt-5.6-sol');
      expect(response.catalogGroups.single.models.first.providerID,
          'custom:cpa');
    });

    test('畸形响应（空 body）→ 不 crash，目录为空', () async {
      final (client, adapter) = buildClient('');
      final api = SettingsApiClient(client);

      final response = await api.models();

      expect(adapter.requests.single.uri.path, '/api/models');
      expect(response.catalogGroups, isEmpty);
      expect(response.defaultModel, isNull);
    });
  });

  group('SettingsApiClient.saveDefaultModel()', () {
    test('POST /api/default-model {model} → 响应 model 字段保留', () async {
      final (client, adapter) =
          buildClient(jsonEncode({'ok': true, 'model': 'grok-4.5'}));
      final api = SettingsApiClient(client);

      final response = await api.saveDefaultModel('grok-4.5');

      final request = adapter.requests.single;
      expect(request.method, 'POST');
      expect(request.uri.toString(), '$base/api/default-model');
      expect(_bodyOf(request)['model'], 'grok-4.5');
      // 回归核心：修复前 saved.model 为 null（二次解析丢字段）。
      expect(response.ok, isTrue);
      expect(response.model, 'grok-4.5');
    });
  });

  group('SettingsApiClient.reasoning()', () {
    test('GET 带 model/provider query → 推理字段保留', () async {
      final (client, adapter) = buildClient(jsonEncode({
        'ok': true,
        'reasoning_effort': 'high',
        'supported_efforts': ['low', 'high'],
        'supports_reasoning_effort': true,
      }));
      final api = SettingsApiClient(client);

      final response =
          await api.reasoning(model: 'deepseek-v4-flash', provider: 'custom:cpa');

      final request = adapter.requests.single;
      expect(request.method, 'GET');
      expect(request.uri.path, '/api/reasoning');
      expect(request.uri.queryParameters['model'], 'deepseek-v4-flash');
      expect(request.uri.queryParameters['provider'], 'custom:cpa');
      expect(response.effectiveEffort, 'high');
      expect(response.normalizedSupportedEfforts, ['low', 'high']);
      expect(response.supportsReasoningEffort, isTrue);
    });

    test('POST {effort} → 响应字段保留', () async {
      final (client, adapter) = buildClient(jsonEncode({
        'ok': true,
        'effort': 'low',
        'supported_efforts': ['low', 'high'],
        'supports_reasoning_effort': true,
      }));
      final api = SettingsApiClient(client);

      final response = await api.saveReasoningEffort('low');

      final request = adapter.requests.single;
      expect(request.method, 'POST');
      expect(request.uri.path, '/api/reasoning');
      expect(_bodyOf(request)['effort'], 'low');
      expect(response.effectiveEffort, 'low');
    });
  });

  group('SettingsApiClient Extensions 生态透传', () {
    test('GET /api/extensions/status', () async {
      final (client, adapter) = buildClient(jsonEncode({
        'enabled': true,
        'extensions': [
          {
            'id': 'ext-1',
            'name': 'Ext 1',
            'enabled': true,
            'sidecar_active': true,
            'sidecar_proxy_consent': true,
          }
        ],
      }));
      final api = SettingsApiClient(client);

      final response = await api.extensionsStatus();

      expect(adapter.requests.single.uri.path, '/api/extensions/status');
      expect(response.enabled, isTrue);
      expect(response.extensions, hasLength(1));
      expect(response.extensions.first.id, 'ext-1');
      expect(response.extensions.first.sidecarActive, isTrue);
    });

    test('GET /api/extensions/registry', () async {
      final (client, adapter) = buildClient(jsonEncode({
        'registry': [
          {
            'id': 'reg-1',
            'name': 'Reg 1',
            'version': '1.0.0',
            'download_url': 'https://example.com/e.tar',
            'sha256': 'sha123',
          }
        ],
      }));
      final api = SettingsApiClient(client);

      final response = await api.extensionsRegistry();

      expect(adapter.requests.single.uri.path, '/api/extensions/registry');
      expect(response.registry, hasLength(1));
      expect(response.registry.first.downloadUrl, 'https://example.com/e.tar');
    });

    test('POST /api/extensions/toggle', () async {
      final (client, adapter) = buildClient(
        jsonEncode({'ok': true, 'id': 'ext-1', 'enabled': true}),
      );
      final api = SettingsApiClient(client);

      final response = await api.toggleExtension('ext-1', true);

      final req = adapter.requests.single;
      expect(req.method, 'POST');
      expect(req.uri.path, '/api/extensions/toggle');
      expect(_bodyOf(req), {'id': 'ext-1', 'enabled': true});
      expect(response.ok, isTrue);
    });

    test('POST /api/extensions/install', () async {
      final (client, adapter) = buildClient(
        jsonEncode({'ok': true, 'installed': 'ext-1'}),
      );
      final api = SettingsApiClient(client);

      final response = await api.installExtension(
        id: 'ext-1',
        downloadUrl: 'https://example.com/ext.zip',
        sha256: 'sha',
      );

      final req = adapter.requests.single;
      expect(req.method, 'POST');
      expect(req.uri.path, '/api/extensions/install');
      expect(_bodyOf(req), {
        'id': 'ext-1',
        'download_url': 'https://example.com/ext.zip',
        'sha256': 'sha',
      });
      expect(response.ok, isTrue);
      expect(response.installed, 'ext-1');
    });

    test('POST /api/extensions/uninstall', () async {
      final (client, adapter) = buildClient(
        jsonEncode({'ok': true, 'uninstalled': 'ext-1'}),
      );
      final api = SettingsApiClient(client);

      final response = await api.uninstallExtension('ext-1');

      final req = adapter.requests.single;
      expect(req.method, 'POST');
      expect(req.uri.path, '/api/extensions/uninstall');
      expect(_bodyOf(req), {'id': 'ext-1'});
      expect(response.ok, isTrue);
    });

    test('POST /api/extensions/sidecar-proxy-consent', () async {
      final (client, adapter) = buildClient(
        jsonEncode({'ok': true, 'id': 'ext-1', 'sidecar_proxy_consent': true}),
      );
      final api = SettingsApiClient(client);

      final response = await api.setExtensionSidecarConsent('ext-1', true);

      final req = adapter.requests.single;
      expect(req.method, 'POST');
      expect(req.uri.path, '/api/extensions/sidecar-proxy-consent');
      expect(_bodyOf(req), {'id': 'ext-1', 'approved': true});
      expect(response.ok, isTrue);
    });
  });

  group('SettingsApiClient MCP 服务器透传', () {
    test('GET /api/mcp/servers', () async {
      final (client, adapter) = buildClient(jsonEncode({
        'servers': [
          {
            'name': 'fetch',
            'command': 'uvx',
            'args': ['fetch'],
            'enabled': true,
            'status': 'connected',
          }
        ],
      }));
      final api = SettingsApiClient(client);

      final response = await api.mcpServers();

      expect(adapter.requests.single.uri.path, '/api/mcp/servers');
      expect(response.servers, hasLength(1));
      expect(response.servers.first.name, 'fetch');
    });

    test('GET /api/mcp/tools', () async {
      final (client, adapter) = buildClient(jsonEncode({
        'tools': [
          {'name': 'fetch_url', 'server': 'fetch', 'description': 'desc'}
        ],
      }));
      final api = SettingsApiClient(client);

      final response = await api.mcpTools();

      expect(adapter.requests.single.uri.path, '/api/mcp/tools');
      expect(response.tools, hasLength(1));
      expect(response.tools.first.name, 'fetch_url');
    });

    test('PUT /api/mcp/servers/{name}', () async {
      final (client, adapter) = buildClient(jsonEncode({
        'ok': true,
        'server': {
          'name': 'fetch',
          'command': 'uvx',
          'args': ['fetch'],
          'enabled': true,
        },
      }));
      final api = SettingsApiClient(client);

      final response = await api.saveMcpServer(
        'fetch',
        command: 'uvx',
        args: ['fetch'],
        env: {'DEBUG': '1'},
        enabled: true,
      );

      final req = adapter.requests.single;
      expect(req.method, 'PUT');
      expect(req.uri.path, '/api/mcp/servers/fetch');
      expect(response.ok, isTrue);
      expect(response.server?.name, 'fetch');
    });

    test('PATCH /api/mcp/servers/{name}', () async {
      final (client, adapter) = buildClient(
        jsonEncode({'ok': true, 'name': 'fetch', 'enabled': false}),
      );
      final api = SettingsApiClient(client);

      final response = await api.toggleMcpServer('fetch', false);

      final req = adapter.requests.single;
      expect(req.method, 'PATCH');
      expect(req.uri.path, '/api/mcp/servers/fetch');
      expect(response.ok, isTrue);
    });

    test('DELETE /api/mcp/servers/{name}', () async {
      final (client, adapter) = buildClient(
        jsonEncode({'ok': true, 'deleted': 'fetch'}),
      );
      final api = SettingsApiClient(client);

      final response = await api.deleteMcpServer('fetch');

      final req = adapter.requests.single;
      expect(req.method, 'DELETE');
      expect(req.uri.path, '/api/mcp/servers/fetch');
      expect(response.ok, isTrue);
    });
  });

  group('SettingsApiClient 辅助模型透传', () {
    test('GET /api/model/auxiliary', () async {
      final (client, adapter) = buildClient(jsonEncode({
        'tasks': [
          {
            'task': 'vision',
            'provider': 'openai',
            'model': 'gpt-4o',
            'api_key_set': true,
            'label': 'Vision',
          }
        ],
        'main': {
          'provider': 'anthropic',
          'model': 'claude-sonnet-4',
        },
      }));
      final api = SettingsApiClient(client);

      final response = await api.auxiliaryModels();

      expect(adapter.requests.single.uri.path, '/api/model/auxiliary');
      expect(response.tasks, hasLength(1));
      expect(response.tasks.first.task, 'vision');
      expect(response.tasks.first.apiKeySet, isTrue);
      expect(response.main.model, 'claude-sonnet-4');
    });

    test('POST /api/model/set', () async {
      final (client, adapter) = buildClient(jsonEncode({
        'ok': true,
        'task': 'vision',
        'provider': 'openai',
        'model': 'gpt-4o',
      }));
      final api = SettingsApiClient(client);

      final response = await api.setAuxiliaryModel(
        task: 'vision',
        provider: 'openai',
        model: 'gpt-4o',
      );

      final req = adapter.requests.single;
      expect(req.method, 'POST');
      expect(req.uri.path, '/api/model/set');
      expect(_bodyOf(req), {
        'scope': 'auxiliary',
        'task': 'vision',
        'provider': 'openai',
        'model': 'gpt-4o',
      });
      expect(response.ok, isTrue);
      expect(response.task, 'vision');
    });
  });
}

Map<String, Object?> _bodyOf(RequestOptions options) {
  final raw = options.data;
  if (raw is String && raw.isNotEmpty) {
    try {
      return Map<String, Object?>.from(jsonDecode(raw) as Map);
    } catch (_) {}
  }
  if (raw is Map) return Map<String, Object?>.from(raw);
  return const {};
}

/// 记录请求并回放固定 JSON 的假 HttpClientAdapter。
class _JsonAdapter implements HttpClientAdapter {
  _JsonAdapter(this.body, {this.status = 200});

  final String body;
  final int status;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(body, status);
  }

  @override
  void close({bool force = false}) {}
}