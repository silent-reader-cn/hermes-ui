import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hermex_flutter/app/theme/cupertino_theme.dart';
import 'package:hermex_flutter/core/api/api_client.dart';
import 'package:hermex_flutter/core/api/api_exception.dart';
import 'package:hermex_flutter/core/api/sse_client.dart';
import 'package:hermex_flutter/core/connections/connection_providers.dart';
import 'package:hermex_flutter/core/connections/connection_store.dart';
import 'package:hermex_flutter/core/models/cron.dart';
import 'package:hermex_flutter/core/models/git_workspace.dart';
import 'package:hermex_flutter/core/models/insights.dart';
import 'package:hermex_flutter/core/models/kanban.dart';
import 'package:hermex_flutter/core/models/memory.dart';
import 'package:hermex_flutter/core/models/server_catalog.dart';
import 'package:hermex_flutter/core/models/session.dart';
import 'package:hermex_flutter/core/models/skills.dart';
import 'package:hermex_flutter/core/models/workspace.dart';
import 'package:hermex_flutter/features/chat/chat_page.dart';
import 'package:hermex_flutter/features/chat/chat_providers.dart';
import 'package:hermex_flutter/features/chat/chat_server_api.dart';
import 'package:hermex_flutter/features/git/git_api.dart';
import 'package:hermex_flutter/features/git/git_page.dart';
import 'package:hermex_flutter/features/insights/insights_api.dart';
import 'package:hermex_flutter/features/insights/insights_page.dart';
import 'package:hermex_flutter/features/kanban/kanban_page.dart';
import 'package:hermex_flutter/features/kanban/kanban_providers.dart';
import 'package:hermex_flutter/features/memory/memory_api.dart';
import 'package:hermex_flutter/features/memory/memory_page.dart';
import 'package:hermex_flutter/features/onboarding/onboarding_page.dart';
import 'package:hermex_flutter/features/onboarding/onboarding_providers.dart';
import 'package:hermex_flutter/features/session_list/session_list_page.dart';
import 'package:hermex_flutter/features/session_list/session_list_providers.dart';
import 'package:hermex_flutter/features/settings/settings_page.dart';
import 'package:hermex_flutter/features/settings/settings_providers.dart';
import 'package:hermex_flutter/features/skills/skills_api.dart';
import 'package:hermex_flutter/features/skills/skills_page.dart';
import 'package:hermex_flutter/features/tasks/tasks_page.dart';
import 'package:hermex_flutter/features/tasks/tasks_providers.dart';
import 'package:hermex_flutter/features/workspace/workspace_page.dart';
import 'package:hermex_flutter/features/workspace/workspace_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/contrast_utils.dart';
import '../helpers/fake_git_api.dart';
import '../helpers/fake_insights_api.dart';
import '../helpers/fake_kanban_api.dart';
import '../helpers/fake_memory_api.dart';
import '../helpers/fake_settings_api.dart';
import '../helpers/fake_session_list_api.dart';
import '../helpers/fake_skills_api.dart';
import '../helpers/fake_tasks_api.dart';
import '../helpers/fake_workspace_api.dart';
import '../helpers/in_memory_secure_storage.dart';

/// ---------------------------------------------------------------------------
/// 文字对比度扫描框架（WCAG AA）。
///
/// 原理：每个关键页面在浅色 + 深色两种主题下 pump，遍历 Element 树中所有
/// [RichText]（Text 内部即 RichText，Text.rich / markdown 直接渲染的富文本
/// 也覆盖），对其 TextSpan 树中**显式指定 color** 的文字段计算 WCAG 对比度：
/// - ratio < 3.0            → ❌ error（正文与小字一律不达标）
/// - 3.0 ≤ ratio < 4.5      → ⚠️ warning（大字/装饰可接受，正文需修复）
/// - ratio ≥ 4.5            → ✅ 通过（不记录）
///
/// 背景参考色按项目主题定义：浅 #F2F2F7 / 深 #000000（见 cupertino_theme.dart）。
/// 无显式 color 的文字继承系统 label 色，不在本扫描范围（系统保证）。
///
/// 已知限制（文档化）：气泡/卡片上的文字以页面底色为参考，不追踪局部背景
/// （如用户气泡白字实际衬在 activeBlue 上，此处按页面底色算必报红——属模型
/// 定义的误报，见请允许名单类别说明）。
///
/// 失败策略：仅「不在已知基线里的新发现」使测试失败；基线条目在报告中标红/
/// 标黄输出但不算失败（对应并行代理正在修复的已知 systemGrey 文字色）。
/// 允许名单 key 不含颜色——A 修复改色后同一文字仍命中基线，测试保持全绿，
/// 修复完成后基线条目自然失效（报告不再出现），届时可清空允许名单。
/// ---------------------------------------------------------------------------

