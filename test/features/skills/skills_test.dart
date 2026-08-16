import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hermex_flutter/core/api/api_client.dart';
import 'package:hermex_flutter/core/api/api_exception.dart';
import 'package:hermex_flutter/core/connections/connection_providers.dart';
import 'package:hermex_flutter/core/models/skills.dart';
import 'package:hermex_flutter/features/skills/skills_api.dart';
import 'package:hermex_flutter/features/skills/skills_page.dart';
import 'package:hermex_flutter/features/skills/skills_providers.dart';

import '../../helpers/fake_skills_api.dart';

SkillSummary buildSkill(
  String name, {
  String? category,
  String? description,
  List<String>? tags,
  bool? disabled,
  String? path,
  List<String>? relatedSkills,
}) {
  return SkillSummary(
    name: name,
    category: category,
    description: description,
    tags: tags,
    disabled: disabled,
    path: path,
    relatedSkills: relatedSkills,
  );
}

/// 组装 ProviderContainer：注入 fake API（apiClientProvider 用占位客户端，
/// 工厂 override 忽略它，不发任何网络请求）。
ProviderContainer makeContainer(FakeSkillsApi api) {
  final container = ProviderContainer(
    overrides: [
      apiClientProvider.overrideWithValue(
        ApiClient(baseUrl: 'http://test.local:30002'),
      ),
      skillsApiFactoryProvider.overrideWithValue((_) => api),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('buildSkillGroups 分组与过滤', () {
    test('按分类分组：分类名升序，组内按展示名升序（大小写不敏感）', () {
      final skills = [
        buildSkill('beta', category: '工具'),
        buildSkill('alpha', category: '工具'),
        buildSkill('zeta', category: 'Agent'),
        buildSkill('omega', category: 'Agent'),
      ];
      final groups = buildSkillGroups(skills);

      expect(groups.map((g) => g.title).toList(), ['Agent', '工具']);
      expect(groups[0].skills.map((s) => s.name).toList(), ['omega', 'zeta']);
      expect(groups[1].skills.map((s) => s.name).toList(), ['alpha', 'beta']);
    });

    test('无分类技能 → 「未分类」分组', () {
      final groups = buildSkillGroups([
        buildSkill('x'),
        buildSkill('y', category: '  '),
      ]);
      expect(groups.map((g) => g.title).toList(), ['未分类']);
      expect(groups.single.skills, hasLength(2));
    });

    test('空输入 / 空查询 → 空分组 / 全部分组', () {
      expect(buildSkillGroups(const []), isEmpty);
      expect(buildSkillGroups([buildSkill('a')], query: '  '), hasLength(1));
    });

    test('搜索：名称 / 描述 / 分类 / 标签任一命中，大小写不敏感', () {
      final skills = [
        buildSkill('bug-finder', description: '查找并修复 bug', tags: ['debug']),
        buildSkill('writer', description: '写文档', tags: ['docs']),
        buildSkill('tool-a', category: 'media'),
        buildSkill('plain', description: 'x'),
      ];
      expect(
        buildSkillGroups(skills, query: 'bug').single.skills.single.name,
        'bug-finder',
      );
      expect(
        buildSkillGroups(skills, query: '写文档').single.skills.single.name,
        'writer',
      );
      expect(
        buildSkillGroups(skills, query: 'MEDIA').single.skills.single.name,
        'tool-a',
      );
      expect(
        buildSkillGroups(skills, query: 'debug').single.skills.single.name,
        'bug-finder',
      );
      expect(buildSkillGroups(skills, query: 'no-such'), isEmpty);
    });
  });

  group('SkillsController 状态机', () {
    test('初始加载成功：AsyncData + 技能列表 + 派生分组', () async {
      final api = FakeSkillsApi(skills: [buildSkill('a'), buildSkill('b')]);
      final container = makeContainer(api);

      await container.read(skillsControllerProvider.future);
      final state = container.read(skillsControllerProvider).valueOrNull!;

      expect(api.fetchCount, 1);
      expect(state.skills, hasLength(2));
      expect(state.searchQuery, isNull);
      expect(container.read(skillsGroupsProvider).single.title, '未分类');
    });

    test('初始加载失败 → AsyncError；refresh 重试成功', () async {
      final api = FakeSkillsApi(skills: [buildSkill('a')]);
      api.fetchError = NetworkException(NetworkExceptionKind.cannotConnect);
      final container = makeContainer(api);

      await expectLater(
        container.read(skillsControllerProvider.future),
        throwsA(isA<ApiException>()),
      );
      expect(container.read(skillsControllerProvider).hasError, isTrue);
      expect(container.read(skillsControllerProvider).valueOrNull, isNull);

      api.fetchError = null;
      await container.read(skillsControllerProvider.notifier).refresh();

      expect(
        container.read(skillsControllerProvider).valueOrNull!.skills,
        hasLength(1),
      );
    });

    test('refresh 重新拉取并保留搜索词', () async {
      final api = FakeSkillsApi(skills: [buildSkill('a')]);
      final container = makeContainer(api);
      await container.read(skillsControllerProvider.future);
      final controller = container.read(skillsControllerProvider.notifier);

      controller.setSearchQuery('a');
      expect(
        container.read(skillsControllerProvider).valueOrNull!.searchQuery,
        'a',
      );

      await controller.refresh();
      expect(api.fetchCount, 2);
      expect(
        container.read(skillsControllerProvider).valueOrNull!.searchQuery,
        'a',
      );
    });

    test('setSearchQuery：本地过滤；空串退出过滤', () async {
      final api = FakeSkillsApi(
        skills: [
          buildSkill('bug'),
          buildSkill('writer', description: '写文档'),
        ],
      );
      final container = makeContainer(api);
      await container.read(skillsControllerProvider.future);
      final controller = container.read(skillsControllerProvider.notifier);

      controller.setSearchQuery('bug');
      expect(
        container.read(skillsGroupsProvider).single.skills.single.name,
        'bug',
      );

      controller.setSearchQuery('');
      expect(
        container.read(skillsControllerProvider).valueOrNull!.searchQuery,
        isNull,
      );
      expect(container.read(skillsGroupsProvider).single.skills, hasLength(2));
    });
  });

  group('SkillsPage widget', () {
    Future<void> pumpSkillsPage(WidgetTester tester, FakeSkillsApi api) async {
      final router = GoRouter(
        initialLocation: '/',
        routes: [GoRoute(path: '/', builder: (_, _) => const SkillsPage())],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(
              ApiClient(baseUrl: 'http://test.local:30002'),
            ),
            skillsApiFactoryProvider.overrideWithValue((_) => api),
          ],
          child: CupertinoApp.router(routerConfig: router),
        ),
      );
      // 首帧（AsyncLoading）+ 异步 build 完成（AsyncData）
      await tester.pump();
      await tester.pump();
    }

    testWidgets('渲染：分类标题 + 技能行（名称/描述/标签/已禁用徽标）', (tester) async {
      final api = FakeSkillsApi(
        skills: [
          buildSkill(
            'bug-finder',
            category: '调试',
            description: '查找并修复 bug',
            tags: ['debug'],
            disabled: true,
          ),
          buildSkill('writer', category: '调试', description: '写文档'),
        ],
      );
      await pumpSkillsPage(tester, api);

      expect(find.text('调试'), findsOneWidget);
      expect(find.text('bug-finder'), findsOneWidget);
      expect(find.text('查找并修复 bug'), findsOneWidget);
      expect(find.text('debug'), findsOneWidget);
      expect(find.text('已禁用'), findsOneWidget);
      expect(find.text('writer'), findsOneWidget);
      expect(find.text('写文档'), findsOneWidget);
    });

    testWidgets('加载态：数据到达前显示 ActivityIndicator，到达后渲染列表', (tester) async {
      final api = FakeSkillsApi(skills: [buildSkill('到了')]);
      api.fetchGate = Completer<void>();
      await pumpSkillsPage(tester, api);

      expect(find.byType(CupertinoActivityIndicator), findsOneWidget);

      api.fetchGate!.complete();
      await tester.pump();
      await tester.pump();
      expect(find.text('到了'), findsOneWidget);
      expect(find.byType(CupertinoActivityIndicator), findsNothing);
    });

    testWidgets('空态：暂无技能', (tester) async {
      await pumpSkillsPage(tester, FakeSkillsApi());

      expect(find.text('暂无技能'), findsOneWidget);
      expect(find.text('服务器的技能将显示在这里'), findsOneWidget);
    });

    testWidgets('错误态：加载失败展示错误信息，重试恢复', (tester) async {
      final api = FakeSkillsApi(skills: [buildSkill('恢复的技能')]);
      api.fetchError = NetworkException(NetworkExceptionKind.cannotConnect);
      await pumpSkillsPage(tester, api);

      expect(find.text('加载失败'), findsOneWidget);
      expect(find.textContaining('无法连接'), findsOneWidget);

      api.fetchError = null;
      await tester.tap(find.byKey(const ValueKey('skills-retry')));
      await tester.pump();
      await tester.pump();

      expect(find.text('恢复的技能'), findsOneWidget);
      expect(find.text('加载失败'), findsNothing);
    });

    testWidgets('搜索：输入即本地过滤；清空恢复全部', (tester) async {
      final api = FakeSkillsApi(
        skills: [
          buildSkill('bug-finder', description: '修复 bug'),
          buildSkill('writer', description: '写文档'),
        ],
      );
      await pumpSkillsPage(tester, api);
      expect(find.text('writer'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('skills-search')),
        'bug',
      );
      await tester.pump();
      expect(find.text('bug-finder'), findsOneWidget);
      expect(find.text('writer'), findsNothing);

      await tester.enterText(find.byKey(const ValueKey('skills-search')), '');
      await tester.pump();
      expect(find.text('writer'), findsOneWidget);
    });

    testWidgets('搜索无结果：未找到相关技能', (tester) async {
      final api = FakeSkillsApi(skills: [buildSkill('bug-finder')]);
      await pumpSkillsPage(tester, api);

      await tester.enterText(
        find.byKey(const ValueKey('skills-search')),
        'zzz',
      );
      await tester.pump();
      expect(find.text('未找到相关技能'), findsOneWidget);
    });

    testWidgets('点击行展开详情（路径/相关技能），再点收起', (tester) async {
      final api = FakeSkillsApi(
        skills: [
          buildSkill(
            'bug-finder',
            description: '修复 bug',
            path: '/skills/bug-finder',
            relatedSkills: ['writer'],
          ),
        ],
      );
      await pumpSkillsPage(tester, api);
      expect(find.textContaining('路径'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('skills-row-bug-finder')));
      await tester.pump();
      expect(find.text('路径：/skills/bug-finder'), findsOneWidget);
      expect(find.text('相关技能：writer'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('skills-row-bug-finder')));
      await tester.pump();
      expect(find.textContaining('路径'), findsNothing);
    });

    testWidgets('无详情技能展开：显示占位文案', (tester) async {
      final api = FakeSkillsApi(skills: [buildSkill('plain')]);
      await pumpSkillsPage(tester, api);

      await tester.tap(find.byKey(const ValueKey('skills-row-plain')));
      await tester.pump();
      expect(find.text('该技能没有更多详情'), findsOneWidget);
    });

    testWidgets('刷新按钮：重新拉取列表', (tester) async {
      final api = FakeSkillsApi(skills: [buildSkill('a')]);
      await pumpSkillsPage(tester, api);
      expect(api.fetchCount, 1);

      await tester.tap(find.byKey(const ValueKey('skills-refresh')));
      await tester.pump();
      await tester.pump();
      expect(api.fetchCount, 2);
    });
  });
}
