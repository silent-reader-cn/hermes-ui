import '../utils/equality.dart';
import '../utils/lossy_json.dart';

/// 单个 MCP 服务器配置与状态。
class McpServer {
  const McpServer({
    this.name = '',
    this.command = '',
    this.args = const [],
    this.enabled = false,
    this.status = '',
    this.env,
  });

  factory McpServer.fromJson(Map<String, Object?> json) {
    final rawArgs = json['args'];
    final args = <String>[];
    if (rawArgs is List) {
      for (final a in rawArgs) {
        if (a is String) {
          args.add(a);
        } else if (a != null) {
          args.add(a.toString());
        }
      }
    }

    Map<String, String>? env;
    final rawEnv = json['env'];
    if (rawEnv is Map) {
      env = {};
      for (final entry in rawEnv.entries) {
        env[entry.key.toString()] = entry.value?.toString() ?? '';
      }
    }

    return McpServer(
      name: lossyString(json, 'name') ?? '',
      command: lossyString(json, 'command') ?? '',
      args: args,
      enabled: lossyBool(json, 'enabled') ?? false,
      status: lossyString(json, 'status') ?? '',
      env: env,
    );
  }

  final String name;
  final String command;
  final List<String> args;
  final bool enabled;
  final String status;
  final Map<String, String>? env;

  Map<String, Object?> toJson() => {
        'name': name,
        'command': command,
        'args': args,
        'enabled': enabled,
        'status': status,
        'env': ?env,
      };

  @override
  bool operator ==(Object other) {
    return other is McpServer &&
        other.name == name &&
        other.command == command &&
        deepEquals(other.args, args) &&
        other.enabled == enabled &&
        other.status == status &&
        deepEquals(other.env, env);
  }

  @override
  int get hashCode => Object.hash(
        name,
        command,
        deepHash(args),
        enabled,
        status,
        deepHash(env),
      );

  @override
  String toString() =>
      'McpServer(name: $name, command: $command, enabled: $enabled, status: $status)';
}

/// MCP 服务器列表响应（GET /api/mcp/servers）。
class McpServersResponse {
  const McpServersResponse({
    this.servers = const [],
  });

  factory McpServersResponse.fromJson(Map<String, Object?> json) {
    final rawList = json['servers'];
    final servers = <McpServer>[];
    if (rawList is List) {
      for (final item in rawList) {
        if (item is Map) {
          servers.add(McpServer.fromJson(Map<String, Object?>.from(item)));
        }
      }
    }
    return McpServersResponse(servers: servers);
  }

  final List<McpServer> servers;

  Map<String, Object?> toJson() => {
        'servers': servers.map((s) => s.toJson()).toList(),
      };

  @override
  bool operator ==(Object other) =>
      other is McpServersResponse && deepEquals(other.servers, servers);

  @override
  int get hashCode => Object.hashAll([deepHash(servers)]);

  @override
  String toString() => 'McpServersResponse(servers: ${servers.length})';
}

/// 单个 MCP 工具信息。
class McpTool {
  const McpTool({
    this.name = '',
    this.server = '',
    this.description = '',
    this.parameters = const {},
  });

  factory McpTool.fromJson(Map<String, Object?> json) {
    final rawParams = json['parameters'];
    final parameters = rawParams is Map
        ? Map<String, dynamic>.from(rawParams)
        : const <String, dynamic>{};
    return McpTool(
      name: lossyString(json, 'name') ?? '',
      server: lossyString(json, 'server') ?? '',
      description: lossyString(json, 'description') ?? '',
      parameters: parameters,
    );
  }

  final String name;
  final String server;
  final String description;
  final Map<String, dynamic> parameters;

  Map<String, Object?> toJson() => {
        'name': name,
        'server': server,
        'description': description,
        'parameters': parameters,
      };

  @override
  bool operator ==(Object other) {
    return other is McpTool &&
        other.name == name &&
        other.server == server &&
        other.description == description &&
        deepEquals(other.parameters, parameters);
  }

  @override
  int get hashCode => Object.hash(
        name,
        server,
        description,
        deepHash(parameters),
      );