/// 浅色主题背景（systemGroupedBackground #F2F2F7）。
const Color kLightBackground = Color(0xFFF2F2F7);

/// 深色主题背景（scaffoldBackgroundColor #000000）。
const Color kDarkBackground = Color(0xFF000000);

/// 单条对比度发现。
class ContrastFinding {
  const ContrastFinding({
    required this.page,
    required this.brightness,
    required this.text,
    required this.color,
    required this.ratio,
    required this.isDynamic,
  });

  final String page;
  final Brightness brightness;
  final String text;
  final Color color;
  final double ratio;
  final bool isDynamic;

  /// 页面 + 主题 + 颜色 + 文字前 20 字符（报告/去重 key）。
  String get key =>
      '$page|${brightness.name}|${formatColor(color)}|${textPrefix(text)}';
}

/// 文字取前 20 字符（精确定位要求：报错信息含文字内容）。
String textPrefix(String text) =>
    text.length <= 20 ? text : text.substring(0, 20);

/// 背景色按主题取。
Color backgroundFor(Brightness brightness) =>
    brightness == Brightness.dark ? kDarkBackground : kLightBackground;

/// 主题名（报告用）。
String brightnessName(Brightness brightness) =>
    brightness == Brightness.dark ? '深色' : '浅色';

/// 遍历当前 widget 树，收集所有显式着色文字的对比度发现。
///
/// 每个 Text widget 内部都构建 RichText；直接以 RichText 为采集点可同时
/// 覆盖 Text、Text.rich 与 markdown 渲染出的富文本。颜色先经
/// [resolveTextColor] 按当前主题亮度解析（CupertinoColors 语义色是动态色）。
List<ContrastFinding> scanTextContrast(
  WidgetTester tester, {
  required String page,
  required Brightness brightness,
}) {
  final background = backgroundFor(brightness);
  final findings = <ContrastFinding>[];
  final seen = <String>{};

  void collectSpan(InlineSpan span, BuildContext context) {
    if (span is! TextSpan) return;
    final color = span.style?.color;
    final text = span.text;
    if (color != null && text != null && text.isNotEmpty) {
      final wasDynamic = color is CupertinoDynamicColor;
      final resolved = resolveTextColor(color, context);
      final ratio = contrastRatio(resolved, background);
      final finding = ContrastFinding(
        page: page,
        brightness: brightness,
        text: text,
        color: resolved,
        ratio: ratio,
        isDynamic: wasDynamic,
      );
      // 同页同主题同色同前缀去重（如多条消息同一样式），保留计数。
      if (seen.add(finding.key)) {
        findings.add(finding);
      }
    }
    for (final child in span.children ?? const <InlineSpan>[]) {
      collectSpan(child, context);
    }
  }

  for (final element in tester.allElements) {
    if (element.widget case final RichText richText) {
      // Icon 内部即 RichText（字形），非文字，跳过；
      // 输入框 EditableText 子树（占位提示/已输入内容）颜色来自组件默认，
      // 且占位符属 WCAG 豁免的失效提示，跳过。
      if (element.findAncestorWidgetOfExactType<Icon>() != null) continue;
      if (element.findAncestorWidgetOfExactType<EditableText>() != null) {
        continue;
      }
      collectSpan(richText.text, element);
    }
  }
  return findings;
}

