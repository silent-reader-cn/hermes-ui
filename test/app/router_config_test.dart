import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hermes_ui/app/router.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/connections/server_connection.dart';

/// 最小激活连接 controller：不 watch connectionsProvider（避免平台存储依赖）。
class _NoConnController extends ActiveConnectionController {
  @override
  ServerConnection? build() => null;
}

/// 路由配置回归（todo #22 补充，2026-08-29 实机反馈）：
/// ShellRoute 内全部顶层路由必须走 `pageBuilder`（HermesPage 转场），
/// 禁止回退为 `builder`（go_router 默认 MaterialPage 转场会让 pop 时
/// 底层页被驱动 + 滑出方向非 iOS 标准）。
void main() {
  test('ShellRoute 内顶层路由统一 HermesPage 转场（pageBuilder）', () {
    final container = ProviderContainer(overrides: [
      activeConnectionProvider.overrideWith(_NoConnController.new),
    ]);
    addTearDown(container.dispose);
    final router = container.read(routerProvider);

    final shell = router.configuration.routes.whereType<ShellRoute>().single;
    final paths = <String>[];
    for (final r in shell.routes) {
      final gr = r as GoRoute;
      expect(
        gr.builder,
        isNull,
        reason: '${gr.path} 误用 builder：pop 时底层页会被默认转场驱动',
      );
      expect(
        gr.pageBuilder,
        isNotNull,
        reason: '${gr.path} 必须走 pageBuilder + HermesPage 转场',
      );
      paths.add(gr.path);
    }
    expect(
      paths,
      containsAll([
        '/',
        '/chat',
        '/chat/:sessionId',
        '/settings',
        '/tasks',
        '/skills',
        '/memory',
        '/workspaces',
        '/kanban',
        '/insights',
      ]),
    );
  });
}
