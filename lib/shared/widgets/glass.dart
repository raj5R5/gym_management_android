import 'dart:ui';

import 'package:flutter/material.dart';

import '../../app/theme/design_tokens.dart';

/// Frosted glass: blurs whatever is behind it, then lays a light fill, a thin
/// rim and a brighter top edge over the blur.
///
/// Flutter's [BackdropFilter] blurs the real backdrop on both platforms, so no
/// blur-target wiring is needed. Never animate [intensity]; fade the whole
/// widget with opacity instead. Blur costs a pass per widget, so lists use
/// [GlassCard] and blur is kept for bars, sheets and hero cards.
class Glass extends StatelessWidget {
  const Glass({
    super.key,
    this.child,
    this.radius = AppRadii.xl,
    this.intensity = AppBlur.card,
    this.tint = AppColors.glass,
    this.borderColor = AppColors.glassBorder,
    this.borderWidth = 1,
    this.highlight = true,
    this.padding,
    this.shadow,
  });

  final Widget? child;
  final double radius;
  final double intensity;
  final Color tint;
  final Color borderColor;
  final double borderWidth;

  /// A light edge along the top, like an inset highlight.
  final bool highlight;
  final EdgeInsetsGeometry? padding;
  final List<BoxShadow>? shadow;

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(radius);
    final sigma = AppBlur.sigma(intensity);
    Widget body = Padding(padding: padding ?? EdgeInsets.zero, child: child);
    body = ClipRRect(
      borderRadius: shape,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: tint,
            borderRadius: shape,
            border: Border.all(color: borderColor, width: borderWidth),
          ),
          child: highlight ? GlassTopEdge(radius: radius, child: body) : body,
        ),
      ),
    );
    if (shadow == null) return body;
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: shape, boxShadow: shadow),
      child: body,
    );
  }
}

/// The simple glass card for scrolling content: no blur, a 7% white fill, a
/// 16% rim and a 30% top edge.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.radius = AppRadii.xl,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.fill = AppColors.cardFill,
    this.borderColor = AppColors.cardBorder,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final Color fill;
  final Color borderColor;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: fill,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: borderColor),
    ),
    child: GlassTopEdge(
      radius: radius,
      color: AppColors.cardTopEdge,
      child: Padding(padding: padding, child: child),
    ),
  );
}

/// Draws a 1px brighter line just inside the top rim, fading out at the
/// rounded corners so it reads as light catching the edge.
class GlassTopEdge extends StatelessWidget {
  const GlassTopEdge({
    super.key,
    required this.radius,
    required this.child,
    this.color = AppColors.glassHighlight,
  });
  final double radius;
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) => CustomPaint(
    foregroundPainter: _TopEdgePainter(radius, color),
    child: child,
  );
}

class _TopEdgePainter extends CustomPainter {
  _TopEdgePainter(this.radius, this.color);
  final double radius;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final inset = radius.clamp(0, size.width / 2).toDouble() * .6;
    if (size.width - inset * 2 <= 0) return;
    final rect = Rect.fromLTWH(inset, 0, size.width - inset * 2, 1);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          colors: [
            color.withValues(alpha: 0),
            color,
            color,
            color.withValues(alpha: 0),
          ],
          stops: const [0, .18, .82, 1],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_TopEdgePainter old) =>
      old.radius != radius || old.color != color;
}