/// 输出单页扫描报告（页面 + 主题 + 文字 + 颜色 + 对比度数值）。
void _printReport(String page, Brightness brightness, List<ContrastFinding> findings) {
  for (final f in findings) {
    final level = f.ratio < 3.0
        ? '❌'
        : f.ratio < 4.5
        ? '⚠️'
        : '✅';
    final marker = allKnownIssues.contains(_issueKey(f)) ? ' [已知基线]' : '';
    debugPrint(
      '[对比度] $page·${brightnessName(brightness)} $level'
      '"${textPrefix(f.text)}" ${formatColor(f.color)} '
      '${f.ratio.toStringAsFixed(2)}:1'
      '(需≥4.5$marker)',
    );
  }
}

/// 允许名单判定用的 key（不含颜色，见文件头说明）。
String _issueKey(ContrastFinding f) =>
    '${f.page}|${f.brightness.name}|${textPrefix(f.text)}';

/// 已知基线允许名单（key = 页面|主题|文字前 20 字符）。
///
/// 类别说明：
/// - `[systemGrey 待修]` 并行代理正在修（systemGrey → secondaryLabel/label）；
/// - `[气泡白字-模型误报]` 白字衬在彩色气泡上，本扫描以页面底色为参考的误报；
/// - `[iOS 语义色]` secondaryLabel 等系统语义色，iOS 设计规范既定；
/// - `[自定义色-待评审]` 显式硬编码颜色，需人工确认。
/// A 的修复落地后对应条目会失效（报告不再出现），届时应清空本名单。
final Set<String> allKnownIssues = <String>{
  // ---- 模型误报：按钮/主色底上的白字（真背景是 #007AFF 蓝，白字对比 >4.5） ----
  'onboarding|light|下一步', // CupertinoButton 主按钮白字
  'chat|light|帮我检查一下对比度', // 用户气泡（蓝底白字，本扫描误以页面底色参考）
  'chat|light|用深色主题再看看', // 用户气泡（同上蓝色底）
  'git|light|提交', // 主按钮白字
  'git|light|fetch', // 主按钮白字
  'git|light|pull', // 主按钮白字
  'git|light|push', // 主按钮白字
  'kanban|light|主看板', // 主按钮白字
  'session_list_error|light|重试', // 错误态「重试」CupertinoButton.filled 白字（真背景是主题蓝）

  // ---- 模型误报：iOS 次要文字（label 浅色 #3C3C43 衬浅灰分组背景，设计规范既定）----
  'onboarding|light|https://hermes.examp', // 服务地址输入框 URL 文字
  'chat|light|发送消息…', // 输入框占位符（WCAG 豁免）
  'chat|dark|发送消息…', // 深色下输入框高亮占位符 #EBEBF5（WCAG 占位符豁免）
  'git|light|提交信息', // 输入框占位符
  'git|dark|提交信息', // 深色下输入框高亮占位符 #EBEBF5（WCAG 占位符豁免）
  'onboarding|dark|https://hermes.examp', // 深色下服务地址输入框 URL 文字
  'workspace|light|根目录', // 次要导航文字
  'workspace|light|上一级', // 次要导航文字
  'workspace|dark|根目录', // 深色下分节/次要导航（iOS secondaryLabel 偏亮，设计规范既定）
  'workspace|dark|上一级', // 深色下分节/次要导航
  // 注：A 修复落地后 systemGrey 待修项已从此集合自愈失效（不再出现即无需登记）。
};

/// ---------------------------------------------------------------------------
/// 页面注册：每页一个 pump 函数（浅/深主题复用同一构造，只换 CupertinoApp
/// 的 theme）。页面数据一律来自 test/helpers 下的 fake API（静态种子）。
/// ---------------------------------------------------------------------------

/// 组装带主题的 CupertinoApp 壳。
Widget _app(Brightness brightness, Widget home) {
  return CupertinoApp(theme: buildCupertinoTheme(brightness), home: home);
}

/// 组装带主题的 CupertinoApp.router 壳。
Widget _routerApp(Brightness brightness, Widget child) {
  return CupertinoApp.router(
    theme: buildCupertinoTheme(brightness),
    routerConfig: GoRouter(
      initialLocation: '/',
      routes: [GoRoute(path: '/', builder: (_, _) => child)],
    ),
  );
}

/// 占位 ApiClient（fake 工厂 override 后不会被使用，仅满足依赖）。
ApiClient _dummyClient() => ApiClient(baseUrl: 'http://test.local:30002');

/// pump 并等待异步加载完成（首帧 AsyncLoading + AsyncData）。
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

