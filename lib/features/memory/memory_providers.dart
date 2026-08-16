import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/connections/connection_providers.dart';
import '../../core/models/memory.dart';
import 'memory_api.dart';

/// 记忆控制器：加载 / 刷新（只读查看，无写入能力）。
///
/// AsyncValue 语义：初始加载与刷新失败 → `AsyncError`（UI 展示错误态 +
/// 重试）；成功 → `AsyncData<MemoryResponse>` 直接携带模型。
final memoryControllerProvider =
    AsyncNotifierProvider<MemoryController, MemoryResponse>(
      MemoryController.new,
    );

class MemoryController extends AsyncNotifier<MemoryResponse> {
  MemoryApi get _api =>
      ref.read(memoryApiFactoryProvider)(ref.read(apiClientProvider));

  @override
  Future<MemoryResponse> build() async {
    // watch：切换服务器（apiClientProvider 重建）或工厂被替换时自动重载。
    final api = ref.watch(memoryApiFactoryProvider)(
      ref.watch(apiClientProvider),
    );
    return api.fetchMemory();
  }

  /// 下拉刷新 / 错误态重试：重新拉取记忆。
  Future<void> refresh() async {
    try {
      state = AsyncData(await _api.fetchMemory());
    } on Exception catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
    }
  }
}

/// 是否有任何记忆内容：三个分区任一非空（trim 后）或项目上下文展示。
bool memoryHasContent(MemoryResponse response) {
  return showsProjectContext(response) ||
      _isNonEmpty(response.memory) ||
      _isNonEmpty(response.user) ||
      _isNonEmpty(response.soul);
}

/// 项目上下文是否展示：服务端下发非空（trim 后）文档
/// （对齐 Hermex `showsProjectContext`；服务端无字段或空白文档时整屏不变）。
bool showsProjectContext(MemoryResponse response) =>
    _isNonEmpty(response.projectContext);

/// 项目上下文明细行「名称 — 工作区」（对齐 Hermex `projectContextDetail`）；
/// 无内容 → null。
String? memoryProjectContextDetail(MemoryResponse response) {
  final parts = <String>[
    response.projectContextName?.trim() ?? '',
    response.projectContextWorkspace?.trim() ?? '',
  ]..removeWhere((s) => s.isEmpty);
  return parts.isEmpty ? null : parts.join(' — ');
}

/// 秒级 mtime → 中文相对时间描述（对齐 Hermex `Modified X ago`）；
/// null / 非法值 → null。[now] 仅供测试注入固定参考时间。
String? formatMemoryMtime(double? mtime, {DateTime? now}) {
  if (mtime == null || !mtime.isFinite) return null;
  final reference = now ?? DateTime.now();
  final date = DateTime.fromMillisecondsSinceEpoch((mtime * 1000).round());
  final diff = reference.difference(date);
  if (diff.inSeconds < 60) return '刚刚更新';
  if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前更新';
  if (diff.inHours < 24) return '${diff.inHours} 小时前更新';
  if (diff.inDays < 30) return '${diff.inDays} 天前更新';
  String two(int v) => v.toString().padLeft(2, '0');
  return '更新于 ${date.year}-${two(date.month)}-${two(date.day)}';
}

/// 记忆分区展示信息（标题 + 空内容占位文案；对齐 Hermex MemorySection
/// 私有扩展 title / emptyMessage）。
class MemorySectionInfo {
  const MemorySectionInfo({required this.title, required this.emptyMessage});

  /// 分区标题（中文）。
  final String title;

  /// 分区内容为空时的占位文案。
  final String emptyMessage;
}

MemorySectionInfo memorySectionInfo(MemorySection section) {
  switch (section) {
    case MemorySection.memory:
      return const MemorySectionInfo(title: '我的笔记', emptyMessage: '暂无笔记');
    case MemorySection.user:
      return const MemorySectionInfo(title: '用户画像', emptyMessage: '暂无画像');
    case MemorySection.soul:
      return const MemorySectionInfo(title: '智能体灵魂', emptyMessage: '暂无灵魂设定');
  }
}

bool _isNonEmpty(String? value) {
  final trimmed = value?.trim();
  return trimmed != null && trimmed.isNotEmpty;
}
