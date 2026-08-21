import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hermex_flutter/core/api/api_client.dart';
import 'package:hermex_flutter/core/api/api_exception.dart';
import 'package:hermex_flutter/core/connections/connection_providers.dart';
import 'package:hermex_flutter/core/models/workspace.dart';
import 'package:hermex_flutter/features/workspace_manager/workspace_manager_page.dart';
import 'package:hermex_flutter/features/workspace_manager/workspace_manager_providers.dart';

import '../../helpers/fake_workspace_manager_api.dart';

WorkspaceRoot wroot(String path, [String? name]) =>
    WorkspaceRoot(path: path, name: name);

/// 普通 CupertinoApp 外壳（不涉及 go_router 跳转的用例）。
Future<void> pumpManager(
  WidgetTester tester,
  FakeWorkspaceManagerApi api,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(
          ApiClient(baseUrl: 'http://test.local:30002'),
        ),
        workspaceManagerApiFactoryProvider.overrideWithValue((_) => api),
      ],
      child: const CupertinoApp(home: WorkspaceManagerPage()),
    ),
  );
  await tester.pump();
  await tester.pump();
}

/// go_router 外壳（验证「点击行 → push /workspace/:sessionId」）。
Future<void> pumpManagerWithRouter(
  WidgetTester tester,
  FakeWorkspaceManagerApi api, {
  required List<String> pushedRoutes,
}) async {
  final router = GoRouter(
    initialLocation: '/workspaces',
    routes: [
      GoRoute(
        path: '/workspaces',
        builder: (context, state) => const WorkspaceManagerPage(),
      ),
      GoRoute(
        path: '/workspace/:sessionId',
        builder: (context, state) {
          final sessionId = state.pathParameters['sessionId'] ?? '';
          pushedRoutes.add(sessionId);
          return CupertinoPageScaffold(
            child: Center(child: Text('browse-$sessionId')),
          );
        },
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(
          ApiClient(baseUrl: 'http://test.local:30002'),
        ),
        workspaceManagerApiFactoryProvider.overrideWithValue((_) => api),
      ],
      child: CupertinoApp.router(routerConfig: router),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  group('WorkspaceManagerPage widget', () {
    testWidgets('列表渲染：名称 + 路径副行 + 当前徽标 + footer 文案', (tester) async {
      final api = FakeWorkspaceManagerApi(
        workspaces: [wroot('/a', 'Alpha'), wroot('/b/beta')],
        last: '/a',
      );
      await pumpManager(tester, api);

      expect(
        find.byKey(const ValueKey('workspace-manager-row-/a')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('workspace-manager-row-/b/beta')),
        findsOneWidget,
      );
      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('/a'), findsOneWidget);
      expect(find.text('/b/beta'), findsOneWidget);
      // 当前徽标
      expect(find.text('当前'), findsOneWidget);
      // footer：强调只注销路径不删文件
      expect(find.text('移除工作区只是从列表注销路径，不会删除磁盘上的文件。'), findsOneWidget);
    });

    testWidgets('空态：还没有工作区 + 添加提示', (tester) async {
      final api = FakeWorkspaceManagerApi(workspaces: []);
      await pumpManager(tester, api);
      expect(find.text('还没有工作区'), findsOneWidget);
      expect(find.text('点右上角 + 添加工作区。'), findsOneWidget);
    });

    testWidgets('错误态：错误详情 + 重试恢复', (tester) async {
      final api = FakeWorkspaceManagerApi(workspaces: [wroot('/a', 'Alpha')])
        ..fetchError = HttpException(500, null, message: '服务器过载');
      await pumpManager(tester, api);

      expect(find.text('加载失败'), findsOneWidget);
      expect(find.text('服务器过载'), findsOneWidget);

      // 清掉错误后点重试 → 列表出现
      api.fetchError = null;
      await tester.tap(find.byKey(const ValueKey('workspaces-retry')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('workspace-manager-row-/a')),
        findsOneWidget,
      );
    });

    testWidgets('添加工作区：表单填写 + 补全选择 + 提交成功列表更新', (tester) async {
      final api = FakeWorkspaceManagerApi(workspaces: [wroot('/a', 'Alpha')])
        ..suggestionsByPrefix['/home/user'] = [
          '/home/user/proj',
          '/home/user/other',
        ];
      await pumpManager(tester, api);

      await tester.tap(find.byKey(const ValueKey('workspaces-add')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('workspace-add-path')), findsOneWidget);

      // 路径输入 → 250ms 防抖 → 建议列表
      await tester.enterText(
        find.byKey(const ValueKey('workspace-add-path')),
        '/home/user',
      );
      await tester.pump(const Duration(milliseconds: 260));
      await tester.pumpAndSettle();
      expect(api.suggestionCalls, ['/home/user']);
      expect(
        find.byKey(const ValueKey('workspace-add-suggestion-0')),
        findsOneWidget,
      );

      // 点击建议填入路径
      await tester.tap(
        find.byKey(const ValueKey('workspace-add-suggestion-0')),
      );
      await tester.pump();
      final pathField = tester.widget<CupertinoTextField>(
        find.byKey(const ValueKey('workspace-add-path')),
      );
      expect(pathField.controller!.text, '/home/user/proj');

      // 可选名称 + 自动创建开关
      await tester.enterText(
        find.byKey(const ValueKey('workspace-add-name')),
        'My Project',
      );
      await tester.tap(find.byKey(const ValueKey('workspace-add-create')));
      await tester.pump();

      // 提交 → fake 变更列表 → sheet 关闭
      await tester.tap(find.byKey(const ValueKey('workspace-add-submit')));
      await tester.pumpAndSettle();

      expect(api.addCalls, ['/home/user/proj|My Project|true']);
      expect(find.byKey(const ValueKey('workspace-add-path')), findsNothing);
      expect(
        find.byKey(const ValueKey('workspace-manager-row-/home/user/proj')),
        findsOneWidget,
      );
      expect(find.text('My Project'), findsOneWidget);
    });

    testWidgets('添加失败：错误以 statusRedText 内联展示，表单不关闭', (tester) async {
      final api = FakeWorkspaceManagerApi(workspaces: [wroot('/a', 'Alpha')])
        ..addError = HttpException(
          400,
          null,
          message: 'Workspace already in list',
        );
      await pumpManager(tester, api);

      await tester.tap(find.byKey(const ValueKey('workspaces-add')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('workspace-add-path')),
        '/a',
      );
      await tester.pump(const Duration(milliseconds: 260));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('workspace-add-submit')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('workspace-add-path')), findsOneWidget);
      expect(find.byKey(const ValueKey('workspace-add-error')), findsOneWidget);
      expect(find.textContaining('Workspace already in list'), findsOneWidget);
    });

    testWidgets('行尾按钮 → 操作菜单 → 重命名弹窗（预填名称）→ 保存调 rename', (tester) async {
      final api = FakeWorkspaceManagerApi(workspaces: [wroot('/a', 'Alpha')]);
      await pumpManager(tester, api);

      await tester.tap(
        find.byKey(const ValueKey('workspace-manager-actions-/a')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('workspace-manager-action-rename-/a')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const ValueKey('workspace-manager-action-rename-/a')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('workspace-manager-rename-field')),
        findsOneWidget,
      );
      final field = tester.widget<CupertinoTextField>(
        find.byKey(const ValueKey('workspace-manager-rename-field')),
      );
      expect(field.controller!.text, 'Alpha');

      await tester.enterText(
        find.byKey(const ValueKey('workspace-manager-rename-field')),
        'Renamed',
      );
      await tester.tap(
        find.byKey(const ValueKey('workspace-manager-rename-save')),
      );
      await tester.pumpAndSettle();

      expect(api.renameCalls, ['/a|Renamed']);
      expect(find.text('Renamed'), findsOneWidget);
      // 成功 notice 弹窗 → 关闭
      expect(find.text('提示'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('workspace-manager-dialog-ok')),
      );
      await tester.pumpAndSettle();
    });

    testWidgets('行尾按钮 → 操作菜单 → 移除确认（强调不删文件）→ 调 remove', (tester) async {
      final api = FakeWorkspaceManagerApi(
        workspaces: [wroot('/a', 'Alpha'), wroot('/b', 'Beta')],
      );
      await pumpManager(tester, api);

      await tester.tap(
        find.byKey(const ValueKey('workspace-manager-actions-/a')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('workspace-manager-action-remove-/a')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey('workspace-manager-action-remove-/a')),
      );
      await tester.pumpAndSettle();

      // 确认文案必须强调「只注销路径不删文件」（对话框标题 + 确认按钮各一处）
      expect(find.text('移除工作区'), findsNWidgets(2));
      expect(find.textContaining('不会删除磁盘上的任何文件'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('workspace-manager-remove-confirm')),
      );
      await tester.pumpAndSettle();

      expect(api.removeCalls, ['/a']);
      expect(
        find.byKey(const ValueKey('workspace-manager-row-/a')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('workspace-manager-row-/b')),
        findsOneWidget,
      );
      // 成功 notice → 关闭
      await tester.tap(
        find.byKey(const ValueKey('workspace-manager-dialog-ok')),
      );
      await tester.pumpAndSettle();
    });

    testWidgets('点击行 → 找到会话 → push /workspace/:sessionId', (tester) async {
      final api = FakeWorkspaceManagerApi(workspaces: [wroot('/a', 'Alpha')])
        ..sessionIdForWorkspace = 's1';
      final pushed = <String>[];
      await pumpManagerWithRouter(tester, api, pushedRoutes: pushed);

      await tester.tap(find.byKey(const ValueKey('workspace-manager-row-/a')));
      await tester.pumpAndSettle();

      expect(api.sessionLookupCalls, ['/a']);
      expect(pushed, ['s1']);
      expect(find.text('browse-s1'), findsOneWidget);
    });

    testWidgets('点击行 → 无会话 → 提示对话框（不跳转）', (tester) async {
      final api = FakeWorkspaceManagerApi(workspaces: [wroot('/a', 'Alpha')])
        ..sessionIdForWorkspace = null;
      final pushed = <String>[];
      await pumpManagerWithRouter(tester, api, pushedRoutes: pushed);

      await tester.tap(find.byKey(const ValueKey('workspace-manager-row-/a')));
      await tester.pumpAndSettle();

      expect(pushed, isEmpty);
      expect(find.text('无法浏览该工作区'), findsOneWidget);
      expect(find.textContaining('当前没有会话使用该工作区'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('workspace-manager-dialog-ok')),
      );
      await tester.pumpAndSettle();
    });
  });
}
