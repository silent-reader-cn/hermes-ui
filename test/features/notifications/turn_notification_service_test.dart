import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/features/diagnostics/diagnostics_models.dart';
import 'package:hermes_ui/features/diagnostics/diagnostics_service.dart';
import 'package:hermes_ui/features/notifications/turn_notification_service.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockPlugin extends Mock implements FlutterLocalNotificationsPlugin {}

class _MockAndroidPlugin extends Mock
    implements AndroidFlutterLocalNotificationsPlugin {}

void main() {
  setUpAll(() {
    registerFallbackValue(const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ));
    registerFallbackValue(const NotificationDetails());
    registerFallbackValue(const NotificationAppLaunchDetails(false));
    registerFallbackValue(const AndroidNotificationChannel('id', 'name'));
  });

  group('LocalNotificationsTurnNotificationService', () {
    late _MockPlugin plugin;
    late LocalNotificationsTurnNotificationService service;
    final List<String> tapped = [];

    setUp(() {
      plugin = _MockPlugin();
      tapped.clear();
      service = LocalNotificationsTurnNotificationService(
        plugin: plugin,
        onTap: tapped.add,
      );
      when(
        () => plugin.initialize(
          settings: any(named: 'settings'),
          onDidReceiveNotificationResponse:
              any(named: 'onDidReceiveNotificationResponse'),
        ),
      ).thenAnswer((_) async => true);
      when(
        () => plugin.show(
          id: any(named: 'id'),
          title: any(named: 'title'),
          body: any(named: 'body'),
          notificationDetails: any(named: 'notificationDetails'),
          payload: any(named: 'payload'),
        ),
      ).thenAnswer((_) async {});
      when(() => plugin.cancelAll()).thenAnswer((_) async {});
    });

    group('notifyTurnCompleted 参数组装', () {
      test('首次调用先 initialize，再 show 到 "turns" 通道、payload 带 sessionId',
          () async {
        await service.notifyTurnCompleted('sess-1', '我的会话', '你好！');

        verify(
          () => plugin.initialize(
            settings: any(named: 'settings'),
            onDidReceiveNotificationResponse:
                any(named: 'onDidReceiveNotificationResponse'),
          ),
        ).called(1);

        final details = verify(
          () => plugin.show(
            id: 1001,
            title: '我的会话',
            body: '你好！',
            notificationDetails: captureAny(named: 'notificationDetails'),
            payload: 'sess-1',
          ),
        ).captured.single as NotificationDetails;

        expect(details.android, isNotNull);
        expect(details.android!.channelId, 'turns');
        expect(details.android!.channelName, '回合完成');
        expect(details.android!.channelDescription, isNotEmpty);
        expect(details.android!.importance, Importance.high);
        expect(details.android!.priority, Priority.high);
        expect(details.windows, isNotNull);
      });

      test('重复通知：initialize 仅一次、固定 id 替换旧通知', () async {
        await service.notifyTurnCompleted('s1', 't', 'p');
        await service.notifyTurnCompleted('s1', 't', 'p');

        verify(
          () => plugin.initialize(
            settings: any(named: 'settings'),
            onDidReceiveNotificationResponse:
                any(named: 'onDidReceiveNotificationResponse'),
          ),
        ).called(1);
        verify(
          () => plugin.show(
            id: 1001,
            title: any(named: 'title'),
            body: any(named: 'body'),
            notificationDetails: any(named: 'notificationDetails'),
            payload: any(named: 'payload'),
          ),
        ).called(2);
      });

      test('sessionId 为空 → 不弹通知', () async {
        await service.notifyTurnCompleted('', 't', 'p');
        verifyNever(
          () => plugin.show(
            id: any(named: 'id'),
            title: any(named: 'title'),
            body: any(named: 'body'),
            notificationDetails: any(named: 'notificationDetails'),
            payload: any(named: 'payload'),
          ),
        );
      });
    });

    group('notifyClarificationNeeded 参数组装', () {
      test('show 到 "clarify" 通道、id 为 1101', () async {
        await service.notifyClarificationNeeded('sess-2', '请问您需要选择哪种模式？');

        final details = verify(
          () => plugin.show(
            id: 1101,
            title: '需要澄清',
            body: '请问您需要选择哪种模式？',
            notificationDetails: captureAny(named: 'notificationDetails'),
            payload: 'sess-2',
          ),
        ).captured.single as NotificationDetails;

        expect(details.android, isNotNull);
        expect(details.android!.channelId, 'clarify');
        expect(details.android!.channelName, '需要澄清');
        expect(details.android!.importance, Importance.high);
        expect(details.windows, isNotNull);
      });
    });

    group('notifySessionError 参数组装', () {
      test('show 到 "errors" 通道、id 为 1201', () async {
        await service.notifySessionError('sess-3', '响应已取消', '用户已停止');

        final details = verify(
          () => plugin.show(
            id: 1201,
            title: '响应已取消',
            body: '用户已停止',
            notificationDetails: captureAny(named: 'notificationDetails'),
            payload: 'sess-3',
          ),
        ).captured.single as NotificationDetails;

        expect(details.android, isNotNull);
        expect(details.android!.channelId, 'errors');
        expect(details.android!.channelName, '异常中断');
        expect(details.android!.importance, Importance.high);
        expect(details.windows, isNotNull);
      });
    });

    group('formatPreview', () {
      test('多行压缩为单行', () {
        expect(
          LocalNotificationsTurnNotificationService.formatPreview(
            '第一行\n第二行\t带缩进',
          ),
          '第一行 第二行 带缩进',
        );
      });

      test('超长截断到 120 字符并带省略号', () {
        final long = 'a' * 200;
        final result =
            LocalNotificationsTurnNotificationService.formatPreview(long);
        expect(result.length, 121); // 120 + '…'
        expect(result.endsWith('…'), isTrue);
        expect(result.substring(0, 120), 'a' * 120);
      });

      test('短文本原样保留', () {
        expect(
          LocalNotificationsTurnNotificationService.formatPreview('完成了'),
          '完成了',
        );
      });

      test('空文本 → 空串', () {
        expect(
          LocalNotificationsTurnNotificationService.formatPreview('   '),
          '',
        );
      });
    });

    group('clearAll', () {
      test('委托插件 cancelAll', () async {
        await service.clearAll();
        verify(() => plugin.cancelAll()).called(1);
      });
    });

    group('点击通知回调', () {
      test('initialize 注册的 response 回调 → payload 转成 onTap(sessionId)',
          () async {
        await service.notifyTurnCompleted('s1', 't', 'p');
        final captured = verify(
          () => plugin.initialize(
            settings: any(named: 'settings'),
            onDidReceiveNotificationResponse:
                captureAny(named: 'onDidReceiveNotificationResponse'),
          ),
        ).captured;
        final callback =
            captured.single as DidReceiveNotificationResponseCallback;

        callback(const NotificationResponse(
          payload: 'sess-9',
          notificationResponseType: NotificationResponseType.selectedNotification,
        ));
        expect(tapped, ['sess-9']);

        // 空 payload 不触发
        callback(const NotificationResponse(
          payload: '',
          notificationResponseType: NotificationResponseType.selectedNotification,
        ));
        expect(tapped, ['sess-9']);
      });
    });

    group('Android 三渠道预创建与时序', () {
      test('冷启动/首次初始化显式批量预创建三通知渠道（turns/clarify/errors）', () async {
        final android = _MockAndroidPlugin();
        when(
          () => plugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>(),
        ).thenReturn(android);
        when(() => android.createNotificationChannel(any()))
            .thenAnswer((_) async {});
        when(() => android.requestNotificationsPermission())
            .thenAnswer((_) async => true);

        await service.requestPermission();

        // 验证三渠道预创建
        final captured = verify(
          () => android.createNotificationChannel(captureAny()),
        ).captured;
        expect(captured, hasLength(3));

        final channels = captured.cast<AndroidNotificationChannel>();
        expect(channels[0].id, 'turns');
        expect(channels[0].name, '回合完成');
        expect(channels[0].description, 'Agent 回合完成时推送系统通知');
        expect(channels[0].importance, Importance.high);

        expect(channels[1].id, 'clarify');
        expect(channels[1].name, '需要澄清');
        expect(channels[1].description, 'Agent 需要用户澄清时推送系统通知');
        expect(channels[1].importance, Importance.high);

        expect(channels[2].id, 'errors');
        expect(channels[2].name, '异常中断');
        expect(channels[2].description, '会话异常中断或出错时推送系统通知');
        expect(channels[2].importance, Importance.high);
      });

      test('notifyTurnCompleted 前若未初始化，先 initialize 并创建三渠道再 show', () async {
        final android = _MockAndroidPlugin();
        when(
          () => plugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>(),
        ).thenReturn(android);
        when(() => android.createNotificationChannel(any()))
            .thenAnswer((_) async {});

        await service.notifyTurnCompleted('s-test', '标题', '正文');

        verifyInOrder([
          () => plugin.initialize(
                settings: any(named: 'settings'),
                onDidReceiveNotificationResponse:
                    any(named: 'onDidReceiveNotificationResponse'),
              ),
          () => android.createNotificationChannel(any()),
          () => plugin.show(
                id: 1001,
                title: '标题',
                body: '正文',
                notificationDetails: any(named: 'notificationDetails'),
                payload: 's-test',
              ),
        ]);
      });
    });

    group('requestPermission / getLaunchSessionId', () {
      test('无 Android 实现（桌面/测试环境）→ 视为已授权', () async {
        // mock 的 resolvePlatformSpecificImplementation 默认返回 null
        expect(await service.requestPermission(), isTrue);
      });

      test('根因②回归：先 initialize 再请求权限，授予结果原样返回', () async {
        final android = _MockAndroidPlugin();
        when(
          () => plugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>(),
        ).thenReturn(android);
        when(() => android.createNotificationChannel(any()))
            .thenAnswer((_) async {});
        when(() => android.requestNotificationsPermission())
            .thenAnswer((_) async => true);

        expect(await service.requestPermission(), isTrue);

        // 权限通道 invoke 前插件必须已完成 initialize（旧实现直接 invoke
        // 权限通道 → 异常被吞返回 false → 后台 show 全被系统丢弃）。
        verifyInOrder([
          () => plugin.initialize(
            settings: any(named: 'settings'),
            onDidReceiveNotificationResponse:
                any(named: 'onDidReceiveNotificationResponse'),
          ),
          () => android.requestNotificationsPermission(),
        ]);
      });

      test('通知点击冷启动 → 返回 payload sessionId', () async {
        when(
          () => plugin.getNotificationAppLaunchDetails(),
        ).thenAnswer(
          (_) async => const NotificationAppLaunchDetails(
            true,
            notificationResponse: NotificationResponse(
              payload: 'sess-cold',
              notificationResponseType:
                  NotificationResponseType.selectedNotification,
            ),
          ),
        );
        expect(await service.getLaunchSessionId(), 'sess-cold');
      });

      test('非通知启动 → null', () async {
        when(
          () => plugin.getNotificationAppLaunchDetails(),
        ).thenAnswer((_) async => const NotificationAppLaunchDetails(false));
        expect(await service.getLaunchSessionId(), isNull);
      });
    });

    group('DiagnosticsService 诊断日志采集', () {
      setUp(() async {
        SharedPreferences.setMockInitialValues({
          kDiagnosticsEnabledKey: true,
        });
        await DiagnosticsService.instance.init();
        await DiagnosticsService.instance.clear();
      });

      test('成功通知、权限请求与渠道预创建均记录 notifications tag 日志', () async {
        final android = _MockAndroidPlugin();
        when(
          () => plugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>(),
        ).thenReturn(android);
        when(() => android.createNotificationChannel(any()))
            .thenAnswer((_) async {});
        when(() => android.requestNotificationsPermission())
            .thenAnswer((_) async => true);

        await service.requestPermission();
        await service.notifyTurnCompleted('s1', '标题1', '正文1');
        await service.notifyClarificationNeeded('s2', '澄清问题');
        await service.notifySessionError('s3', '错误标题', '错误正文');
        await service.clearAll();

        final logs = DiagnosticsService.instance.logs
            .where((l) => l.tag == 'notifications')
            .toList();
        expect(logs, isNotEmpty);

        final messages = logs.map((l) => l.message).toList();
        expect(messages, contains('预创建 Android 通知渠道成功'));
        expect(messages, contains('请求通知权限结果: true'));
        expect(messages, contains('发送回合完成通知'));
        expect(messages, contains('发送需要澄清通知'));
        expect(messages, contains('发送异常中断通知'));
        expect(messages, contains('清除全部通知'));
      });

      test('异常吞没时记录 DiagnosticsLogLevel.error', () async {
        when(
          () => plugin.show(
            id: any(named: 'id'),
            title: any(named: 'title'),
            body: any(named: 'body'),
            notificationDetails: any(named: 'notificationDetails'),
            payload: any(named: 'payload'),
          ),
        ).thenThrow(Exception('系统通知通道失效'));

        await service.notifyTurnCompleted('s1', '标题', '正文');

        final errorLogs = DiagnosticsService.instance.logs
            .where((l) =>
                l.tag == 'notifications' && l.level == DiagnosticsLogLevel.error)
            .toList();
        expect(errorLogs, hasLength(1));
        expect(errorLogs.single.message, '回合完成通知发送失败');
        expect(errorLogs.single.errorKind, contains('系统通知通道失效'));
      });
    });
  });
}
