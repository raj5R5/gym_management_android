import 'package:flutter/material.dart';

import '../../app/theme/design_tokens.dart';
import 'iso_plates.dart';
import 'motion.dart';

/// Shared brand moment for the Dashboard and authentication: the floating
/// plate object over an overline and a display title. Operational data stays
/// outside the artwork.
class IronHero extends StatelessWidget {
  const IronHero({
    super.key,
    required this.title,
    required this.eyebrow,
    this.description,
    this.compact = false,
  });

  final String title, eyebrow;
  final String? description;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Rise(child: IsoPlates(compact: compact)),
        const SizedBox(height: AppSpacing.lg),
        Rise.staggered(
          index: 1,
          child: Text(
            eyebrow,
            style: AppType.overline.copyWith(color: AppColors.label),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Rise.staggered(
          index: 2,
          child: Semantics(
            header: true,
            child: Text(
              title,
              style: AppType.display.copyWith(color: AppColors.text),
            ),
          ),
        ),
        if (description != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Rise.staggered(
            index: 3,
            child: Text(
              description!,
              style: AppType.body.copyWith(color: AppColors.textMuted),
            ),
          ),
        ],
      ],
    );
  }
}
