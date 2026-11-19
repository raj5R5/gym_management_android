import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../app/theme/design_tokens.dart';
import 'ambient_motion.dart';

/// A locally projected, bevelled tri-grip rubber plate with a machined steel hub.
/// Decorative autoplay follows the platform's reduced-motion and lifecycle state.
class WeightPlate extends StatelessWidget {
  const WeightPlate({super.key, this.size = 176, this.animate = true});
  final double size;
  final bool animate;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: ExcludeSemantics(
      child: IgnorePointer(
        child: RepaintBoundary(
          child: AmbientMotion(
            duration: AppMotion.plateLoop,
            enabled: animate,
            builder: (context, animation) =>
                CustomPaint(painter: _WeightPlatePainter(animation)),
          ),
        ),
      ),
    ),
  );
}

class _Point3 {
  const _Point3(this.x, this.y, this.z);
  final double x, y, z;
}

class _WeightPlatePainter extends CustomPainter {
  _WeightPlatePainter(this.animation) : super(repaint: animation);
  final Animation<double> animation;

  static const _segments = 64;
  static final _holes = [
    (x: 0.0, y: 0.0, radius: .19),
    for (var i = 0; i < 3; i++)
      (
        x: math.cos(math.pi / 2 + i * math.pi * 2 / 3) * .64,
        y: math.sin(math.pi / 2 + i * math.pi * 2 / 3) * .64,
        radius: .17,
      ),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final phase = animation.value * math.pi * 2;
    final yaw = -.5 + math.sin(phase) * .34;
    final pitch = .19 + math.cos(phase) * .07;
    final roll = -.22 + math.sin(phase) * .045;
    final scale = size.shortestSide * .40;
    final center = size.center(Offset(0, math.sin(phase) * size.height * .025));

    _Point3 rotate(_Point3 p) {
      final x = p.x * math.cos(roll) - p.y * math.sin(roll);
      final y = p.x * math.sin(roll) + p.y * math.cos(roll);
      final rx = x * math.cos(yaw) + p.z * math.sin(yaw);
      final rz = -x * math.sin(yaw) + p.z * math.cos(yaw);
      return _Point3(
        rx,
        y * math.cos(pitch) - rz * math.sin(pitch),
        y * math.sin(pitch) + rz * math.cos(pitch),
      );
    }

    Offset project(_Point3 p) {
      final q = rotate(p);
      final perspective = 6 / (6 - q.z);
      return center + Offset(q.x * scale, -q.y * scale) * perspective;
    }

    List<_Point3> circle(double x, double y, double radius, double z) =>
        List.generate(_segments, (i) {
          final theta = i * math.pi * 2 / _segments;
          final grip = x != 0 || y != 0;
          final orientation = grip ? math.atan2(y, x) + math.pi / 2 : 0.0;
          final u = math.cos(theta) * radius * (grip ? 1.45 : 1);
          final v = math.sin(theta) * radius * (grip ? .82 : 1);
          return _Point3(
            x + u * math.cos(orientation) - v * math.sin(orientation),
            y + u * math.sin(orientation) + v * math.cos(orientation),
            z,
          );
        });

    Path loop(List<_Point3> vertices) =>
        Path()..addPolygon(vertices.map(project).toList(), true);

    Path face(double z) {
      final path = loop(circle(0, 0, 1.03, z))..fillType = PathFillType.evenOdd;
      for (final hole in _holes) {
        path.addPath(loop(circle(hole.x, hole.y, hole.radius, z)), Offset.zero);
      }
      return path;
    }

    canvas.drawOval(
      Rect.fromCenter(
        center: center + Offset(0, scale * 1.08),
        width: scale * 1.6,
        height: scale * .22,
      ),
      Paint()
        ..color = AppPalette.plateSide.withValues(alpha: .28)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, size.width * .04),
    );
    canvas.drawPath(face(-.19), Paint()..color = AppPalette.plateSide);

    final walls = <({Path path, double depth, Color color})>[];
    void addWalls(double x, double y, double radius, {bool inside = false}) {
      final front = circle(x, y, radius, .19);
      final back = circle(x, y, radius, -.19);
      for (var i = 0; i < _segments; i++) {
        final next = (i + 1) % _segments;
        final points = [front[i], back[i], back[next], front[next]];
        final angle = (i + .5) * math.pi * 2 / _segments;
        final light =
            (.45 + .3 * math.cos(angle + yaw + (inside ? math.pi : 0))).clamp(
              0.0,
              1.0,
            );
        walls.add((
          path: loop(points),
          depth: points.map(rotate).fold(0.0, (sum, p) => sum + p.z) / 4,
          color: Color.lerp(
            AppPalette.plateSide,
            inside ? AppPalette.plateSteel : AppPalette.plateRubber,
            inside ? light * .5 : light,
          )!,
        ));
      }
    }

