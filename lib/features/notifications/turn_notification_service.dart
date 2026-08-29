import 'dart:developer' as developer;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../diagnostics/diagnostics_models.dart';
import '../diagnostics/diagnostics_service.dart';

/// 回合/澄清/错误三类通知服务（抽象接口，平台无关契约）。
///
/// 生产实现 [LocalNotificationsTurnNotificationService] 基于
/// flutter_local_notifications；测试注入 fake 实现即可验证通知触发逻辑。
abstract interface class TurnNotificationService {
  /// 回合完成 → 弹系统通知（Android channel: "turns", ID: 1001; Windows）。
  ///
  /// [sessionId] 编码进点击 payload（点击回到对应会话）；[title] 为通知标题，
  /// [preview] 为内容预览（由实现负责单行化/截断）。
  Future<void> notifyTurnCompleted(
    String sessionId,
    String title,
    String preview,
  );

  /// 需要澄清 → 弹系统通知（Android channel: "clarify", ID: 1101; Windows）。
  ///
  /// [sessionId] 编码进点击 payload；[question] 为澄清问题正文。
  Future<void> notifyClarificationNeeded(
    String sessionId,
    String question,
  );

  /// 异常中断/错误 → 弹系统通知（Android channel: "errors", ID: 1201; Windows）。
  ///
  /// [sessionId] 编码进点击 payload；[title] 为异常标题，[preview] 为错误预览。
  Future<void> notifySessionError(
    String sessionId,
    String title,
    String preview,
  );

  /// 清除全部通知（回到前台 / 点击通知后调用）。
  Future<void> clearAll();

  /// 请求通知权限（Android 13+ 必需；其他平台视为已授权）。
  Future<bool> requestPermission();

  /// 冷启动来源 sessionId：由通知点击拉起 app 时返回 payload 中的
  /// sessionId（非通知启动返回 null）。
  Future<String?> getLaunchSessionId();
}

/// flutter_local_notifications 生产实现（Android 3 通道 + Windows Toast）。
///
/// 行为对齐契约：
/// 1. Android 分区 1001(turns)/1101(clarify)/1201(errors)；
/// 2. Windows Toast 初始化 (Hermes UI + AUMID com.hermes.ui)；
/// 3. 点击回到对应会话，回到 app 自动清除。所有平台调用均吞异常并记日志。
class LocalNotificationsTurnNotificationService
    implements TurnNotificationService {
  LocalNotificationsTurnNotificationService({
    FlutterLocalNotificationsPlugin? plugin,
    this.onTap,
  }) : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  /// Android 通知通道：回合完成。
  static const channelTurnsId = 'turns';
  static const channelTurnsName = '回合完成';
  static const channelTurnsDescription = 'Agent 回合完成时推送系统通知';
  static const notificationTurnsId = 1001;

  /// Android 通知通道：需要澄清。
  static const channelClarifyId = 'clarify';
  static const channelClarifyName = '需要澄清';
  static const channelClarifyDescription = 'Agent 需要用户澄清时推送系统通知';
  static const notificationClarifyId = 1101;

  /// Android 通知通道：异常中断。
  static const channelErrorsId = 'errors';
  static const channelErrorsName = '异常中断';
  static const channelErrorsDescription = '会话异常中断或出错时推送系统通知';
  static const notificationErrorsId = 1201;

  /// 兼容历史 channel 常量。
  static const channelId = channelTurnsId;
  static const channelName = channelTurnsName;
  static const channelDescription = channelTurnsDescription;
  static const notificationId = notificationTurnsId;

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
          windows: WindowsInitializationSettings(
            appName: 'Hermes UI',
            appUserModelId: 'com.hermes.ui',
            guid: 'd9b0a6fb-9a4f-4d33-97be-4ef018260827',
          ),
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
        id: notificationTurnsId,
        title: title,
        body: formatPreview(preview),
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            channelTurnsId,
            channelTurnsName,
            channelDescription: channelTurnsDescription,
            importance: Importance.high,
            priority: Priority.high,
          ),
          windows: WindowsNotificationDetails(),
        ),
        payload: sessionId,
      );
    } on Object catch (error) {
      developer.log('回合完成通知发送失败: $error', name: 'notifications');
    }
  }

  @override
  Future<void> notifyClarificationNeeded(
    String sessionId,
    String question,
  ) async {
    if (sessionId.isEmpty) return;
    await _ensureInitialized();
    try {
      await _plugin.show(
        id: notificationClarifyId,
        title: '需要澄清',
        body: formatPreview(question),
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            channelClarifyId,
            channelClarifyName,
            channelDescription: channelClarifyDescription,
            importance: Importance.high,
            priority: Priority.high,
          ),
          windows: WindowsNotificationDetails(),
        ),
        payload: sessionId,
      );
    } on Object catch (error) {
      developer.log('澄清请求通知发送失败: $error', name: 'notifications');
    }
  }

  @override
  Future<void> notifySessionError(
    String sessionId,
    String title,
    String preview,
  ) async {
    if (sessionId.isEmpty) return;
    await _ensureInitialized();
    final heading = title.trim().isNotEmpty ? title.trim() : '会话异常';
    try {
      await _plugin.show(
        id: notificationErrorsId,
        title: heading,
        body: formatPreview(preview),
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            channelErrorsId,
            channelErrorsName,
            channelDescription: channelErrorsDescription,
            importance: Importance.high,
            priority: Priority.high,
          ),
          windows: WindowsNotificationDetails(),
        ),
        payload: sessionId,
      );
    } on Object catch (error) {
      developer.log('异常中断通知发送失败: $error', name: 'notifications');
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
    // 必须先初始化插件（根因②：此前未 initialize 直接 invoke 权限通道，
    // 异常被 catch 吞 → false → 后台 show 全被系统丢弃）。
    await _ensureInitialized();
    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      final granted = await android?.requestNotificationsPermission();
      final result = granted ?? true;
      DiagnosticsService.instance.log(
        level: DiagnosticsLogLevel.info,
        tag: 'notifications',
        message: '请求通知权限结果: $result',
      );
      return result;
    } on Object catch (error) {
      developer.log('请求通知权限失败: $error', name: 'notifications');
      DiagnosticsService.instance.log(
        level: DiagnosticsLogLevel.error,
        tag: 'notifications',
        message: '请求通知权限失败',
        errorKind: error.toString(),
      );
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
