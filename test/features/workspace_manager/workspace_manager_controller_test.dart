import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermex_flutter/core/api/api_client.dart';
import 'package:hermex_flutter/core/api/api_exception.dart';
import 'package:hermex_flutter/core/connections/connection_providers.dart';
import 'package:hermex_flutter/core/models/workspace.dart';
import 'package:hermex_flutter/features/workspace_manager/workspace_manager_providers.dart';

import '../../helpers/fake_workspace_manager_api.dart';

/// 组装 ProviderContainer：注入 fake API（apiClientProvider 用占位客户端，
/// 工厂 override 忽略它，不发任何网络请求）。
ProviderContainer makeContainer(FakeWorkspaceManagerApi api) {
  final container = ProviderContainer(
    overrides: [
      apiClientProvider.overrideWithValue(
        ApiClient(baseUrl: 'http://test.local:30002'),
      ),
      workspaceManagerApiFactoryProvider.overrideWithValue((_) => api),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

WorkspaceRoot root(String path, [String? name]) =>
    WorkspaceRoot(path: path, name: name);

void main() {
  group('WorkspaceManagerController 状态机', () {
    test('初始加载成功：AsyncData + 服务端顺序 + last', () async {
      final api = FakeWorkspaceManagerApi(
        workspaces: [root('/a', 'A'), root('/b')],
        last: '/a',
      );
      final container = makeContainer(api);

      await container.read(workspaceManagerControllerProvider.future);
      final state = container
          .read(workspaceManagerControllerProvider)
          .valueOrNull!;

      expect(api.fetchCalls, ['fetch']);
      expect(state.workspaces, hasLength(2));
      expect(state.workspaces.first.name, 'A');
      expect(state.last, '/a');
      expect(state.isCurrent(state.workspaces.first), isTrue);
      expect(state.isCurrent(state.workspaces.last), isFalse);
      expect(state.isMutating, isFalse);
    });

    test('初始加载失败：AsyncError，error 可读', () async {
      final api = FakeWorkspaceManagerApi()
        ..fetchError = HttpException(500, null, message: 'boom');
      final container = makeContainer(api);

      await expectLater(
        container.read(workspaceManagerControllerProvider.future),
        throwsA(isA<HttpException>()),
      );
    });

    test('refresh 成功更新列表；refresh 失败 → AsyncError', () async {
      final api = FakeWorkspaceManagerApi(workspaces: [root('/a', 'A')]);
      final container = makeContainer(api);
      await container.read(workspaceManagerControllerProvider.future);

      api
        ..workspaces = [root('/a', 'A'), root('/b', 'B')]
        ..last = '/b';
      await container
          .read(workspaceManagerControllerProvider.notifier)
          .refresh();
      final state = container
          .read(workspaceManagerControllerProvider)
          .valueOrNull!;
      expect(state.workspaces, hasLength(2));
      expect(state.isCurrent(state.workspaces.last), isTrue);

      api.fetchError = HttpException(500, null, message: 'boom');
      await container
          .read(workspaceManagerControllerProvider.notifier)
          .refresh();
      expect(
        container.read(workspaceManagerControllerProvider).hasError,
        isTrue,
      );
    });

    test('addWorkspace 成功：返回 null + 列表被响应替换 + 无 notice 弹窗字段', () async {
      final api = FakeWorkspaceManagerApi(workspaces: [root('/a', 'A')]);
      final container = makeContainer(api);
      await container.read(workspaceManagerControllerProvider.future);

      final error = await container
          .read(workspaceManagerControllerProvider.notifier)
          .addWorkspace(path: '/new', name: 'New', create: true);

      expect(error, isNull);
      expect(api.addCalls, ['/new|New|true']);
      final state = container
          .read(workspaceManagerControllerProvider)
          .valueOrNull!;
      expect(state.workspaces.map((w) => w.path), ['/a', '/new']);
      expect(state.workspaces.last.name, 'New');
      expect(state.isMutating, isFalse);
      expect(state.actionError, isNull);
    });

    test('addWorkspace 失败：返回错误消息 + isMutating 复位（不弹窗）', () async {
      final api = FakeWorkspaceManagerApi(workspaces: [root('/a', 'A')])
        ..addError = HttpException(
          400,
          null,
          message: 'Workspace already in list',
        );
      final container = makeContainer(api);
      await container.read(workspaceManagerControllerProvider.future);

      final error = await container
          .read(workspaceManagerControllerProvider.notifier)
          .addWorkspace(path: '/a');

      expect(error, contains('Workspace already in list'));
      final state = container
          .read(workspaceManagerControllerProvider)
          .valueOrNull!;
      expect(state.isMutating, isFalse);
      expect(state.actionError, isNull); // 表单内联，不进 actionError
      expect(state.workspaces, hasLength(1));
    });

    test('addWorkspace 在途时二次 mutation 被拒绝（isMutating 守卫）', () async {
      final api = FakeWorkspaceManagerApi(workspaces: [root('/a', 'A')]);
      final container = makeContainer(api);
      await container.read(workspaceManagerControllerProvider.future);

      // 第一次 add 挂起（gate 未放行），期间 isMutating=true
      api.addGate = Completer<void>();
      final first = container
          .read(workspaceManagerControllerProvider.notifier)
          .addWorkspace(path: '/first');
      await Future<void>.delayed(Duration.zero);
      expect(
        container
            .read(workspaceManagerControllerProvider)
            .valueOrNull!
            .isMutating,
        isTrue,
      );

      // 第二次 add 被守卫拒绝，不触达 API
      final second = await container
          .read(workspaceManagerControllerProvider.notifier)
          .addWorkspace(path: '/second');
      expect(second, isNotNull);
      expect(api.addCalls, hasLength(1));

      // 放行第一次 → 成功
      api.addGate!.complete();
      final firstResult = await first;
      expect(firstResult, isNull);
      final state = container
          .read(workspaceManagerControllerProvider)
          .valueOrNull!;
      expect(state.workspaces.map((w) => w.path), ['/a', '/first']);
      expect(state.isMutating, isFalse);
    });

    test('renameWorkspace 成功：notice 设置 + 列表更新；失败：actionError', () async {
      final api = FakeWorkspaceManagerApi(workspaces: [root('/a', 'A')]);
      final container = makeContainer(api);
      await container.read(workspaceManagerControllerProvider.future);

      final ok = await container
          .read(workspaceManagerControllerProvider.notifier)
          .renameWorkspace(path: '/a', name: 'Renamed');

      expect(ok, isTrue);
      expect(api.renameCalls, ['/a|Renamed']);
      var state = container
          .read(workspaceManagerControllerProvider)
          .valueOrNull!;
      expect(state.workspaces.single.name, 'Renamed');
      expect(state.notice, contains('Renamed'));

      // notice 展示后清除
      await container
          .read(workspaceManagerControllerProvider.notifier)
          .clearNotice();
      state = container.read(workspaceManagerControllerProvider).valueOrNull!;
      expect(state.notice, isNull);

      api.renameError = HttpException(
        404,
        null,
        message: 'Workspace not found',
      );
      final failed = await container
          .read(workspaceManagerControllerProvider.notifier)
          .renameWorkspace(path: '/a', name: 'X');
      expect(failed, isFalse);
      state = container.read(workspaceManagerControllerProvider).valueOrNull!;
      expect(state.actionError, contains('Workspace not found'));
    });

    test('removeWorkspace 成功：列表移除 + notice；失败：actionError', () async {
      final api = FakeWorkspaceManagerApi(
        workspaces: [root('/a', 'A'), root('/b', 'B')],
      );
      final container = makeContainer(api);
      await container.read(workspaceManagerControllerProvider.future);

      final ok = await container
          .read(workspaceManagerControllerProvider.notifier)
          .removeWorkspace('/a');

      expect(ok, isTrue);
      expect(api.removeCalls, ['/a']);
      var state = container
          .read(workspaceManagerControllerProvider)
          .valueOrNull!;
      expect(state.workspaces.map((w) => w.path), ['/b']);
      expect(state.notice, contains('a'));

      await container
          .read(workspaceManagerControllerProvider.notifier)
          .clearNotice();
      api.removeError = HttpException(500, null, message: 'boom');
      final failed = await container
          .read(workspaceManagerControllerProvider.notifier)
          .removeWorkspace('/b');
      expect(failed, isFalse);
      state = container.read(workspaceManagerControllerProvider).valueOrNull!;
      expect(state.actionError, contains('boom'));
      expect(state.isMutating, isFalse);
    });

    test('clearActionError 仅在存在时清除', () async {
      final api = FakeWorkspaceManagerApi(workspaces: [root('/a', 'A')]);
      final container = makeContainer(api);
      await container.read(workspaceManagerControllerProvider.future);

      await container
          .read(workspaceManagerControllerProvider.notifier)
          .clearActionError();
      expect(
        container
            .read(workspaceManagerControllerProvider)
            .valueOrNull!
            .actionError,
        isNull,
      );

      api.removeError = HttpException(500, null, message: 'boom');
      await container
          .read(workspaceManagerControllerProvider.notifier)
          .removeWorkspace('/a');
      expect(
        container
            .read(workspaceManagerControllerProvider)
            .valueOrNull!
            .actionError,
        isNotNull,
      );
      await container
          .read(workspaceManagerControllerProvider.notifier)
          .clearActionError();
      expect(
        container
            .read(workspaceManagerControllerProvider)
            .valueOrNull!
            .actionError,
        isNull,
      );
    });

    test('loadSuggestions：成功返回列表；失败返回空列表不打断流程', () async {
      final api = FakeWorkspaceManagerApi(workspaces: []);
      api.suggestionsByPrefix['/ho'] = ['/home/u', '/home/u2'];
      final container = makeContainer(api);

      final suggestions = await container
          .read(workspaceManagerControllerProvider.notifier)
          .loadSuggestions('/ho');
      expect(suggestions, ['/home/u', '/home/u2']);
      expect(api.suggestionCalls, ['/ho']);

      api.suggestionError = HttpException(500, null, message: 'boom');
      final failed = await container
          .read(workspaceManagerControllerProvider.notifier)
          .loadSuggestions('/bad');
      expect(failed, isEmpty);
    });

    test('findSessionIdForWorkspace 委托 API', () async {
      final api = FakeWorkspaceManagerApi()..sessionIdForWorkspace = 's1';
      final container = makeContainer(api);

      final sessionId = await container
          .read(workspaceManagerControllerProvider.notifier)
          .findSessionIdForWorkspace('/a');
      expect(sessionId, 's1');
      expect(api.sessionLookupCalls, ['/a']);
    });

    test('空列表：state.workspaces 为空（不允许依赖「至少一条」假设）', () async {
      final api = FakeWorkspaceManagerApi(workspaces: []);
      final container = makeContainer(api);

      await container.read(workspaceManagerControllerProvider.future);
      final state = container
          .read(workspaceManagerControllerProvider)
          .valueOrNull!;
      expect(state.workspaces, isEmpty);
      expect(state.last, isNull);
    });
  });
}
