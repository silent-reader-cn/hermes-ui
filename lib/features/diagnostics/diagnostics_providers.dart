import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'diagnostics_models.dart';
import 'diagnostics_service.dart';

/// 诊断服务单例 Provider。
final diagnosticsServiceProvider = Provider<DiagnosticsService>((ref) {
  return DiagnosticsService.instance;
});

/// 诊断模式是否开启 Provider。
final diagnosticsEnabledProvider =
    NotifierProvider<DiagnosticsEnabledController, bool>(
      DiagnosticsEnabledController.new,
    );

/// 诊断模式开关控制器。
class DiagnosticsEnabledController extends Notifier<bool> {
  @override
  bool build() {
    final service = ref.watch(diagnosticsServiceProvider);
    return service.enabled;
  }

  Future<void> setEnabled(bool value) async {
    final service = ref.read(diagnosticsServiceProvider);
    await service.setEnabled(value);
    state = value;
  }
}

/// 诊断日志列表 Provider（实时监听诊断更新流）。
final diagnosticsLogsProvider =
    NotifierProvider<DiagnosticsLogsController, List<DiagnosticsLogEntry>>(
      DiagnosticsLogsController.new,
    );

/// 诊断日志列表控制器。
class DiagnosticsLogsController extends Notifier<List<DiagnosticsLogEntry>> {
  StreamSubscription<List<DiagnosticsLogEntry>>? _subscription;

  @override
  List<DiagnosticsLogEntry> build() {
    final service = ref.watch(diagnosticsServiceProvider);
    unawaited(_subscription?.cancel());
    _subscription = service.logsStream.listen((logs) {
      state = logs;
    });
    ref.onDispose(() {
      unawaited(_subscription?.cancel());
    });
    return service.logs;
  }

  Future<void> clear() async {
    final service = ref.read(diagnosticsServiceProvider);
    await service.clear();
    state = const [];
  }
}

/// 诊断筛选条件控制器 Provider。
final diagnosticsFilterProvider =
    NotifierProvider<DiagnosticsFilterController, DiagnosticsFilterState>(
      DiagnosticsFilterController.new,
    );

/// 诊断筛选条件控制器。
class DiagnosticsFilterController extends Notifier<DiagnosticsFilterState> {
  @override
  DiagnosticsFilterState build() => const DiagnosticsFilterState();

  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
  }

  void toggleLevel(DiagnosticsLogLevel level) {
    final current = Set<DiagnosticsLogLevel>.from(state.selectedLevels);
    if (current.contains(level)) {
      if (current.length > 1) {
        current.remove(level);
      }
    } else {
      current.add(level);
    }
    state = state.copyWith(selectedLevels: current);
  }

  void setTimeFilter(DiagnosticsTimeFilter filter) {
    state = state.copyWith(timeFilter: filter);
  }

  void resetFilters() {
    state = const DiagnosticsFilterState();
  }
}

/// 过滤后的诊断日志列表 Provider。
final filteredDiagnosticsLogsProvider = Provider<List<DiagnosticsLogEntry>>((
  ref,
) {
  final logs = ref.watch(diagnosticsLogsProvider);
  final filter = ref.watch(diagnosticsFilterProvider);

  final query = filter.searchQuery.trim().toLowerCase();
  final now = DateTime.now();
  final todayStart = DateTime(now.year, now.month, now.day);
  final sevenDaysAgo = now.subtract(const Duration(days: 7));

  final results = <DiagnosticsLogEntry>[];

  // 逆序遍历：最新日志排在最前
  for (var i = logs.length - 1; i >= 0; i--) {
    final entry = logs[i];

    // 1. 级别过滤
    if (!filter.selectedLevels.contains(entry.level)) {
      continue;
    }

    // 2. 时间过滤
    switch (filter.timeFilter) {
      case DiagnosticsTimeFilter.all:
        break;
      case DiagnosticsTimeFilter.today:
        if (entry.timestamp.isBefore(todayStart)) continue;
        break;
      case DiagnosticsTimeFilter.last7Days:
        if (entry.timestamp.isBefore(sevenDaysAgo)) continue;
        break;
      case DiagnosticsTimeFilter.custom:
        if (filter.customStartDate != null &&
            entry.timestamp.isBefore(filter.customStartDate!)) {
          continue;
        }
        if (filter.customEndDate != null &&
            entry.timestamp.isAfter(filter.customEndDate!)) {
          continue;
        }
        break;
    }

    // 3. 全文搜索（时间/级别/Tag/内容/详情 JSON）
    if (query.isNotEmpty) {
      final tagMatch = entry.tag.toLowerCase().contains(query);
      final msgMatch = entry.message.toLowerCase().contains(query);
      final levelMatch = entry.level.label.toLowerCase().contains(query) ||
          entry.level.code.toLowerCase() == query;
      final timeMatch = formatLogTimestamp(entry.timestamp).contains(query);
      final errorMatch =
          entry.errorKind?.toLowerCase().contains(query) ?? false;
      final detailsMatch =
          entry.details != null && entry.detailsJson.toLowerCase().contains(query);

      if (!tagMatch &&
          !msgMatch &&
          !levelMatch &&
          !timeMatch &&
          !errorMatch &&
          !detailsMatch) {
        continue;
      }
    }

    results.add(entry);
  }

  return results;
});

/// 选中的日志 ID 集合 Provider。
final diagnosticsSelectedIdsProvider =
    NotifierProvider<DiagnosticsSelectedIdsController, Set<String>>(
      DiagnosticsSelectedIdsController.new,
    );

/// 选中的日志 ID 集合控制器。
class DiagnosticsSelectedIdsController extends Notifier<Set<String>> {
  @override
  Set<String> build() => const <String>{};

  void setSelected(Set<String> ids) => state = ids;
  void clear() => state = const <String>{};
  void toggle(String id) {
    if (state.contains(id)) {
      state = state.where((item) => item != id).toSet();
    } else {
      state = {...state, id};
    }
  }
}

/// 是否处于多选模式 Provider。
final diagnosticsIsSelectionModeProvider =
    NotifierProvider<DiagnosticsIsSelectionModeController, bool>(
      DiagnosticsIsSelectionModeController.new,
    );

/// 多选模式控制器。
class DiagnosticsIsSelectionModeController extends Notifier<bool> {
  @override
  bool build() => false;

  void setMode(bool value) => state = value;
}
