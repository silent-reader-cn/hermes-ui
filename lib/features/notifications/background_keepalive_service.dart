import 'dart:async';
import 'dart:developer' as developer;

import 'package:android_intent_plus/android_intent.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    hide NotificationVisibility;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../diagnostics/diagnostics_models.dart';
import '../diagnostics/diagnostics_service.dart';
import 'turn_notification_service.dart';

/// HyperOS / Android 系统保活与权限跳转类型。
enum HyperOsSettingType {
  /// 自启动管理（小米安全中心 / 标准应用详情）
  autoStart,

  /// 省电策略（无限制 / 电池优化）
  batteryOptimization,

  /// 联网控制（WLAN / 移动数据）
  networkControl,

  /// 系统通知设置
  notificationSettings,
}

/// 后台保活服务接口（抽象接口，便于单元测试与平台解耦）。
abstract interface class BackgroundKeepaliveService {
  /// 单例实例访问（默认指向生产单例或测试注入实例）。
  static BackgroundKeepaliveService instance =
      ProductionBackgroundKeepaliveService();

  /// 冷启动初始化（注册 WorkManager 与 ForegroundTask 配置）。
  Future<void> initialize();

  /// App 生命周期变更联动。
  Future<void> onAppLifecycleChanged({
    required AppLifecycleState state,
    required String? activeSessionId,
    required String? activeStreamId,
    required bool isStreaming,
    required bool foregroundServiceEnabled,
  });

  /// 启动前台服务（持 WakeLock 保活网络）。
  Future<void> startForegroundService({
    required String sessionId,
    required String? streamId,
  });

  /// 停止前台服务。
  Future<void> stopForegroundService();

  /// 调度 WorkManager 加急/退避单次轮询任务。
  Future<void> scheduleExpeditedOneOffPoll({
    required String sessionId,
    required String? streamId,
  });

  /// 取消指定会话的单次轮询任务。
  Future<void> cancelOneOffPoll(String sessionId);

  /// 标记某回合已由前台或后台发送过通知（去重）。
  Future<void> recordTurnNotified({
    required String sessionId,
    required String? streamId,
  });

  /// 检查某回合是否已发送过通知。
  Future<bool> isTurnAlreadyNotified({
    required String sessionId,
    required String? streamId,
  });

  /// 打开系统/HyperOS 引导设置页。
  Future<void> openHyperOsSetting(HyperOsSettingType type);

  /// WorkManager 任务处理静态入口。
  static Future<bool> handleWorkManagerTask(
    String taskName,
    Map<String, dynamic>? inputData,
  ) async {
    return await ProductionBackgroundKeepaliveService.handleTask(
      taskName,
      inputData,
    );
  }
}

/// WorkManager 顶层回调分发器（必须为 top-level 或 static 函数并标 @pragma('vm:entry-point')）。
@pragma('vm:entry-point')
void workmanagerCallbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    return await BackgroundKeepaliveService.handleWorkManagerTask(
      taskName,
      inputData,
    );
  });
}

