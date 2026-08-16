import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hermex_flutter/core/api/api_client.dart';
import 'package:hermex_flutter/core/api/api_exception.dart';
import 'package:hermex_flutter/core/connections/connection_providers.dart';
import 'package:hermex_flutter/core/models/memory.dart';
import 'package:hermex_flutter/features/memory/memory_api.dart';
import 'package:hermex_flutter/features/memory/memory_page.dart';
import 'package:hermex_flutter/features/memory/memory_providers.dart';

import '../../helpers/fake_memory_api.dart';

/// 组装 ProviderContainer：注入 fake API（apiClientProvider 用占位客户端，
/// 工厂 override 忽略它，不发任何网络请求）。
ProviderContainer makeContainer(FakeMemoryApi api) {
  final container = ProviderContainer(
    overrides: [
      apiClientProvider.overrideWithValue(
        ApiClient(baseUrl: 'http://test.local:30002'),
      ),
      memoryApiFactoryProvider.overrideWithValue((_) => api),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('记忆辅助函数', () {
    test('showsProjectContext：仅非空（trim 后）文档展示', () {
      expect(showsProjectContext(const MemoryResponse()), isFalse);
      expect(
        showsProjectContext(const MemoryResponse(projectContext: '   ')),
        isFalse,
      );
      expect(
        showsProjectContext(const MemoryResponse(projectContext: 'x')),
        isTrue,
      );
    });

    test('memoryProjectContextDetail：「名称 — 工作区」，空 → null', () {
      expect(memoryProjectContextDetail(const MemoryResponse()), isNull);
      expect(
        memoryProjectContextDetail(
          const MemoryResponse(
            projectContextName: '  ',
            projectContextWorkspace: '',
          ),
        ),
        isNull,
      );
      expect(
        memoryProjectContextDetail(
          const MemoryResponse(
            projectContextName: 'p',
            projectContextWorkspace: 'w',
          ),
        ),
        'p — w',
      );
      expect(
        memoryProjectContextDetail(
          const MemoryResponse(projectContextName: 'p'),
        ),
        'p',
      );
    });

    test('memoryHasContent：全空 false，任一分区/项目上下文非空 true', () {
      expect(memoryHasContent(const MemoryResponse()), isFalse);
      expect(memoryHasContent(const MemoryResponse(memory: 'm')), isTrue);
      expect(memoryHasContent(const MemoryResponse(user: '  ')), isFalse);
      expect(memoryHasContent(const MemoryResponse(soul: 's')), isTrue);
      expect(
        memoryHasContent(const MemoryResponse(projectContext: 'pc')),
        isTrue,
      );
    });

    test('formatMemoryMtime：相对时间中文描述；null/非法 → null', () {
      final now = DateTime(2026, 8, 16, 12, 0, 0);
      double secs(Duration d) => now.subtract(d).millisecondsSinceEpoch / 1000;

      expect(formatMemoryMtime(null), isNull);
      expect(formatMemoryMtime(double.nan), isNull);
      expect(
        formatMemoryMtime(secs(const Duration(seconds: 30)), now: now),
        '刚刚更新',
      );
      expect(
        formatMemoryMtime(secs(const Duration(minutes: 5)), now: now),
        '5 分钟前更新',
      );
      expect(
        formatMemoryMtime(secs(const Duration(hours: 3)), now: now),
        '3 小时前更新',
      );
      expect(
        formatMemoryMtime(secs(const Duration(days: 10)), now: now),
        '10 天前更新',
      );
      expect(
        formatMemoryMtime(secs(const Duration(days: 40)), now: now),
        '更新于 2026-07-07',
      );
    });
  });

  group('MemoryController 状态机', () {
    test('初始加载成功：AsyncData 携带 MemoryResponse', () async {
      final api = FakeMemoryApi(
        response: const MemoryResponse(memory: '笔记', user: '画像'),
      );
      final container = makeContainer(api);

      await container.read(memoryControllerProvider.future);
      final response = container.read(memoryControllerProvider).valueOrNull!;

      expect(api.fetchCount, 1);
      expect(response.memory, '笔记');
      expect(response.user, '画像');
      expect(response.soul, isNull);
    });

    test('初始加载失败 → AsyncError；refresh 重试成功', () async {
      final api = FakeMemoryApi(
        response: const MemoryResponse(memory: '恢复的记忆'),
      );
      api.fetchError = NetworkException(NetworkExceptionKind.cannotConnect);
      final container = makeContainer(api);

      await expectLater(
        container.read(memoryControllerProvider.future),
        throwsA(isA<ApiException>()),
      );
      expect(container.read(memoryControllerProvider).hasError, isTrue);
      expect(container.read(memoryControllerProvider).valueOrNull, isNull);

      api.fetchError = null;
      await container.read(memoryControllerProvider.notifier).refresh();

      expect(
        container.read(memoryControllerProvider).valueOrNull!.memory,
        '恢复的记忆',
      );
    });

    test('refresh 重新拉取', () async {
      final api = FakeMemoryApi(response: const MemoryResponse(memory: 'm'));
      final container = makeContainer(api);
      await container.read(memoryControllerProvider.future);
      expect(api.fetchCount, 1);

      await container.read(memoryControllerProvider.notifier).refresh();
      expect(api.fetchCount, 2);
    });
  });

  group('MemoryPage widget', () {
    Future<void> pumpMemoryPage(WidgetTester tester, FakeMemoryApi api) async {
      final router = GoRouter(
        initialLocation: '/',
        routes: [GoRoute(path: '/', builder: (_, _) => const MemoryPage())],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(
              ApiClient(baseUrl: 'http://test.local:30002'),
            ),
            memoryApiFactoryProvider.overrideWithValue((_) => api),
          ],
          child: CupertinoApp.router(routerConfig: router),
        ),
      );
      // 首帧（AsyncLoading）+ 异步 build 完成（AsyncData）
      await tester.pump();
      await tester.pump();
    }

    testWidgets('渲染：三个分区标题 + 内容 + 相对修改时间', (tester) async {
      final mtime =
          DateTime.now()
              .subtract(const Duration(hours: 2))
              .millisecondsSinceEpoch /
          1000;
      final api = FakeMemoryApi(
        response: MemoryResponse(
          memory: '记住用户偏好',
          user: '资深开发者',
          soul: '乐于助人',
          memoryMtime: mtime,
          userMtime: mtime,
          soulMtime: mtime,
        ),
      );
      await pumpMemoryPage(tester, api);

      expect(find.text('我的笔记'), findsOneWidget);
      expect(find.text('用户画像'), findsOneWidget);
      expect(find.text('智能体灵魂'), findsOneWidget);
      expect(find.text('记住用户偏好'), findsOneWidget);
      expect(find.text('资深开发者'), findsOneWidget);
      expect(find.text('乐于助人'), findsOneWidget);
      expect(find.text('2 小时前更新'), findsNWidgets(3));
    });

    testWidgets('分区空内容 → 斜体占位文案', (tester) async {
      final api = FakeMemoryApi(response: const MemoryResponse(user: '有内容'));
      await pumpMemoryPage(tester, api);

      expect(find.text('暂无笔记'), findsOneWidget);
      expect(find.text('有内容'), findsOneWidget);
      expect(find.text('暂无灵魂设定'), findsOneWidget);
    });

    testWidgets('项目上下文分区：内容 + 明细 + 只读锁 + 覆盖警告', (tester) async {
      final api = FakeMemoryApi(
        response: const MemoryResponse(
          projectContext: '这是项目上下文',
          projectContextName: 'demo',
          projectContextWorkspace: '/workspace/demo',
          projectContextShadowed: true,
        ),
      );
      await pumpMemoryPage(tester, api);

      expect(find.text('项目上下文'), findsOneWidget);
      expect(find.text('这是项目上下文'), findsOneWidget);
      expect(find.text('demo — /workspace/demo'), findsOneWidget);
      expect(find.textContaining('覆盖'), findsOneWidget);
      expect(find.byIcon(CupertinoIcons.lock_fill), findsOneWidget);
    });

    testWidgets('加载态：数据到达前显示 ActivityIndicator，到达后渲染分区', (tester) async {
      final api = FakeMemoryApi(response: const MemoryResponse(memory: '到了'));
      api.fetchGate = Completer<void>();
      await pumpMemoryPage(tester, api);

      expect(find.byType(CupertinoActivityIndicator), findsOneWidget);

      api.fetchGate!.complete();
      await tester.pump();
      await tester.pump();
      expect(find.text('到了'), findsOneWidget);
      expect(find.byType(CupertinoActivityIndicator), findsNothing);
    });

    testWidgets('全空 → 暂无记忆空态', (tester) async {
      await pumpMemoryPage(tester, FakeMemoryApi());

      expect(find.text('暂无记忆'), findsOneWidget);
      expect(find.text('还没有任何记忆内容'), findsOneWidget);
      // 全空时不再渲染分区标题
      expect(find.text('我的笔记'), findsNothing);
    });

    testWidgets('错误态：加载失败展示错误信息，重试恢复', (tester) async {
      final api = FakeMemoryApi(
        response: const MemoryResponse(memory: '恢复的记忆'),
      );
      api.fetchError = NetworkException(NetworkExceptionKind.cannotConnect);
      await pumpMemoryPage(tester, api);

      expect(find.text('加载失败'), findsOneWidget);
      expect(find.textContaining('无法连接'), findsOneWidget);

      api.fetchError = null;
      await tester.tap(find.byKey(const ValueKey('memory-retry')));
      await tester.pump();
      await tester.pump();

      expect(find.text('恢复的记忆'), findsOneWidget);
      expect(find.text('加载失败'), findsNothing);
    });

    testWidgets('刷新按钮：重新拉取记忆', (tester) async {
      final api = FakeMemoryApi(response: const MemoryResponse(memory: 'm'));
      await pumpMemoryPage(tester, api);
      expect(api.fetchCount, 1);

      await tester.tap(find.byKey(const ValueKey('memory-refresh')));
      await tester.pump();
      await tester.pump();
      expect(api.fetchCount, 2);
    });
  });
}
