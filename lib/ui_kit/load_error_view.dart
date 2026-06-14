import 'package:flutter/material.dart';

/// Generic error state with optional retry button.
///
/// Intended for async load failures — shows an error icon, a
/// title, the exception text, and optionally a retry FilledButton.
/// Used by AgentProfilePage, AgentConfigPage, GoRouter 404 page,
/// and future data-loading panels.
class LoadErrorView extends StatelessWidget {
  final Object error;
  final String title;
  final String retryLabel;
  final VoidCallback? onRetry;

  const LoadErrorView({
    super.key,
    required this.error,
    this.title = '无法加载数据',
    this.retryLabel = '重试',
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 12),
            Text(title, style: theme.textTheme.bodyLarge),
            const SizedBox(height: 8),
            Text(
              '$error',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 16),
            if (onRetry != null)
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: Text(retryLabel),
              ),
          ],
        ),
      ),
    );
  }
}
