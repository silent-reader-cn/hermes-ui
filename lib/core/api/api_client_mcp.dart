import 'api_client.dart';
import 'endpoints.dart';
import '../models/mcp.dart';

/// MCP 服务器管理相关 ApiClient 扩展（5 个端点，对应规格 §3.2）。
extension ApiClientMcp on ApiClient {
  /// GET /api/mcp/servers
  Future<McpServersResponse> mcpServers() async {
    final json = await sendJson(Endpoint.mcpServers);
    return McpServersResponse.fromJson(_asMap(json));
  }

  /// GET /api/mcp/tools
  Future<McpToolsResponse> mcpTools() async {
    final json = await sendJson(Endpoint.mcpTools);
    return McpToolsResponse.fromJson(_asMap(json));
  }

  /// PUT /api/mcp/servers/{name}
  Future<McpServerWriteResponse> saveMcpServer(
    String name, {
    required String command,
    required List<String> args,
    Map<String, String>? env,
    bool enabled = true,
  }) async {
    final json = await sendJson(
      Endpoint.mcpServerUpdate(name),
      method: 'PUT',
      body: {
        'command': command,
        'args': args,
        'env': ?env,
        'enabled': enabled,
      },
    );
    return McpServerWriteResponse.fromJson(_asMap(json));
  }

  /// PATCH /api/mcp/servers/{name}
  Future<McpServerToggleResponse> toggleMcpServer(
    String name,
    bool enabled,
  ) async {
    final json = await sendJson(
      Endpoint.mcpServerToggle(name),
      method: 'PATCH',
      body: {'enabled': enabled},
    );
    return McpServerToggleResponse.fromJson(_asMap(json));
  }

  /// DELETE /api/mcp/servers/{name}
  Future<McpServerDeleteResponse> deleteMcpServer(String name) async {
    final json = await sendJson(
      Endpoint.mcpServerDelete(name),
      method: 'DELETE',
    );
    return McpServerDeleteResponse.fromJson(_asMap(json));
  }
}

Map<String, Object?> _asMap(Object? json) =>
    json is Map<String, Object?>
        ? json
        : (json is Map ? Map<String, Object?>.from(json) : const <String, Object?>{});
