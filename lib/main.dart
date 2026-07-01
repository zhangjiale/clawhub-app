import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:workmanager/workmanager.dart';
import 'package:claw_hub/app/bootstrap.dart';
import 'package:claw_hub/app/router/router.dart';
import 'package:claw_hub/app/theme/theme.dart';
import 'package:claw_hub/app/di/providers.dart';
import 'package:claw_hub/app/notifications/notification_bootstrap.dart';
import 'package:claw_hub/app/background_sync/callback_dispatcher.dart';
import 'package:claw_hub/data/local/database/database_initializer.dart';
import 'package:claw_hub/domain/models/user_preferences.dart';
import 'package:claw_hub/ui_kit/startup_fatal_screen.dart';
import 'package:claw_hub/core/debug_print_logger.dart';

/// Module-scoped flag that survives for the lifetime of the isolate.
/// `WidgetsFlutterBinding.ensureInitialized()` can only be called once per
/// isolate; the Retry button on the fatal screen calls `main()` and we must
/// not re-init the binding on retry.
bool _bindingInitialized = false;

Future<void> main() async {
  if (!_bindingInitialized) {
    WidgetsFlutterBinding.ensureInitialized();
    _bindingInitialized = true;
  }
  runZonedGuarded(
    () => bootstrapApp(
      // US-018: register the background-sync entry point. MUST happen before
      // runApp so workmanager can dispatch to callbackDispatcher from a
      // background isolate. Same-process (enableSeparateBackgroundProcess is
      // NOT called) so flutter_secure_storage keychain access works
      // cross-isolate.
      initializeWorkmanager: () => Workmanager().initialize(
        // workmanager 0.9: isInDebugMode is deprecated and has no effect
        // (confirmed in workmanager_impl.dart:122-127). Omit it entirely.
        callbackDispatcher,
      ),
      createDatabase: createAppDatabase,
      buildSuccess: (database) => ProviderScope(
        overrides: [
          // overrideWith (not overrideWithValue) lets us register an
          // onDispose hook that closes the DB when the ProviderScope
          // is torn down (hot-restart, test teardown, app exit).
          databaseProvider.overrideWith((ref) {
            ref.onDispose(() => database.close());
            return database;
          }),
        ],
        child: const ClawHubApp(),
      ),
      showFatal: (error, stackTrace) => runApp(
        StartupFatalScreen(error: error, stackTrace: stackTrace, onRetry: main),
      ),
    ),
    _onZoneError,
  );
}

/// Handler for uncaught async errors that escape [bootstrapApp]'s
/// inner try/catch AND the `await` chain — e.g. an un-awaited Future that
/// throws, a Timer/microtask callback that throws, or a Stream with no
/// `onError` listener.
///
/// **Why this MUST NOT call `runApp`:** by the time such an error lands
/// here, [bootstrapApp] has already mounted the real app (runApp was
/// called inside this zone). Calling `runApp` again would unmount the
/// existing `ProviderScope`, which disposes `databaseProvider` and fires
/// its `ref.onDispose(() => database.close())` — closing the database and
/// dropping all in-memory state (drafts, view-model state, nav stack) for
/// a single transient async error. The cure would be worse than the disease.
///
/// pre-runApp startup failures are a different beast: there the
/// `ProviderScope` is not yet mounted, so [bootstrapApp]'s `showFatal`
/// path CAN safely `runApp(StartupFatalScreen)`. This handler only ever
/// sees post-mount async orphans, for which `runApp(fatal)` is a misfit.
///
/// Build/gesture/layout errors do not enter the zone — they are routed to
/// `FlutterError.onError` / `ErrorWidget.builder` (set in `bootstrap.dart`).
void _onZoneError(Object error, StackTrace stackTrace) {
  const logger = DebugPrintLogger();
  logger.error('[main] uncaught async error: $error', stackTrace);
}

/// 应用启动后初始化连接编排器。
///
/// 在首次 build 时调用，确保 [ConnectionOrchestrator] 在依赖注入容器
/// 就绪后才开始自动连接。使用 [ConsumerStatefulWidget] 的 initState
/// 访问 ref 来触发初始化。
///
/// 初始化结果写入 [connectionInitStateProvider]，供父级 UI 展示错误状态。
class _ConnectionInitializer extends ConsumerStatefulWidget {
  final Widget child;

