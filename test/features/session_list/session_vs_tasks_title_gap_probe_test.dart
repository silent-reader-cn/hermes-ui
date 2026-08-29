import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/app/theme/cupertino_theme.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/features/session_list/session_list_page.dart';
import 'package:hermes_ui/features/tasks/tasks_page.dart';
import 'package:hermes_ui/features/tasks/tasks_providers.dart';

import '../../golden/golden_screens_test.dart' show sessionListOverrides;
import '../../helpers/fake_tasks_api.dart';

/// 注册应用真机字体 MiSans（Regular + Medium，同 golden_helpers 做法；
/// 文件缺失环境静默跳过）。
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

/// #24 探针：主页「会话」大标题 vs 定时任务页（系统 CupertinoSliverNavigationBar）
/// 展开态大标题文字 RenderParagraph 顶距状态栏底的真实 gap。
///
/// 视口固定 400×800（DPR 1.0），无状态栏 padding 与 24px 状态栏 padding
/// 两场景一并记录。gap = 大标题文字 RenderParagraph 的 global top - 状态栏底
/// （=padding.top）；数据经 debugPrint 落账。
///
/// 两组环境（探针定标依据 = 「真实MiSans+应用主题」组）：
/// - 「默认字体(Ahem)、无主题」：flutter_test 默认环境（同 2026-08-26 旧探针
///   与 session_title_alignment_test 的环境）。Ahem 方块字 34pt 行高 = 34px，
///   恰使系统组件大标题（44pt 持久栏下 44px 区 bottomStart 对齐，顶 =
///   88 - 行高）== 54，与会话页常量 54 巧合相等——旧探针因此误判两页一致。
/// - 「真实 MiSans + 应用主题」：真机同度量（注册 assets/fonts/MiSans 真字体，
///   同 golden_helpers 做法）。2026-08-29 实测：MiSans 34pt 行高 = 45.0px →
///   系统页大标题顶 = 88 - 45 = 43.0 vs 会话页 54.0，Δ=11px（会话页上方空白
///   更高，与 #24 主人实机观测方向一致）。
///
/// 定标状态：#24 规格要求「若实测两页 gap 相同则不要硬调」——旧探针环境两页
/// 均为 54.0（相同）→ 本探针当前只记录不断言；真机度量组显示真实差值为 11px，
/// 目标值 43.0（= 系统页真机 gap），待主人二次确认后把 `_spaciousLargeTitleTopGap`
/// 54.0 → 43.0 并将本文件 assertAligned 打开（同时需柚子收口时重生成
/// session_list 金照，子代理禁止 --update-goldens）。
///
/// 固定时钟：会话页经 [sessionListOverrides] 固定 2026-08-10 12:00；
/// 定时任务页用 FakeTasksApi（空列表，无时钟依赖）。
void main() {
  const String sessionTitle = '会话';
  const String tasksTitle = '定时任务';

  // gap = 大标题文字 RenderParagraph 顶（global） - 状态栏底（=padding.top）。
  // 同文案渲染两份（收起中标题 17pt + 展开大标题 34pt）时取渲染更高那份。
  double? measureTop(WidgetTester tester, String text) {
    final finder = find.text(text);
    if (finder.evaluate().isEmpty) return null;
    double? top;
    double? height;
    var count = 0;
    for (final e in finder.evaluate()) {
      count++;
      final ro = e.renderObject! as RenderBox;
      final t = ro.localToGlobal(Offset.zero).dy;
      final h = ro.size.height;
      if (height == null || h > height) {
        height = h;
        top = t;
      }
    }
    debugPrint('PROBE find.text($text) instances=$count tallestHeight=$height');
    return top;
  }

  void setupViewport(WidgetTester tester, {double statusBarHeight = 0}) {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    if (statusBarHeight > 0) {
      tester.view.padding = FakeViewPadding(top: statusBarHeight);
    }
    addTearDown(tester.view.reset);
  }

  CupertinoApp app({required Widget home, required bool withTheme}) {
    return CupertinoApp(
      theme: withTheme ? buildCupertinoTheme(Brightness.light) : null,
      home: home,
    );
  }

  Future<void> pumpSessionPage(
    WidgetTester tester, {
    required bool withTheme,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: await sessionListOverrides(),
        child: app(home: const SessionListPage(), withTheme: withTheme),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> pumpTasksPage(
    WidgetTester tester, {
    required bool withTheme,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(
            ApiClient(baseUrl: 'http://test.local:30002'),
          ),
          tasksApiFactoryProvider.overrideWithValue(
            (_) => FakeTasksApi(jobs: []),
          ),
        ],
        child: app(home: const TasksPage(), withTheme: withTheme),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  void runProbeGroup(
    String groupName, {
    required bool assertAligned,
    required bool withMiSans,
    required bool withTheme,
  }) {
    group(groupName, () {
      double? sessionGap0;
      double? tasksGap0;
      double? sessionGap24;
      double? tasksGap24;

      testWidgets('无padding：会话页大标题顶（记录）', (tester) async {
        if (withMiSans) await _registerMiSans();
        setupViewport(tester);
        await pumpSessionPage(tester, withTheme: withTheme);
        sessionGap0 = measureTop(tester, sessionTitle);
        debugPrint('PROBE [$groupName] 无padding 会话页 gap=$sessionGap0');
        expect(sessionGap0, isNotNull);
      });

      testWidgets('无padding：定时任务页大标题顶（记录）', (tester) async {
        setupViewport(tester);
        await pumpTasksPage(tester, withTheme: withTheme);
        tasksGap0 = measureTop(tester, tasksTitle);
        debugPrint('PROBE [$groupName] 无padding 定时任务页 gap=$tasksGap0');
        expect(tasksGap0, isNotNull);
      });

      testWidgets('无padding：两页 gap 对比', (tester) async {
        expect(sessionGap0, isNotNull);
        expect(tasksGap0, isNotNull);
        final delta = (sessionGap0! - tasksGap0!).abs();
        debugPrint(
          'PROBE [$groupName] 无padding Δgap=${delta.toStringAsFixed(2)} '
          '(session=$sessionGap0, tasks=$tasksGap0)',
        );
        if (assertAligned) {
          expect(
            delta,
            lessThanOrEqualTo(1.0),
            reason: '无padding：会话页 gap($sessionGap0) 应与定时任务页 gap($tasksGap0) 一致',
          );
        }
      });

      testWidgets('有padding(24)：会话页大标题顶（记录）', (tester) async {
        setupViewport(tester, statusBarHeight: 24);
        await pumpSessionPage(tester, withTheme: withTheme);
        final top = measureTop(tester, sessionTitle);
        sessionGap24 = top! - 24;
        debugPrint(
          'PROBE [$groupName] 有padding(24) 会话页 gap=$sessionGap24 '
          '(top=$top, statusBottom=24)',
        );
        expect(sessionGap24, isNotNull);
      });

      testWidgets('有padding(24)：定时任务页大标题顶（记录）', (tester) async {
        setupViewport(tester, statusBarHeight: 24);
        await pumpTasksPage(tester, withTheme: withTheme);
        final top = measureTop(tester, tasksTitle);
        tasksGap24 = top! - 24;
        debugPrint(
          'PROBE [$groupName] 有padding(24) 定时任务页 gap=$tasksGap24 '
          '(top=$top, statusBottom=24)',
        );
        expect(tasksGap24, isNotNull);
      });

      testWidgets('有padding(24)：两页 gap 对比', (tester) async {
        expect(sessionGap24, isNotNull);
        expect(tasksGap24, isNotNull);
        final delta = (sessionGap24! - tasksGap24!).abs();
        debugPrint(
          'PROBE [$groupName] 有padding(24) Δgap=${delta.toStringAsFixed(2)} '
          '(session=$sessionGap24, tasks=$tasksGap24)',
        );
        if (assertAligned) {
          expect(
            delta,
            lessThanOrEqualTo(1.0),
            reason: '有padding(24)：会话页 gap($sessionGap24) 应与定时任务页 gap($tasksGap24) 一致',
          );
        }
      });
    });
  }

  runProbeGroup(
    '默认字体(Ahem)+无主题（旧探针环境，只记录）',
    assertAligned: false,
    withMiSans: false,
    withTheme: false,
  );
  runProbeGroup(
    '真实MiSans+应用主题（真机度量，定标待主人确认）',
    assertAligned: false,
    withMiSans: true,
    withTheme: true,
  );
}