import 'package:flutter/material.dart';

import '../../app/theme/design_tokens.dart';

/// A round icon with a short label below, like a phone's contact screen.
/// Use a row of these for the few actions people take most on a screen.
class RoundAction extends StatelessWidget {
  const RoundAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.semanticLabel,
    this.primary = false,
  });

  final IconData icon;
  final String label;

  /// Read by screen readers when [label] is shortened for space.
  final String? semanticLabel;
  final VoidCallback? onTap;

  /// Fills the circle to mark the main action of the row.
  final bool primary;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: onTap != null,
    label: semanticLabel ?? label,
    excludeSemantics: true,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.lg),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Column(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: primary ? AppColors.primary : AppColors.glassStrong,
                shape: BoxShape.circle,
                border: primary
                    ? null
                    : Border.all(color: AppColors.glassBorder),
              ),
              child: Icon(
                icon,
                size: 22,
                color: primary ? AppColors.onPrimary : null,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ],
        ),
      ),
    ),
  );
}

/// [actions] spread evenly across the width.
class RoundActionRow extends StatelessWidget {
  const RoundActionRow({super.key, required this.actions});
  final List<RoundAction> actions;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [for (final action in actions) Expanded(child: action)],
  );
}
