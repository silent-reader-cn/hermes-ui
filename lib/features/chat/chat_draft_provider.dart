import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 会话级输入草稿（按 `sessionId` 隔离，对齐 `pendingSelectionsProvider`
/// 模式：无 autoDispose，ProviderScope 生命周期内常驻）。
///
/// 切换会话 / 进入设置页再返回时，输入框文字与已写内容不丢；
/// 草稿与 pending 附件（见 `pending_attachments_provider.dart`）同为内存态，
/// 应用重启不保留（与附件口径一致）。
class ChatDraftNotifier extends StateNotifier<String> {
  ChatDraftNotifier() : super('');

  /// 更新草稿（输入变化时实时落盘）。
  void update(String text) {
    if (state == text) return;
    state = text;
  }

  /// 发送成功后清空草稿。
  void clear() => update('');
}

/// 按 `sessionId` 隔离的输入框草稿。
final chatDraftProvider =
    StateNotifierProvider.family<ChatDraftNotifier, String, String>(
  (ref, sessionId) => ChatDraftNotifier(),
);