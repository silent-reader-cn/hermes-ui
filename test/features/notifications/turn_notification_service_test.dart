import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_ui/features/notifications/turn_notification_service.dart';
import 'package:mocktail/mocktail.dart';

class _MockPlugin extends Mock implements FlutterLocalNotificationsPlugin {}

void main() {
  setUpAll(() {
    registerFallbackValue(const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ));
    registerFallbackValue(const NotificationDetails());
    registerFallbackValue(const NotificationAppLaunchDetails(false));
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

    group('requestPermission / getLaunchSessionId', () {
      test('无 Android 实现（桌面/测试环境）→ 视为已授权', () async {
        // mock 的 resolvePlatformSpecificImplementation 默认返回 null
        expect(await service.requestPermission(), isTrue);
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
  });
}
