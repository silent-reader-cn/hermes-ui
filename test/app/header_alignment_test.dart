import 'package:flutter/cupertino.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/app/shell/sidebar_utility_toolbar.dart';
import 'package:hermes_ui/app/widgets/adaptive_sliver_navigation_bar.dart';
import 'package:hermes_ui/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 宽屏双栏 Header 对齐探针：侧栏工具条（44px）与内容区紧凑导航条等高。
///
/// 回归守卫：桌面端两侧顶部高度参差（曾因 CupertinoButton 默认 44px 最小
/// 高度 + 外层 6px×2 边距导致工具条实际 56px）不可复现。
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  const List<LocalizationsDelegate<dynamic>> testDelegates = [
    AppLocalizationsDelegate(),
    DefaultCupertinoLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  Widget buildRow() {
    return const CupertinoApp(
      localizationsDelegates: testDelegates,
      home: ProviderScope(
        child: SafeArea(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 320,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: SidebarUtilityToolbar(currentLocation: '/skills'),
                ),
              ),
              Expanded(
                child: CustomScrollView(
                  slivers: [
                    AdaptiveSliverNavigationBar(
                      title: '技能',
                      leading: SizedBox.shrink(),
                    ),
                    SliverToBoxAdapter(
                      child: SizedBox(height: 1000, width: double.infinity),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  testWidgets('宽屏（>=900）：侧栏工具条与内容区导航条等高 44px', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(buildRow());
    await tester.pumpAndSettle();

    final toolbarSize = tester.getSize(find.byType(SidebarUtilityToolbar));

    // 工具条收 44px（修复前 56px：CupertinoButton 默认 44 高 + 外层 12 边距）；
    // 44.5 = 44 + 底部 0.5px 分隔线，允许 1px 容差。
    expect(toolbarSize.height, closeTo(44, 1));

    // 导航条宽屏收敛为 44pt 紧凑条：标题只有一个（middle 中标题），
    // 且文字位于 44px 条内（17pt 行盒高 ~20，top < 24）。
    expect(find.text('技能'), findsOneWidget);
    final titleRect = tester.getRect(find.text('技能'));
    expect(titleRect.height, lessThanOrEqualTo(24));
    expect(titleRect.top, greaterThanOrEqualTo(0));
    expect(titleRect.bottom, lessThanOrEqualTo(44));
  });

  testWidgets('窄屏（<900）：内容区保持大标题展开高度（手机样式不变）', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const CupertinoApp(
        localizationsDelegates: testDelegates,
        home: ProviderScope(
          child: SafeArea(
            child: CustomScrollView(
              slivers: [
                AdaptiveSliverNavigationBar(
                  title: '技能',
                  leading: SizedBox.shrink(),
                ),
                SliverToBoxAdapter(
                  child: SizedBox(height: 1000, width: double.infinity),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 2026-09-03 TASK sep03：窄屏改自绘 LargeTitleSliverHeaderDelegate，
    // 收起态中标题仅 showMiddleOnNarrow 页面渲染——默认页大标题只有 1 份。
    final titleFinder = find.text('技能');
    expect(titleFinder, findsOneWidget);
    final maxHeight = tester.getRect(titleFinder).height;
    // Ahem 字体下行盒高 == fontSize：34pt 大标题 → 34（±3 覆盖字体差异）。
    expect(maxHeight, greaterThanOrEqualTo(31));
    expect(maxHeight, lessThanOrEqualTo(42));
  });

  testWidgets('窄屏（<900）：▾ 位于大标题右侧而非右上角 trailing', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const CupertinoApp(
        localizationsDelegates: testDelegates,
        home: ProviderScope(
          child: SafeArea(
            child: CustomScrollView(
              slivers: [
                AdaptiveSliverNavigationBar(
                  title: '技能',
                  leading: SizedBox.shrink(),
                  trailing: SizedBox(
                    key: ValueKey('page-trailing'),
                    width: 30,
                    height: 30,
                  ),
                ),
                SliverToBoxAdapter(
                  child: SizedBox(height: 1000, width: double.infinity),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final titleRect = tester.getRect(find.text('技能'));
    final dropdownRect = tester.getRect(
      find.byKey(const ValueKey('narrow-nav-dropdown')),
    );
    final trailingRect = tester.getRect(find.byKey(const ValueKey('page-trailing')));

    // ▾ 紧贴标题右缘（间距约 4px，容忍字体度量差），而不是贴在 trailing 左侧。
    expect(dropdownRect.left, greaterThan(titleRect.right - 8));
    expect(dropdownRect.left, lessThan(titleRect.right + 24));
    // ▾ 垂直中心与大标题行中心一致（展开态同行）。
    expect(
      (dropdownRect.center.dy - titleRect.center.dy).abs(),
      lessThan(12),
    );
    // ▾ 明显位于页面 trailing 按钮左侧（不再挤右上角一排）。
    expect(dropdownRect.right, lessThan(trailingRect.left));
  });
}
