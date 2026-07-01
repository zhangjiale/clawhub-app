import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:claw_hub/app/di/providers.dart';
import 'package:claw_hub/app/router/router.dart';
import 'package:claw_hub/domain/models/user_preferences.dart';

/// 通知子系统启动器 (US-018 app 装配)。
///
/// 在 [ConnectionOrchestrator.initialize] **之前**调用 [init]，确保
/// coordinator 的订阅先于首次连接建立 (避免漏掉 InstanceConnectedEvent)。
///
/// 职责：
/// - 初始化平台通知服务、创建通道
/// - 注册点击深链回调 ([handleNotificationTap] → AppRouter.router.go)
/// - 订阅 [ISettingsRepo.watchPreferences] → 更新 [notificationPrefsHolderProvider]
///   并通知 [NotificationCoordinator.onPrefsChanged] 重排 DND Timer
/// - 启动 [NotificationCoordinator] (含 dispatcher 接线)
/// - 启动时若不在 DND 且有积压 → 补发汇总
/// - US-018: 注册 [WidgetsBindingObserver] 监听 app 生命周期
///   (paused → 打开 gate, resumed → 关闭 gate)
/// - US-018: 冷启动时 warmup dispatcher LRU + 确保后台同步已被调度
class NotificationBootstrap with WidgetsBindingObserver {
  final WidgetRef _ref;
  StreamSubscription<UserPreferences>? _prefsSub;
  bool _initialized = false;

  NotificationBootstrap(this._ref);

  /// 是否已初始化 (供测试/重复调用守卫)。
  bool get isInitialized => _initialized;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    final logger = _ref.read(loggerProvider);
    final service = _ref.read(iLocalNotificationServiceProvider);

    // Local helper — most init steps are best-effort and only need a logged
    // failure; this collapses the try/catch boilerplate.
    Future<void> guarded(String name, Future<void> Function() op) async {
      try {
        await op();
      } catch (e, st) {
        logger.error('[NotificationBootstrap] $name failed: $e', st);
      }
    }

    await guarded('service initialize', () => service.initialize());

    // 注册点击深链回调 (路由跳转逻辑留在 app 层，data 层不反向依赖 router)。
    service.setupOnTap(handleNotificationTap);

    // 订阅设置变更 → 更新 prefs holder (dispatcher/coordinator 同步读取) +
    // 通知 coordinator 重排 DND Timer (DND 时段/开关变更后立即生效)。
    _prefsSub = _ref.read(settingsRepoProvider).watchPreferences().listen(
      (prefs) {
        _ref.read(notificationPrefsHolderProvider.notifier).state = prefs;
        _ref.read(notificationCoordinatorProvider).onPrefsChanged();
      },
      onError: (Object e, StackTrace st) =>
          logger.error('[NotificationBootstrap] prefs stream error: $e', st),
    );

    // 首次同步一次当前 prefs (流的首事件可能延迟)。
    await guarded('initial prefs/permission', () async {
      final prefs = await _ref.read(settingsRepoProvider).getPreferences();
      _ref.read(notificationPrefsHolderProvider.notifier).state = prefs;

      // 仅当用户已开启通知总开关时请求权限；关闭则延后到首次开启时。
      if (prefs.notificationsEnabled) {
        await service.requestPermissions();
      }
    });

    // 启动 coordinator (含 dispatcher 接线、实例订阅、DND Timer)。
    // coordinator.start() 内部按当前是否在 DND 决定：
    // 不在 → 立即 flushDndSummary 补发跨重启积压，并排定下一个 DND 起点；
    // 在   → 排定 DND 结束时刻定时器。
    await guarded(
      'coordinator start',
      () => _ref.read(notificationCoordinatorProvider).start(),
    );

    // US-018: reseed in-memory dedup LRU from persisted pending notifications
    // so the live messageStream doesn't re-notify messages the background
    // isolate already enqueued before this cold start.
    await guarded(
      'warmupDispatcherFromPending',
      () => _ref
          .read(notificationCoordinatorProvider)
          .warmupDispatcherFromPending(),
    );

    // US-018: schedule background sync + observe app lifecycle.
    await guarded('scheduler init', () async {
      await _ref.read(backgroundSyncSchedulerProvider).ensureScheduled();
      WidgetsBinding.instance.addObserver(this);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final scheduler = _ref.read(backgroundSyncSchedulerProvider);
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        // `inactive` covers transient foreground losses (control-center pull,
        // incoming call, app switcher); treat as paused so the gate flips
        // off and a background tick can run if the user lingers away.
        // best-effort; gate write is async (see spec Known Risk).
        scheduler.onAppPaused();
      case AppLifecycleState.resumed:
        scheduler.onAppResumed();
        // US-018 — on resume, re-seed the dispatcher's in-memory
        // `_notifiedKeys` LRU from the pending_notifications table.
        // Without this, messages the background isolate enqueued
        // while the app was paused would be re-fired by the live
        // messageStream the moment the app comes back to the
        // foreground (duplicate notification bug).
        unawaited(
          _ref
              .read(notificationCoordinatorProvider)
              .warmupDispatcherFromPending(),
        );
      default:
        break;
    }
  }

  Future<void> dispose() async {
    WidgetsBinding.instance.removeObserver(this);
    await _prefsSub?.cancel();
    _prefsSub = null;
  }
}

/// 把通知点击的 routePath 转为实际路由跳转 (US-018 AC-2)。
///
/// 由 [NotificationBootstrap] 注册为 [ILocalNotificationService.setupOnTap]
/// 回调。空路径静默忽略。定义在 app 层，避免 data 层
/// ([LocalNotificationService]) 反向依赖 [AppRouter]。
void handleNotificationTap(String? routePath) {
  if (routePath == null || routePath.isEmpty) return;
  AppRouter.router.go(routePath);
}
