import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show MaterialApp;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hermes_ui/app/widgets/hermes_page_route.dart';

/// HermesPageRoute 转场方向测试（todo #22 验收，修正 #17 行为；分数位移修复）：
/// - push 进入：新页从右滑入（x: +1.0 → 0），与 Cupertino 一致；
/// - pop 返回：当前页向右滑出（x: 0 → +1.0，iOS 标准），**方向不反**
///   （中间帧 dx > 0）；
/// - 底层页全程静止（偏移量用 push 前记录的基准比对）；
/// - pop 滑出时叠轻微淡出；
/// - go_router pageBuilder + HermesPage 的 push/pop 转场方向一致。
///
/// 注意（实测坑）：
/// - go_router 下 home/detail 都走 HermesPage → 页面树中 slideKey 出现 2 个，
///   必须用 ancestor(of: 详情页内容) 精确定位详情页的 SlideTransition；
/// - push 完成后底层 route 被 Overlay 置为 offstage，find.byKey 默认
///   skipOffstage: true 找不到 —— 底层基准位置必须在 push 前记录。

const _bottomKey = ValueKey('bottom-page');

class _BottomPage extends StatelessWidget {
  const _BottomPage({super.key});

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      child: Center(
        child: Builder(
          builder: (context) => CupertinoButton(
            onPressed: () => Navigator.of(context).push(
              HermesPageRoute<void>(builder: (context) => const _DetailPage()),
            ),
            child: const Text('push'),
          ),
        ),
      ),
    );
  }
}

class _DetailPage extends StatelessWidget {
  const _DetailPage();

  @override
  Widget build(BuildContext context) {
    return const CupertinoPageScaffold(child: Center(child: Text('detail')));
  }
}

/// 读取 Hermes 转场 SlideTransition 当前 dx 位移。
/// 用 ancestor 锚定「detail」文本，避免命中底层页/首页的同 key 转场。
double _slideDx(WidgetTester tester) {
  final slide = tester.widget<SlideTransition>(
    find
        .ancestor(
          of: find.text('detail'),
          matching: find.byKey(HermesPageRoute.slideKey),
        )
        .first,
  );
  return slide.position.value.dx;
}

Future<void> _pumpApp(WidgetTester tester) async {
  await tester.pumpWidget(
    const CupertinoApp(home: _BottomPage(key: _bottomKey)),
  );
}

Future<void> _pushDetail(WidgetTester tester) async {
  await tester.tap(find.text('push'));
  await tester.pumpAndSettle();
  expect(find.text('detail'), findsOneWidget);
}