  @override
  String toString() => 'McpTool(name: $name, server: $server)';
}

/// MCP 工具列表响应（GET /api/mcp/tools）。
class McpToolsResponse {
  const McpToolsResponse({
    this.tools = const [],
  });

  factory McpToolsResponse.fromJson(Map<String, Object?> json) {
    final rawList = json['tools'];
    final tools = <McpTool>[];
    if (rawList is List) {
      for (final item in rawList) {
        if (item is Map) {
          tools.add(McpTool.fromJson(Map<String, Object?>.from(item)));
        }
      }
    }
    return McpToolsResponse(tools: tools);
  }

  final List<McpTool> tools;

  Map<String, Object?> toJson() => {
        'tools': tools.map((t) => t.toJson()).toList(),
      };

  @override
  bool operator ==(Object other) =>
      other is McpToolsResponse && deepEquals(other.tools, tools);

  @override
  int get hashCode => Object.hashAll([deepHash(tools)]);

  @override
  String toString() => 'McpToolsResponse(tools: ${tools.length})';
}

/// MCP 服务器写入响应（PUT /api/mcp/servers/{name}）。
class McpServerWriteResponse {
  const McpServerWriteResponse({
    this.ok = false,
    this.server,
  });

  factory McpServerWriteResponse.fromJson(Map<String, Object?> json) {
    final serverRaw = json['server'];
    final server = serverRaw is Map
        ? McpServer.fromJson(Map<String, Object?>.from(serverRaw))
        : null;
    return McpServerWriteResponse(
      ok: lossyBool(json, 'ok') ?? false,
      server: server,
    );
  }

  final bool ok;
  final McpServer? server;

  Map<String, Object?> toJson() => {
        'ok': ok,
        'server': ?server?.toJson(),
      };

  @override
  bool operator ==(Object other) {
    return other is McpServerWriteResponse &&
        other.ok == ok &&
        other.server == server;
  }

  @override
  int get hashCode => Object.hash(ok, server);

  @override
  String toString() => 'McpServerWriteResponse(ok: $ok, server: $server)';
}

/// MCP 服务器启停响应（PATCH /api/mcp/servers/{name}）。
class McpServerToggleResponse {
  const McpServerToggleResponse({
    this.ok = false,
    this.name = '',
    this.enabled = false,
  });

  factory McpServerToggleResponse.fromJson(Map<String, Object?> json) {
    return McpServerToggleResponse(
      ok: lossyBool(json, 'ok') ?? false,
      name: lossyString(json, 'name') ?? '',
      enabled: lossyBool(json, 'enabled') ?? false,
    );
  }

  final bool ok;
  final String name;
  final bool enabled;

  Map<String, Object?> toJson() => {
        'ok': ok,
        'name': name,
        'enabled': enabled,
      };

  @override
  bool operator ==(Object other) {
    return other is McpServerToggleResponse &&
        other.ok == ok &&
        other.name == name &&
        other.enabled == enabled;
  }

  @override
  int get hashCode => Object.hash(ok, name, enabled);

  @override
  String toString() =>
      'McpServerToggleResponse(ok: $ok, name: $name, enabled: $enabled)';
}

/// MCP 服务器删除响应（DELETE /api/mcp/servers/{name}）。
class McpServerDeleteResponse {
  const McpServerDeleteResponse({
    this.ok = false,
    this.deleted = '',
  });

  factory McpServerDeleteResponse.fromJson(Map<String, Object?> json) {
    return McpServerDeleteResponse(
      ok: lossyBool(json, 'ok') ?? false,
      deleted: lossyString(json, 'deleted') ?? lossyString(json, 'name') ?? '',
    );
  }

  final bool ok;
  final String deleted;

  Map<String, Object?> toJson() => {
        'ok': ok,
        'deleted': deleted,
      };

  @override
  bool operator ==(Object other) {
    return other is McpServerDeleteResponse &&
        other.ok == ok &&
        other.deleted == deleted;
  }

  @override
  int get hashCode => Object.hash(ok, deleted);

  @override
  String toString() => 'McpServerDeleteResponse(ok: $ok, deleted: $deleted)';
}
