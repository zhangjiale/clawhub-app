import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:claw_hub/app/router/router.dart';
import 'package:claw_hub/app/theme/theme.dart';
import 'package:claw_hub/app/di/providers.dart';
import 'package:claw_hub/data/local/database/database_initializer.dart';
import 'package:claw_hub/ui_kit/error_boundary.dart';

void main() async {
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

/// ClawHub 应用根组件
class ClawHubApp extends ConsumerWidget {
  const ClawHubApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'ClawHub',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      routerConfig: AppRouter.router,
    );
  }
}
