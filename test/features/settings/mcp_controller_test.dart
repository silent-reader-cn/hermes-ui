import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/api/api_exception.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/models/mcp.dart';
import 'package:hermes_ui/features/settings/settings_providers.dart';

import '../../helpers/fake_settings_api.dart';

ProviderContainer makeContainer(FakeSettingsApi api) {
  final container = ProviderContainer(
    overrides: [
      apiClientProvider.overrideWithValue(
        ApiClient(baseUrl: 'http://test.local:30002'),
      ),
      settingsApiFactoryProvider.overrideWithValue((_) => api),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('McpController 加载状态机', () {
    test('加载成功：解析 MCP 服务器列表 + 工具列表', () async {
      final api = FakeSettingsApi();
      api.mcpServersResponse = const McpServersResponse(
        servers: [
          McpServer(
            name: 'fetch',
            command: 'uvx',
            args: ['mcp-server-fetch'],
            enabled: true,
            status: 'connected',
          ),
        ],
      );
      api.mcpToolsResponse = const McpToolsResponse(
        tools: [
          McpTool(
            name: 'fetch_url',
            server: 'fetch',
            description: 'Fetch web content',
          ),
        ],
      );
      final container = makeContainer(api);

      await container.read(mcpControllerProvider.future);
      final state = container.read(mcpControllerProvider).valueOrNull!;

      expect(api.mcpServersCount, 1);
      expect(api.mcpToolsCount, 1);
      expect(state.servers, hasLength(1));
      expect(state.servers.first.name, 'fetch');
      expect(state.servers.first.command, 'uvx');
      expect(state.servers.first.status, 'connected');
      expect(state.tools, hasLength(1));
      expect(state.tools.first.name, 'fetch_url');
    });

    test('tools 加载失败 → 不阻断整体加载，tools 设为空', () async {
      final api = FakeSettingsApi();
      api.mcpServersResponse = const McpServersResponse(
        servers: [McpServer(name: 'srv-1')],
      );
      api.mcpToolsError = HttpException(500, null, message: 'Tools error');
      final container = makeContainer(api);

      await container.read(mcpControllerProvider.future);
      final state = container.read(mcpControllerProvider).valueOrNull!;

      expect(api.mcpServersCount, 1);
      expect(state.servers, hasLength(1));
      expect(state.tools, isEmpty);
      expect(state.actionError, isNull);
    });

    test('mcpServers 加载失败 → AsyncError；refresh 重试成功', () async {
      final api = FakeSettingsApi();
      api.mcpServersError = NetworkException(NetworkExceptionKind.timedOut);
      final container = makeContainer(api);

      await expectLater(
        container.read(mcpControllerProvider.future),
        throwsA(isA<ApiException>()),
      );
      expect(container.read(mcpControllerProvider).hasError, isTrue);

      api.mcpServersError = null;
      api.mcpServersResponse = const McpServersResponse(
        servers: [McpServer(name: 'srv-1')],
      );
      await container.read(mcpControllerProvider.notifier).refresh();

      final state = container.read(mcpControllerProvider).valueOrNull!;
      expect(state.servers, hasLength(1));
    });
  });

  group('McpController 操作方法', () {
    test('toggleServer 成功：调 API 并刷新', () async {
      final api = FakeSettingsApi();
      api.mcpServersResponse = const McpServersResponse(
        servers: [McpServer(name: 'srv-1', enabled: false)],
      );
      final container = makeContainer(api);
      await container.read(mcpControllerProvider.future);

      final controller = container.read(mcpControllerProvider.notifier);
      final ok = await controller.toggleServer('srv-1', true);

      expect(ok, isTrue);
      expect(api.toggleMcpServerCalls, [('srv-1', true)]);
      expect(api.mcpServersCount, 2);
    });

    test('saveServer 成功：调 API 并刷新', () async {
      final api = FakeSettingsApi();
      final container = makeContainer(api);
      await container.read(mcpControllerProvider.future);

      final controller = container.read(mcpControllerProvider.notifier);
      final ok = await controller.saveServer(
        'new-server',
        command: 'node',
        args: ['index.js'],
        env: {'PORT': '8080'},
        enabled: true,
      );

      expect(ok, isTrue);
      expect(api.saveMcpServerCalls, hasLength(1));
      final call = api.saveMcpServerCalls.single;
      expect(call.name, 'new-server');
      expect(call.command, 'node');
      expect(call.args, ['index.js']);
      expect(call.env, {'PORT': '8080'});
      expect(call.enabled, isTrue);
      expect(api.mcpServersCount, 2);
    });

    test('deleteServer 成功：调 API 并刷新', () async {
      final api = FakeSettingsApi();
      api.mcpServersResponse = const McpServersResponse(
        servers: [McpServer(name: 'srv-1')],
      );
      final container = makeContainer(api);
      await container.read(mcpControllerProvider.future);

      final controller = container.read(mcpControllerProvider.notifier);
      final ok = await controller.deleteServer('srv-1');

      expect(ok, isTrue);
      expect(api.deleteMcpServerCalls, ['srv-1']);
      expect(api.mcpServersCount, 2);
    });

    test('操作失败：设置 actionError 并可通过 clearActionError 清除', () async {
      final api = FakeSettingsApi();
      api.deleteMcpServerError = HttpException(400, null, message: '无法删除');
      final container = makeContainer(api);
      await container.read(mcpControllerProvider.future);

      final controller = container.read(mcpControllerProvider.notifier);
      final ok = await controller.deleteServer('srv-1');

      expect(ok, isFalse);
      var state = container.read(mcpControllerProvider).valueOrNull!;
      expect(state.actionError, contains('无法删除'));

      await controller.clearActionError();
      state = container.read(mcpControllerProvider).valueOrNull!;
      expect(state.actionError, isNull);
    });

    test('切换服务器（apiClientProvider 重建）→ mcp 自动重载', () async {
      final api = FakeSettingsApi();
      final container = makeContainer(api);
      await container.read(mcpControllerProvider.future);
      expect(api.mcpServersCount, 1);

      container.invalidate(apiClientProvider);
      await container.pump();
      await container.read(mcpControllerProvider.future);
      expect(api.mcpServersCount, 2);
    });
  });
}
