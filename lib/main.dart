import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:claw_hub/app/router/router.dart';
import 'package:claw_hub/app/theme/theme.dart';
import 'package:claw_hub/app/di/providers.dart';
import 'package:claw_hub/data/local/database/database_initializer.dart';
import 'package:claw_hub/ui_kit/error_boundary.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set global error widget fallback once — avoids the multi-instance
  // conflict that would occur if set per ErrorBoundary widget.
  ErrorWidget.builder = (details) => const DefaultErrorFallback();

  // Initialize Drift/SQLite database before the app starts.
  // This ensures all Riverpod providers that depend on databaseProvider
  // have a valid database instance from the first frame.
  final database = await createAppDatabase();

  runApp(
    ProviderScope(
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
  );
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

    return _ConnectionInitializer(
      child: MaterialApp.router(
        title: 'ClawHub',
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
