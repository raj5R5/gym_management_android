import 'package:flutter/material.dart';

import '../../../app/theme/design_tokens.dart';
import '../../../shared/widgets/soft_panel.dart';

/// Opaque, content-sized metric cards keep financial values readable.
class MetricCard extends StatelessWidget {
  const MetricCard({
    super.key,
    required this.title,
    required this.metrics,
    required this.icon,
    required this.contextLabel,
    this.accent,
    this.summary,
  });
  final String title, contextLabel;
  final IconData icon;
  final List<({String label, String value})> metrics;
  final Color? accent;
  final Widget? summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surfaces = AppSurfaces.of(context);
    return SoftPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: accent ?? surfaces.active,
                  borderRadius: BorderRadius.circular(AppRadii.control),
                ),
                child: Icon(icon, color: surfaces.onStatus, size: 24),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleLarge),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      contextLabel,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          if (metrics.isNotEmpty) ...[
            Text(metrics.first.value, style: theme.textTheme.headlineMedium),
            const SizedBox(height: AppSpacing.xs),
            Text(
              metrics.first.label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (summary != null) ...[
            const SizedBox(height: AppSpacing.lg),
            summary!,
          ],
          if (metrics.length > 1) ...[
            const SizedBox(height: AppSpacing.lg),
            Divider(height: 1, color: surfaces.border),
            const SizedBox(height: AppSpacing.sm),
            for (final metric in metrics.skip(1))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final label = Text(
                      metric.label,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    );
                    final value = Text(
                      metric.value,
                      style: theme.textTheme.titleMedium,
                    );
                    return constraints.maxWidth < 220 ||
                            MediaQuery.textScalerOf(context).scale(16) > 24
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              label,
                              const SizedBox(height: AppSpacing.xs),
                              value,
                            ],
                          )
                        : Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(flex: 3, child: label),
                              const SizedBox(width: AppSpacing.md),
                              Flexible(
                                flex: 2,
                                child: Align(
                                  alignment: Alignment.centerRight,
                                  child: value,
                                ),
                              ),
                            ],
                          );
                  },
                ),
              ),
          ],
        ],
      ),
    );
  }
}