/// 生产级后台保活实现（基于 WorkManager + flutter_foreground_task + android_intent_plus）。
class ProductionBackgroundKeepaliveService
    implements BackgroundKeepaliveService {
  ProductionBackgroundKeepaliveService({
    Workmanager? workmanager,
  }) : _workmanager = workmanager ?? Workmanager();

  final Workmanager _workmanager;

  static const String periodicTaskTag = 'hermes-bg-poll';
  static const String periodicTaskUniqueName = 'hermes-bg-poll-periodic';
  static const String periodicTaskName = 'hermes.bg.poll.periodic';

  static const String oneOffTaskTag = 'hermes-bg-oneoff';
  static const String oneOffTaskName = 'hermes.bg.poll.oneoff';

  static const String keyActiveBaseUrl = 'bg_active_base_url';
  static const String keyActiveSessionId = 'bg_active_session_id';
  static const String keyActiveStreamId = 'bg_active_stream_id';
  static const String keyIsStreaming = 'bg_is_streaming';
  static const String keyLastNotifiedStreamPrefix = 'bg_last_notified_stream_';
  static const String keyLastNotifiedSessionPrefix = 'bg_last_notified_session_';

  bool _initialized = false;
  bool _foregroundServiceRunning = false;

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  Future<void> initialize() async {
    if (_initialized || !_isAndroid) return;
    _initialized = true;

    try {
      // 1. 初始化 WorkManager
      await _workmanager.initialize(
        workmanagerCallbackDispatcher,
        isInDebugMode: false,
      );

      // 2. 注册周期性轮询（15min 系统最小周期，约束：联网）
      await _workmanager.registerPeriodicTask(
        periodicTaskUniqueName,
        periodicTaskName,
        tag: periodicTaskTag,
        frequency: const Duration(minutes: 15),
        constraints: Constraints(
          networkType: NetworkType.connected,
        ),
        existingWorkPolicy: ExistingWorkPolicy.keep,
        backoffPolicy: BackoffPolicy.exponential,
        backoffPolicyDelay: const Duration(seconds: 30),
      );

      // 3. 初始化 Foreground Task
      FlutterForegroundTask.init(
        androidNotificationOptions: AndroidNotificationOptions(
          channelId: 'hermes_foreground_service',
          channelName: '后台生成保活',
          channelDescription: '后台流式生成进行中常驻通知',
          channelImportance: NotificationChannelImportance.LOW,
          priority: NotificationPriority.LOW,
          enableVibration: false,
          playSound: false,
          showWhen: false,
          visibility: NotificationVisibility.VISIBILITY_PUBLIC,
        ),
        iosNotificationOptions: const IOSNotificationOptions(
          showNotification: false,
          playSound: false,
        ),
        foregroundTaskOptions: ForegroundTaskOptions(
          eventAction: ForegroundTaskEventAction.nothing(),
          autoRunOnBoot: false,
          autoRunOnMyPackageReplaced: false,
          allowWakeLock: true,
          allowWifiLock: true,
        ),
      );

      DiagnosticsService.instance.log(
        level: DiagnosticsLogLevel.info,
        tag: 'keepalive',
        message: '后台保活服务初始化成功（WorkManager + ForegroundTask）',
      );
    } catch (e, st) {
      developer.log('后台保活服务初始化失败: $e', error: e, stackTrace: st);
      DiagnosticsService.instance.log(
        level: DiagnosticsLogLevel.error,
        tag: 'keepalive',
        message: '后台保活服务初始化失败',
        errorKind: e.toString(),
      );
    }
  }

  @override
  Future<void> onAppLifecycleChanged({
    required AppLifecycleState state,
    required String? activeSessionId,
    required String? activeStreamId,
    required bool isStreaming,
    required bool foregroundServiceEnabled,
  }) async {
    if (!_isAndroid) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(keyActiveSessionId, activeSessionId ?? '');
      await prefs.setString(keyActiveStreamId, activeStreamId ?? '');
      await prefs.setBool(keyIsStreaming, isStreaming);

      if (state == AppLifecycleState.resumed) {
        // 回到前台：停止前台服务并清理通知
        await stopForegroundService();
        if (activeSessionId != null && activeSessionId.isNotEmpty) {
          await cancelOneOffPoll(activeSessionId);
        }
      } else {
        // 切后台：若正在生成
        if (isStreaming || (activeStreamId != null && activeStreamId.isNotEmpty)) {
          if (foregroundServiceEnabled) {
            await startForegroundService(
              sessionId: activeSessionId ?? '',
              streamId: activeStreamId,
            );
          }
          if (activeSessionId != null && activeSessionId.isNotEmpty) {
            await scheduleExpeditedOneOffPoll(
              sessionId: activeSessionId,
              streamId: activeStreamId,
            );
          }
        }
      }
    } catch (e) {
      developer.log('onAppLifecycleChanged error: $e');
    }
  }

  @override
  Future<void> startForegroundService({
    required String sessionId,
    required String? streamId,
  }) async {
    if (!_isAndroid) return;
    if (_foregroundServiceRunning) return;

    try {
      if (!_initialized) {
        await initialize();
      }
      final isRunning = await FlutterForegroundTask.isRunningService;
      if (isRunning) {
        _foregroundServiceRunning = true;
        return;
      }

      await FlutterForegroundTask.startService(
        notificationTitle: 'Hermes',
        notificationText: 'Hermes 正在生成…',
      );
      _foregroundServiceRunning = true;
      DiagnosticsService.instance.log(
        level: DiagnosticsLogLevel.info,
        tag: 'keepalive',
        message: '启动前台保活服务成功',
        details: {'sessionId': sessionId, 'streamId': streamId},
      );
    } catch (e) {
      developer.log('startForegroundService error: $e');
      DiagnosticsService.instance.log(
        level: DiagnosticsLogLevel.error,
        tag: 'keepalive',
        message: '启动前台保活服务失败',
        errorKind: e.toString(),
      );
    }
  }

  @override
  Future<void> stopForegroundService() async {
    if (!_isAndroid) return;
    try {
      final isRunning = await FlutterForegroundTask.isRunningService;
      if (isRunning) {
        await FlutterForegroundTask.stopService();
      }
      _foregroundServiceRunning = false;
      DiagnosticsService.instance.log(
        level: DiagnosticsLogLevel.info,
        tag: 'keepalive',
        message: '停止前台保活服务',
      );
    } catch (e) {
      developer.log('stopForegroundService error: $e');
    }
  }

  @override
  Future<void> scheduleExpeditedOneOffPoll({
    required String sessionId,
    required String? streamId,
  }) async {
    if (!_isAndroid || sessionId.isEmpty) return;
    try {
      final uniqueName = 'hermes-bg-oneoff-$sessionId';
      await _workmanager.registerOneOffTask(
        uniqueName,
        oneOffTaskName,
        tag: oneOffTaskTag,
        initialDelay: const Duration(minutes: 1),
        constraints: Constraints(
          networkType: NetworkType.connected,
        ),
        backoffPolicy: BackoffPolicy.exponential,
        backoffPolicyDelay: const Duration(seconds: 30),
        outOfQuotaPolicy: OutOfQuotaPolicy.run_as_non_expedited_work_request,
        inputData: {
          'sessionId': sessionId,
          'streamId': streamId ?? '',
        },
      );
      DiagnosticsService.instance.log(
        level: DiagnosticsLogLevel.info,
        tag: 'keepalive',
        message: '调度 WorkManager 加急探活任务',
        details: {'sessionId': sessionId, 'streamId': streamId},
      );
    } catch (e) {
      developer.log('scheduleExpeditedOneOffPoll error: $e');
    }
  }

  @override
  Future<void> cancelOneOffPoll(String sessionId) async {
    if (!_isAndroid || sessionId.isEmpty) return;
    try {
      final uniqueName = 'hermes-bg-oneoff-$sessionId';
      await _workmanager.cancelByUniqueName(uniqueName);
    } catch (e) {
      developer.log('cancelOneOffPoll error: $e');
    }
  }

  @override
  Future<void> recordTurnNotified({
    required String sessionId,
    required String? streamId,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final nowStr = DateTime.now().toIso8601String();
      if (streamId != null && streamId.isNotEmpty) {
        await prefs.setString('$keyLastNotifiedStreamPrefix$streamId', nowStr);
      }
      if (sessionId.isNotEmpty) {
        await prefs.setString(
            '$keyLastNotifiedSessionPrefix$sessionId', nowStr);
      }
    } catch (e) {
      developer.log('recordTurnNotified error: $e');
    }
  }

  @override
  Future<bool> isTurnAlreadyNotified({
    required String sessionId,
    required String? streamId,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (streamId != null && streamId.isNotEmpty) {
        final val = prefs.getString('$keyLastNotifiedStreamPrefix$streamId');
        if (val != null && val.isNotEmpty) return true;
      }
      if (sessionId.isNotEmpty) {
        final val = prefs.getString('$keyLastNotifiedSessionPrefix$sessionId');
        if (val != null && val.isNotEmpty) {
          // 30秒内同一会话判定为已通知
          final dt = DateTime.tryParse(val);
          if (dt != null &&
              DateTime.now().difference(dt).inSeconds < 30) {
            return true;
          }
        }
      }
    } catch (e) {
      developer.log('isTurnAlreadyNotified error: $e');
    }
    return false;
  }

  @override
  Future<void> openHyperOsSetting(HyperOsSettingType type) async {
    if (!_isAndroid) return;
    try {
      String? packageName;
      try {
        final pkgInfo = await PackageInfo.fromPlatform();
        packageName = pkgInfo.packageName;
      } catch (_) {
        packageName = 'com.silentreader.hermes_ui';
      }

      switch (type) {
        case HyperOsSettingType.autoStart:
          await _tryLaunchIntents([
            // 1. 小米安全中心自启动管理
            const AndroidIntent(
              action: 'miui.intent.action.OP_AUTO_START',
              componentName:
                  'com.miui.securitycenter/com.miui.permcenter.autostart.AutoStartManagementActivity',
            ),
            // 2. 小米应用权限管理
            AndroidIntent(
              action: 'miui.intent.action.APP_PERM_EDITOR',
              componentName:
                  'com.miui.securitycenter/com.miui.permcenter.permissions.PermissionsEditorActivity',
              arguments: {'extra_pkgname': packageName},
            ),
            // 3. 通用应用详情
            AndroidIntent(
              action: 'android.settings.APPLICATION_DETAILS_SETTINGS',
              data: 'package:$packageName',
            ),
          ]);
          break;

        case HyperOsSettingType.batteryOptimization:
          await _tryLaunchIntents([
            // 1. 小米省电策略详情
            AndroidIntent(
              componentName:
                  'com.miui.powerkeeper/com.miui.powerkeeper.ui.HiddenAppsConfigActivity',
              arguments: {
                'package_name': packageName,
                'package_label': 'Hermes',
              },
            ),
            // 2. 原生忽略电池优化设置
            const AndroidIntent(
              action: 'android.settings.IGNORE_BATTERY_OPTIMIZATION_SETTINGS',
            ),
            // 3. 通用应用详情
            AndroidIntent(
              action: 'android.settings.APPLICATION_DETAILS_SETTINGS',
              data: 'package:$packageName',
            ),
          ]);
          break;

        case HyperOsSettingType.networkControl:
          await _tryLaunchIntents([
            // 1. 小米网络助手 / 联网控制
            const AndroidIntent(
              componentName:
                  'com.miui.networkassistant/com.miui.networkassistant.ui.NetworkAssistantActivity',
            ),
            // 2. 原生网络设置
            const AndroidIntent(
              action: 'android.settings.WIRELESS_SETTINGS',
            ),
            // 3. 通用应用详情
            AndroidIntent(
              action: 'android.settings.APPLICATION_DETAILS_SETTINGS',
              data: 'package:$packageName',
            ),
          ]);
          break;

        case HyperOsSettingType.notificationSettings:
          await _tryLaunchIntents([
            // 1. 原生应用通知设置 (API 26+)
            AndroidIntent(
              action: 'android.settings.APP_NOTIFICATION_SETTINGS',
              arguments: {
                'android.provider.extra.APP_PACKAGE': packageName,
              },
            ),
            // 2. 通用应用详情
            AndroidIntent(
              action: 'android.settings.APPLICATION_DETAILS_SETTINGS',
              data: 'package:$packageName',
            ),
          ]);
          break;
      }
    } catch (e) {
      developer.log('openHyperOsSetting error: $e');
      DiagnosticsService.instance.log(
        level: DiagnosticsLogLevel.error,
        tag: 'keepalive',
        message: '跳转系统设置页异常',
        errorKind: e.toString(),
      );
    }
  }

  Future<void> _tryLaunchIntents(List<AndroidIntent> intents) async {
    for (final intent in intents) {
      try {
        await intent.launch();
        return;
      } catch (_) {
        // 尝试下一个候选 intent
      }
    }
  }

  /// 静态后台任务执行体（由 WorkManager 在后台 Isolate 调用）。
  static Future<bool> handleTask(
    String taskName,
    Map<String, dynamic>? inputData,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final notifyTurns = prefs.getBool('notify_turns_enabled') ?? true;
      final notifyClarify = prefs.getBool('notify_clarify_enabled') ?? true;
      final notifyErrors = prefs.getBool('notify_errors_enabled') ?? true;

      if (!notifyTurns && !notifyClarify && !notifyErrors) {
        return true;
      }

      final baseUrl = prefs.getString(keyActiveBaseUrl);
      if (baseUrl == null || baseUrl.isEmpty) {
        return true;
      }

      final sessionId = (inputData?['sessionId'] as String?) ??
          prefs.getString(keyActiveSessionId) ??
          '';
      final streamId = (inputData?['streamId'] as String?) ??
          prefs.getString(keyActiveStreamId) ??
          '';

      if (sessionId.isEmpty && streamId.isEmpty) {
        return true;
      }

      final dio = Dio(
        BaseOptions(
          baseUrl: baseUrl.endsWith('/')
              ? baseUrl.substring(0, baseUrl.length - 1)
              : baseUrl,
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 15),
          headers: {'Accept': 'application/json'},
        ),
      );

      // 1. 若有 activeStreamId，查 /api/chat/stream/status
      if (streamId.isNotEmpty) {
        try {
          final res = await dio.get<Map<String, dynamic>>(
            '/api/chat/stream/status',
            queryParameters: {'stream_id': streamId},
          );
          final data = res.data;
          if (data != null) {
            final active = data['active'] == true;
            final journal = data['journal'] as Map<String, dynamic>?;
            final terminal = journal?['terminal'] == true;
            final terminalState = journal?['terminal_state']?.toString();

            if (!active || terminal) {
              // 流已在服务端收尾，检查是否已通知
              final alreadyNotified =
                  prefs.getString('$keyLastNotifiedStreamPrefix$streamId') != null;
              if (!alreadyNotified) {
                // 判断完成/澄清/错误类型
                final isError = terminalState == 'error' ||
                    terminalState == 'cancelled' ||
                    terminalState == 'interrupted';
                final isClarify = terminalState == 'clarify' ||
                    terminalState == 'clarification_needed';

                if (isClarify && notifyClarify) {
                  await _showBackgroundNotification(
                    id: LocalNotificationsTurnNotificationService
                        .notificationClarifyId,
                    channelId: LocalNotificationsTurnNotificationService
                        .channelClarifyId,
                    channelName: LocalNotificationsTurnNotificationService
                        .channelClarifyName,
                    channelDesc: LocalNotificationsTurnNotificationService
                        .channelClarifyDescription,
                    title: '需要澄清',
                    body: 'Agent 需要你澄清，点击查看',
                    payload: sessionId,
                  );
                } else if (isError && notifyErrors) {
                  await _showBackgroundNotification(
                    id: LocalNotificationsTurnNotificationService
                        .notificationErrorsId,
                    channelId: LocalNotificationsTurnNotificationService
                        .channelErrorsId,
                    channelName: LocalNotificationsTurnNotificationService
                        .channelErrorsName,
                    channelDesc: LocalNotificationsTurnNotificationService
                        .channelErrorsDescription,
                    title: '会话异常',
                    body: '会话生成异常中断，点击查看',
                    payload: sessionId,
                  );
                } else if (notifyTurns) {
                  // 补拉会话最新内容作为预览
                  String preview = 'Agent 回合已生成完毕，点击查看';
                  try {
                    final sessionRes = await dio.get<Map<String, dynamic>>(
                      '/api/session',
                      queryParameters: {
                        'session_id': sessionId,
                        'messages': 1,
                        'include_messages': true,
                      },
                    );
                    final sessData = sessionRes.data;
                    final sDetail = sessData?['session'] as Map<String, dynamic>? ??
                        sessData;
                    final msgs = sDetail?['messages'] as List?;
                    if (msgs != null && msgs.isNotEmpty) {
                      for (final m in msgs.reversed) {
                        if (m is Map &&
                            m['role'] == 'assistant' &&
                            m['content'] is String &&
                            (m['content'] as String).trim().isNotEmpty) {
                          preview = LocalNotificationsTurnNotificationService
                              .formatPreview(m['content'] as String);
                          break;
                        }
                      }
                    }
                  } catch (_) {}

                  await _showBackgroundNotification(
                    id: LocalNotificationsTurnNotificationService
                        .notificationTurnsId,
                    channelId: LocalNotificationsTurnNotificationService
                        .channelTurnsId,
                    channelName: LocalNotificationsTurnNotificationService
                        .channelTurnsName,
                    channelDesc: LocalNotificationsTurnNotificationService
                        .channelTurnsDescription,
                    title: '回合完成',
                    body: preview,
                    payload: sessionId,
                  );
                }

                // 标记已通知
                final nowStr = DateTime.now().toIso8601String();
                await prefs.setString(
                    '$keyLastNotifiedStreamPrefix$streamId', nowStr);
                if (sessionId.isNotEmpty) {
                  await prefs.setString(
                      '$keyLastNotifiedSessionPrefix$sessionId', nowStr);
                }
              }

              // 清理 activeStream 状态并取消 OneOff
              await prefs.setString(keyActiveStreamId, '');
              await prefs.setBool(keyIsStreaming, false);
              try {
                await Workmanager().cancelByUniqueName('hermes-bg-oneoff-$sessionId');
              } catch (_) {}
              return true;
            }
          }
        } catch (e) {
          developer.log('WorkManager /api/chat/stream/status error: $e');
          // 网络抖动，返回 false 触发指数退避
          return false;
        }
      }

      // 2. 查 /api/session
      if (sessionId.isNotEmpty) {
        try {
          final res = await dio.get<Map<String, dynamic>>(
            '/api/session',
            queryParameters: {
              'session_id': sessionId,
              'messages': 1,
              'include_messages': true,
            },
          );
          final sessData = res.data;
          final sDetail =
              sessData?['session'] as Map<String, dynamic>? ?? sessData;
          final isStreaming = sDetail?['is_streaming'] == true;
          final activeStream = sDetail?['active_stream_id'] as String?;

          if (!isStreaming && (activeStream == null || activeStream.isEmpty)) {
            // 已不在生成状态，检查去重
            final lastNotified =
                prefs.getString('$keyLastNotifiedSessionPrefix$sessionId');
            final wasStreaming = prefs.getBool(keyIsStreaming) ?? false;

            if (wasStreaming && lastNotified == null && notifyTurns) {
              String preview = 'Agent 回合已生成完毕，点击查看';
              final msgs = sDetail?['messages'] as List?;
              if (msgs != null && msgs.isNotEmpty) {
                for (final m in msgs.reversed) {
                  if (m is Map &&
                      m['role'] == 'assistant' &&
                      m['content'] is String &&
                      (m['content'] as String).trim().isNotEmpty) {
                    preview = LocalNotificationsTurnNotificationService
                        .formatPreview(m['content'] as String);
                    break;
                  }
                }
              }

              await _showBackgroundNotification(
                id: LocalNotificationsTurnNotificationService
                    .notificationTurnsId,
                channelId: LocalNotificationsTurnNotificationService
                    .channelTurnsId,
                channelName: LocalNotificationsTurnNotificationService
                    .channelTurnsName,
                channelDesc: LocalNotificationsTurnNotificationService
                    .channelTurnsDescription,
                title: '回合完成',
                body: preview,
                payload: sessionId,
              );

              final nowStr = DateTime.now().toIso8601String();
              await prefs.setString(
                  '$keyLastNotifiedSessionPrefix$sessionId', nowStr);
              await prefs.setBool(keyIsStreaming, false);
            }
          }
        } catch (e) {
          developer.log('WorkManager /api/session error: $e');
          return false;
        }
      }

      return true;
    } catch (e) {
      developer.log('handleTask unexpected error: $e');
      return false;
    }
  }

  static Future<void> _showBackgroundNotification({
    required int id,
    required String channelId,
    required String channelName,
    required String channelDesc,
    required String title,
    required String body,
    required String payload,
  }) async {
    try {
      final plugin = FlutterLocalNotificationsPlugin();
      await plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );
      await plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            channelId,
            channelName,
            channelDescription: channelDesc,
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
        payload: payload,
      );
    } catch (e) {
      developer.log('showBackgroundNotification error: $e');
    }
  }
}

