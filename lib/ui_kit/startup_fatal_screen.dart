import 'package:flutter/material.dart';

import 'package:claw_hub/ui_kit/default_error_fallback.dart';

/// 全屏 fatal error UI used when a pre-`runApp` startup await fails
/// (e.g. `Workmanager().initialize(...)` or `createAppDatabase()`).
///
/// Renders [error] + [stackTrace] + a "Retry" button via
/// [DefaultErrorFallback]. The Retry button invokes [onRetry], which in
/// `main.dart` re-runs `main()` (with a guard against re-initializing
/// `WidgetsFlutterBinding`).
class StartupFatalScreen extends StatelessWidget {
  final Object error;
  final StackTrace stackTrace;
  final VoidCallback onRetry;

  const StartupFatalScreen({
    super.key,
    required this.error,
    required this.stackTrace,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      body: SafeArea(
        child: DefaultErrorFallback(
          error: error,
          stackTrace: stackTrace,
          onRetry: onRetry,
        ),
      ),
    ),
  );
}
