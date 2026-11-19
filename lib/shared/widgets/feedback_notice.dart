import 'package:flutter/material.dart';
import '../../app/theme/design_tokens.dart';

/// A shared, readable state treatment; the caller keeps its safe error and retry.
class FeedbackNotice extends StatelessWidget {
  const FeedbackNotice({
    super.key,
    required this.message,
    this.retry,
    this.error = true,
    this.primaryRetry = false,
  });
  final String message;
  final VoidCallback? retry;
  final bool error;
  final bool primaryRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: error ? colors.errorContainer : colors.primaryContainer,
        borderRadius: BorderRadius.circular(AppRadii.control),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExcludeSemantics(
                child: Icon(
                  error ? Icons.info_outline : Icons.check_circle_outline,
                  size: 20,
                  color: error
                      ? colors.onErrorContainer
                      : colors.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    message,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: error
                          ? colors.onErrorContainer
                          : colors.onPrimaryContainer,
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (retry != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: primaryRetry
                  ? FilledButton.icon(
                      onPressed: retry,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                    )
                  : TextButton.icon(
                      onPressed: retry,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                    ),
            ),
        ],
      ),
    );
  }
}
