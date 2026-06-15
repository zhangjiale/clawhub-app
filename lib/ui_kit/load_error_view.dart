import 'package:flutter/material.dart';
import 'package:claw_hub/app/theme/tokens.dart';

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
        padding: const EdgeInsets.all(XiaSpacing.s7),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: XiaSpacing.s3),
            Text(title, style: theme.textTheme.bodyLarge),
            const SizedBox(height: XiaSpacing.s2),
            Text(
              '$error',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: XiaSpacing.s4),
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
