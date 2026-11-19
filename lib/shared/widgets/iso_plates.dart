import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme/design_tokens.dart';
import 'ambient_motion.dart';

/// The first screen's floating 3D object: a glass slab tilted
/// `perspective(700) rotateX(58°) rotateZ(-38°)` carrying four stacks of
/// weight plates at different heights, a dashed ring turning around it, and
/// the whole thing bobbing 12px.
///
/// Flutter has no preserve-3d, so every stack is drawn as its own layer with
/// the same tilt, lifted on screen by its height (a lift of h along the
/// slab's normal moves up h·sin 58°). Thin slices between the floor and the
/// top make each stack read as a solid cylinder, and a darker slice every
/// plate-width reads as the gap between plates. Layers are drawn back to
/// front. Static when reduced motion is on. Decorative: hidden from screen
/// readers.
class IsoPlates extends StatelessWidget {
  const IsoPlates({super.key, this.compact = false});
  final bool compact;

  static const _size = 150.0;
  static const _inset = 18.0;
  static final _lift = math.sin(58 * math.pi / 180);

  /// Back to front for this tilt: top-right farthest, bottom-left nearest.
  static const _stacks = [
    _Stack(
      left: false,
      top: true,
      height: 44,
      plate: 13,
      diameter: 54,
      face: AppPalette.graphite,
      side: AppPalette.shade,
    ),
    _Stack(
      left: true,
      top: true,
      height: 26,
      plate: 13,
      diameter: 48,
      face: AppPalette.steel,
      side: AppPalette.graphite,
    ),
    _Stack(
      left: false,
      top: false,
      height: 60,
      plate: 12,
      diameter: 58,
      face: AppPalette.pearl,
      side: AppPalette.pearlSide,
    ),
    _Stack(
      left: true,
      top: false,
      height: 34,
      plate: 11,
      diameter: 50,
      face: AppPalette.silver,
      side: AppPalette.steel,
    ),
  ];

  static Matrix4 _tilt([double lift = 0]) =>
      Matrix4.translationValues(0, -lift * _lift, 0)
        ..multiply(Matrix4.identity()..setEntry(3, 2, -1 / 700))
        ..rotateX(58 * math.pi / 180)
        ..rotateZ(-38 * math.pi / 180);

  @override
  Widget build(BuildContext context) {
    final reduced = AppMotion.reduced(context);
    final stage = SizedBox(
      height: 168,
      child: Center(
        child: SizedBox.square(
          dimension: _size,
          child: AmbientMotion(
            enabled: !reduced,
            duration: AppMotion.float,
            builder: (context, bob) => AnimatedBuilder(
              animation: bob,
              builder: (context, child) {
                // 0 → -12 → 0 over one period, eased in and out.
                final wave = bob.value < .5 ? bob.value * 2 : 2 - bob.value * 2;
                final y = -12 * AppMotion.loopEaseInOut.transform(wave);
                return Transform.translate(offset: Offset(0, y), child: child);
              },
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  _layer(
                    AmbientMotion(
                      enabled: !reduced,
                      duration: AppMotion.ringSpin,
                      builder: (context, spin) => AnimatedBuilder(
                        animation: spin,
                        builder: (context, _) => Transform.rotate(
                          angle: spin.value * 2 * math.pi,
                          child: const CustomPaint(
                            painter: _DashedRing(),
                            size: Size.square(_size),
                          ),
                        ),
                      ),
                    ),
                  ),
                  _layer(
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: AppColors.glass,
                              borderRadius: BorderRadius.circular(22),
                              border: Border.all(
                                color: AppColors.glassBorderStrong,
                              ),
                            ),
                          ),
                        ),
                        for (final s in _stacks)
                          _disc(s, const Color.fromRGBO(0, 0, 0, .35)),
                      ],
                    ),
                  ),
                  for (final s in _stacks) ..._slices(s),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return ExcludeSemantics(
      child: IgnorePointer(
        child: compact
            ? SizedBox(
                height: 128,
                child: Transform.scale(scale: .78, child: stage),
              )
            : stage,
      ),
    );
  }

  static Widget _layer(Widget child, [double lift = 0]) => Positioned.fill(
    child: Transform(
      alignment: Alignment.center,
      transform: _tilt(lift),
      child: child,
    ),
  );

  static Widget _disc(_Stack s, Color color, {bool top = false}) {
    final cell = _size / 2 - _inset;
    final cx = (s.left ? _inset : _size - _inset - cell) + cell / 2;
    final cy = (s.top ? _inset : _size - _inset - cell) + cell / 2;
    return Positioned(
      left: cx - s.diameter / 2,
      top: cy - s.diameter / 2,
      width: s.diameter,
      height: s.diameter,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: top
              ? Border.all(color: const Color.fromRGBO(255, 255, 255, .35))
              : null,
        ),
        child: top
            ? Center(
                child: FractionallySizedBox(
                  widthFactor: .22,
                  heightFactor: .22,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppPalette.shade.withValues(alpha: .7),
                      shape: BoxShape.circle,
                      border: Border.all(color: s.side),
                    ),
                  ),
                ),
              )
            : null,
      ),
    );
  }

  static List<Widget> _slices(_Stack s) => [
    for (var h = 2.0; h < s.height; h += 3)
      _layer(
        Stack(
          clipBehavior: Clip.none,
          children: [
            _disc(
              s,
              // A darker slice at each plate boundary reads as the gap.
              (h % s.plate) < 3 && h > 3
                  ? Color.lerp(s.side, AppPalette.shade, .55)!
                  : s.side,
            ),
          ],
        ),
        h,
      ),
    _layer(
      Stack(clipBehavior: Clip.none, children: [_disc(s, s.face, top: true)]),
      s.height,
    ),
  ];
}

class _Stack {
  const _Stack({
    required this.left,
    required this.top,
    required this.height,
    required this.plate,
    required this.diameter,
    required this.face,
    required this.side,
  });
  final bool left, top;
  final double height, plate, diameter;
  final Color face, side;
}

class _DashedRing extends CustomPainter {
  const _DashedRing();

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 + IsoPlates._inset;
    final paint = Paint()
      ..color = const Color.fromRGBO(255, 255, 255, .35)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    const dashes = 56;
    const sweep = 2 * math.pi / dashes;
    for (var i = 0; i < dashes; i++) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        i * sweep,
        sweep * .55,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DashedRing oldDelegate) => false;
}
