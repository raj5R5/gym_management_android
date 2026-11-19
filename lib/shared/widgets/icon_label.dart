import 'package:flutter/material.dart';
import '../../app/theme/design_tokens.dart';

/// Scannable metadata that keeps the complete text available at large sizes.
/// Use in a bounded section/list; the icon supplements the visible label.
class IconLabel extends StatelessWidget {
  const IconLabel(this.label, {super.key, required this.icon, this.style});
  final String label;
  final IconData icon;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(
          child: Icon(
            icon,
            size: 20,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Text(label, style: style)),
      ],
    ),
  );
}
