import 'package:flutter/material.dart';

/// Shared dashboard section layout, sized by content for small screens/text scaling.
class MetricCard extends StatelessWidget {
  const MetricCard({super.key, required this.title, required this.metrics});
  final String title;
  final List<({String label, String value})> metrics;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          for (final metric in metrics)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Wrap(
                spacing: 16,
                runSpacing: 4,
                children: [
                  Text(metric.label),
                  Text(
                    metric.value,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
  );
}
