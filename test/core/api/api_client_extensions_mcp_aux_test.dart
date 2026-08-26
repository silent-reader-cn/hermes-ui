import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/api/api_client_extensions.dart';
import 'package:hermes_ui/core/api/api_client_mcp.dart';
import 'package:hermes_ui/core/api/api_client_server_panels.dart';
import 'package:hermes_ui/core/models/auxiliary_model.dart';
import 'package:hermes_ui/core/models/extensions.dart';
import 'package:hermes_ui/core/models/mcp.dart';

void main() {
  const base = 'http://hermes.local:8787';

  ApiClient buildClient(_MockAdapter adapter) {
    final dio = Dio(
      BaseOptions(validateStatus: (_) => true, followRedirects: false),
    );
    dio.httpClientAdapter = adapter;
    final publicDio = Dio(
      BaseOptions(validateStatus: (_) => true, followRedirects: false),
    );
    publicDio.httpClientAdapter = adapter;
    return ApiClient(
      baseUrl: base,
      dio: dio,
      publicMediaDio: publicDio,
    );
  }

  group('ApiClientExtensions (1.17)', () {
    test('extensionsStatus: GET /api/extensions/status', () async {
      final adapter = _MockAdapter(
        responder: (opt) {
          expect(opt.method, 'GET');
          expect(opt.path, '$base/api/extensions/status');
          return ResponseBody.fromString(
            '{"enabled":true,"extensions":[{"id":"ext-1","name":"Ext 1","enabled":true,"sidecar_active":true,"sidecar_proxy_consent":true}]}',
            200,
          );
        },
      );
      final client = buildClient(adapter);
      final res = await client.extensionsStatus();
      expect(res, isA<ExtensionsStatusResponse>());
      expect(res.enabled, isTrue);
      expect(res.extensions.length, 1);
      expect(res.extensions.first.id, 'ext-1');
      expect(res.extensions.first.sidecarActive, isTrue);
    });

    test('extensionsRegistry: GET /api/extensions/registry', () async {
      final adapter = _MockAdapter(
        responder: (opt) {
          expect(opt.method, 'GET');
          expect(opt.path, '$base/api/extensions/registry');
          return ResponseBody.fromString(
            '{"registry":[{"id":"pkg-1","name":"Package 1","version":"1.0.0","download_url":"https://pkg.com/1","sha256":"hash1"}]}',
            200,
          );
        },
      );
      final client = buildClient(adapter);
      final res = await client.extensionsRegistry();
      expect(res, isA<ExtensionsRegistryResponse>());
      expect(res.registry.length, 1);
      expect(res.registry.first.id, 'pkg-1');
      expect(res.registry.first.downloadUrl, 'https://pkg.com/1');
    });

    test('toggleExtension: POST /api/extensions/toggle', () async {
      final adapter = _MockAdapter(
        responder: (opt) {
          expect(opt.method, 'POST');
          expect(opt.path, '$base/api/extensions/toggle');
          final body = jsonDecode(opt.data as String) as Map<String, dynamic>;
          expect(body['id'], 'ext-1');
          expect(body['enabled'], isTrue);
          return ResponseBody.fromString(
            '{"ok":true,"id":"ext-1","enabled":true}',
            200,
          );
        },
      );
      final client = buildClient(adapter);
      final res = await client.toggleExtension('ext-1', true);
      expect(res, isA<ExtensionToggleResponse>());
      expect(res.ok, isTrue);
      expect(res.id, 'ext-1');
      expect(res.enabled, isTrue);
    });

    test('installExtension: POST /api/extensions/install', () async {
      final adapter = _MockAdapter(
        responder: (opt) {
          expect(opt.method, 'POST');
          expect(opt.path, '$base/api/extensions/install');
          final body = jsonDecode(opt.data as String) as Map<String, dynamic>;
          expect(body['id'], 'ext-new');
          expect(body['download_url'], 'https://ext.com/tar');
          expect(body['sha256'], 'sha123');
          return ResponseBody.fromString(
            '{"ok":true,"installed":"ext-new"}',
            200,
          );
        },
      );
      final client = buildClient(adapter);
      final res = await client.installExtension(
        id: 'ext-new',
        downloadUrl: 'https://ext.com/tar',
        sha256: 'sha123',
      );
      expect(res, isA<ExtensionInstallResponse>());
      expect(res.ok, isTrue);
      expect(res.installed, 'ext-new');
    });

    test('uninstallExtension: POST /api/extensions/uninstall', () async {
      final adapter = _MockAdapter(
        responder: (opt) {
          expect(opt.method, 'POST');
          expect(opt.path, '$base/api/extensions/uninstall');
          final body = jsonDecode(opt.data as String) as Map<String, dynamic>;
          expect(body['id'], 'ext-old');
          return ResponseBody.fromString(
            '{"ok":true,"uninstalled":"ext-old"}',
            200,
          );
        },
      );
      final client = buildClient(adapter);
      final res = await client.uninstallExtension('ext-old');
      expect(res, isA<ExtensionUninstallResponse>());
      expect(res.ok, isTrue);
      expect(res.uninstalled, 'ext-old');
    });

    test('setExtensionSidecarConsent: POST /api/extensions/sidecar-proxy-consent', () async {
      final adapter = _MockAdapter(
        responder: (opt) {
          expect(opt.method, 'POST');
          expect(opt.path, '$base/api/extensions/sidecar-proxy-consent');
          final body = jsonDecode(opt.data as String) as Map<String, dynamic>;
          expect(body['id'], 'ext-side');
          expect(body['approved'], isTrue);
          return ResponseBody.fromString(
            '{"ok":true,"id":"ext-side","sidecar_proxy_consent":true}',
            200,
          );
        },
      );
      final client = buildClient(adapter);
      final res = await client.setExtensionSidecarConsent('ext-side', true);
      expect(res, isA<ExtensionConsentResponse>());
      expect(res.ok, isTrue);
      expect(res.id, 'ext-side');
      expect(res.sidecarProxyConsent, isTrue);
    });
  });

  group('ApiClientMcp (1.18)', () {
    test('mcpServers: GET /api/mcp/servers', () async {
      final adapter = _MockAdapter(
        responder: (opt) {
          expect(opt.method, 'GET');
          expect(opt.path, '$base/api/mcp/servers');
          return ResponseBody.fromString(
            '{"servers":[{"name":"srv1","command":"npx","args":["-y","mcp"],"enabled":true,"status":"connected"}]}',
            200,
          );
        },
      );
      final client = buildClient(adapter);
      final res = await client.mcpServers();
      expect(res, isA<McpServersResponse>());
      expect(res.servers.length, 1);
      expect(res.servers.first.name, 'srv1');
      expect(res.servers.first.status, 'connected');
    });

    test('mcpTools: GET /api/mcp/tools', () async {
      final adapter = _MockAdapter(
        responder: (opt) {
          expect(opt.method, 'GET');
          expect(opt.path, '$base/api/mcp/tools');
          return ResponseBody.fromString(
            '{"tools":[{"name":"tool1","server":"srv1","description":"A tool","parameters":{"type":"object"}}]}',
            200,
          );
        },
      );
      final client = buildClient(adapter);
      final res = await client.mcpTools();
      expect(res, isA<McpToolsResponse>());
      expect(res.tools.length, 1);
      expect(res.tools.first.name, 'tool1');
      expect(res.tools.first.server, 'srv1');
    });

    test('saveMcpServer: PUT /api/mcp/servers/{name} with path encoding', () async {
      final adapter = _MockAdapter(
        responder: (opt) {
          expect(opt.method, 'PUT');
          expect(opt.path, '$base/api/mcp/servers/special%20server');
          final body = jsonDecode(opt.data as String) as Map<String, dynamic>;
          expect(body['command'], 'python');
          expect(body['args'], ['main.py']);
          expect(body['env'], {'KEY': 'VAL'});
          expect(body['enabled'], isTrue);
          return ResponseBody.fromString(
            '{"ok":true,"server":{"name":"special server","command":"python","args":["main.py"],"enabled":true,"status":"connected"}}',
            200,
          );
        },
      );
      final client = buildClient(adapter);
      final res = await client.saveMcpServer(
        'special server',
        command: 'python',
        args: ['main.py'],
        env: {'KEY': 'VAL'},
        enabled: true,
      );
      expect(res, isA<McpServerWriteResponse>());
      expect(res.ok, isTrue);
      expect(res.server, isNotNull);
      expect(res.server!.name, 'special server');
    });

    test('toggleMcpServer: PATCH /api/mcp/servers/{name}', () async {
      final adapter = _MockAdapter(
        responder: (opt) {
          expect(opt.method, 'PATCH');
          expect(opt.path, '$base/api/mcp/servers/srv1');
          final body = jsonDecode(opt.data as String) as Map<String, dynamic>;
          expect(body['enabled'], isFalse);
          return ResponseBody.fromString(
            '{"ok":true,"name":"srv1","enabled":false}',
            200,
          );
        },
      );
      final client = buildClient(adapter);
      final res = await client.toggleMcpServer('srv1', false);
      expect(res, isA<McpServerToggleResponse>());
      expect(res.ok, isTrue);
      expect(res.name, 'srv1');
      expect(res.enabled, isFalse);
    });

    test('deleteMcpServer: DELETE /api/mcp/servers/{name}', () async {
      final adapter = _MockAdapter(
        responder: (opt) {
          expect(opt.method, 'DELETE');
          expect(opt.path, '$base/api/mcp/servers/srv-del');
          return ResponseBody.fromString(
            '{"ok":true,"deleted":"srv-del"}',
            200,
          );
        },
      );
      final client = buildClient(adapter);
      final res = await client.deleteMcpServer('srv-del');
      expect(res, isA<McpServerDeleteResponse>());
      expect(res.ok, isTrue);
      expect(res.deleted, 'srv-del');
    });
  });

  group('ApiClientServerPanels (Auxiliary Models - 1.19)', () {
    test('auxiliaryModels: GET /api/model/auxiliary', () async {
      final adapter = _MockAdapter(
        responder: (opt) {
          expect(opt.method, 'GET');
          expect(opt.path, '$base/api/model/auxiliary');
          return ResponseBody.fromString(
            '{"tasks":[{"task":"vision","provider":"openai","model":"gpt-4o"}],"main":{"provider":"anthropic","model":"claude-3-5-sonnet"}}',
            200,
          );
        },
      );
      final client = buildClient(adapter);
      final res = await client.auxiliaryModels();
      expect(res, isA<AuxiliaryModelsResponse>());
      expect(res.tasks.length, 1);
      expect(res.tasks.first.task, 'vision');
      expect(res.main.provider, 'anthropic');
    });

    test('setAuxiliaryModel: POST /api/model/set', () async {
      final adapter = _MockAdapter(
        responder: (opt) {
          expect(opt.method, 'POST');
          expect(opt.path, '$base/api/model/set');
          final body = jsonDecode(opt.data as String) as Map<String, dynamic>;
          expect(body['scope'], 'auxiliary');
          expect(body['task'], 'compression');
          expect(body['provider'], 'gemini');
          expect(body['model'], 'gemini-1.5-flash');
          expect(body['advanced'], {'temp': 0.1});
          return ResponseBody.fromString(
            '{"ok":true,"task":"compression","provider":"gemini","model":"gemini-1.5-flash"}',
            200,
          );
        },
      );
      final client = buildClient(adapter);
      final res = await client.setAuxiliaryModel(
        task: 'compression',
        provider: 'gemini',
        model: 'gemini-1.5-flash',
        advanced: {'temp': 0.1},
      );
      expect(res, isA<ModelSetResponse>());
      expect(res.ok, isTrue);
      expect(res.task, 'compression');
      expect(res.provider, 'gemini');
      expect(res.model, 'gemini-1.5-flash');
    });
  });
}

class _MockAdapter implements HttpClientAdapter {
  _MockAdapter({required this.responder});

  ResponseBody Function(RequestOptions options) responder;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return responder(options);
  }

  @override
  void close({bool force = false}) {}
}
