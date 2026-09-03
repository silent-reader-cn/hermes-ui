import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hermes_ui/core/api/api_client.dart';
import 'package:hermes_ui/core/connections/connection_providers.dart';
import 'package:hermes_ui/core/models/session.dart';
import 'package:hermes_ui/features/projects/project_providers.dart';
import 'package:hermes_ui/features/session_list/session_list_page.dart';
import 'package:hermes_ui/features/session_list/session_list_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_session_list_api.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });
  SessionSummary session(
    String id,
    String title, {
    String? sourceLabel,
    String? projectId,
    bool archived = false,
  }) {
    return SessionSummary(
      sessionId: id,
      title: title,
      sourceLabel: sourceLabel,
      projectId: projectId,
      archived: archived,
      createdAt: (DateTime.now().millisecondsSinceEpoch / 1000) - 3600,
    );
  }

  Future<void> pumpList(
    WidgetTester tester,
    FakeSessionListApi api, {
    ProjectApi? projectApi,
  }) async {
    final router = GoRouter(
      initialLocation: '/',
      routes: [GoRoute(path: '/', builder: (_, _) => const SessionListPage())],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(
            ApiClient(baseUrl: 'http://test.local:30002'),
          ),
          sessionListApiFactoryProvider.overrideWithValue((_) => api),
          projectApiFactoryProvider.overrideWithValue(
            (_) => projectApi ?? _FakeProjectApi(),
          ),
        ],
        child: CupertinoApp.router(routerConfig: router),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  group('筛选弹窗三段等宽与选中回调', () {
    testWidgets('三段等宽：会话/渠道/项目 section 同宽同边距', (tester) async {
      final api = FakeSessionListApi(
        sessions: [
          session('s1', '会话一', sourceLabel: 'telegram', projectId: 'p1'),
          session('s2', '会话二', sourceLabel: 'qq', projectId: 'p2'),
        ],
      );
      final projectApi = _FakeProjectApi(
        projects: const [
          ProjectSummary(projectId: 'p1', name: '项目一'),
          ProjectSummary(projectId: 'p2', name: '项目二'),
        ],
      );
      await pumpList(tester, api, projectApi: projectApi);
      await tester.tap(
        find.byKey(const ValueKey('session-list-filter-trigger')),
      );
      await tester.pumpAndSettle();

      final sessionsSection = tester.getRect(
        find.byKey(const ValueKey('filter-section-sessions')),
      );
      final channelsSection = tester.getRect(
        find.byKey(const ValueKey('filter-section-channels')),
      );
      final projectsSection = tester.getRect(
        find.byKey(const ValueKey('filter-section-projects')),
      );

      // 三段等宽（同一横向内边距 → width 相等）
      expect(sessionsSection.width, closeTo(channelsSection.width, 1.0));
      expect(sessionsSection.width, closeTo(projectsSection.width, 1.0));
      // 同左对齐（insetGrouped 统一 16 边距）
      expect(sessionsSection.left, closeTo(channelsSection.left, 1.0));
      expect(sessionsSection.left, closeTo(projectsSection.left, 1.0));
      // 三段可见
      expect(
        find.byKey(const ValueKey('filter-section-sessions')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('filter-section-channels')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('filter-section-projects')),
        findsOneWidget,
      );
    });

    testWidgets('渠道列表行：纵向单选，checkmark 选中态', (tester) async {
      final api = FakeSessionListApi(
        sessions: [
          session('s1', '会话一', sourceLabel: 'telegram'),
          session('s2', '会话二', sourceLabel: 'qq'),
        ],
      );
      await pumpList(tester, api);
      await tester.tap(
        find.byKey(const ValueKey('session-list-filter-trigger')),
      );
      await tester.pumpAndSettle();

      // 渠道以列表行呈现，点击来源后弹层关闭并过滤
      expect(
        find.byKey(const ValueKey('filter-chip-telegram')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('filter-chip-qq')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('filter-chip-telegram')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('session-filter-sheet')), findsNothing);
      expect(find.text('会话一'), findsOneWidget);
      expect(find.text('会话二'), findsNothing);
    });

    testWidgets('项目列表行：选中回调正确，项目筛选生效', (tester) async {
      final api = FakeSessionListApi(
        sessions: [
          session('s1', '会话一', projectId: 'p1'),
          session('s2', '会话二', projectId: 'p2'),
        ],
      );
      final projectApi = _FakeProjectApi(
        projects: const [
          ProjectSummary(projectId: 'p1', name: '项目一'),
          ProjectSummary(projectId: 'p2', name: '项目二'),
        ],
      );
      await pumpList(tester, api, projectApi: projectApi);
      await tester.tap(
        find.byKey(const ValueKey('session-list-filter-trigger')),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('project-chip-p1')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('project-chip-p1')));
      await tester.pumpAndSettle();
      expect(find.text('会话一'), findsOneWidget);
      expect(find.text('会话二'), findsNothing);
    });

    testWidgets('选中态：在对应筛选下进入弹层，选中行展示 checkmark', (tester) async {
      final api = FakeSessionListApi(
        sessions: [session('s1', '会话一', sourceLabel: 'telegram')],
      );
      await pumpList(tester, api);
      await tester.tap(
        find.byKey(const ValueKey('session-list-filter-trigger')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('filter-chip-telegram')));
      await tester.pumpAndSettle();

      // 再次打开应显示清除筛选项
      await tester.tap(
        find.byKey(const ValueKey('session-list-filter-trigger')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('sheet-filter-clear')), findsOneWidget);
      // telegram 选中行应带系统 checkmark（CupertinoIcons.check_mark）
      expect(find.byIcon(CupertinoIcons.check_mark), findsWidgets);
    });

    testWidgets('去白条：弹层背景为 grouped 无底部白条残留', (tester) async {
      final api = FakeSessionListApi(
        sessions: [session('s1', '会话一', sourceLabel: 'telegram')],
      );
      await pumpList(tester, api);
      await tester.tap(
        find.byKey(const ValueKey('session-list-filter-trigger')),
      );
      await tester.pumpAndSettle();

      // 弹层根容器存在且可滚动内容紧凑（SizedBox 8 而非 16）
      final sheet = find.byKey(const ValueKey('session-filter-sheet'));
      expect(sheet, findsOneWidget);
      final sheetBox = tester.getRect(sheet);
      // 不应占满全屏（紧凑高度）
      expect(sheetBox.height, lessThan(600));
    });

    testWidgets(
      '分割线全宽：dividerMargin 与 additionalDividerMargin 均置 0（起点=容器左缘）',
      (tester) async {
        final api = FakeSessionListApi(
          sessions: [
            session('s1', '会话一', sourceLabel: 'telegram', projectId: 'p1'),
            session('s2', '会话二', sourceLabel: 'qq', projectId: 'p2'),
          ],
        );
        final projectApi = _FakeProjectApi(
          projects: const [
            ProjectSummary(projectId: 'p1', name: '项目一'),
            ProjectSummary(projectId: 'p2', name: '项目二'),
          ],
        );
        await pumpList(tester, api, projectApi: projectApi);
        await tester.tap(
          find.byKey(const ValueKey('session-list-filter-trigger')),
        );
        await tester.pumpAndSettle();

        final sessionsSection = tester.widget<CupertinoListSection>(
          find.byKey(const ValueKey('filter-section-sessions')),
        );
        final channelsSection = tester.widget<CupertinoListSection>(
          find.byKey(const ValueKey('filter-section-channels')),
        );
        final projectsSection = tester.widget<CupertinoListSection>(
          find.byKey(const ValueKey('filter-section-projects')),
        );

        // #28 分割线全宽：divider 起点 = dividerMargin + additionalDividerMargin
        // → 两者均置 0，分割线从容器（children group）左缘起笔全长贯穿。
        expect(sessionsSection.dividerMargin, equals(0.0));
        expect(sessionsSection.additionalDividerMargin, equals(0.0));
        expect(channelsSection.dividerMargin, equals(0.0));
        expect(channelsSection.additionalDividerMargin, equals(0.0));
        expect(projectsSection.dividerMargin, equals(0.0));
        expect(projectsSection.additionalDividerMargin, equals(0.0));
      },
    );

    testWidgets('分割线坐标探针：筛选弹层内分隔线起点 x == 容器左缘', (tester) async {
      final api = FakeSessionListApi(
        sessions: [
          session('s1', '会话一', sourceLabel: 'telegram'),
          session('s2', '会话二', sourceLabel: 'qq'),
        ],
      );
      await pumpList(tester, api);
      await tester.tap(
        find.byKey(const ValueKey('session-list-filter-trigger')),
      );
      await tester.pumpAndSettle();

      // 渠道分区（telegram/qq 两行 → 中间有一条分隔线）
      final section = find.byKey(const ValueKey('filter-section-channels'));
      expect(section, findsOneWidget);
      // 取分区内高度 ≤ 1 的分隔线 Container（SDK 以 constraints 承载高度）
      final divider = find.descendant(
        of: section,
        matching: find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.constraints != null &&
              w.constraints!.maxHeight <= 1.0 &&
              w.margin != null,
        ),
      );
      expect(divider, findsWidgets);
      final dividerRect = tester.getRect(divider.first);
      // 容器左缘 = section 整体的 left + 16（insetGrouped margin.left）
      final sectionRect = tester.getRect(section);
      final containerLeft = sectionRect.left + 16;
      expect(dividerRect.left, closeTo(containerLeft, 0.5));
    });

    testWidgets('深色模式：分割线颜色保持 CupertinoColors.separator 解析色', (tester) async {
      final api = FakeSessionListApi(
        sessions: [
          session('s1', '会话一', sourceLabel: 'telegram'),
          session('s2', '会话二', sourceLabel: 'qq'),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(
              ApiClient(baseUrl: 'http://test.local:30002'),
            ),
            sessionListApiFactoryProvider.overrideWithValue((_) => api),
            projectApiFactoryProvider.overrideWithValue(
              (_) => _FakeProjectApi(),
            ),
          ],
          child: CupertinoApp.router(
            theme: const CupertinoThemeData(brightness: Brightness.dark),
            routerConfig: GoRouter(
              initialLocation: '/',
              routes: [
                GoRoute(path: '/', builder: (_, _) => const SessionListPage()),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('session-list-filter-trigger')),
      );
      await tester.pumpAndSettle();

      final section = find.byKey(const ValueKey('filter-section-channels'));
      final expected = CupertinoColors.separator.resolveFrom(
        tester.element(section),
      );
      final divider = find.descendant(
        of: section,
        matching: find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.constraints != null &&
              w.constraints!.maxHeight <= 1.0 &&
              w.margin != null,
        ),
      );
      expect(divider, findsWidgets);
      for (final e in divider.evaluate().take(10)) {
        final container = e.widget as Container;
        if (container.constraints != null &&
            container.constraints!.maxHeight <= 1.0) {
          expect(container.color, equals(expected));
        }
      }
    });
  });

  group('全部与已归档 checkbox 样式及单选互斥', () {
    testWidgets('全部/已归档行渲染 checkbox 图标（checkmark_square 系）', (tester) async {
      final api = FakeSessionListApi(
        sessions: [
          session('s1', '会话一'),
          session('s2', '会话二', archived: true),
        ],
      );
      await pumpList(tester, api);
      await tester.tap(
        find.byKey(const ValueKey('session-list-filter-trigger')),
      );
      await tester.pumpAndSettle();

      // 「全部」行：默认选中，左侧展示 checkmark_square_fill，颜色为 activeBlue
      final allRow = find.byKey(const ValueKey('sheet-filter-all'));
      expect(allRow, findsOneWidget);
      final allIcon = tester.widget<Icon>(
        find.descendant(of: allRow, matching: find.byType(Icon)),
      );
      expect(allIcon.icon, equals(CupertinoIcons.checkmark_square_fill));
      expect(
        allIcon.color,
        equals(CupertinoColors.activeBlue.resolveFrom(tester.element(allRow))),
      );

      // 「已归档」行：默认未选中，左侧展示 checkmark_square，颜色为 secondaryLabel
      final archivedRow = find.byKey(const ValueKey('sheet-filter-archived'));
      expect(archivedRow, findsOneWidget);
      final archivedIcon = tester.widget<Icon>(
        find.descendant(of: archivedRow, matching: find.byType(Icon)),
      );
      expect(archivedIcon.icon, equals(CupertinoIcons.checkmark_square));
      expect(
        archivedIcon.color,
        equals(
          CupertinoColors.secondaryLabel.resolveFrom(
            tester.element(archivedRow),
          ),
        ),
      );

      // 两行右侧均不再展示旧 checkmark（CupertinoIcons.check_mark）
      expect(
        find.descendant(
          of: allRow,
          matching: find.byIcon(CupertinoIcons.check_mark),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: archivedRow,
          matching: find.byIcon(CupertinoIcons.check_mark),
        ),
        findsNothing,
      );
    });

    testWidgets('选中互斥：点已归档后全部行为空框，反选全部后已归档为空框', (tester) async {
      final api = FakeSessionListApi(
        sessions: [
          session('s1', '普通会话'),
          session('s2', '已归档会话', archived: true),
        ],
      );
      await pumpList(tester, api);
      await tester.tap(
        find.byKey(const ValueKey('session-list-filter-trigger')),
      );
      await tester.pumpAndSettle();

      // 1. 默认进入：全部为 fill，已归档为 empty
      expect(
        tester
            .widget<Icon>(
              find.descendant(
                of: find.byKey(const ValueKey('sheet-filter-all')),
                matching: find.byType(Icon),
              ),
            )
            .icon,
        equals(CupertinoIcons.checkmark_square_fill),
      );
      expect(
        tester
            .widget<Icon>(
              find.descendant(
                of: find.byKey(const ValueKey('sheet-filter-archived')),
                matching: find.byType(Icon),
              ),
            )
            .icon,
        equals(CupertinoIcons.checkmark_square),
      );

      // 2. 点击「已归档」
      await tester.tap(find.byKey(const ValueKey('sheet-filter-archived')));
      await tester.pumpAndSettle();

      // 3. 重新打开筛选弹层验证互斥状态：已归档为 fill，全部为空框
      await tester.tap(
        find.byKey(const ValueKey('session-list-filter-trigger')),
      );
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<Icon>(
              find.descendant(
                of: find.byKey(const ValueKey('sheet-filter-all')),
                matching: find.byType(Icon),
              ),
            )
            .icon,
        equals(CupertinoIcons.checkmark_square),
      );
      expect(
        tester
            .widget<Icon>(
              find.descendant(
                of: find.byKey(const ValueKey('sheet-filter-archived')),
                matching: find.byType(Icon),
              ),
            )
            .icon,
        equals(CupertinoIcons.checkmark_square_fill),
      );

      // 4. 反向点击「全部」→ 互斥恢复：全部为 fill，已归档为空框
      await tester.tap(find.byKey(const ValueKey('sheet-filter-all')));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('session-list-filter-trigger')),
      );
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<Icon>(
              find.descendant(
                of: find.byKey(const ValueKey('sheet-filter-all')),
                matching: find.byType(Icon),
              ),
            )
            .icon,
        equals(CupertinoIcons.checkmark_square_fill),
      );
      expect(
        tester
            .widget<Icon>(
              find.descendant(
                of: find.byKey(const ValueKey('sheet-filter-archived')),
                matching: find.byType(Icon),
              ),
            )
            .icon,
        equals(CupertinoIcons.checkmark_square),
      );
    });

    testWidgets('圆角与边框层级：卡片 14pt 圆角 + 1px 分割线边框，弹层顶部 16pt 圆角', (tester) async {
      final api = FakeSessionListApi(
        sessions: [session('s1', '普通会话')],
      );
      await pumpList(tester, api);
      await tester.tap(
        find.byKey(const ValueKey('session-list-filter-trigger')),
      );
      await tester.pumpAndSettle();

      // 弹层顶部大圆角（16pt）
      final sheetBox = tester.widget<DecoratedBox>(
        find.byKey(const ValueKey('session-filter-sheet')),
      );
      final sheetDecoration = sheetBox.decoration as BoxDecoration;
      expect(
        sheetDecoration.borderRadius,
        equals(const BorderRadius.vertical(top: Radius.circular(16))),
      );

      // 裁切组件同步配置 16pt 顶部圆角
      final clipRRect = tester.widget<ClipRRect>(
        find.ancestor(
          of: find.byKey(const ValueKey('session-filter-sheet')),
          matching: find.byType(ClipRRect),
        ),
      );
      expect(
        clipRRect.borderRadius,
        equals(const BorderRadius.vertical(top: Radius.circular(16))),
      );

      // 分组卡片：14pt 圆角 + 1px separator 边框
      final section = tester.widget<CupertinoListSection>(
        find.byKey(const ValueKey('filter-section-sessions')),
      );
      final cardDec = section.decoration as BoxDecoration;
      expect(cardDec.borderRadius, equals(BorderRadius.circular(14)));
      expect(cardDec.border, isNotNull);
      expect(cardDec.border!.top.width, equals(1.0));
      expect(
        cardDec.border!.top.color,
        equals(
          CupertinoColors.separator.resolveFrom(tester.element(
            find.byKey(const ValueKey('filter-section-sessions')),
          )),
        ),
      );
    });

    testWidgets('宽屏下居中盒保留圆角且约束最大宽度 480', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final api = FakeSessionListApi(
        sessions: [session('s1', '普通会话')],
      );
      await pumpList(tester, api);
      await tester.tap(
        find.byKey(const ValueKey('session-list-filter-trigger')),
      );
      await tester.pumpAndSettle();

      final sheet = find.byKey(const ValueKey('session-filter-sheet'));
      expect(sheet, findsOneWidget);
      final sheetRect = tester.getRect(sheet);
      expect(sheetRect.width, equals(480.0));
      // 居中于 1200 宽屏（left 应为 (1200 - 480) / 2 = 360）
      expect(sheetRect.left, closeTo(360.0, 1.0));

      // 居中盒自身带有 16pt 顶部圆角裁切
      final clip = tester.widget<ClipRRect>(
        find.ancestor(of: sheet, matching: find.byType(ClipRRect)),
      );
      expect(
        clip.borderRadius,
        equals(const BorderRadius.vertical(top: Radius.circular(16))),
      );
    });
  });

  group('subagent 显示开关（默认关闭）', () {
    SessionSummary subagentSession(String id, String title) {
      return SessionSummary(
        sessionId: id,
        title: title,
        sourceLabel: 'Subagent',
        sourceTag: 'subagent',
        rawSource: 'subagent',
        createdAt: (DateTime.now().millisecondsSinceEpoch / 1000) - 1800,
      );
    }

    // #27 症状 A 实证：服务端委派 subagent 子会话 source 四字段不保证含
    // 'subagent'（session_source 归一为 'other'），仅 title 带 Subagent 字样
    // → title-only fixture：source 无 subagent 标记，仅标题「Subagent Session」。
    SessionSummary titleOnlySubagentSession(String id, String title) {
      return SessionSummary(
        sessionId: id,
        title: title,
        sessionSource: 'other',
        createdAt: (DateTime.now().millisecondsSinceEpoch / 1000) - 1800,
      );
    }

    testWidgets('默认关闭：开关为 off，Subagent 渠道不出现', (tester) async {
      final api = FakeSessionListApi(
        sessions: [
          session('s1', '普通会话', sourceLabel: 'telegram'),
          subagentSession('sub1', '子代理会话'),
        ],
      );
      await pumpList(tester, api);
      await tester.tap(
        find.byKey(const ValueKey('session-list-filter-trigger')),
      );
      await tester.pumpAndSettle();

      final sw = tester.widget<CupertinoSwitch>(
        find.byKey(const ValueKey('session-filter-subagent-switch')),
      );
      expect(sw.value, isFalse);
      // 隐藏时渠道列表剔除 Subagent，普通渠道保留
      expect(find.byKey(const ValueKey('filter-chip-Subagent')), findsNothing);
      expect(
        find.byKey(const ValueKey('filter-chip-telegram')),
        findsOneWidget,
      );
      // 列表默认不展示子代理会话
      expect(find.text('子代理会话'), findsNothing);
    });

    testWidgets('切换开关：弹层不关闭、即时生效、持久化到 SharedPreferences', (tester) async {
      final api = FakeSessionListApi(
        sessions: [
          session('s1', '普通会话', sourceLabel: 'telegram'),
          subagentSession('sub1', '子代理会话'),
        ],
      );
      await pumpList(tester, api);
      await tester.tap(
        find.byKey(const ValueKey('session-list-filter-trigger')),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('session-filter-subagent-switch')),
      );
      await tester.pumpAndSettle();

      // 弹层保持打开，开关即时翻转
      expect(
        find.byKey(const ValueKey('session-filter-sheet')),
        findsOneWidget,
      );
      final sw = tester.widget<CupertinoSwitch>(
        find.byKey(const ValueKey('session-filter-subagent-switch')),
      );
      expect(sw.value, isTrue);
      // Subagent 渠道恢复出现
      expect(
        find.byKey(const ValueKey('filter-chip-Subagent')),
        findsOneWidget,
      );
      // 持久化
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('session_list_show_subagent'), isTrue);

      // 关闭弹层后列表展示子代理会话
      await tester.tap(
        find.byKey(const ValueKey('session-filter-sheet-close')),
      );
      await tester.pumpAndSettle();
      expect(find.text('子代理会话'), findsOneWidget);
      expect(find.text('普通会话'), findsOneWidget);
    });

    testWidgets('预置 prefs=true：打开弹层开关即开，Subagent 渠道出现', (tester) async {
      SharedPreferences.setMockInitialValues({
        'session_list_show_subagent': true,
      });
      final api = FakeSessionListApi(
        sessions: [
          session('s1', '普通会话', sourceLabel: 'telegram'),
          subagentSession('sub1', '子代理会话'),
        ],
      );
      await pumpList(tester, api);
      await tester.tap(
        find.byKey(const ValueKey('session-list-filter-trigger')),
      );
      await tester.pumpAndSettle();

      final sw = tester.widget<CupertinoSwitch>(
        find.byKey(const ValueKey('session-filter-subagent-switch')),
      );
      expect(sw.value, isTrue);
      expect(
        find.byKey(const ValueKey('filter-chip-Subagent')),
        findsOneWidget,
      );
    });

    testWidgets('#27 title-only：关闭开关隐藏仅标题带 Subagent 的会话（含搜索命中）',
        (tester) async {
      final api = FakeSessionListApi(
        sessions: [
          session('s1', '普通会话', sourceLabel: 'telegram'),
          titleOnlySubagentSession('sub1', 'Subagent Session'),
        ],
      );
      await pumpList(tester, api);
      // 默认关闭：列表不展示标题含 Subagent 的会话
      expect(find.text('Subagent Session'), findsNothing);
      expect(find.text('普通会话'), findsOneWidget);

      // 打开开关 → 恢复显示
      await tester.tap(
        find.byKey(const ValueKey('session-list-filter-trigger')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('session-filter-subagent-switch')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('session-filter-sheet-close')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Subagent Session'), findsOneWidget);

      // 再关回 → 隐藏
      await tester.tap(
        find.byKey(const ValueKey('session-list-filter-trigger')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('session-filter-subagent-switch')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('session-filter-sheet-close')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Subagent Session'), findsNothing);

      // 搜索命中同样被过滤（关闭状态下）
      api.searchResults['Subagent'] = [
        titleOnlySubagentSession('sub1', 'Subagent Session'),
      ];
      await tester.enterText(
        find.byKey(const ValueKey('session-list-search')),
        'Subagent',
      );
      // 防抖窗口 + 搜索完成
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump();
      await tester.pump();
      expect(find.text('Subagent Session'), findsNothing);
    });
  });
}

class _FakeProjectApi implements ProjectApi {
  _FakeProjectApi({this.projects = const []});

  List<ProjectSummary> projects;

  @override
  Future<ProjectsResponse> fetchProjects() async =>
      ProjectsResponse(projects: projects);

  @override
  Future<ProjectMutationResponse> createProject({
    required String name,
    String? color,
  }) async => const ProjectMutationResponse(ok: true, project: null);

  @override
  Future<ProjectMutationResponse> deleteProject(String projectId) async =>
      const ProjectMutationResponse();

  @override
  Future<ProjectMutationResponse> renameProject({
    required String projectId,
    required String name,
    String? color,
  }) async => const ProjectMutationResponse();
}
