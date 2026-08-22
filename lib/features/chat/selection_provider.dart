import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/selected_context.dart';

/// 待发选区模型（对齐 `messages.js:170 PendingSelection{id,name,text}`）.
class PendingSelection {
  const PendingSelection({
    required this.id,
    required this.name,
    required this.text,
  });

  /// 形如 `ctx-N`.
  final String id;

  /// 显示为 `**name:**` 的 label，输入上限 120，解析上限 200.
  final String name;

  /// 选中原文，全量.
  final String text;

  @override
  bool operator ==(Object other) =>
      other is PendingSelection &&
      other.id == id &&
      other.name == name &&
      other.text == text;

  @override
  int get hashCode => Object.hash(id, name, text);

  @override
  String toString() => 'PendingSelection(id: $id, name: $name)';
}

/// 预览截断（对齐 `messages.js:926-931`，复用 [SelectedContextParser.preview]）.
String selectedContextPreview(String raw) =>
    SelectedContextParser.preview(raw);

/// 组装 `messageForAPI`（对齐 `messages.js:1023-1028`）.
///
/// `pending` 为当前会话的待发块列表；`currentText` 为输入框原文.
String buildMessageForApiWithPending(
  List<PendingSelection> pending,
  String currentText,
) {
  if (pending.isEmpty) return currentText;
  String fmt(PendingSelection s) {
    final norm = s.text
        .replaceAll(RegExp(r'\r\n?'), '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
    if (norm.isEmpty) return '';
    final quoted = norm.split('\n').map((l) => '> $l').join('\n');
    return '**${s.name}:**\n$kSelectedContextMarker\n$quoted';
  }

  final blocks = pending.map(fmt).where((b) => b.isNotEmpty).join('\n\n');
  if (blocks.isEmpty) return currentText;
  if (currentText.trim().isEmpty) return '$blocks\n\n';
  return '${currentText.replaceAll(RegExp(r'\s+$'), '')}\n\n$blocks\n\n';
}

/// 待发区状态（按 `sessionId` 隔离）.
class SelectionNotifier extends StateNotifier<List<PendingSelection>> {
  SelectionNotifier() : super(const []);

  int _counter = 0;

  /// 新增一个选区块（自动命名 `Context N`）.
  void add(String text) {
    _counter++;
    final name = 'Context $_counter';
    final id = 'ctx-$_counter';
    state = [...state, PendingSelection(id: id, name: name, text: text)];
  }

  /// 重命名（`trim` + `slice(0,120)`；空回退原名）.
  void rename(String id, String newName) {
    final trimmed = newName.trim();
    state = [
      for (final s in state)
        if (s.id == id)
          PendingSelection(
            id: s.id,
            name: trimmed.isEmpty
                ? s.name
                : (trimmed.length > 120
                      ? trimmed.substring(0, 120)
                      : trimmed),
            text: s.text,
          )
        else
          s,
    ];
  }

  /// 移除指定 `id`.
  void remove(String id) {
    final next = state.where((s) => s.id != id).toList(growable: false);
    state = next;
    if (next.isEmpty) _counter = 0;
  }

  /// 清空全部（`counter` 归零）.
  void clear() {
    _counter = 0;
    state = const [];
  }

  /// 构建 `messageForAPI`（当前输入框文本 + 本会话待发块）.
  String buildMessageForApi(String currentText) =>
      buildMessageForApiWithPending(state, currentText);
}

/// 按 `sessionId` 隔离的待发选区（与 WebUI 全局 `_pendingSelections` 不同，Flutter 按会话隔离）.
final pendingSelectionsProvider =
    StateNotifierProvider.family<SelectionNotifier, List<PendingSelection>, String>(
      (ref, sessionId) => SelectionNotifier(),
    );
