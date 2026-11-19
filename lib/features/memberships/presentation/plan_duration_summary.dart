import 'package:flutter/material.dart';
import '../../../app/theme/design_tokens.dart';
import '../../../shared/widgets/titanium_surface.dart';

String _monthEstimate(int days) => days % 30 == 0
    ? '${days ~/ 30}'
    : (days / 30)
          .toStringAsFixed(2)
          .replaceFirst(RegExp(r'0+$'), '')
          .replaceFirst(RegExp(r'\.$'), '');

/// Presentation only: saved days, not the month estimate, govern membership dates.
class PlanDurationSummary extends StatelessWidget {
  const PlanDurationSummary({super.key, required this.durationDays});
  final int durationDays;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final months = _monthEstimate(durationDays);
      final colors = Theme.of(context).colorScheme;
      final monthValue = _DurationValue(
        value: '≈$months',
        label: 'Months (approx.)',
        semantics:
            'Approximately $months ${months == '1' ? 'month' : 'months'}, using 30 days per month',
        color: colors.primary,
      );
      final days = _DurationValue(
        value: '$durationDays',
        label: 'Total days',
        semantics:
            'Exact duration: $durationDays ${durationDays == 1 ? 'day' : 'days'}',
        color: colors.onSurface,
      );
      final stacked =
          constraints.maxWidth < 288 ||
          MediaQuery.textScalerOf(context).scale(16) > 22;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (stacked) ...[
            monthValue,
            const SizedBox(height: AppSpacing.lg),
            days,
          ] else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: monthValue),
                const SizedBox(width: AppSpacing.lg),
                Expanded(child: days),
              ],
            ),
        ],
      );
    },
  );
}

class PlanDurationInfoButton extends StatelessWidget {
  const PlanDurationInfoButton({
    super.key,
    required this.planName,
    required this.durationDays,
  });
  final String planName;
  final int durationDays;

  void _explainDuration(BuildContext context) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      scrollable: true,
      icon: const Icon(Icons.calendar_month_outlined),
      title: const Text('Plan duration'),
      content: Text(
        '$planName lasts exactly $durationDays ${durationDays == 1 ? 'day' : 'days'}.\n\n'
        'The month figure (≈${_monthEstimate(durationDays)}) uses 30 days per month for comparison. '
        'It does not mean calendar months. Membership dates and expiry still follow the saved days.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Got it'),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return TitaniumPress(
      child: IconButton.filledTonal(
        tooltip: 'Explain duration for $planName',
        onPressed: () => _explainDuration(context),
        style: IconButton.styleFrom(
          minimumSize: const Size.square(AppSpacing.xl * 2),
          backgroundColor: colors.primaryContainer,
          foregroundColor: colors.onPrimaryContainer,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.control),
          ),
        ),
        icon: const Icon(Icons.calendar_month_outlined),
      ),
    );
  }
}

class _DurationValue extends StatelessWidget {
  const _DurationValue({
    required this.value,
    required this.label,
    required this.semantics,
    required this.color,
  });
  final String value, label, semantics;
  final Color color;
  @override
  Widget build(BuildContext context) => Semantics(
    label: semantics,
    excludeSemantics: true,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontFamily: AppTypography.bodyFamily,
            fontWeight: FontWeight.w700,
            fontFeatures: const [FontFeature.tabularFigures()],
            color: color,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(label, style: Theme.of(context).textTheme.labelLarge),
      ],
    ),
  );
}