    addWalls(0, 0, 1.03);
    for (final hole in _holes) {
      addWalls(hole.x, hole.y, hole.radius, inside: true);
    }
    walls.sort((a, b) => a.depth.compareTo(b.depth));
    for (final wall in walls) {
      canvas.drawPath(wall.path, Paint()..color = wall.color);
    }

    final front = face(.195);
    canvas.drawPath(
      front,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-.7, -.8),
          radius: 1.6,
          colors: [
            Color.lerp(AppPalette.plateRubber, AppPalette.plateSteel, .28)!,
            AppPalette.plateRubber,
            AppPalette.plateSide,
          ],
        ).createShader(front.getBounds()),
    );
    // Raised rubber rim, recessed face and a fine volt inlay.
    canvas.drawPath(
      loop(circle(0, 0, 1.01, .20)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * .018
        ..color = AppPalette.plateSide,
    );
    canvas.drawPath(
      loop(circle(0, 0, .89, .205)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * .025
        ..color = AppPalette.plateSide.withValues(alpha: .6),
    );
    canvas.drawPath(
      loop(circle(0, 0, .86, .21)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = .7
        ..color = AppPalette.plateSteel.withValues(alpha: .20),
    );
    // Fine deterministic rubber grain stays clipped away from the grip holes.
    canvas.save();
    canvas.clipPath(front);
    for (var i = 0; i < 240; i++) {
      final angle = i * 2.399963;
      final radius = math.sqrt((i + .5) / 240) * .95;
      final point = project(
        _Point3(math.cos(angle) * radius, math.sin(angle) * radius, .21),
      );
      canvas.drawCircle(
        point,
        size.width * .0018,
        Paint()
          ..color = AppPalette.plateSteel.withValues(
            alpha: i.isEven ? .10 : .035,
          ),
      );
    }
    canvas.restore();
    canvas.drawPath(
      loop(circle(0, 0, .985, .20)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(.75, size.width / 130)
        ..color = AppPalette.volt,
    );
    final hub = loop(circle(0, 0, .265, .215))
      ..fillType = PathFillType.evenOdd
      ..addPath(loop(circle(0, 0, .19, .215)), Offset.zero);
    canvas.drawPath(
      hub,
      Paint()
        ..shader = SweepGradient(
          transform: GradientRotation(yaw),
          colors: [
            AppPalette.plateSteel,
            AppPalette.plateSide,
            AppPalette.heroInk,
            AppPalette.plateSteel,
            AppPalette.plateSide,
            AppPalette.plateSteel,
          ],
        ).createShader(hub.getBounds()),
    );
    canvas.drawPath(
      loop(circle(0, 0, .19, .22)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = AppPalette.plateSide,
    );
    for (final hole in _holes.skip(1)) {
      canvas.drawPath(
        loop(circle(hole.x, hole.y, hole.radius, .20)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = .6
          ..color = AppPalette.plateSteel.withValues(alpha: .32),
      );
    }

    final text = TextPainter(
      text: TextSpan(
        text: '20 KG',
        style: TextStyle(
          fontFamily: AppTypography.bodyFamily,
          color: AppPalette.heroInk.withValues(alpha: .82),
          fontSize: size.width * .063,
          fontWeight: FontWeight.w700,
          shadows: const [
            Shadow(
              color: AppPalette.plateSide,
              offset: Offset(0, 1),
              blurRadius: 1,
            ),
          ],
          letterSpacing: .4,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final origin = project(const _Point3(0, -.58, .21));
    final axis = project(const _Point3(1, -.58, .21)) - origin;
    canvas.save();
    canvas.translate(origin.dx, origin.dy);
    canvas.rotate(math.atan2(axis.dy, axis.dx));
    canvas.scale(axis.distance / scale, 1);
    canvas.drawLine(
      Offset(-text.width * .6, text.height),
      Offset(text.width * .6, text.height),
      Paint()
        ..strokeWidth = .7
        ..color = AppPalette.plateSteel.withValues(alpha: .25),
    );
    text.paint(canvas, Offset(-text.width / 2, -text.height / 2));
    canvas.restore();
    text.dispose();
  }

  @override
  bool shouldRepaint(_WeightPlatePainter oldDelegate) =>
      oldDelegate.animation != animation;
}
