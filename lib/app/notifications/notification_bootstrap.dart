import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:claw_hub/app/di/providers.dart';
import 'package:claw_hub/app/router/router.dart';
import 'package:claw_hub/domain/models/user_preferences.dart';

/// Lightweight dependency — `T Function<T>(ProviderListenable<T> provider)`.
///
/// `NotificationBootstrap` only needs the ability to call `.read(provider)`;
/// storing a full `WidgetRef` or `Ref` is unnecessary and creates a
/// Provider/Widget context mismatch (Riverpod 2.6.x: `WidgetRef` and `Ref` are
/// sibling abstract classes, not related by inheritance). Method-tear-off from
/// any `WidgetRef` or `Ref` is assignable here.
typedef ProviderReader = T Function<T>(ProviderListenable<T> provider);

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
  final ProviderReader _read;
  StreamSubscription<UserPreferences>? _prefsSub;
  bool _initialized = false;

  NotificationBootstrap(this._read);

  /// 是否已初始化 (供测试/重复调用守卫)。
  bool get isInitialized => _initialized;

  Future<void> init() async {
    if (_initialized) return;

    final logger = _read(loggerProvider);
    final service = _read(iLocalNotificationServiceProvider);

    // Local helper — most init steps are best-effort and only need a logged
    // failure; this collapses the try/catch boilerplate.
    Future<void> guarded(String name, Future<void> Function() op) async {
      try {
        await op();
      } catch (e, st) {
        logger.error('[NotificationBootstrap] $name failed: $e', st);
      }
    }

    // Intentionally NOT guarded: service.initialize() (plugin init) failure must
    // propagate to the Tier-1 fatal path per the tier-gate design (notifications
    // = Tier 1 fatal). The remaining guarded() blocks below are explicitly
    // best-effort - their failure is logged but does NOT block app mount.
    // (ARB finding #1: previously this was guarded, so a real plugin-init failure
    // was silently swallowed and init "succeeded" -> the fatal path was never
    // reached by the realistic failure mode, and the early `_initialized = true`
    // defeated retry on top of that.)
    await service.initialize();

    // 注册点击深链回调 (路由跳转逻辑留在 app 层，data 层不反向依赖 router)。
    service.setupOnTap(handleNotificationTap);

    // 订阅设置变更 → 更新 prefs holder (dispatcher/coordinator 同步读取) +
    // 通知 coordinator 重排 DND Timer (DND 时段/开关变更后立即生效)。
    _prefsSub = _read(settingsRepoProvider).watchPreferences().listen(
      (prefs) {
        _read(notificationPrefsHolderProvider.notifier).state = prefs;
        _read(notificationCoordinatorProvider).onPrefsChanged();
      },
      onError: (Object e, StackTrace st) =>
          logger.error('[NotificationBootstrap] prefs stream error: $e', st),
    );

    // 首次同步一次当前 prefs (流的首事件可能延迟)。
    await guarded('initial prefs/permission', () async {
      final prefs = await _read(settingsRepoProvider).getPreferences();
      _read(notificationPrefsHolderProvider.notifier).state = prefs;

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
      () => _read(notificationCoordinatorProvider).start(),
    );

    // US-018: reseed in-memory dedup LRU from persisted pending notifications
    // so the live messageStream doesn't re-notify messages the background
    // isolate already enqueued before this cold start.
    await guarded(
      'warmupDispatcherFromPending',
      () =>
          _read(notificationCoordinatorProvider).warmupDispatcherFromPending(),
    );

    // US-018: schedule background sync + observe app lifecycle.
    // Observer registration is NOT best-effort: a Workmanager scheduling
    // failure must not silently disable app-lifecycle observation.
    await guarded(
      'scheduler init',
      () => _read(backgroundSyncSchedulerProvider).ensureScheduled(),
    );
    WidgetsBinding.instance.addObserver(this);

    // Mark initialized only after every step has run - a throw above (most
    // importantly the un-guarded service.initialize) must leave this false so a
    // retry re-runs init() instead of short-circuiting (ARB finding #1).
    _initialized = true;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final scheduler = _read(backgroundSyncSchedulerProvider);
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
          _read(notificationCoordinatorProvider).warmupDispatcherFromPending(),
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
