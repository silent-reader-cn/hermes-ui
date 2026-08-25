import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/upload_response.dart';

/// 待发附件状态（按 `sessionId` 隔离，对齐 `pendingSelectionsProvider` 模式）。
class PendingAttachmentsNotifier
    extends StateNotifier<List<PendingAttachment>> {
  PendingAttachmentsNotifier() : super(const []);

  /// 新增一个已上传完成的附件（进入发送队列，不立即发送）。
  void add(PendingAttachment attachment) {
    state = [...state, attachment];
  }

  /// 移除指定 `id` 的附件。
  void remove(String id) {
    state = state.where((a) => a.id != id).toList(growable: false);
  }

  /// 清空全部待发附件。
  void clear() {
    state = const [];
  }
}

/// 按 `sessionId` 隔离的待发附件列表：上传/粘贴完成即入列，点发送才一并提交。
final pendingAttachmentsProvider = StateNotifierProvider.family<
    PendingAttachmentsNotifier,
    List<PendingAttachment>,
    String>(
  (ref, sessionId) => PendingAttachmentsNotifier(),
);