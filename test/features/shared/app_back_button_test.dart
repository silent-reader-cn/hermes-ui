import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hermex_flutter/features/shared/app_back_button.dart';

/// 迷你页面：导航栏带 [AppBackButton]，可选 push 出口与自定义 fallback。
///
/// 模拟 App 两种进入方式：
/// - `go` 直进（无页面堆栈，如真实 App 的顶层路由）→ 返回走 fallback；
/// - `push` 进入（有页面堆栈，如真实 App 的详情页）→ 返回走 pop。
class _SimplePage extends StatelessWidget {
  const _SimplePage({
    required this.label,
    this.pushTarget,
    this.fallback = '/',
  });

  final String label;
  final String? pushTarget;
  final String fallback;

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        leading: AppBackButton(fallback: fallback),
        middle: Text(label),
        trailing: pushTarget == null
            ? null
            : CupertinoButton(
                key: const ValueKey('push-btn'),
                onPressed: () => context.push(pushTarget!),
                child: const Text('push'),
              ),
      ),
      child: const SizedBox.shrink(),
    );
  }
}

/// 构造三页路由：`/home`（入口）、`/stacked`（push 详情）、`/dest`（fallback）。
GoRouter buildRouter() {
  return GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(
        path: '/home',
        builder: (_, _) => const _SimplePage(
          label: 'Home',
          pushTarget: '/stacked',
          fallback: '/dest',
        ),
      ),
      GoRoute(
        path: '/stacked',
        builder: (_, _) => const _SimplePage(label: 'Stacked'),
      ),
      GoRoute(
        path: '/dest',
        builder: (_, _) => const _SimplePage(label: 'Dest'),
      ),
    ],
  );
}

/// go_router 页面切换过渡动画 300ms，等足 6 帧 × 200ms 结算。
Future<void> settleNavigation(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

void main() {
  testWidgets('go 直进（无 pop 堆栈）→ 返回按钮按 fallback 兜底跳转', (tester) async {
    final router = buildRouter();
    await tester.pumpWidget(CupertinoApp.router(routerConfig: router));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Home'), findsOneWidget);
    await tester.tap(find.byType(CupertinoNavigationBarBackButton));
    await settleNavigation(tester);

    // 无堆栈可 pop → 跳 fallback 目标页，而不是原地不动或崩溃
    expect(find.text('Dest'), findsOneWidget);
    expect(find.text('Home'), findsNothing);
  });

  testWidgets('push 进入（有 pop 堆栈）→ 返回按钮 pop 回上一页', (tester) async {
    final router = buildRouter();
    await tester.pumpWidget(CupertinoApp.router(routerConfig: router));
    await tester.pump(const Duration(milliseconds: 400));

    // 从 home push 进 stacked（堆栈：home → stacked）
    await tester.tap(find.byKey(const ValueKey('push-btn')));
    await settleNavigation(tester);
    expect(find.text('Stacked'), findsOneWidget);

    // 有堆栈可 pop → 返回上一页 home，而不是跳 fallback
    await tester.tap(find.byType(CupertinoNavigationBarBackButton));
    await settleNavigation(tester);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Stacked'), findsNothing);
  });
}