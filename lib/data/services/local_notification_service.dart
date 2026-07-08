import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'package:claw_hub/core/i_local_notification_service.dart';

/// [ILocalNotificationService] 的 flutter_local_notifications 实现 (US-018)。
///
/// ACL 性质：唯一触碰平台通知插件的代码。负责：
/// - 创建三个 Android 通知通道 (回复/错误/连接)
/// - iOS/Android 权限请求
/// - 发通知，把 routePath 存入 payload
/// - 点击回调：把 payload routePath 透传给 [setupOnTap] 注册的回调
///   (实际路由跳转由 app 层 [handleNotificationTap] 完成，本类不依赖 router)。
///
/// routePath 由 dispatcher 写入 payload；点击跳转路径由
/// [AppRoutes.chatWithParams] 生成 (在 coordinator 中调用)。
class LocalNotificationService implements ILocalNotificationService {
  final FlutterLocalNotificationsPlugin _plugin;

  /// [plugin] 可注入以便单测用 mocktail 替换平台插件，避免触发真实
  /// platform channel (无 handler 时抛 MissingPluginException)。
  /// 生产路径省略参数，内部 new 真实插件。
  LocalNotificationService({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  void Function(String? routePath)? _onTap;

  /// 冷启动时点击通知的 payload，待 setupOnTap 注册后补投。
  String? _pendingLaunchPayload;

  bool _initialized = false;

  @override
  Future<void> initialize() async {
    if (_initialized) return;

    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _handleTap,
    );

    if (defaultTargetPlatform == TargetPlatform.android) {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await android?.createNotificationChannelGroup(_channelGroup);
      for (final channel in _channels) {
        await android?.createNotificationChannel(channel);
      }
    }
    // 注：channel 元数据 (id/name/importance) 单一来源见 _channelConfigs，
    // 上面的 _channels 与下面的 _androidDetailsFor 均从它派生，避免三处重复。

    // 冷启动点击通知：payload 已在启动前到达，在此缓存并补投给回调。
    final launch = await _plugin.getNotificationAppLaunchDetails();
    final launchPayload = launch?.notificationResponse?.payload;
    if (launchPayload != null && launchPayload.isNotEmpty) {
      _pendingLaunchPayload = launchPayload;
      _flushPendingLaunchPayload();
    }
    // Mark initialized only after every throwable step has succeeded - a throw
    // above (e.g. _plugin.initialize) must leave this false so a retry actually
    // re-runs instead of short-circuiting on `if (_initialized) return`
    // (ARB finding #1, nested layer).
    _initialized = true;
  }

  void _flushPendingLaunchPayload() {
    if (_onTap != null && _pendingLaunchPayload != null) {
      final p = _pendingLaunchPayload;
      _pendingLaunchPayload = null;
      _onTap!(p);
    }
  }

  @override
  Future<bool> requestPermissions() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      final granted = await android?.requestNotificationsPermission();
      return granted ?? false;
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final ios = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      final granted = await ios?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      return granted ?? false;
    }
    return false;
  }

  @override
  Future<void> show({
    required int id,
    required NotificationChannelId channel,
    required String title,
    required String body,
    String? routePath,
  }) async {
    final details = NotificationDetails(
      android: _androidDetailsFor(channel),
      iOS: const DarwinNotificationDetails(),
    );
    await _plugin.show(id, title, body, details, payload: routePath);
  }

  @override
  Future<void> cancel(int id) => _plugin.cancel(id);

  @override
  void setupOnTap(void Function(String? routePath) onTap) {
    _onTap = onTap;
    _flushPendingLaunchPayload();
  }

  @override
  Future<void> dispose() async {
    _onTap = null;
  }

  // ---------------------------------------------------------------------------

  void _handleTap(NotificationResponse response) {
    final payload = response.payload;
    if (_onTap != null) {
      _onTap!(payload);
    } else if (payload != null && payload.isNotEmpty) {
      // 回调尚未注册 —— 缓存待 setupOnTap。
      _pendingLaunchPayload = payload;
    }
  }

  AndroidNotificationDetails _androidDetailsFor(NotificationChannelId channel) {
    final c = _channelConfigs[channel]!;
    return AndroidNotificationDetails(
      c.id,
      c.name,
      groupKey: _channelGroupId,
      importance: c.importance,
      priority: c.priority,
    );
  }

  /// 通道组 id / 名称 — 通道注册与 show 时 details 共用。
  static const _channelGroupId = 'clawhub_notifications';
  static const _channelGroupName = '虾Hub 通知';

  static const _channelGroup = AndroidNotificationChannelGroup(
    _channelGroupId,
    _channelGroupName,
  );

  /// 通道元数据单一来源：id / 显示名 / importance / priority。
  /// [_channels] (注册) 与 [_androidDetailsFor] (show) 均从此派生。
  static const _channelConfigs = <NotificationChannelId, _ChannelConfig>{
    NotificationChannelId.reply: _ChannelConfig(
      'clawhub_reply',
      '虾回复',
      Importance.high,
      Priority.high,
    ),
    NotificationChannelId.error: _ChannelConfig(
      'clawhub_error',
      '虾出错',
      Importance.high,
      Priority.high,
    ),
    NotificationChannelId.connection: _ChannelConfig(
      'clawhub_connection',
      '连接变化',
      Importance.defaultImportance,
      Priority.defaultPriority,
    ),
  };

  static List<AndroidNotificationChannel> get _channels => [
    for (final entry in _channelConfigs.entries)
      AndroidNotificationChannel(
        entry.value.id,
        entry.value.name,
        groupId: _channelGroupId,
        importance: entry.value.importance,
      ),
  ];
}

/// 通道元数据值对象 (id / 显示名 / importance / priority)。
class _ChannelConfig {
  final String id;
  final String name;
  final Importance importance;
  final Priority priority;

  const _ChannelConfig(this.id, this.name, this.importance, this.priority);
}
