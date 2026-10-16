import 'dart:ui';
import 'package:flutter/material.dart';
import '../../app/theme/design_tokens.dart';

/// Glass is opt-in for calm headers; content panels stay opaque and readable.
class SoftPanel extends StatelessWidget {
  const SoftPanel({
    super.key,
    required this.child,
    this.glass = false,
    this.padding = const EdgeInsets.all(AppSpacing.xl),
    this.gradient,
    this.backgroundColor,
    this.onTap,
    this.tone = AppTone.neutral,
  });
  final Widget child;
  final bool glass;
  final EdgeInsetsGeometry padding;
  final Gradient? gradient;
  final Color? backgroundColor;
  final VoidCallback? onTap;
  final AppTone tone;

  @override
  Widget build(BuildContext context) {
    final surfaces = AppSurfaces.of(context);
    final radius = BorderRadius.circular(AppRadii.panel);
    final decoration = BoxDecoration(
      color:
          backgroundColor ??
          (glass
              ? surfaces.glass
              : surfaces.panel(tone, Theme.of(context).brightness)),
      gradient: gradient,
      borderRadius: radius,
      border: Border.all(color: surfaces.border),
    );
    final content = Padding(padding: padding, child: child);
    final panel = onTap == null
        ? DecoratedBox(decoration: decoration, child: content)
        : Material(
            type: MaterialType.transparency,
            child: Ink(
              decoration: decoration,
              child: InkWell(
                onTap: onTap,
                borderRadius: radius,
                child: content,
              ),
            ),
          );
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: surfaces.softShadow,
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: glass
            ? BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                child: panel,
              )
            : panel,
      ),
    );
  }
}
