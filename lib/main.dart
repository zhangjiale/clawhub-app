import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:workmanager/workmanager.dart';
import 'package:claw_hub/app/bootstrap.dart';
import 'package:claw_hub/app/router/router.dart';
import 'package:claw_hub/app/theme/theme.dart';
import 'package:claw_hub/app/di/providers.dart';
import 'package:claw_hub/app/splash/startup_gate.dart';
import 'package:claw_hub/app/background_sync/callback_dispatcher.dart';
import 'package:claw_hub/data/local/database/database_initializer.dart';
import 'package:claw_hub/domain/models/user_preferences.dart';
import 'package:claw_hub/ui_kit/fatal_screen.dart';
import 'package:claw_hub/core/debug_print_logger.dart';

Future<void> main() async {
  // ensureInitialized() is documented as safe to call multiple times — the
  // fatal-screen Retry button re-enters main() and we want a fresh binding
  // path (Flutter internally short-circuits re-init).
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();

  // Native splash 自管：让 native splash 在 Flutter 接管前继续显示，
  // 直到 StartupGate 完成 init（或 fatal）后调 FlutterNativeSplash.remove()
  // 通知系统让 Flutter 接管首帧。否则 Flutter runApp 一调用 native splash
  // 立即消失，背景是裸 #08090D 暗色，app 第一帧（ChatRoom / 实例列表）还没
  // layout 完就暴露给用户 = 黑屏闪烁。preserve() 由 StartupGate 在状态机
  // 终态（splash→app 切换 或 _initError fatal）时 remove()。
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

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
        // Use AppTheme.darkTheme so the fatal screen matches the running
        // app's look — without these args MaterialApp falls back to
        // ThemeData.light(), producing a jarring light-on-dark flip on
        // startup failure.
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.darkTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: ThemeMode.dark,
          home: FatalScreen(
            error: error,
            stackTrace: stackTrace,
            // `() => main()` (not `main`) keeps the VoidCallback
            // assignment explicit and lets the framework's
            // `onPressed` handler fire-and-forget the Future — any
            // synchronous throw inside `main` is caught by the
            // framework's error pipeline rather than swallowed by
            // an implicit Future<void> → VoidCallback cast.
            onRetry: () => main(),
          ),
        ),
      ),
    ),
    // Build/gesture/layout errors are routed to FlutterError.onError /
    // ErrorWidget.builder (set in bootstrap.dart). The zone only sees async
    // orphans that escape bootstrapApp's try/catch — for those we MUST NOT
    // re-runApp, because the real ProviderScope is already mounted and
    // re-running would dispose databaseProvider and drop all in-memory state
    // (drafts, view-model state, nav stack). Log-only is the intended sink.
    (error, stackTrace) => const DebugPrintLogger().error(
      '[main] uncaught async error: $error',
      stackTrace,
    ),
  );
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

    return StartupGate(
      // onAppReady：splash→app 切换成功 或 fatal 后调，通知 native 退出。
      // FlutterNativeSplash.remove() 走 MethodChannel，测试环境无插件注册
      // 会抛 MissingPluginException —— 此处 try/catch + logger 兜底，让
      // widget_test / app_integration_test 直接进 ClawHubApp 不爆。
      onAppReady: () {
        try {
          FlutterNativeSplash.remove();
        } catch (e, st) {
          ref
              .read(loggerProvider)
              .error('[splash] FlutterNativeSplash.remove() skipped: $e', st);
        }
      },
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
