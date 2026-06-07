import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:claw_hub/app/router/router.dart';
import 'package:claw_hub/app/theme/theme.dart';
import 'package:claw_hub/ui_kit/error_boundary.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Set global error widget fallback once — avoids the multi-instance
  // conflict that would occur if set per ErrorBoundary widget.
  ErrorWidget.builder = (details) => const DefaultErrorFallback();

  runApp(const ProviderScope(child: ClawHubApp()));
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
