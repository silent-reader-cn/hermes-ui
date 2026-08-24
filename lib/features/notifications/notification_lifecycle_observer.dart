import 'dart:async';

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/router.dart';
import 'notification_providers.dart';

/// 生命周期观察器（挂载在 App 壳根部）。
///
/// 职责：
/// 1. 驱动 [appLifecycleStateProvider]（前后台判断依据，hook 据此决定发不发）；
/// 2. 回到前台自动清除通知（回到 app 通知即消失）；
/// 3. 冷启动恢复：由通知点击拉起 app 时跳到对应会话；
/// 4. 启动时请求通知权限（Android 13+ 系统弹窗，一次性）。
class NotificationLifecycleObserver extends ConsumerStatefulWidget {
  const NotificationLifecycleObserver({super.key, required this.child});

  /// 被包裹的 App 根 Widget。
  final Widget child;

  @override
  ConsumerState<NotificationLifecycleObserver> createState() =>
      _NotificationLifecycleObserverState();
}

class _NotificationLifecycleObserverState
    extends ConsumerState<NotificationLifecycleObserver>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (defaultTargetPlatform == TargetPlatform.android) {
        // 仅 Android：冷启动恢复 + 通知权限（桌面端无 POST_NOTIFICATIONS）。
        unawaited(_handleLaunchDetails());
        unawaited(ref.read(turnNotificationServiceProvider).requestPermission());
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    ref.read(appLifecycleStateProvider.notifier).setState(state);
    if (state == AppLifecycleState.resumed) {
      // 回到 app：通知使命完成，自动清除。
      unawaited(ref.read(turnNotificationServiceProvider).clearAll());
    }
  }

  /// 冷启动由通知拉起 → 跳转对应会话并清除通知。
  Future<void> _handleLaunchDetails() async {
    final sessionId =
        await ref.read(turnNotificationServiceProvider).getLaunchSessionId();
    if (sessionId == null || sessionId.isEmpty) return;
    ref.read(routerProvider).go('/chat/$sessionId');
    unawaited(ref.read(turnNotificationServiceProvider).clearAll());
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