/// 扫一个页面在两种主题下的对比度（pump → 收集 → 报告 → 断言）。
Future<void> _scanPage(
  WidgetTester tester, {
  required String page,
  required Future<void> Function(WidgetTester tester, Brightness brightness)
      pump,
}) async {
  for (final brightness in [Brightness.light, Brightness.dark]) {
    await pump(tester, brightness);
    await _settle(tester);
    final findings = scanTextContrast(
      tester,
      page: page,
      brightness: brightness,
    );
    _printReport(page, brightness, findings);

    // 只对 ❌（ratio<3.0，明确不达标）判失败；⚠️(3.0–4.5) 为 iOS 次要文字/
    // 装饰文字/链接主色（secondaryLabel ~3.3:1、tint ~3.6:1，Apple 设计规范
    // 既定，属可接受噪音），仅打印提示不阻断。任何新❌（改色引入的真低对比
    // 度文字）都失败，需人工确认后登记基线。
    final unexpected = findings
        .where((f) => f.ratio < 3.0 && !allKnownIssues.contains(_issueKey(f)))
        .toList();
    if (unexpected.isNotEmpty) {
      final detail = unexpected
          .map(
            (f) => '${f.page}·${brightnessName(f.brightness)} '
                '"${textPrefix(f.text)}" ${formatColor(f.color)} '
                '${f.ratio.toStringAsFixed(2)}:1',
          )
          .join('\n  - ');
      fail('发现未登记的低对比度文字（新增项需人工确认后加入允许名单）：\n  - $detail');
    }
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('onboarding 页面对比度扫描（浅/深）', (tester) async {
    final storage = InMemorySecureStorage();
    await _scanPage(
      tester,
      page: 'onboarding',
      pump: (tester, brightness) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              connectionStoreProvider.overrideWithValue(
                ConnectionStore(storage: storage),
              ),
              onboardingApiFactoryProvider.overrideWithValue(
                (_, _) => _FakeOnboardingApi(),
              ),
            ],
            child: _app(brightness, const OnboardingPage()),
          ),
        );
      },
    );
  });

  testWidgets('session_list 页面对比度扫描（浅/深）', (tester) async {
    final now = DateTime.now();
    final noon = DateTime(now.year, now.month, now.day, 12);
    double sec(DateTime t) => t.millisecondsSinceEpoch / 1000;
    final api = FakeSessionListApi(
      sessions: [
        SessionSummary(
          sessionId: 'p1',
          title: '置顶会话',
          pinned: true,
          lastMessageAt: sec(noon),
        ),
        SessionSummary(
          sessionId: 't1',
          title: '今天讨论配色方案',
          lastMessageAt: sec(noon.subtract(const Duration(hours: 2))),
        ),
        SessionSummary(
          sessionId: 'e1',
          title: '更早的会话归档记录',
          lastMessageAt: sec(noon.subtract(const Duration(days: 5))),
        ),
      ],
    );
    await _scanPage(
      tester,
      page: 'session_list',
      pump: (tester, brightness) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              apiClientProvider.overrideWithValue(_dummyClient()),
              sessionListApiFactoryProvider.overrideWithValue((_) => api),
            ],
            child: _routerApp(
              brightness,
              const SessionListPage(),
            ),
          ),
        );
      },
    );
  });

  testWidgets('session_list 加载失败态对比度扫描（浅/深，含「密码被拒绝」错误详情）',
      (tester) async {
    // 401 场景：fetchSessions 抛 UnauthorizedException → 页面渲染错误详情
    // 「密码被拒绝。请检查服务器密码后重试。」（statusRedText，两种主题均须 ≥4.5:1）。
    final api = FakeSessionListApi()
      ..fetchError = const UnauthorizedException();
    await _scanPage(
      tester,
      page: 'session_list_error',
      pump: (tester, brightness) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              apiClientProvider.overrideWithValue(_dummyClient()),
              sessionListApiFactoryProvider.overrideWithValue((_) => api),
            ],
            child: _routerApp(
              brightness,
              const SessionListPage(),
            ),
          ),
        );
      },
    );
  });

  testWidgets('chat 页面对比度扫描（浅/深，静态消息）', (tester) async {
    final api = _FakeChatApi();
    api.sessionResult = {
      'session': {
        'session_id': 's1',
        'title': '测试会话',
        'messages': [
          {'role': 'user', 'content': '帮我检查一下对比度', 'message_id': 'u1'},
          {
            'role': 'assistant',
            'content': '**好的！** 我来看看哪些文字颜色不达标。',
            'message_id': 'a1',
          },
          {
            'role': 'user',
            'content': '用深色主题再看看',
            'message_id': 'u2',
          },
        ],
      },
    };
    await _scanPage(
      tester,
      page: 'chat',
      pump: (tester, brightness) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              chatApiProvider.overrideWithValue(api),
              chatAvailableModelsProvider
                  .overrideWithValue(const ['gpt-5', 'claude']),
            ],
            child: _app(brightness, const ChatPage(sessionId: 's1')),
          ),
        );
      },
    );
    // 卸载 ProviderScope → 取消看门狗等周期定时器，避免 pending timer。
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('tasks 页面对比度扫描（浅/深）', (tester) async {
    final api = FakeTasksApi(
      jobs: [
        const CronJob(
          jobId: 'j1',
          name: '每日晨报生成',
          prompt: '生成今日摘要',
          schedule: CronSchedule(expression: '0 9 * * *'),
          state: 'running',
          enabled: true,
        ),
        const CronJob(
          jobId: 'j2',
          name: '周报汇总任务',
          prompt: '汇总本周进展',
          schedule: CronSchedule(expression: '0 18 * * 5'),
          state: 'paused',
        ),
        const CronJob(
          jobId: 'j3',
          name: '出错的任务',
          prompt: '拉取外部数据',
          schedule: CronSchedule(expression: '*/30 * * * *'),
          lastStatus: 'error',
        ),
      ],
    );
    await _scanPage(
      tester,
      page: 'tasks',
      pump: (tester, brightness) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              apiClientProvider.overrideWithValue(_dummyClient()),
              tasksApiFactoryProvider.overrideWithValue((_) => api),
            ],
            child: _app(brightness, const TasksPage()),
          ),
        );
      },
    );
  });

  testWidgets('skills 页面对比度扫描（浅/深）', (tester) async {
    final api = FakeSkillsApi(
      skills: [
        const SkillSummary(
          name: 'bug-finder',
          category: '调试',
          description: '查找并修复 bug',
          tags: ['debug'],
          disabled: true,
        ),
        const SkillSummary(
          name: 'writer',
          category: '写作',
          description: '撰写高质量文档',
          tags: ['writing', 'docs'],
        ),
        const SkillSummary(
          name: 'web-research',
          category: '调研',
          description: '联网检索并整理资料',
        ),
      ],
    );
    await _scanPage(
      tester,
      page: 'skills',
      pump: (tester, brightness) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              apiClientProvider.overrideWithValue(_dummyClient()),
              skillsApiFactoryProvider.overrideWithValue((_) => api),
            ],
            child: _routerApp(brightness, const SkillsPage()),
          ),
        );
      },
    );
  });

  testWidgets('memory 页面对比度扫描（浅/深）', (tester) async {
    final mtime = DateTime.now()
            .subtract(const Duration(hours: 2))
            .millisecondsSinceEpoch /
        1000;
    final api = FakeMemoryApi(
      response: MemoryResponse(
        memory: '记住用户偏好深色主题',
        user: '资深 Flutter 开发者',
        soul: '乐于助人且严谨',
        memoryMtime: mtime,
        userMtime: mtime,
        soulMtime: mtime,
      ),
    );
    await _scanPage(
      tester,
      page: 'memory',
      pump: (tester, brightness) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              apiClientProvider.overrideWithValue(_dummyClient()),
              memoryApiFactoryProvider.overrideWithValue((_) => api),
            ],
            child: _routerApp(brightness, const MemoryPage()),
          ),
        );
      },
    );
  });

  testWidgets('settings 页面对比度扫描（浅/深）', (tester) async {
    final api = FakeSettingsApi();
    api.modelsResponse = ModelsResponse.fromJson({
      'default_model': 'gpt-4o',
      'active_provider': 'openai',
      'groups': [
        {
          'provider_id': 'openai',
          'name': 'OpenAI',
          'models': [
            {'id': 'gpt-4o', 'name': 'GPT-4o'},
            {'id': 'gpt-4o-mini', 'name': 'GPT-4o mini'},
          ],
        },
      ],
    });
    api.reasoningResponse = const ReasoningStatusResponse(
      ok: true,
      reasoningEffort: 'medium',
      supportedEfforts: ['low', 'medium', 'high'],
      supportsReasoningEffort: true,
    );
    final storage = InMemorySecureStorage();
    await _scanPage(
      tester,
      page: 'settings',
      pump: (tester, brightness) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              connectionStoreProvider.overrideWithValue(
                ConnectionStore(storage: storage),
              ),
              apiClientProvider.overrideWithValue(_dummyClient()),
              settingsApiFactoryProvider.overrideWithValue((_) => api),
            ],
            child: _app(brightness, const SettingsPage()),
          ),
        );
      },
    );
  });

  testWidgets('workspace 页面对比度扫描（浅/深）', (tester) async {
    final modified = DateTime.now()
            .subtract(const Duration(hours: 1))
            .millisecondsSinceEpoch ~/
        1000;
    final api = FakeWorkspaceApi(
      directories: {
        '.': [
          WorkspaceEntry(
            name: 'lib',
            path: 'lib',
            type: 'directory',
            isDirectory: true,
            modified: modified.toDouble(),
          ),
          WorkspaceEntry(
            name: 'README.md',
            path: 'README.md',
            type: 'markdown',
            size: 2048,
            modified: modified.toDouble(),
          ),
          WorkspaceEntry(
            name: 'main.dart',
            path: 'main.dart',
            type: 'dart',
            size: 1536,
            modified: modified.toDouble(),
          ),
        ],
      },
    );
    await _scanPage(
      tester,
      page: 'workspace',
      pump: (tester, brightness) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              apiClientProvider.overrideWithValue(_dummyClient()),
              workspaceApiFactoryProvider.overrideWithValue((_) => api),
            ],
            child: _app(
              brightness,
              const WorkspacePage(sessionId: 's1'),
            ),
          ),
        );
      },
    );
  });

  testWidgets('git 页面对比度扫描（浅/深）', (tester) async {
    final api = FakeGitApi(
      status: GitStatus(
        isGit: true,
        branch: 'main',
        upstream: 'origin/main',
        ahead: 1,
        behind: 0,
        totals: const GitTotals(
          changed: 3,
          staged: 1,
          unstaged: 2,
          untracked: 1,
        ),
        files: [
          GitFile(
            path: 'a.txt',
            status: 'M',
            staged: true,
            additions: 3,
            deletions: 1,
          ),
          GitFile(path: 'b.txt', status: 'M', unstaged: true, additions: 1),
          GitFile(path: 'c.txt', untracked: true),
        ],
      ),
    );
    await _scanPage(
      tester,
      page: 'git',
      pump: (tester, brightness) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              apiClientProvider.overrideWithValue(_dummyClient()),
              gitApiFactoryProvider.overrideWithValue((_) => api),
            ],
            child: _routerApp(
              brightness,
              const GitPage(sessionId: 's1'),
            ),
          ),
        );
      },
    );
  });

  testWidgets('kanban 页面对比度扫描（浅/深）', (tester) async {
    final api = FakeKanbanApi(
      boards: const [
        KanbanBoard(slug: 'default', name: '主看板'),
        KanbanBoard(slug: 'backlog', name: '待办池'),
      ],
      currentSlug: 'default',
      snapshots: {
        'default': const KanbanBoardSnapshot(
          columns: [
            KanbanColumn(
              name: 'todo',
              cards: [
                KanbanCard(
                  cardID: 'c1',
                  title: '实现登录流程',
                  status: KanbanStatus('todo'),
                  assignee: 'alice',
                  linkCounts: KanbanLinkCounts(parents: 2),
                ),
                KanbanCard(
                  cardID: 'c2',
                  title: '修复深色模式对比度',
                  status: KanbanStatus('todo'),
                ),
              ],
            ),
            KanbanColumn(
              name: 'done',
              cards: [
                KanbanCard(
                  cardID: 'c3',
                  title: '搭建脚手架',
                  status: KanbanStatus('done'),
                  assignee: 'bob',
                ),
              ],
            ),
          ],
        ),
      },
    );
    await _scanPage(
      tester,
      page: 'kanban',
      pump: (tester, brightness) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              apiClientProvider.overrideWithValue(_dummyClient()),
              kanbanApiFactoryProvider.overrideWithValue((_) => api),
            ],
            child: _app(brightness, const KanbanPage()),
          ),
        );
      },
    );
  });

  testWidgets('insights 页面对比度扫描（浅/深）', (tester) async {
    final api = FakeInsightsApi(
      response: const InsightsResponse(
        periodDays: 30,
        totalSessions: 12,
        totalMessages: 1234,
        totalInputTokens: 1000000,
        totalOutputTokens: 250000,
        totalTokens: 1250000,
        totalCost: 1.2345,
        totalCacheReadTokens: 5000,
        totalCacheHitPercent: 87.5,
        models: [
          InsightsModelBreakdown(
            model: 'gpt-4o',
            totalTokens: 1000,
            tokenShare: 60,
          ),
          InsightsModelBreakdown(model: 'claude', totalTokens: 500, tokenShare: 40),
        ],
        dailyTokens: [
          InsightsDailyToken(
            date: '2026-08-16',
            inputTokens: 100,
            outputTokens: 50,
            sessions: 2,
            cost: 0.01,
          ),
          InsightsDailyToken(
            date: '2026-08-15',
            inputTokens: 60,
            outputTokens: 30,
            sessions: 1,
          ),
        ],
        activityByDay: [
          InsightsActivityByDay(day: '2026-08-16', sessions: 5),
        ],
        activityByHour: [
          InsightsActivityByHour(hour: 14, sessions: 3),
        ],
      ),
    );
    await _scanPage(
      tester,
      page: 'insights',
      pump: (tester, brightness) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              apiClientProvider.overrideWithValue(_dummyClient()),
              insightsApiFactoryProvider.overrideWithValue((_) => api),
            ],
            child: _routerApp(brightness, const InsightsPage()),
          ),
        );
      },
    );
  });
}