void main() {
  testWidgets('push 进入：新页从右滑入（x: +1.0 → 0）', (tester) async {
    await _pumpApp(tester);

    await tester.tap(find.text('push'));
    // tap 事件需要一帧才触发 push，先 pump() 空帧处理，再进动画中帧。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.text('detail'), findsOneWidget);
    // 动画中帧：仍在右侧、正在向左滑入（0 < dx <= 1.0）。
    final earlyDx = _slideDx(tester);
    expect(earlyDx, greaterThan(0));
    expect(earlyDx, lessThanOrEqualTo(1.0));

    await tester.pump(const Duration(milliseconds: 200));
    final midDx = _slideDx(tester);
    expect(midDx, greaterThan(0));
    expect(midDx, lessThanOrEqualTo(1.0));
    expect(midDx, lessThan(earlyDx)); // 向左滑入，dx 递减

    await tester.pumpAndSettle();
    expect(_slideDx(tester), 0);
    expect(find.text('detail'), findsOneWidget);
  });

  testWidgets('pop 返回：当前页向右滑出（x: 0 → +1.0），底层页静止', (tester) async {
    await _pumpApp(tester);
    // push 前记录底层基准（push 完成后底层会 offstage，无法再取）。
    final bottomX = tester.getTopLeft(find.byKey(_bottomKey)).dx;
    await _pushDetail(tester);

    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    // 中帧：正在向右滑出（0 < dx <= 1.0）。
    final earlyDx = _slideDx(tester);
    expect(earlyDx, greaterThan(0));
    expect(earlyDx, lessThanOrEqualTo(1.0));

    await tester.pump(const Duration(milliseconds: 200));
    final midDx = _slideDx(tester);
    expect(midDx, greaterThan(0));
    expect(midDx, lessThanOrEqualTo(1.0));
    expect(midDx, greaterThan(earlyDx)); // 向右滑出，dx 递增

    await tester.pump(const Duration(milliseconds: 100));
    // 深帧（累计 360ms，接近 400ms 动画尾声但 route 未移除）：dx 明显为正且接近 1.0。
    expect(_slideDx(tester), greaterThan(0.5));
    expect(_slideDx(tester), lessThanOrEqualTo(1.0));

    await tester.pumpAndSettle();
    expect(find.text('detail'), findsNothing);
    // 底层页重新 onstage，位置与 push 前基准一致（静止）。
    final bottomAfter = tester.getTopLeft(
      find.byKey(_bottomKey, skipOffstage: false),
    );
    expect(bottomAfter.dx, bottomX);
  });

  testWidgets('pop 方向不反：中间帧位移为正（向右），非负（向左）', (tester) async {
    await _pumpApp(tester);
    await _pushDetail(tester);

    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pump();
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 80));
      expect(_slideDx(tester), greaterThan(0), reason: '第 $i 帧 pop 方向应为向右');
      expect(_slideDx(tester), lessThanOrEqualTo(1.0));
    }
  });

  testWidgets('pop 滑出时当前页叠轻微淡出', (tester) async {
    await _pumpApp(tester);
    await _pushDetail(tester);

    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    // 中帧：当前页 FadeTransition 透明度低于 1（淡出中），但未完全透明。
    final fade = tester.widget<FadeTransition>(
      find
          .ancestor(
            of: find.text('detail'),
            matching: find.byType(FadeTransition),
          )
          .first,
    );
    expect(fade.opacity.value, lessThan(1));
    expect(fade.opacity.value, greaterThan(0.5));
  });

  testWidgets('go_router pageBuilder + HermesPage：push 从右滑入、pop 向右滑出', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/home',
      routes: [
        GoRoute(
          path: '/home',
          pageBuilder: (context, state) =>
              const HermesPage<void>(builder: _goHomePage, name: 'home'),
        ),
        GoRoute(
          path: '/detail',
          pageBuilder: (context, state) =>
              const HermesPage<void>(builder: _goDetailPage, name: 'detail'),
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));

    await tester.tap(find.text('gopush'));
    // 路由入树需要一帧，先 pump() 处理 tap 再推进 60ms 进入动画中帧。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.text('detail'), findsOneWidget);
    // 中帧：从右滑入（0 < dx <= 1.0）。
    final pushDx = _slideDx(tester);
    expect(pushDx, greaterThan(0));
    expect(pushDx, lessThanOrEqualTo(1.0));
    await tester.pumpAndSettle();
    expect(_slideDx(tester), 0);
    expect(find.text('detail'), findsOneWidget);

    await tester.tap(find.text('back'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump(const Duration(milliseconds: 200));
    // 中帧：向右滑出（0 < dx <= 1.0）。
    expect(_slideDx(tester), greaterThan(0));
    expect(_slideDx(tester), lessThanOrEqualTo(1.0));
    await tester.pumpAndSettle();
    expect(find.text('detail'), findsNothing);
  });
}

Widget _goHomePage(BuildContext context) {
  return CupertinoPageScaffold(
    child: Center(
      child: Builder(
        builder: (context) => CupertinoButton(
          onPressed: () => context.push('/detail'),
          child: const Text('gopush'),
        ),
      ),
    ),
  );
}

Widget _goDetailPage(BuildContext context) {
  return CupertinoPageScaffold(
    child: Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('detail'),
          CupertinoButton(
            onPressed: () => context.pop(),
            child: const Text('back'),
          ),
        ],
      ),
    ),
  );
}