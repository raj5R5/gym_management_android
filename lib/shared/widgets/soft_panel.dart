import 'dart:ui';
import 'package:flutter/material.dart';
import '../../app/theme/design_tokens.dart';
import 'glass.dart';
import 'titanium_surface.dart';
import 'card_reveal.dart';

/// Frosted headers and directional smoked-glass highlights share one surface recipe.
class SoftPanel extends StatelessWidget {
  const SoftPanel({
    super.key,
    required this.child,
    this.glass = false,
    this.glassOpacity,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.gradient,
    this.backgroundColor,
    this.onTap,
    this.tone = AppTone.neutral,
  });
  final Widget child;
  final bool glass;
  final double? glassOpacity;
  final EdgeInsetsGeometry padding;
  final Gradient? gradient;
  final Color? backgroundColor;
  final VoidCallback? onTap;
  final AppTone tone;

  @override
  Widget build(BuildContext context) {
    final surfaces = AppSurfaces.of(context);
    final radius = BorderRadius.circular(AppRadii.panel);
    final color =
        backgroundColor ??
        (glass
            ? AppColors.cardFill
            : surfaces.panel(tone, Theme.of(context).brightness));
    final decoration = BoxDecoration(
      color: gradient == null ? color : null,
      gradient: gradient,
      borderRadius: radius,
      border: Border.all(
        color: glass ? AppColors.glassBorder : surfaces.statusBorder(tone),
      ),
    );
    final content = GlassTopEdge(
      radius: AppRadii.panel,
      color: AppColors.cardTopEdge,
      child: Padding(padding: padding, child: child),
    );
    final panel = onTap == null
        ? DecoratedBox(decoration: decoration, child: content)
        : Material(
            type: MaterialType.transparency,
            child: Ink(
              decoration: decoration,
              child: InkWell(
                // A page opened from this panel grows out of it.
                onTap: () {
                  CardOrigin.mark(context);
                  onTap!();
                },
                borderRadius: radius,
                child: content,
              ),
            ),
          );
    return TitaniumPress(
      enabled: onTap != null,
      child: ClipRRect(
        borderRadius: radius,
        child: glass
            ? BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: AppBlur.sigma(AppBlur.card),
                  sigmaY: AppBlur.sigma(AppBlur.card),
                ),
                child: panel,
              )
            : panel,
      ),
    );
  }
}
