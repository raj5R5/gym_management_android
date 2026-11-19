import 'package:flutter/material.dart';

import '../../app/theme/design_tokens.dart';
import 'app_text.dart';
import 'glass.dart';
import 'motion.dart';

enum AppButtonVariant { primary, glass }

/// The two button shapes. [AppButtonVariant.primary] is a 54px pearl pill
/// with carbon text, a hairline white top edge, the CTA shadow and a light
/// haptic: one per screen. [AppButtonVariant.glass] is a glass pill.
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.icon,
    this.loading = false,
    this.loadingLabel,
  });

  final String label;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final IconData? icon;
  final bool loading;

  /// Read to screen readers while [loading].
  final String? loadingLabel;

  static const height = 54.0;

  @override
  Widget build(BuildContext context) {
    final primary = variant == AppButtonVariant.primary;
    final disabled = onPressed == null;
    final inactive = disabled || loading;
    final ink = primary ? AppColors.onPrimary : AppColors.text;
    final content = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (loading)
          SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: ink,
              semanticsLabel: loadingLabel,
            ),
          )
        else ...[
          Flexible(
            child: AppText(
              label,
              variant: AppTextVariant.bodyStrong,
              color: ink,
              style: const TextStyle(fontSize: 16),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (icon != null) ...[
            const SizedBox(width: AppSpacing.sm),
            Icon(icon, size: 20, color: ink),
          ],
        ],
      ],
    );
    final shape = BorderRadius.circular(height / 2);
    final body = primary
        ? DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: shape,
              border: const Border(
                top: BorderSide(color: AppPalette.white, width: .5),
              ),
              boxShadow: inactive ? null : AppShadow.cta,
            ),
            child: SizedBox(
              height: height,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Center(child: content),
              ),
            ),
          )
        : Glass(
            radius: height / 2,
            tint: AppColors.glassStrong,
            borderColor: AppColors.glassBorderStrong,
            child: SizedBox(
              height: height,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Center(child: content),
              ),
            ),
          );
    return Semantics(
      button: true,
      enabled: !inactive,
      label: loading ? (loadingLabel ?? label) : label,
      excludeSemantics: true,
      onTap: inactive ? null : onPressed,
      child: Opacity(
        opacity: disabled && !loading ? .5 : 1,
        child: PressableScale(
          enabled: !inactive,
          haptic: primary,
          onPressed: inactive ? null : onPressed,
          child: body,
        ),
      ),
    );
  }
}
