import 'package:flutter_test/flutter_test.dart';
import 'package:hermex_flutter/core/models/mcp.dart';

void main() {
  group('McpServer', () {
    test('正常解析全量字段与 env 字典', () {
      final s = McpServer.fromJson({
        'name': 'postgres-mcp',
        'command': 'npx',
        'args': ['-y', '@modelcontextprotocol/server-postgres'],
        'enabled': true,
        'status': 'connected',
        'env': {'DATABASE_URL': 'postgresql://localhost:5432/db'},
      });
      expect(s.name, 'postgres-mcp');
      expect(s.command, 'npx');
      expect(s.args, ['-y', '@modelcontextprotocol/server-postgres']);
      expect(s.enabled, isTrue);
      expect(s.status, 'connected');
      expect(s.env, {'DATABASE_URL': 'postgresql://localhost:5432/db'});

      final json = s.toJson();
      expect(json['name'], 'postgres-mcp');
      expect(json['command'], 'npx');
      expect(json['args'], ['-y', '@modelcontextprotocol/server-postgres']);
      expect(json['enabled'], isTrue);
      expect(json['status'], 'connected');
      expect(json['env'], {'DATABASE_URL': 'postgresql://localhost:5432/db'});
    });

    test('args 与 env 包含非字符串元素容错转换', () {
      final s = McpServer.fromJson({
        'name': 'dirty-server',
        'args': ['--port', 8080, true],
        'env': {'PORT': 8080, 'DEBUG': true},
      });
      expect(s.args, ['--port', '8080', 'true']);
      expect(s.env, {'PORT': '8080', 'DEBUG': 'true'});
    });

    test('缺失字段与畸形输入', () {
      const empty = McpServer();
      expect(empty.name, '');
      expect(empty.command, '');
      expect(empty.args, isEmpty);
      expect(empty.enabled, isFalse);
      expect(empty.status, '');
      expect(empty.env, isNull);

      final bad = McpServer.fromJson({
        'name': null,
        'command': 123,
        'args': 'not-a-list',
        'enabled': 'invalid',
        'status': null,
        'env': 'not-a-map',
      });
      expect(bad.name, '');
      expect(bad.command, '123');
      expect(bad.args, isEmpty);
      expect(bad.enabled, isFalse);
      expect(bad.status, '');
      expect(bad.env, isNull);
    });

    test('== / hashCode / toString', () {
      const a = McpServer(name: 's1', command: 'cmd', args: ['a']);
      const b = McpServer(name: 's1', command: 'cmd', args: ['a']);
      const c = McpServer(name: 's2', command: 'cmd', args: ['b']);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
      expect(a.toString(), contains('McpServer'));
    });
  });

  group('McpServersResponse', () {
    test('正常解析与脏列表容错', () {
      final res = McpServersResponse.fromJson({
        'servers': [
          {'name': 'srv-1', 'command': 'cmd1'},
          'invalid_entry',
          null,
        ],
      });
      expect(res.servers.length, 1);
      expect(res.servers.first.name, 'srv-1');

      final badRes = McpServersResponse.fromJson({'servers': 'bad'});
      expect(badRes.servers, isEmpty);
    });

    test('== / hashCode / toString', () {
      const a = McpServersResponse(servers: [McpServer(name: '1')]);
      const b = McpServersResponse(servers: [McpServer(name: '1')]);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a.toString(), contains('McpServersResponse'));
    });
  });

  group('McpTool & McpToolsResponse', () {
    test('正常解析 Schema 与 parameters Map', () {
      final tool = McpTool.fromJson({
        'name': 'query_db',
        'server': 'postgres-mcp',
        'description': 'Execute read query',
        'parameters': {
          'type': 'object',
          'properties': {
            'sql': {'type': 'string'},
          },
          'required': ['sql'],
        },
      });
      expect(tool.name, 'query_db');
      expect(tool.server, 'postgres-mcp');
      expect(tool.description, 'Execute read query');
      expect(tool.parameters['type'], 'object');
      expect(tool.parameters['required'], ['sql']);

      final json = tool.toJson();
      expect(json['name'], 'query_db');
      expect(json['parameters'], isA<Map<String, dynamic>>());
    });

    test('parameters 缺失或非 Map', () {
      final tool = McpTool.fromJson({
        'name': 'simple_tool',
        'parameters': 'invalid',
      });
      expect(tool.parameters, isEmpty);
    });

    test('McpToolsResponse 解析与容错', () {
      final res = McpToolsResponse.fromJson({
        'tools': [
          {'name': 't1', 'server': 's1'},
        ],
      });
      expect(res.tools.length, 1);
      expect(res.tools.first.name, 't1');

      final bad = McpToolsResponse.fromJson({'tools': 123});
      expect(bad.tools, isEmpty);
    });

    test('== / hashCode / toString', () {
      const tA = McpTool(name: 't1', server: 's1');
      const tB = McpTool(name: 't1', server: 's1');
      expect(tA, equals(tB));
      expect(tA.hashCode, equals(tB.hashCode));
      expect(tA.toString(), contains('McpTool'));

      const rA = McpToolsResponse(tools: [tA]);
      const rB = McpToolsResponse(tools: [tB]);
      expect(rA, equals(rB));
      expect(rA.hashCode, equals(rB.hashCode));
      expect(rA.toString(), contains('McpToolsResponse'));
    });
  });

  group('写操作响应模型', () {
    test('McpServerWriteResponse 嵌套 server 对象解析', () {
      final res = McpServerWriteResponse.fromJson({
        'ok': true,
        'server': {
          'name': 'new-server',
          'command': 'python',
          'args': ['server.py'],
          'enabled': true,
          'status': 'connected',
        },
      });
      expect(res.ok, isTrue);
      expect(res.server, isNotNull);
      expect(res.server!.name, 'new-server');
      expect(res.server!.command, 'python');
      expect(res.server!.args, ['server.py']);

      final json = res.toJson();
      expect(json['ok'], isTrue);
      expect(json['server'], isA<Map<String, Object?>>());
    });

    test('McpServerWriteResponse server 为 null 或非 Map 容错', () {
      final res = McpServerWriteResponse.fromJson({
        'ok': true,
        'server': 'not-a-map',
      });
      expect(res.ok, isTrue);
      expect(res.server, isNull);

      final empty = McpServerWriteResponse.fromJson({});
      expect(empty.ok, isFalse);
      expect(empty.server, isNull);
    });

    test('McpServerToggleResponse', () {
      final res = McpServerToggleResponse.fromJson({
        'ok': true,
        'name': 'mcp-1',
        'enabled': true,
      });
      expect(res.ok, isTrue);
      expect(res.name, 'mcp-1');
      expect(res.enabled, isTrue);

      final lossy = McpServerToggleResponse.fromJson({
        'ok': 'yes',
        'name': 42,
        'enabled': '0',
      });
      expect(lossy.ok, isTrue);
      expect(lossy.name, '42');
      expect(lossy.enabled, isFalse);

      const a = McpServerToggleResponse(ok: true, name: 'x', enabled: true);
      const b = McpServerToggleResponse(ok: true, name: 'x', enabled: true);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a.toString(), contains('McpServerToggleResponse'));
    });

    test('McpServerDeleteResponse', () {
      final res = McpServerDeleteResponse.fromJson({
        'ok': true,
        'deleted': 'mcp-to-delete',
      });
      expect(res.ok, isTrue);
      expect(res.deleted, 'mcp-to-delete');

      // fallback to name
      final resFallback = McpServerDeleteResponse.fromJson({
        'ok': true,
        'name': 'mcp-name',
      });
      expect(resFallback.deleted, 'mcp-name');

      const a = McpServerDeleteResponse(ok: true, deleted: 'x');
      const b = McpServerDeleteResponse(ok: true, deleted: 'x');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a.toString(), contains('McpServerDeleteResponse'));
    });
  });
}
