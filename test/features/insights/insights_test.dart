import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hermex_flutter/core/api/api_client.dart';
import 'package:hermex_flutter/core/api/api_exception.dart';
import 'package:hermex_flutter/core/connections/connection_providers.dart';
import 'package:hermex_flutter/core/models/insights.dart';
import 'package:hermex_flutter/features/insights/insights_api.dart';
import 'package:hermex_flutter/features/insights/insights_page.dart';
import 'package:hermex_flutter/features/insights/insights_providers.dart';

import '../../helpers/fake_insights_api.dart';

/// 组装 ProviderContainer：注入 fake API（apiClientProvider 用占位客户端，
/// 工厂 override 忽略它，不发任何网络请求）。
ProviderContainer makeContainer(FakeInsightsApi api) {
  final container = ProviderContainer(
    overrides: [
      apiClientProvider.overrideWithValue(
        ApiClient(baseUrl: 'http://test.local:30002'),
      ),
      insightsApiFactoryProvider.overrideWithValue((_) => api),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// 带完整指标的统计响应（页面 / 控制器测试共用）。
InsightsResponse sampleResponse() {
  return const InsightsResponse(
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
    activityByDay: [InsightsActivityByDay(day: '2026-08-16', sessions: 5)],
    activityByHour: [InsightsActivityByHour(hour: 14, sessions: 3)],
  );
}

void main() {
  group('Insights 模型 JSON 解析', () {
    test('snake_case 正常解析（真实服务器格式）', () {
      final response = InsightsResponse.fromJson({
        'period_days': 30,
        'total_sessions': 12,
        'total_messages': 1234,
        'total_input_tokens': 1000000,
        'total_output_tokens': 250000,
        'total_tokens': 1250000,
        'total_cost': 1.23,
        'total_cache_read_tokens': 5000,
        'total_cache_hit_percent': 87.5,
        'models': [
          {'model': 'gpt-4o', 'total_tokens': 1000, 'token_share': 60},
        ],
        'daily_tokens': [
          {'date': '2026-08-16', 'input_tokens': 100, 'output_tokens': 50},
        ],
        'activity_by_day': [
          {'day': '2026-08-16', 'sessions': 5},
        ],
        'activity_by_hour': [
          {'hour': 14, 'sessions': 3},
        ],
      });
      expect(response.periodDays, 30);
      expect(response.totalSessions, 12);
      expect(response.totalMessages, 1234);
      expect(response.totalInputTokens, 1000000);
      expect(response.totalCost, 1.23);
      expect(response.totalCacheHitPercent, 87.5);
      expect(response.models, hasLength(1));
      expect(response.models!.single.model, 'gpt-4o');
      expect(response.models!.single.displayShare, 60);
      expect(response.dailyTokens!.single.date, '2026-08-16');
      expect(response.dailyTokens!.single.totalTokens, 150);
      expect(response.activityByDay!.single.sessions, 5);
      expect(response.activityByHour!.single.hour, 14);
      expect(response.hasData, isTrue);
    });

    test('camelCase 别名兼容（Swift 模型键名）', () {
      final response = InsightsResponse.fromJson({
        'periodDays': 7,
        'totalSessions': 3,
        'models': [
          {'model': 'gpt-4o', 'totalTokens': 100, 'costShare': 80},
        ],
        'dailyTokens': [
          {'date': '2026-08-16', 'inputTokens': 10, 'outputTokens': 5},
        ],
      });
      expect(response.periodDays, 7);
      expect(response.totalSessions, 3);
      expect(response.models!.single.totalTokens, 100);
      expect(response.models!.single.displayShare, 80);
      expect(response.dailyTokens!.single.totalTokens, 15);
    });

    test('畸形输入容错：类型不符给安全默认值', () {
      final response = InsightsResponse.fromJson({
        'period_days': '三十',
        'total_sessions': '12',
        'total_cost': '1.5',
        'models': 'not-a-list',
        'daily_tokens': [
          {'date': 123, 'input_tokens': 'oops'},
        ],
      });
      expect(response.periodDays, isNull);
      expect(response.totalSessions, 12);
      expect(response.totalCost, 1.5);
      expect(response.models, isNull);
      // daily_tokens 逐项容错：date 数字 → '123'，input_tokens 非法 → null
      expect(response.dailyTokens, hasLength(1));
      expect(response.dailyTokens!.single.date, '123');
      expect(response.dailyTokens!.single.inputTokens, isNull);
      expect(response.hasData, isTrue);
      expect(InsightsResponse.fromJson({}).hasData, isFalse);
    });
  });

  group('InsightsController 状态机', () {
    test('初始加载成功：默认近 30 天，AsyncData 携带状态', () async {
      final api = FakeInsightsApi(response: sampleResponse());
      final container = makeContainer(api);

      final state = await container.read(insightsControllerProvider.future);
      expect(api.fetchCount, 1);
      expect(api.requestedDays, [30]);
      expect(state.timeframe, InsightsTimeframe.last30Days);
      expect(state.response.totalSessions, 12);
      expect(state.isLoading, isFalse);
    });

    test('初始加载失败 → AsyncError；refresh 重试成功', () async {
      final api = FakeInsightsApi(response: sampleResponse());
      api.fetchError = NetworkException(NetworkExceptionKind.cannotConnect);
      final container = makeContainer(api);

      await expectLater(
        container.read(insightsControllerProvider.future),
        throwsA(isA<ApiException>()),
      );
      expect(container.read(insightsControllerProvider).hasError, isTrue);

      api.fetchError = null;
      await container.read(insightsControllerProvider.notifier).refresh();
      final state = container.read(insightsControllerProvider).valueOrNull!;
      expect(state.response.totalSessions, 12);
      expect(api.fetchCount, 2);
    });

    test('refresh 按当前时间范围重新拉取', () async {
      final api = FakeInsightsApi(response: sampleResponse());
      final container = makeContainer(api);
      await container.read(insightsControllerProvider.future);

      await container
          .read(insightsControllerProvider.notifier)
          .setTimeframe(InsightsTimeframe.last7Days);
      expect(api.requestedDays, [30, 7]);

      await container.read(insightsControllerProvider.notifier).refresh();
      expect(api.requestedDays, [30, 7, 7]);
      expect(
        container.read(insightsControllerProvider).valueOrNull!.timeframe,
        InsightsTimeframe.last7Days,
      );
    });

    test('setTimeframe 切换范围重新拉取；相同范围不重复请求', () async {
      final api = FakeInsightsApi(response: sampleResponse());
      final container = makeContainer(api);
      await container.read(insightsControllerProvider.future);

      await container
          .read(insightsControllerProvider.notifier)
          .setTimeframe(InsightsTimeframe.today);
      expect(api.requestedDays, [30, 1]);
      expect(
        container.read(insightsControllerProvider).valueOrNull!.timeframe,
        InsightsTimeframe.today,
      );

      await container
          .read(insightsControllerProvider.notifier)
          .setTimeframe(InsightsTimeframe.today);
      expect(api.requestedDays, [30, 1]);
    });

    test('setTimeframe 失败 → AsyncError（回错误态可重试）', () async {
      final api = FakeInsightsApi(response: sampleResponse());
      final container = makeContainer(api);
      await container.read(insightsControllerProvider.future);

      api.fetchError = NetworkException(NetworkExceptionKind.timedOut);
      await container
          .read(insightsControllerProvider.notifier)
          .setTimeframe(InsightsTimeframe.allTime);
      expect(container.read(insightsControllerProvider).hasError, isTrue);

      api.fetchError = null;
      await container.read(insightsControllerProvider.notifier).refresh();
      expect(
        container.read(insightsControllerProvider).valueOrNull!.timeframe,
        InsightsTimeframe.allTime,
      );
      expect(api.requestedDays, [30, 365, 365]);
    });
  });

  group('InsightsPage widget', () {
    Future<void> pumpInsightsPage(
      WidgetTester tester,
      FakeInsightsApi api,
    ) async {
      final router = GoRouter(
        initialLocation: '/',
        routes: [GoRoute(path: '/', builder: (_, _) => const InsightsPage())],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(
              ApiClient(baseUrl: 'http://test.local:30002'),
            ),
            insightsApiFactoryProvider.overrideWithValue((_) => api),
          ],
          child: CupertinoApp.router(routerConfig: router),
        ),
      );
      // 首帧（AsyncLoading）+ 异步 build 完成（AsyncData）
      await tester.pump();
      await tester.pump();
    }

    testWidgets('渲染：指标卡片 + 模型拆分 + 柱状图 + 活动', (tester) async {
      final api = FakeInsightsApi(response: sampleResponse());
      await pumpInsightsPage(tester, api);

      expect(find.text('用量统计'), findsOneWidget);
      expect(find.text('会话'), findsOneWidget);
      expect(find.text('12'), findsOneWidget);
      expect(find.text('消息'), findsOneWidget);
      expect(find.text('1,234'), findsOneWidget);
      expect(find.text('输入令牌'), findsOneWidget);
      expect(find.text('1,000,000'), findsOneWidget);
      expect(find.text('输出令牌'), findsOneWidget);
      expect(find.text('250,000'), findsOneWidget);
      expect(find.text('总令牌'), findsOneWidget);
      expect(find.text('1,250,000'), findsOneWidget);
      expect(find.text('估算费用'), findsOneWidget);
      expect(find.text(r'$1.2345'), findsOneWidget);
      expect(find.text('缓存命中率'), findsOneWidget);
      expect(find.text('87.5%'), findsOneWidget);
      expect(find.text('缓存读取令牌'), findsOneWidget);
      expect(find.text('5,000'), findsOneWidget);
      expect(find.text('最近 30 天'), findsOneWidget);

      // 模型拆分（需要滚动到可见）
      await tester.scrollUntilVisible(find.text('模型'), 200);
      expect(find.text('gpt-4o'), findsOneWidget);
      expect(find.text('60%'), findsOneWidget);
      expect(find.text('claude'), findsOneWidget);

      // 近 14 天令牌柱状图
      await tester.scrollUntilVisible(find.text('近 14 天令牌'), 200);
      expect(find.byType(BarChart), findsOneWidget);

      // 活动：最活跃的一天 / 时段
      await tester.scrollUntilVisible(find.text('活动'), 200);
      expect(find.text('最活跃的一天'), findsOneWidget);
      expect(find.textContaining('2026-08-16'), findsOneWidget);
      expect(find.text('最活跃时段'), findsOneWidget);
      expect(find.textContaining('14:00'), findsOneWidget);
    });

    testWidgets('分段控件切换时间范围：重新拉取对应天数', (tester) async {
      final api = FakeInsightsApi(response: sampleResponse());
      await pumpInsightsPage(tester, api);
      expect(api.requestedDays, [30]);

      await tester.tap(find.text('近 7 天'));
      await tester.pump();
      await tester.pump();
      expect(api.requestedDays, [30, 7]);

      await tester.tap(find.text('今天'));
      await tester.pump();
      await tester.pump();
      expect(api.requestedDays, [30, 7, 1]);
    });

    testWidgets('加载态：数据到达前显示 ActivityIndicator，到达后渲染指标', (tester) async {
      final api = FakeInsightsApi(response: sampleResponse());
      api.fetchGate = Completer<void>();
      await pumpInsightsPage(tester, api);

      expect(find.byType(CupertinoActivityIndicator), findsOneWidget);

      api.fetchGate!.complete();
      await tester.pump();
      await tester.pump();
      expect(find.text('会话'), findsOneWidget);
      expect(find.byType(CupertinoActivityIndicator), findsNothing);
    });

    testWidgets('全空 → 暂无统计空态', (tester) async {
      await pumpInsightsPage(tester, FakeInsightsApi());

      expect(find.text('暂无统计'), findsOneWidget);
      expect(find.text('有对话后这里会显示用量数据。'), findsOneWidget);
      expect(find.text('会话'), findsNothing);
    });

    testWidgets('错误态：加载失败展示错误信息，重试恢复', (tester) async {
      final api = FakeInsightsApi(response: sampleResponse());
      api.fetchError = NetworkException(NetworkExceptionKind.cannotConnect);
      await pumpInsightsPage(tester, api);

      expect(find.text('加载失败'), findsOneWidget);
      expect(find.textContaining('无法连接'), findsOneWidget);

      api.fetchError = null;
      await tester.tap(find.byKey(const ValueKey('insights-retry')));
      await tester.pump();
      await tester.pump();

      expect(find.text('会话'), findsOneWidget);
      expect(find.text('加载失败'), findsNothing);
    });

    testWidgets('刷新按钮：重新拉取', (tester) async {
      final api = FakeInsightsApi(response: sampleResponse());
      await pumpInsightsPage(tester, api);
      expect(api.fetchCount, 1);

      await tester.tap(find.byKey(const ValueKey('insights-refresh')));
      await tester.pump();
      await tester.pump();
      expect(api.fetchCount, 2);
    });
  });

  group('Insights 格式化工具', () {
    test('formatInsightsNumber：千分位；null → —', () {
      expect(formatInsightsNumber(null), '—');
      expect(formatInsightsNumber(0), '0');
      expect(formatInsightsNumber(1234), '1,234');
      expect(formatInsightsNumber(1000000), '1,000,000');
      expect(formatInsightsNumber(-1234), '-1,234');
    });

    test('formatInsightsCost：最多 4 位小数去尾零；null → —', () {
      expect(formatInsightsCost(null), '—');
      expect(formatInsightsCost(1.2345), r'$1.2345');
      expect(formatInsightsCost(0.0123), r'$0.0123');
      expect(formatInsightsCost(1.0), r'$1');
      expect(formatInsightsCost(1.5), r'$1.5');
    });

    test('formatInsightsPercent：1 位小数；null → —', () {
      expect(formatInsightsPercent(null), '—');
      expect(formatInsightsPercent(87.5), '87.5%');
      expect(formatInsightsPercent(0), '0.0%');
    });
  });
}
