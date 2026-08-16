import 'dart:developer' as developer;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// 回合完成通知服务（抽象接口，平台无关契约）。
///
/// 生产实现 [LocalNotificationsTurnNotificationService] 基于
/// flutter_local_notifications；测试注入 fake 实现即可验证通知触发逻辑。
abstract interface class TurnNotificationService {
  /// 回合完成 → 弹系统通知。
  ///
  /// [sessionId] 编码进点击 payload（点击回到对应会话）；[title] 为通知标题，
  /// [preview] 为内容预览（由实现负责单行化/截断）。
  Future<void> notifyTurnCompleted(
    String sessionId,
    String title,
    String preview,
  );

  /// 清除全部回合完成通知（回到前台 / 点击通知后调用）。
  Future<void> clearAll();

  /// 请求通知权限（Android 13+ 必需；其他平台视为已授权）。
  Future<bool> requestPermission();

  /// 冷启动来源 sessionId：由通知点击拉起 app 时返回 payload 中的
  /// sessionId（非通知启动返回 null）。
  Future<String?> getLaunchSessionId();
}

/// flutter_local_notifications 生产实现（Android 通知通道 "turns"）。
///
/// 行为对齐 hermes-android v2.0.1 的 Background turn notifications 思路：
/// 回合完成弹系统通知、点击回到对应会话、回到 app 自动清除。所有平台调用
/// 均吞异常并记日志——通知失败绝不影响聊天主流程。
class LocalNotificationsTurnNotificationService
    implements TurnNotificationService {
  LocalNotificationsTurnNotificationService({
    FlutterLocalNotificationsPlugin? plugin,
    this.onTap,
  }) : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  /// Android 通知通道 ID（"turns"）。
  static const channelId = 'turns';

  /// Android 通知通道显示名。
  static const channelName = '回合完成';

  /// Android 通知通道描述。
  static const channelDescription = 'Agent 回合完成时推送系统通知';

  /// 通知 ID 固定：新回合通知替换旧通知，通知栏不堆积。
  static const notificationId = 1001;

  /// 预览正文最大长度（超出截断）。
  static const maxPreviewLength = 120;

  final FlutterLocalNotificationsPlugin _plugin;

  /// 点击通知回调（入参为 payload 中的 sessionId）。
  final void Function(String sessionId)? onTap;

  bool _initialized = false;

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
        onDidReceiveNotificationResponse: (response) {
          final sessionId = response.payload;
          if (sessionId != null && sessionId.isNotEmpty) {
            onTap?.call(sessionId);
          }
        },
      );
      _initialized = true;
    } on Object catch (error) {
      // 平台插件未注册（如测试环境 / 桌面端）或初始化失败：
      // 通知是增强功能，绝不影响聊天主流程。
      developer.log('通知服务初始化失败: $error', name: 'notifications');
    }
  }

  @override
  Future<void> notifyTurnCompleted(
    String sessionId,
    String title,
    String preview,
  ) async {
    if (sessionId.isEmpty) return;
    await _ensureInitialized();
    try {
      await _plugin.show(
        id: notificationId,
        title: title,
        body: formatPreview(preview),
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            channelId,
            channelName,
            channelDescription: channelDescription,
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
        payload: sessionId,
      );
    } on Object catch (error) {
      developer.log('回合完成通知发送失败: $error', name: 'notifications');
    }
  }

  @override
  Future<void> clearAll() async {
    try {
      await _plugin.cancelAll();
    } on Object catch (error) {
      developer.log('清除通知失败: $error', name: 'notifications');
    }
  }

  @override
  Future<bool> requestPermission() async {
    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      final granted = await android?.requestNotificationsPermission();
      return granted ?? true;
    } on Object catch (error) {
      developer.log('请求通知权限失败: $error', name: 'notifications');
      return false;
    }
  }

  @override
  Future<String?> getLaunchSessionId() async {
    try {
      final details = await _plugin.getNotificationAppLaunchDetails();
      if (details?.didNotificationLaunchApp != true) return null;
      final payload = details?.notificationResponse?.payload;
      if (payload == null || payload.isEmpty) return null;
      return payload;
    } on Object catch (error) {
      developer.log('读取启动通知失败: $error', name: 'notifications');
      return null;
    }
  }

  /// preview 单行化 + 截断（通知栏正文展示用）。
  static String formatPreview(String preview) {
    final oneLine = preview.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (oneLine.length <= maxPreviewLength) return oneLine;
    return '${oneLine.substring(0, maxPreviewLength)}…';
  }
}
