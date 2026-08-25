import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 聊天发送快捷键模式：Enter 发送 / Ctrl+Enter（macOS Cmd+Enter）发送。
enum ChatSendShortcutMode {
  /// Enter 发送（单行输入，现状行为，默认）。
  enter,

  /// Ctrl+Enter（macOS Cmd+Enter）发送，Enter 换行（多行输入）。
  ctrlEnter,
}

/// 聊天发送快捷键偏好模型（TASK: 设置新增 Enter 发送 / Ctrl+Enter 发送选项）。
///
/// 持久化到 [SharedPreferences]，键 `chat_send_shortcut_mode`，
/// 未存时默认 `enter`（= 现状行为）。
class ChatSendShortcutSettings {
  const ChatSendShortcutSettings({this.mode = ChatSendShortcutMode.enter});

  /// 发送快捷键模式。
  final ChatSendShortcutMode mode;

  ChatSendShortcutSettings copyWith({ChatSendShortcutMode? mode}) {
    return ChatSendShortcutSettings(mode: mode ?? this.mode);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatSendShortcutSettings &&
          runtimeType == other.runtimeType &&
          mode == other.mode;

  @override
  int get hashCode => mode.hashCode;

  @override
  String toString() => 'ChatSendShortcutSettings(mode: $mode)';
}

/// 发送快捷键偏好 Provider（持久化到 shared_preferences）。
final chatSendShortcutSettingsProvider =
    NotifierProvider<ChatSendShortcutController, ChatSendShortcutSettings>(
      ChatSendShortcutController.new,
    );

/// 发送快捷键偏好 Controller。
class ChatSendShortcutController extends Notifier<ChatSendShortcutSettings> {
  /// SharedPreferences key（值存枚举 [ChatSendShortcutMode.name]）。
  static const String keySendMode = 'chat_send_shortcut_mode';

  /// 读取发送快捷键模式的静态辅助（供非 Riverpod 调用方或测试注入
  /// [customPrefs] 使用 `SharedPreferences.setMockInitialValues`）。
  static Future<ChatSendShortcutMode> loadShortcutModePref({
    SharedPreferences? customPrefs,
  }) async {
    try {
      final prefs = customPrefs ?? await SharedPreferences.getInstance();
      final raw = prefs.getString(keySendMode);
      return ChatSendShortcutMode.values.asNameMap()[raw] ??
          ChatSendShortcutMode.enter;
    } catch (_) {
      // 单测环境无 SharedPreferences mock 时回落默认值，避免抛异常。
      return ChatSendShortcutMode.enter;
    }
  }

  bool _hasCustomState = false;

  @override
  ChatSendShortcutSettings build() {
    _hasCustomState = false;
    unawaited(_load());
    return const ChatSendShortcutSettings();
  }

  Future<void> _load() async {
    try {
      final mode = await loadShortcutModePref();
      if (!_hasCustomState) {
        state = ChatSendShortcutSettings(mode: mode);
      }
    } catch (_) {
      // Ignored in unit test environments.
    }
  }

  Future<void> load() => _load();

  /// 切换发送快捷键模式并立即持久化到 [keySendMode]。
  ///
  /// 通过 Provider 通知聊天输入栏重建（watch 此 provider 即动态生效，
  /// 输入框已有内容由外层 State 持有不丢失）。
  Future<void> setMode(ChatSendShortcutMode mode) async {
    _hasCustomState = true;
    state = state.copyWith(mode: mode);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(keySendMode, mode.name);
    } catch (_) {
      // Ignored in unit test environments.
    }
  }
}
