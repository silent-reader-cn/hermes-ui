import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/models/insights.dart';
import '../../app/theme/status_colors.dart';
import 'insights_providers.dart';

/// 用量统计页（对齐 Hermex InsightsView 的展示形态）。
///
/// Cupertino 风格：大标题 + 刷新按钮 + 下拉刷新；时间范围用分段控件切换
/// （今天 / 近 7 天 / 近 30 天 / 全部），指标卡片展示会话 / 消息 / 令牌 /
/// 费用等汇总，模型拆分列表 + 近 14 天令牌柱状图（fl_chart）+ 峰值活动；
/// 含加载 / 错误 / 空态。
class InsightsPage extends ConsumerWidget {
  const InsightsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(insightsControllerProvider);
    final state = async.valueOrNull;

    return CupertinoPageScaffold(
      child: CustomScrollView(
        key: const ValueKey('insights-scroll'),
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          CupertinoSliverNavigationBar(
            largeTitle: const Text('用量统计'),
            trailing: CupertinoButton(
              key: const ValueKey('insights-refresh'),
              padding: EdgeInsets.zero,
              onPressed: () => unawaited(
                ref.read(insightsControllerProvider.notifier).refresh(),
              ),
              child: const Icon(CupertinoIcons.arrow_clockwise),
            ),
          ),
          CupertinoSliverRefreshControl(
            onRefresh: () =>
                ref.read(insightsControllerProvider.notifier).refresh(),
          ),
          ..._buildContentSlivers(ref, async, state),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // 内容 slivers：加载 / 错误 / 空态 / 统计正文
  // -------------------------------------------------------------------------

  List<Widget> _buildContentSlivers(
    WidgetRef ref,
    AsyncValue<InsightsState> async,
    InsightsState? state,
  ) {
    if (state == null) {
      if (async.isLoading) {
        return const [
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: CupertinoActivityIndicator(radius: 14)),
          ),
        ];
      }
      return [_buildErrorSliver(ref, async.error)];
    }

    if (!state.response.hasData) {
      return [_buildEmptySliver()];
    }

    final response = state.response;
    final timeframe = state.timeframe;
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: CupertinoSlidingSegmentedControl<InsightsTimeframe>(
            groupValue: timeframe,
            onValueChanged: (value) {
              if (value != null) {
                unawaited(
                  ref
                      .read(insightsControllerProvider.notifier)
                      .setTimeframe(value),
                );
              }
            },
            children: {
              for (final t in InsightsTimeframe.values)
                t: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(t.title),
                ),
            },
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: CupertinoListSection.insetGrouped(
          header: _periodHeader(response, timeframe),
          children: [
            _MetricTile(
              title: '会话',
              value: _formatNumber(response.totalSessions),
              icon: CupertinoIcons.bubble_left_bubble_right,
            ),
            _MetricTile(
              title: '消息',
              value: _formatNumber(response.totalMessages),
              icon: CupertinoIcons.text_bubble,
            ),
            _MetricTile(
              title: '输入令牌',
              value: _formatNumber(response.totalInputTokens),
              icon: CupertinoIcons.arrow_down_circle,
            ),
            _MetricTile(
              title: '输出令牌',
              value: _formatNumber(response.totalOutputTokens),
              icon: CupertinoIcons.arrow_up_circle,
            ),
            _MetricTile(
              title: '总令牌',
              value: _formatNumber(response.totalTokens),
              icon: CupertinoIcons.sum,
            ),
            _MetricTile(
              title: '估算费用',
              value: _formatCost(response.totalCost),
              icon: CupertinoIcons.money_dollar_circle,
            ),
            if (response.totalCacheHitPercent != null)
              _MetricTile(
                title: '缓存命中率',
                value: _formatPercent(response.totalCacheHitPercent),
                icon: CupertinoIcons.bolt_circle,
              ),
            if (response.totalCacheReadTokens != null)
              _MetricTile(
                title: '缓存读取令牌',
                value: _formatNumber(response.totalCacheReadTokens),
                icon: CupertinoIcons.arrow_counterclockwise_circle,
              ),
          ],
        ),
      ),
      if (_modelBreakdowns(response).isNotEmpty)
        SliverToBoxAdapter(
          child: CupertinoListSection.insetGrouped(
            header: const Text('模型'),
            children: [
              for (final model in _modelBreakdowns(response))
                _ModelBreakdownTile(model: model),
            ],
          ),
        ),
      if (_recentDailyTokens(response).isNotEmpty)
        SliverToBoxAdapter(
          child: CupertinoListSection.insetGrouped(
            header: const Text('近 14 天令牌'),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                child: _DailyTokensBarChart(days: _recentDailyTokens(response)),
              ),
            ],
          ),
        ),
      if (_hasActivity(response))
        SliverToBoxAdapter(
          child: CupertinoListSection.insetGrouped(
            header: const Text('活动'),
            children: [
              if (_peakDay(response) != null)
                CupertinoListTile(
                  title: const Text('最活跃的一天'),
                  trailing: Text(
                    '${_peakDay(response)!.day ?? '未知'}'
                    ' · ${_peakDay(response)!.sessions ?? 0} 个会话',
                    style: const TextStyle(
                      fontSize: 13,
                      color: CupertinoColors.secondaryLabel,
                    ),
                  ),
                ),
              if (_peakHour(response) != null)
                CupertinoListTile(
                  title: const Text('最活跃时段'),
                  trailing: Text(
                    '${_formatHour(_peakHour(response)!.hour)}'
                    ' · ${_peakHour(response)!.sessions ?? 0} 个会话',
                    style: const TextStyle(
                      fontSize: 13,
                      color: CupertinoColors.secondaryLabel,
                    ),
                  ),
                ),
            ],
          ),
        ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: Text(
            '来源：服务器按最近 ${response.periodDays ?? timeframe.serverDays} 天统计。',
            style: const TextStyle(
              fontSize: 12,
              color: CupertinoColors.secondaryLabel,
            ),
          ),
        ),
      ),
    ];
  }

  Widget _buildErrorSliver(WidgetRef ref, Object? error) {
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              CupertinoIcons.exclamationmark_triangle,
              size: 48,
              color: CupertinoColors.systemGrey,
            ),
            const SizedBox(height: 12),
            const Text(
              '加载失败',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              _errorMessage(error),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: statusRedText,
              ),
            ),
            const SizedBox(height: 20),
            CupertinoButton.filled(
              key: const ValueKey('insights-retry'),
              onPressed: () => unawaited(
                ref.read(insightsControllerProvider.notifier).refresh(),
              ),
              child: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptySliver() {
    return const SliverFillRemaining(
      hasScrollBody: false,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              CupertinoIcons.chart_bar,
              size: 48,
              color: CupertinoColors.systemGrey,
            ),
            SizedBox(height: 12),
            Text(
              '暂无统计',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 6),
            Text(
              '有对话后这里会显示用量数据。',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: CupertinoColors.secondaryLabel,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // 派生展示数据
  // -------------------------------------------------------------------------

  List<InsightsModelBreakdown> _modelBreakdowns(InsightsResponse response) {
    final models = response.models ?? const [];
    return models.length <= 10 ? models : models.sublist(0, 10);
  }

  List<InsightsDailyToken> _recentDailyTokens(InsightsResponse response) {
    final tokens = response.dailyTokens ?? const [];
    final recent = tokens.length <= 14
        ? tokens
        : tokens.sublist(tokens.length - 14);
    // 服务器按最新在前返回，图表按时间正序绘制。
    return recent.reversed.toList(growable: false);
  }

  bool _hasActivity(InsightsResponse response) =>
      _peakDay(response) != null || _peakHour(response) != null;

  InsightsActivityByDay? _peakDay(InsightsResponse response) {
    final days = response.activityByDay ?? const [];
    if (days.isEmpty) return null;
    return days.reduce(
      (a, b) => (a.sessions ?? 0) >= (b.sessions ?? 0) ? a : b,
    );
  }

  InsightsActivityByHour? _peakHour(InsightsResponse response) {
    final hours = response.activityByHour ?? const [];
    if (hours.isEmpty) return null;
    return hours.reduce(
      (a, b) => (a.sessions ?? 0) >= (b.sessions ?? 0) ? a : b,
    );
  }

  Widget _periodHeader(InsightsResponse response, InsightsTimeframe timeframe) {
    if (response.periodDays != null) {
      return Text('最近 ${response.periodDays} 天');
    }
    return Text(timeframe.title);
  }

  String _errorMessage(Object? error) {
    if (error is ApiException) return error.message;
    return error?.toString() ?? '未知错误';
  }
}

// ---------------------------------------------------------------------------
// 指标行
// ---------------------------------------------------------------------------

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.title,
    required this.value,
    required this.icon,
  });

  final String title;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return CupertinoListTile(
      leading: Icon(icon, color: CupertinoColors.systemBlue),
      title: Text(title),
      trailing: Text(
        value,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _ModelBreakdownTile extends StatelessWidget {
  const _ModelBreakdownTile({required this.model});

  final InsightsModelBreakdown model;

  @override
  Widget build(BuildContext context) {
    final share = model.displayShare;
    final title = model.model?.isNotEmpty == true ? model.model! : '未知模型';
    return CupertinoListTile(
      title: Text(title),
      subtitle: Text('${formatInsightsNumber(model.totalTokens)} 令牌'),
      trailing: share == null
          ? null
          : Text(
              '$share%',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: CupertinoColors.systemBlue,
              ),
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// 近 14 天令牌柱状图
// ---------------------------------------------------------------------------

class _DailyTokensBarChart extends StatelessWidget {
  const _DailyTokensBarChart({required this.days});

  final List<InsightsDailyToken> days;

  @override
  Widget build(BuildContext context) {
    final maxTokens = days.fold<int>(
      0,
      (max, day) => day.totalTokens > max ? day.totalTokens : max,
    );
    final safeMax = maxTokens <= 0 ? 1.0 : maxTokens * 1.15;

    return SizedBox(
      height: 180,
      width: double.infinity,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: safeMax.toDouble(),
          minY: 0,
          barTouchData: const BarTouchData(enabled: false),
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            leftTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                getTitlesWidget: _bottomTitle,
              ),
            ),
          ),
          barGroups: [
            for (var i = 0; i < days.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: days[i].totalTokens.toDouble(),
                    color: CupertinoColors.systemBlue,
                    width: 10,
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _bottomTitle(double value, TitleMeta meta) {
    final index = value.toInt();
    if (index < 0 || index >= days.length) {
      return const SizedBox.shrink();
    }
    // 标签过密时只显示部分日期。
    if (days.length > 7 && index % 3 != 0 && index != days.length - 1) {
      return const SizedBox.shrink();
    }
    final date = days[index].date;
    if (date == null || date.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        _shortDate(date),
        style: const TextStyle(fontSize: 10, color: CupertinoColors.secondaryLabel),
      ),
    );
  }

  /// '2026-08-16' / '2026/08/16' → '08-16'；其余原样截断。
  static String _shortDate(String date) {
    final parts = date.split(RegExp(r'[-/]'));
    if (parts.length >= 3) {
      return '${parts[1]}-${parts[2]}';
    }
    return date.length <= 5 ? date : date.substring(date.length - 5);
  }
}

// ---------------------------------------------------------------------------
// 数字格式化
// ---------------------------------------------------------------------------

/// 千分位格式化（null → '—'）。
String formatInsightsNumber(int? value) {
  if (value == null) return '—';
  final digits = value.abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return value < 0 ? '-$buffer' : buffer.toString();
}

/// 费用格式化：保留最多 4 位小数，去掉末尾 0（null → '—'）。
String formatInsightsCost(double? value) {
  if (value == null) return '—';
  final text = value.toStringAsFixed(4).replaceFirst(RegExp(r'0+$'), '');
  return '\$${text.replaceFirst(RegExp(r'\.$'), '')}';
}

/// 百分比格式化（null → '—'）。
String formatInsightsPercent(double? value) {
  if (value == null) return '—';
  return '${value.toStringAsFixed(1)}%';
}

String _formatNumber(int? value) => formatInsightsNumber(value);

String _formatCost(double? value) => formatInsightsCost(value);

String _formatPercent(double? value) => formatInsightsPercent(value);

String _formatHour(int? hour) {
  if (hour == null) return '未知';
  return '${hour.toString().padLeft(2, '0')}:00';
}
