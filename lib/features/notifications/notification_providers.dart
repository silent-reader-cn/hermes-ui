import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/router.dart';
import '../chat/chat_providers.dart';
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

/// 回合完成通知服务（生产 [LocalNotificationsTurnNotificationService]；
/// 测试可 override 注入 fake）。
final turnNotificationServiceProvider = Provider<TurnNotificationService>(
  (ref) {
    return LocalNotificationsTurnNotificationService(
      onTap: (sessionId) => openSessionFromNotification(ref, sessionId),
    );
  },
);

/// 通知点击 → 跳转对应会话（go_router；无激活连接时守卫自动重定向）。
void openSessionFromNotification(Ref ref, String sessionId) {
  if (sessionId.isEmpty) return;
  ref.read(routerProvider).go('/chat/$sessionId');
}

/// chat 收尾 hook：chat_controller 在 done / stream_end 成功收尾处调用
/// （cancel / error 路径不触发）。
///
/// 触发时机（通知触发点 = 回合完成点）：
/// - app 前台（resumed）：不发通知，顺带清掉残留通知（防旧通知残留）；
/// - app 后台（paused / inactive / detached / hidden）：发回合完成通知。
final turnNotificationHookProvider = Provider<ChatTurnCompletedCallback>(
  (ref) {
    final service = ref.watch(turnNotificationServiceProvider);
    return (sessionId, title, preview) {
      final lifecycle = ref.read(appLifecycleStateProvider);
      if (lifecycle == AppLifecycleState.resumed) {
        unawaited(service.clearAll());
      } else {
        unawaited(service.notifyTurnCompleted(sessionId, title, preview));
      }
    };
  },
);
