import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/router.dart';
import '../../core/utils/uuid.dart';
import '../chat/chat_providers.dart';
import '../desktop/window_title_service.dart';
import 'turn_notification_service.dart';

/// App 生命周期状态（生产由 [NotificationLifecycleObserver] 驱动；测试可
/// 直接调用 notifier.setState 或 override 注入）。
final appLifecycleStateProvider = NotifierProvider<AppLifecycleNotifier,
    AppLifecycleState>(AppLifecycleNotifier.new);

/// 生命周期跟踪：默认前台（resumed）——观察器未挂载时 hook 保守不发通知。
class AppLifecycleNotifier extends Notifier<AppLifecycleState> {
  @override
  AppLifecycleState build() => AppLifecycleState.resumed;

  /// 更新生命周期状态（相同值不重复通知）。
  void setState(AppLifecycleState state) {
    if (state == this.state) return;
    this.state = state;
  }
}

/// 通知设置状态。
class NotificationSettings {
  const NotificationSettings({
    this.notifyTurnsEnabled = true,
    this.notifyClarifyEnabled = true,
    this.notifyErrorsEnabled = true,
  });

  final bool notifyTurnsEnabled;
  final bool notifyClarifyEnabled;
  final bool notifyErrorsEnabled;

  NotificationSettings copyWith({
    bool? notifyTurnsEnabled,
    bool? notifyClarifyEnabled,
    bool? notifyErrorsEnabled,
  }) {
    return NotificationSettings(
      notifyTurnsEnabled: notifyTurnsEnabled ?? this.notifyTurnsEnabled,
      notifyClarifyEnabled: notifyClarifyEnabled ?? this.notifyClarifyEnabled,
      notifyErrorsEnabled: notifyErrorsEnabled ?? this.notifyErrorsEnabled,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NotificationSettings &&
          runtimeType == other.runtimeType &&
          notifyTurnsEnabled == other.notifyTurnsEnabled &&
          notifyClarifyEnabled == other.notifyClarifyEnabled &&
          notifyErrorsEnabled == other.notifyErrorsEnabled;

  @override
  int get hashCode => Object.hash(
        notifyTurnsEnabled,
        notifyClarifyEnabled,
        notifyErrorsEnabled,
      );
}

class NotificationSettingsNotifier extends Notifier<NotificationSettings> {
  static const keyTurns = 'notify_turns_enabled';
  static const keyClarify = 'notify_clarify_enabled';
  static const keyErrors = 'notify_errors_enabled';

  bool _loaded = false;

  @override
  NotificationSettings build() {
    _loaded = false;
    unawaited(_loadFromPrefs());
    return const NotificationSettings();
  }

  Future<void> _loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_loaded) return;
      _loaded = true;
      state = NotificationSettings(
        notifyTurnsEnabled: prefs.getBool(keyTurns) ?? state.notifyTurnsEnabled,
        notifyClarifyEnabled:
            prefs.getBool(keyClarify) ?? state.notifyClarifyEnabled,
        notifyErrorsEnabled:
            prefs.getBool(keyErrors) ?? state.notifyErrorsEnabled,
      );
    } catch (_) {}
  }

  Future<void> setNotifyTurnsEnabled(bool value) async {
    _loaded = true;
    state = state.copyWith(notifyTurnsEnabled: value);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(keyTurns, value);
    } catch (_) {}
  }

  Future<void> setNotifyClarifyEnabled(bool value) async {
    _loaded = true;
    state = state.copyWith(notifyClarifyEnabled: value);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(keyClarify, value);
    } catch (_) {}
  }

  Future<void> setNotifyErrorsEnabled(bool value) async {
    _loaded = true;
    state = state.copyWith(notifyErrorsEnabled: value);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(keyErrors, value);
    } catch (_) {}
  }
}

/// 通知设置 Provider。
final notificationSettingsProvider =
    NotifierProvider<NotificationSettingsNotifier, NotificationSettings>(
  NotificationSettingsNotifier.new,
);

/// In-app 通知类型。
enum InAppNotificationType {
  turnCompleted,
  clarificationNeeded,
  sessionError,
}

/// In-app 通知条目模型。
class InAppNotificationItem {
  const InAppNotificationItem({
    required this.id,
    required this.sessionId,
    required this.title,
    required this.message,
    required this.type,
  });

  final String id;
  final String sessionId;
  final String title;
  final String message;
  final InAppNotificationType type;
}

