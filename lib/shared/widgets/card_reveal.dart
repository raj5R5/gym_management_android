import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/design_tokens.dart';

/// Remembers the card a page was opened from, so the page can grow out of
/// it and shrink back into it on Back. Nothing just appears: everything
/// comes from somewhere.
abstract final class CardOrigin {
  static Rect? _pending;
  static DateTime? _markedAt;

  /// How long a marked card waits for its page to be built.
  static const _window = Duration(milliseconds: 800);

  /// Marks the widget at [context] as the origin of the next page.
  static void mark(BuildContext context) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return;
    _pending = box.localToGlobal(Offset.zero) & box.size;
    _markedAt = DateTime.now();
  }

  /// The marked rect, once; null when nothing was marked recently.
  static Rect? take() {
    final rect = _pending, at = _markedAt;
    _pending = null;
    _markedAt = null;
    if (rect == null || at == null) return null;
    return DateTime.now().difference(at) <= _window ? rect : null;
  }

  /// Forgets a pending origin (tests, or a push that was cancelled).
  @visibleForTesting
  static void clear() => _pending = _markedAt = null;
}

/// Opens [location] from the card at [context].
void pushFromCard(BuildContext context, String location) {
  CardOrigin.mark(context);
  context.push(location);
}

final _origins = Expando<_Origin>('card origin');

class _Origin {
  const _Origin(this.rect);
  final Rect? rect;
}

/// The origin of [route], taken the first time the route is built.
Rect? cardOriginFor(PageRoute<Object?> route) => (_origins[route] ??= _Origin(
  route.isFirst ? null : CardOrigin.take(),
)).rect;

/// Grows [child] from [origin] (a global rect) to its full size as
/// [animation] runs, on a solid surface so the page below never shows
/// through. Reversing the animation shrinks it back into the card.
class CardReveal extends StatelessWidget {
  const CardReveal({
    super.key,
    required this.animation,
    required this.origin,
    required this.child,
    this.radius = AppRadii.card,
  });

  final Animation<double> animation;
  final Rect origin;
  final double radius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final grow = CurvedAnimation(
      parent: animation,
      curve: AppMotion.easeOut,
      // Back lands evenly on the card instead of hovering over it.
      reverseCurve: Curves.easeInOutCubic,
    );
    // The card's own content gives way to the page early in the move.
    final content = CurvedAnimation(
      parent: animation,
      curve: const Interval(.15, .6, curve: Curves.easeOut),
    );
    return _CardRevealBox(
      animation: grow,
      origin: origin,
      radius: radius,
      surface: Color.alphaBlend(AppColors.cardFill, AppPalette.carbon),
      background: AppColors.background,
      child: FadeTransition(opacity: content, child: child),
    );
  }
}

class _CardRevealBox extends SingleChildRenderObjectWidget {
  const _CardRevealBox({
    required this.animation,
    required this.origin,
    required this.radius,
    required this.surface,
    required this.background,
    super.child,
  });

  final Animation<double> animation;
  final Rect origin;
  final double radius;
  final Color surface, background;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderCardReveal(
    animation: animation,
    origin: origin,
    radius: radius,
    surface: surface,
    background: background,
  );

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderCardReveal renderObject,
  ) {
    renderObject
      ..animation = animation
      ..origin = origin
      ..radius = radius
      ..surface = surface
      ..background = background;
  }
}

class _RenderCardReveal extends RenderProxyBox {
  _RenderCardReveal({
    required Animation<double> animation,
    required this.origin,
    required this.radius,
    required this.surface,
    required this.background,
  }) : _animation = animation;

  Animation<double> _animation;
  Rect origin;
  double radius;

  /// The card colour the reveal starts from and the page background it ends
  /// on; the page itself is transparent.
  Color surface, background;
  final _clip = LayerHandle<ClipRRectLayer>();

  set animation(Animation<double> value) {
    if (identical(value, _animation)) return;
    if (attached) _animation.removeListener(markNeedsPaint);
    _animation = value;
    if (attached) _animation.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _animation.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _animation.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void dispose() {
    _clip.layer = null;
    super.dispose();
  }

  /// The clip at progress [t], in this box's coordinates.
  RRect _shape(double t) {
    final from = origin.shift(-localToGlobal(Offset.zero));
    final rect = Rect.lerp(from, Offset.zero & size, t)!;
    return RRect.fromRectAndRadius(
      rect,
      Radius.circular(lerpDouble(radius, 0, t)!.clamp(0, double.infinity)),
    );
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    final t = _animation.value;
    if (t < 1 && !_shape(t).contains(position)) return false;
    return super.hitTest(result, position: position);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final t = _animation.value;
    if (t >= 1) {
      // Keep the page opaque until the route below stops painting.
      _clip.layer = null;
      context.canvas.drawRect(offset & size, Paint()..color = background);
      super.paint(context, offset);
      return;
    }
    if (t <= 0 || child == null) {
      _clip.layer = null;
      return;
    }
    final shape = _shape(t);
    // The surface fades in over the card as it starts to grow, and out again
    // as it lands back on it, so the card itself shows at both ends.
    final cover = (t / .35).clamp(0.0, 1.0);
    final color = Color.lerp(surface, background, t)!;
    context.canvas.drawRRect(
      shape.shift(offset),
      Paint()..color = color.withValues(alpha: color.a * cover),
    );
    _clip.layer = context.pushClipRRect(
      needsCompositing,
      offset,
      Offset.zero & size,
      shape,
      super.paint,
      oldLayer: _clip.layer,
    );
  }
}
