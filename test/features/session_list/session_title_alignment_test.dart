import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/app/theme/cupertino_theme.dart';
import 'package:hermes_ui/features/session_list/session_list_page.dart';
import 'package:hermes_ui/features/skills/skills_page.dart';
import 'package:hermes_ui/features/workspace_manager/workspace_manager_page.dart';

import '../../golden/golden_screens_test.dart' show sessionListOverrides;

/// 注册应用真机字体 MiSans（Regular + Medium，同 golden_helpers 做法；
/// 文件缺失环境静默跳过）。默认 Ahem 方块字行高与真机差距大
/// （Ahem 34pt 行高 34px vs MiSans 45px），会误判大标题对齐，故本测试
/// 必须注入真字体保持真机语义（2026-08-29 #24 定标后）。
Future<void> _registerMiSans() async {
  for (final path in [
    'assets/fonts/MiSans-Regular.ttf',
    'assets/fonts/MiSans-Medium.ttf',
  ]) {
    final file = File(path);
    if (!file.existsSync()) continue;
    final bytes = file.readAsBytesSync();
    final loader = FontLoader('MiSans')
      ..addFont(Future.value(ByteData.sublistView(bytes)));
    await loader.load();
  }
}

/// 窄屏大标题顶部对齐回归：会话列表页（自定义
/// [SessionListHeaderDelegate]）与技能/工作区页（系统
/// `CupertinoSliverNavigationBar`）的 34pt 大标题距屏幕顶部距离一致。
///
/// 2026-08-26 实测基准（Ahem）：系统组件大标题顶 = 54px，会话列表 54px。
/// 2026-08-29 #24 真 MiSans 探针修订：真机语义下系统页顶 = 43px，
/// 会话页常量 54→43 后二者仍对齐（测试环境注入 MiSans 真字体保证断言
/// 与真机同一度量）。
void main() {
  setUpAll(() async {
    await _registerMiSans();
  });
  double? sessionTop;
  double? skillsTop;
  double? workspaceTop;

  double? titleTop(WidgetTester tester, String text) {
    final finder = find.text(text);
    if (finder.evaluate().isEmpty) return null;
    // 同文案渲染两份（收起中标题 + 展开大标题）：取渲染更高（34pt）那份，
    // 其全局顶部即标题距屏幕距离。
    double? tallestTop;
    double? tallestHeight;
    for (final e in finder.evaluate()) {
      final ro = e.renderObject! as RenderBox;
      final top = ro.localToGlobal(Offset.zero).dy;
      final h = ro.size.height;
      if (tallestHeight == null || h > tallestHeight) {
        tallestHeight = h;
        tallestTop = top;
      }
    }
    return tallestTop;
  }

  void setupNarrow(WidgetTester tester) {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  Future<void> pumpWithOverrides(
    WidgetTester tester,
    List<Override> overrides,
    Widget home,
  ) async {
    // 注入应用主题（MiSans fontFamily）保证与真机同一字体度量（#24 定标后）。
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: CupertinoApp(
          theme: buildCupertinoTheme(Brightness.light),
          home: home,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('窄屏：会话列表大标题顶部（记录）', (tester) async {
    setupNarrow(tester);

    await pumpWithOverrides(
      tester,
      await sessionListOverrides(),
      const SessionListPage(),
    );
    sessionTop = titleTop(tester, '会话');
    expect(sessionTop, isNotNull);
  });

  testWidgets('窄屏：技能页大标题顶部（记录）', (tester) async {
    setupNarrow(tester);
    await pumpWithOverrides(tester, const [], const SkillsPage());
    skillsTop = titleTop(tester, '技能');
  });

  testWidgets('窄屏：工作区页大标题顶部（记录）', (tester) async {
    setupNarrow(tester);
    await pumpWithOverrides(tester, const [], const WorkspaceManagerPage());
    workspaceTop = titleTop(tester, '工作区');
    expect(workspaceTop, isNotNull);
  });

  testWidgets('窄屏：会话列表与系统导航条页面大标题顶部对齐（±1px）', (tester) async {
    // 技能页与工作区同用系统导航条，取其一作基准（技能可能因 loading 态
    // 时序取不到大标题，宽限跳过）。
    final systemTop = workspaceTop ?? skillsTop;
    expect(systemTop, isNotNull);
    expect(
      (sessionTop! - systemTop!).abs(),
      lessThanOrEqualTo(1.0),
      reason: '会话列表大标题顶（$sessionTop）应与系统导航条页面（$systemTop）对齐',
    );
  });
}