/// In-app 通知事件 Provider（前台跨会话触发时推送）。
final inAppNotificationProvider =
    StateProvider<InAppNotificationItem?>((ref) => null);

/// 当前激活会话 ID（从 activeSessionIdProvider 读）。
String? getActiveSessionId(Ref ref) {
  try {
    return ref.read(activeSessionIdProvider);
  } catch (_) {
    return null;
  }
}

/// 回合/澄清/错误通知服务（生产 [LocalNotificationsTurnNotificationService]；
/// 测试可 override 注入 fake）。
final turnNotificationServiceProvider = Provider<TurnNotificationService>(
  (ref) {
    return LocalNotificationsTurnNotificationService(
      onTap: (sessionId) => openSessionFromNotification(ref, sessionId),
    );
  },
);

/// 通知点击 → 跳转对应会话（go_router；无激活连接时守卫自动重定向）。
void openSessionFromNotification(dynamic ref, String sessionId) {
  if (sessionId.isEmpty) return;
  ref.read(routerProvider).go('/chat/$sessionId');
}

/// chat 收尾 hook：chat_controller 在 done / stream_end 成功收尾处调用。
///
/// 触发时机：
/// - 开关关闭：不发系统通知也不发 in-app
/// - app 前台（resumed）：仅事件会话 ≠ 当前激活会话时触发 in-app 提示，并清除残留系统通知
/// - app 后台（paused / inactive / detached / hidden）：发系统通知
final turnNotificationHookProvider = Provider<ChatTurnCompletedCallback>(
  (ref) {
    final service = ref.watch(turnNotificationServiceProvider);
    return (sessionId, title, preview) {
      final settings = ref.read(notificationSettingsProvider);
      if (!settings.notifyTurnsEnabled) return;
      final lifecycle = ref.read(appLifecycleStateProvider);
      if (lifecycle == AppLifecycleState.resumed) {
        final active = getActiveSessionId(ref);
        if (active != sessionId) {
          ref.read(inAppNotificationProvider.notifier).state =
              InAppNotificationItem(
            id: uuidV4(),
            sessionId: sessionId,
            title: title.isNotEmpty ? title : '回合完成',
            message: preview,
            type: InAppNotificationType.turnCompleted,
          );
        }
        unawaited(service.clearAll());
      } else {
        unawaited(service.notifyTurnCompleted(sessionId, title, preview));
      }
    };
  },
);

/// chat 澄清请求 hook：chat_controller 在收到 clarify 事件时调用。
final clarificationNotificationHookProvider =
    Provider<ChatClarificationNeededCallback>(
  (ref) {
    final service = ref.watch(turnNotificationServiceProvider);
    return (sessionId, question) {
      final settings = ref.read(notificationSettingsProvider);
      if (!settings.notifyClarifyEnabled) return;
      final lifecycle = ref.read(appLifecycleStateProvider);
      if (lifecycle == AppLifecycleState.resumed) {
        final active = getActiveSessionId(ref);
        if (active != sessionId) {
          ref.read(inAppNotificationProvider.notifier).state =
              InAppNotificationItem(
            id: uuidV4(),
            sessionId: sessionId,
            title: '需要澄清',
            message: question,
            type: InAppNotificationType.clarificationNeeded,
          );
        }
      } else {
        unawaited(service.notifyClarificationNeeded(sessionId, question));
      }
    };
  },
);

/// chat 会话异常 hook：chat_controller 在 cancel / error / 重连失败时调用。
final sessionErrorNotificationHookProvider =
    Provider<ChatSessionErrorCallback>(
  (ref) {
    final service = ref.watch(turnNotificationServiceProvider);
    return (sessionId, title, preview) {
      final settings = ref.read(notificationSettingsProvider);
      if (!settings.notifyErrorsEnabled) return;
      final lifecycle = ref.read(appLifecycleStateProvider);
      if (lifecycle == AppLifecycleState.resumed) {
        final active = getActiveSessionId(ref);
        if (active != sessionId) {
          ref.read(inAppNotificationProvider.notifier).state =
              InAppNotificationItem(
            id: uuidV4(),
            sessionId: sessionId,
            title: title.isNotEmpty ? title : '会话异常',
            message: preview,
            type: InAppNotificationType.sessionError,
          );
        }
      } else {
        unawaited(service.notifySessionError(sessionId, title, preview));
      }
    };
  },
);