/// 测试用 FakeBackgroundKeepaliveService 实现。
class FakeBackgroundKeepaliveService implements BackgroundKeepaliveService {
  final List<String> startedForegroundServices = [];
  final List<String> stoppedForegroundServices = [];
  final List<(String sessionId, String? streamId)> scheduledOneOffPolls = [];
  final List<String> cancelledOneOffPolls = [];
  final List<(String sessionId, String? streamId)> notifiedRecords = [];
  final List<HyperOsSettingType> openedSettings = [];

  bool isInitialized = false;

  @override
  Future<void> initialize() async {
    isInitialized = true;
  }

  @override
  Future<void> onAppLifecycleChanged({
    required AppLifecycleState state,
    required String? activeSessionId,
    required String? activeStreamId,
    required bool isStreaming,
    required bool foregroundServiceEnabled,
  }) async {
    if (state == AppLifecycleState.resumed) {
      await stopForegroundService();
      if (activeSessionId != null && activeSessionId.isNotEmpty) {
        await cancelOneOffPoll(activeSessionId);
      }
    } else {
      if (isStreaming || (activeStreamId != null && activeStreamId.isNotEmpty)) {
        if (foregroundServiceEnabled) {
          await startForegroundService(
            sessionId: activeSessionId ?? '',
            streamId: activeStreamId,
          );
        }
        if (activeSessionId != null && activeSessionId.isNotEmpty) {
          await scheduleExpeditedOneOffPoll(
            sessionId: activeSessionId,
            streamId: activeStreamId,
          );
        }
      }
    }
  }

  @override
  Future<void> startForegroundService({
    required String sessionId,
    required String? streamId,
  }) async {
    startedForegroundServices.add(sessionId);
  }

  @override
  Future<void> stopForegroundService() async {
    stoppedForegroundServices.add('stopped');
  }

  @override
  Future<void> scheduleExpeditedOneOffPoll({
    required String sessionId,
    required String? streamId,
  }) async {
    scheduledOneOffPolls.add((sessionId, streamId));
  }

  @override
  Future<void> cancelOneOffPoll(String sessionId) async {
    cancelledOneOffPolls.add(sessionId);
  }

  @override
  Future<void> recordTurnNotified({
    required String sessionId,
    required String? streamId,
  }) async {
    notifiedRecords.add((sessionId, streamId));
  }

  @override
  Future<bool> isTurnAlreadyNotified({
    required String sessionId,
    required String? streamId,
  }) async {
    return notifiedRecords.any(
      (r) =>
          (streamId != null && streamId.isNotEmpty && r.$2 == streamId) ||
          (sessionId.isNotEmpty && r.$1 == sessionId),
    );
  }

  @override
  Future<void> openHyperOsSetting(HyperOsSettingType type) async {
    openedSettings.add(type);
  }
}
