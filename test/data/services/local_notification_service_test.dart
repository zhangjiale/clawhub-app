import 'package:claw_hub/app/notifications/notification_bootstrap.dart';
import 'package:claw_hub/core/i_local_notification_service.dart';
import 'package:claw_hub/data/services/local_notification_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockPlugin extends Mock implements FlutterLocalNotificationsPlugin {}

/// 延迟捕获 initialize 注册的点击回调，便于测试模拟"通知被点击"。
DidReceiveNotificationResponseCallback? _capturedTapCallback;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    // mocktail 对复杂/Function 类型的 matcher 需注册 fallback value。
    registerFallbackValue(
      const InitializationSettings(
        android: AndroidInitializationSettings('ic_launcher'),
      ),
    );
    registerFallbackValue(NotificationDetails());
    registerFallbackValue(
      (NotificationResponse _) {} as DidReceiveNotificationResponseCallback,
    );
  });

  // ---- handleNotificationTap (来自 bootstrap，命名误导但保留) ----
  group('handleNotificationTap', () {
    test('null routePath is a no-op', () {
      handleNotificationTap(null);
    });

    test('empty routePath is a no-op', () {
      handleNotificationTap('');
    });
  });

  // ---- LocalNotificationService 核心逻辑 ----
  // 注：平台通道创建/权限请求依赖真实平台 API，这里只测与平台解耦的纯逻辑：
  // payload 透传、点击回调注册、冷启动 payload 补投时序。
  group('LocalNotificationService', () {
    late _MockPlugin plugin;
    late LocalNotificationService service;

    setUp(() {
      _capturedTapCallback = null;
      plugin = _MockPlugin();

      // initialize: 捕获 onDidReceiveNotificationResponse 回调，返回 true。
      when(
        () => plugin.initialize(
          any(),
          onDidReceiveNotificationResponse: any(
            named: 'onDidReceiveNotificationResponse',
          ),
        ),
      ).thenAnswer((inv) async {
        _capturedTapCallback =
            inv.namedArguments[#onDidReceiveNotificationResponse]
                as DidReceiveNotificationResponseCallback?;
        return true;
      });
      // 默认无冷启动 payload。
      when(
        () => plugin.getNotificationAppLaunchDetails(),
      ).thenAnswer((_) async => null);
      // show 默认成功 (返回 Future<void>)；具体断言在各 test 里 verify。
      // notificationDetails 是位置参数 (第 4 个)，非命名参数。
      when(
        () => plugin.show(
          any(),
          any(),
          any(),
          any(),
          payload: any(named: 'payload'),
        ),
      ).thenAnswer((_) async {});

      service = LocalNotificationService(plugin: plugin);
    });

    test('show forwards routePath as payload to the plugin', () async {
      await service.show(
        id: 42,
        channel: NotificationChannelId.reply,
        title: '虾',
        body: '你好',
        routePath: '/claws/chat/a',
      );

      verify(
        () => plugin.show(42, '虾', '你好', any(), payload: '/claws/chat/a'),
      ).called(1);
    });

    test('show forwards null payload when routePath omitted', () async {
      await service.show(
        id: 1,
        channel: NotificationChannelId.connection,
        title: 't',
        body: 'b',
      );

      verify(() => plugin.show(1, 't', 'b', any(), payload: null)).called(1);
    });

    test(
      'tap callback registered via setupOnTap receives payload when plugin fires onDidReceiveNotificationResponse',
      () async {
        await service.initialize();

        String? received;
        service.setupOnTap((routePath) => received = routePath);

        // 模拟用户点击通知 —— plugin 触发 initialize 时注册的回调。
        expect(_capturedTapCallback, isNotNull);
        _capturedTapCallback!(
          const NotificationResponse(
            id: 7,
            payload: '/claws/chat/a',
            notificationResponseType:
                NotificationResponseType.selectedNotification,
          ),
        );

        expect(received, '/claws/chat/a');
      },
    );

    test(
      'cold-launch payload is cached until setupOnTap, then flushed once',
      () async {
        // 冷启动点击通知：launch payload 在 initialize 阶段已到达。
        when(() => plugin.getNotificationAppLaunchDetails()).thenAnswer(
          (_) async => NotificationAppLaunchDetails(
            true,
            notificationResponse: const NotificationResponse(
              id: 1,
              payload: '/claws/chat/cold',
              notificationResponseType:
                  NotificationResponseType.selectedNotification,
            ),
          ),
        );

        await service.initialize();

        final calls = <String?>[];
        // 注册回调前 —— payload 应已缓存、未投递。
        service.setupOnTap((routePath) => calls.add(routePath));
        // 注册瞬间触发补投。
        expect(calls, ['/claws/chat/cold']);
      },
    );

    test(
      'tap arriving before setupOnTap is buffered and flushed on register',
      () async {
        await service.initialize();

        // 点击先到达，此时回调尚未注册。
        _capturedTapCallback!(
          const NotificationResponse(
            id: 1,
            payload: '/late',
            notificationResponseType:
                NotificationResponseType.selectedNotification,
          ),
        );

        final calls = <String?>[];
        service.setupOnTap((routePath) => calls.add(routePath));

        expect(calls, ['/late']);
      },
    );

    test('initialize is idempotent (second call is a no-op)', () async {
      await service.initialize();
      await service.initialize();

      // plugin.initialize 只应被调用一次。
      verify(
        () => plugin.initialize(
          any(),
          onDidReceiveNotificationResponse: any(
            named: 'onDidReceiveNotificationResponse',
          ),
        ),
      ).called(1);
    });

    test('dispose clears the tap callback', () async {
      await service.initialize();
      String? received;
      service.setupOnTap((routePath) => received = routePath);

      await service.dispose();

      // dispose 后点击不应再触发回调。
      _capturedTapCallback!(
        const NotificationResponse(
          id: 1,
          payload: '/after',
          notificationResponseType:
              NotificationResponseType.selectedNotification,
        ),
      );
      expect(received, isNull);
    });
  });
}