  const _ConnectionInitializer({required this.child});

  @override
  ConsumerState<_ConnectionInitializer> createState() =>
      _ConnectionInitializerState();
}

class _ConnectionInitializerState
    extends ConsumerState<_ConnectionInitializer> {
  bool _initialized = false;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _initConnections();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> _initConnections() async {
    if (_initialized) return;
    _initialized = true;

    try {
      // US-018: 通知子系统必须先于连接建立 —— coordinator 的订阅要在
      // orchestrator.initialize() 发出首次 InstanceConnectedEvent 前就绪，
      // 否则漏订阅。bootstrap 内部按当前 prefs 决定是否请求权限。
      //
      // 注：bootstrap 持有一条 watchPreferences() 订阅，生命周期与 App 进程
      // 一致，不在 State.dispose 中显式 cancel —— Drift 的 QueryStream 在
      // cancel 时会内部 schedule 0-duration 定时器 (StreamQueryStore
      // .markAsClosed)，在 widget unmount 同步 teardown 阶段无后续 pump
      // flush，会触发 flutter_test 的 "Timer still pending" 断言。残留订阅
      // 本身无害：coordinator 的 _disposed 守卫 + StateProvider 的
      // last-write-wins 语义使 hot-reload 后旧订阅回调退化为幂等 no-op。
      final bootstrap = NotificationBootstrap(ref);
      await bootstrap.init();

      final orchestrator = ref.read(connectionOrchestratorProvider);
      await orchestrator.initialize();

      if (_disposed || !mounted) return;
      ref.read(connectionInitStateProvider.notifier).state =
          const AsyncValue.data(null);
    } catch (error, stackTrace) {
      if (_disposed || !mounted) return;
      ref.read(connectionInitStateProvider.notifier).state = AsyncValue.error(
        error,
        stackTrace,
      );
      debugPrint(
        'ConnectionOrchestrator initialization failed: $error\n$stackTrace',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

/// Global key for ScaffoldMessenger so snackbars can be shown from outside
/// the MaterialApp's widget subtree (e.g., from connection init error listener).
final GlobalKey<ScaffoldMessengerState> _rootMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

/// ClawHub 应用根组件
class ClawHubApp extends ConsumerWidget {
  const ClawHubApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch init state to show error feedback when connection init fails
    ref.listen<AsyncValue<void>?>(connectionInitStateProvider, (prev, next) {
      if (next is AsyncValue && next.hasError) {
        _rootMessengerKey.currentState?.showSnackBar(
          SnackBar(
            content: const Text(
              'Failed to connect to some instances. '
              'Check your network and try again.',
            ),
            duration: const Duration(seconds: 6),
            action: SnackBarAction(
              label: 'Dismiss',
              onPressed: () =>
                  _rootMessengerKey.currentState?.hideCurrentSnackBar(),
            ),
          ),
        );
      }
    });

    // US-018: 用户运行时首次开启通知总开关时请求系统权限
    // (Bootstrap 仅在启动时按当时 prefs 请求一次)。
    ref.listen<UserPreferences>(notificationPrefsHolderProvider, (prev, next) {
      final wasEnabled = prev?.notificationsEnabled ?? false;
      if (!wasEnabled && next.notificationsEnabled) {
        _requestNotificationPermissions(ref);
      }
    });

    return _ConnectionInitializer(
      child: MaterialApp.router(
        title: '虾Hub',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.dark,
        routerConfig: AppRouter.router,
        scaffoldMessengerKey: _rootMessengerKey,
      ),
    );
  }
}

/// US-018: 请求系统通知权限 (用户运行时首次开启通知总开关时触发)。
///
/// 权限请求是异步平台调用，独立于 listener 的同步回调；失败仅记录日志，
/// 不阻塞 UI。Bootstrap 启动时已按当时 prefs 请求过一次。
Future<void> _requestNotificationPermissions(WidgetRef ref) async {
  try {
    await ref.read(iLocalNotificationServiceProvider).requestPermissions();
  } catch (e, st) {
    ref
        .read(loggerProvider)
        .error('[Notification] request permissions failed: $e', st);
  }
}