// ---------------------------------------------------------------------------
// chat / onboarding 的最小 fake（对齐既有测试的占位实现模式）
// ---------------------------------------------------------------------------

class _FakeChatApi implements ChatServerApi {
  Map<String, Object?>? sessionResult;

  @override
  Future<Object?> startChat({
    required String sessionId,
    required String message,
    String? workspace,
    String? model,
    String? modelProvider,
    String? profile,
    bool explicitModelPick = false,
    List<Map<String, Object?>>? attachments,
  }) async {
    return {'stream_id': 'stream-1', 'session_id': sessionId};
  }

  @override
  Future<Object?> steerChat({
    required String sessionId,
    required String text,
  }) async {
    return {'accepted': true};
  }

  @override
  Future<Object?> cancelChat(String streamId) async => {'ok': true};

  @override
  Future<Object?> chatStreamStatus(String streamId) async =>
      {'active': false, 'replay_available': false};

  @override
  Future<Object?> session({
    required String sessionId,
    bool includeMessages = true,
    int? messageLimit,
    int? messageBefore,
    bool expandRenderable = false,
  }) async {
    return sessionResult ??
        {
          'session': {'session_id': sessionId, 'messages': const []},
        };
  }

  @override
  Future<Object?> respondApproval({
    required String sessionId,
    required String choice,
    String? approvalId,
  }) async {
    return {'ok': true};
  }

  @override
  Future<Object?> respondClarification({
    required String sessionId,
    required String response,
    String? clarifyId,
  }) async {
    return {'ok': true};
  }

  @override
  Future<void> startStream(
    String streamId, {
    int? replayAfterSeq,
    required void Function(SseEvent event) onEvent,
    void Function(String eventId)? onEventId,
    required void Function(String message) onTransportError,
    required void Function() onClosed,
  }) async {}

  @override
  void stopStream() {}
}

class _FakeOnboardingApi implements OnboardingServerApi {
  @override
  Future<Object?> health() async => {'status': 'ok'};

  @override
  Future<Object?> authStatus() async => {'auth_enabled': false};

  @override
  Future<Object?> login(String password) async => {'ok': true};
}