import 'package:flutter/material.dart';

/// Default error UI used by both the global `ErrorWidget.builder` (in
/// `lib/app/bootstrap.dart`) and the `StartupFatalScreen` for fatal
/// pre-`runApp` startup failures.
///
/// All fields are optional so existing call sites that only pass `error`
/// (e.g. legacy `ErrorWidget.builder` substitutions in widget tests) keep
/// working unchanged.
///
/// * [error] — the exception object; rendered as text (up to 6 lines).
/// * [stackTrace] — when provided, rendered in a collapsed `ExpansionTile`
///   so a developer can expand to read the full Dart stack.
/// * [onRetry] — when provided, a "重试" `FilledButton` is shown. Wired
///   up by the startup-fatal screen to re-run `main()`.
class DefaultErrorFallback extends StatelessWidget {
  final Object? error;
  final StackTrace? stackTrace;
  final VoidCallback? onRetry;

  const DefaultErrorFallback({
    super.key,
    this.error,
    this.stackTrace,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 64, color: theme.colorScheme.error),
          const SizedBox(height: 16),
          Text('应用出现了问题', style: theme.textTheme.titleMedium),
          if (error != null) ...[
            const SizedBox(height: 12),
            Text(
              '$error',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
              textAlign: TextAlign.center,
              maxLines: 6,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (onRetry != null) ...[
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
          if (stackTrace != null) ...[
            const SizedBox(height: 16),
            ExpansionTile(
              title: const Text('堆栈信息'),
              childrenPadding: const EdgeInsets.all(8),
              children: [
                Text(stackTrace.toString(), style: theme.textTheme.bodySmall),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
