import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../../app/theme/design_tokens.dart';
import '../../../shared/formatting/inr.dart';
import '../../../shared/widgets/soft_panel.dart';
import '../../../shared/widgets/card_reveal.dart';

/// A decorative reveal, deliberately without progress/percentage semantics.
class MetricRing extends StatelessWidget {
  const MetricRing({
    super.key,
    required this.color,
    required this.reveal,
    required this.child,
    this.inset = AppSpacing.lg,
  });
  final Color color;
  final double reveal;
  final Widget child;
  final double inset;

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _RingPainter(
      color,
      Theme.of(context).colorScheme.surface,
      color.withValues(alpha: .12),
      reveal,
    ),
    child: Padding(padding: EdgeInsets.all(inset), child: child),
  );
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.color, this.surface, this.track, this.reveal);
  final Color color, surface, track;
  final double reveal;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(5);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    canvas.drawOval(
      rect.shift(const Offset(0, 2)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..color = Colors.black.withValues(alpha: .12)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawOval(rect, paint..color = track);
    if (reveal > 0) {
      paint.shader = SweepGradient(
        transform: const GradientRotation(-math.pi / 2),
        colors: [
          Color.lerp(color, surface, .38)!,
          color,
          Color.lerp(color, surface, .18)!,
        ],
        stops: const [0, .6, 1],
      ).createShader(rect);
      canvas.drawArc(
        rect,
        -math.pi / 2,
        math.pi * 2 * reveal.clamp(0, 1),
        false,
        paint..color = color,
      );
      canvas.drawArc(
        rect.deflate(2.5),
        -math.pi / 2,
        math.pi * 2 * reveal.clamp(0, 1),
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = Colors.white.withValues(alpha: .32),
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      color != old.color ||
      surface != old.surface ||
      track != old.track ||
      reveal != old.reveal;
}

/// Layouts share one finite reveal/count animation and exact-paise formatting.
enum MetricCardLayout { circular, revenueHero, compact, balance }

class CircularMetricCard extends StatefulWidget {
  const CircularMetricCard({
    super.key,
    required this.title,
    required this.caption,
    required this.color,
    this.value,
    this.money = false,
    this.error,
    this.retry,
    this.icon = Icons.insights_outlined,
    this.surfaceTint,
    this.iconBackground,
    this.periodLabel,
    this.layout = MetricCardLayout.circular,
    this.onTap,
  });
  final String title, caption;
  final Color color;
  final int? value;
  final bool money;
  final String? error;
  final VoidCallback? retry;
  final IconData icon;
  final Color? surfaceTint;
  final Color? iconBackground;
  final String? periodLabel;
  final MetricCardLayout layout;
  final VoidCallback? onTap;

  @override
  State<CircularMetricCard> createState() => _CircularMetricCardState();
}

class _CircularMetricCardState extends State<CircularMetricCard>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  );
  int _beginCount = 0;
  bool _reduceMotion = false;
  double get _reveal => Curves.easeOutCubic.transform(_controller.value);
  int get _count => _controller.isCompleted
      ? widget.value ?? 0
      : IntTween(begin: _beginCount, end: widget.value ?? 0).transform(_reveal);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final media = MediaQuery.of(context);
    _reduceMotion = media.disableAnimations || media.accessibleNavigation;
    if (widget.value != null) {
      if (_reduceMotion) {
        _controller.value = 1;
      } else if (!_controller.isAnimating && !_controller.isCompleted) {
        _controller.forward();
      }
    }
  }

  @override
  void didUpdateWidget(CircularMetricCard old) {
    super.didUpdateWidget(old);
    if (old.value == widget.value) return;
    // Count interpolation is presentation only. Money is always formatted from
    // the authoritative integer paise and only fades; never tween money as double.
    _beginCount = widget.money || old.value == null
        ? 0
        : (_controller.isCompleted
              ? old.value!
              : IntTween(
                  begin: _beginCount,
                  end: old.value!,
                ).transform(_reveal));
    if (widget.value == null) {
      _controller.stop();
      _controller.value = 0;
    } else if (_reduceMotion) {
      _controller.value = 1;
    } else {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tint = widget.surfaceTint ?? widget.color;
    final strength = widget.surfaceTint == null ? .08 : .32;
    final cardGradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color.lerp(
          theme.colorScheme.surface,
          tint,
          strength,
        )!.withValues(alpha: AppGlass.dashboard(theme.brightness)),
        Color.lerp(
          theme.colorScheme.surface,
          tint,
          strength / 4,
        )!.withValues(alpha: AppGlass.dashboard(theme.brightness)),
      ],
    );
    final captionStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    final captionLineHeight =
        MediaQuery.textScalerOf(context).scale(captionStyle?.fontSize ?? 12) *
        (captionStyle?.height ?? 1.4);
    final value = widget.value;
    final formatted = value == null
        ? null
        : widget.money
        ? formatInrPaise(value)
        : '$value';
    final label = widget.error != null
        ? '${widget.title}: unavailable. ${widget.error}'
        : formatted == null
        ? 'Loading ${widget.title}'
        : '${widget.title}: $formatted. ${widget.periodLabel == null ? '' : '${widget.periodLabel}. '}${widget.caption}';
    if (widget.layout != MetricCardLayout.circular) {
      return Semantics(
        container: true,
        button: widget.onTap != null,
        label: label,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final visual = switch (widget.layout) {
              MetricCardLayout.revenueHero => _hero(context, formatted),
              MetricCardLayout.balance => _balance(context, formatted),
              _ => _compact(context, formatted, cardGradient),
            };
            if (widget.onTap == null ||
                widget.layout == MetricCardLayout.compact ||
                widget.layout == MetricCardLayout.balance) {
              return visual;
            }
            // Transparent Material above the opaque panel keeps ink visible over
            // gradients. Failed-plan cards retain their separate retry button.
            return Stack(
              children: [
                visual,
                Positioned.fill(
                  child: Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(AppRadii.panel),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () {
                        CardOrigin.mark(context);
                        widget.onTap!();
                      },
                      borderRadius: BorderRadius.circular(AppRadii.panel),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      );
    }
    return Semantics(
      container: true,
      label: label,
      child: SoftPanel(
        padding: const EdgeInsets.all(AppSpacing.lg),
        gradient: cardGradient,
        child: Column(
          children: [
            ExcludeSemantics(
              child: Text(
                widget.title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -.2,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            if (widget.periodLabel != null) ...[
              ExcludeSemantics(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: widget.color.withValues(alpha: .07),
                    borderRadius: BorderRadius.circular(AppRadii.control),
                  ),
                  child: Text(
                    widget.periodLabel!,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: .4,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            ExcludeSemantics(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final diameter = math.min(144.0, constraints.maxWidth);
                  return SizedBox.square(
                    dimension: diameter,
                    child: AnimatedBuilder(
                      animation: _controller,
                      builder: (context, _) => MetricRing(
                        color: widget.color,
                        reveal: value == null ? 0 : _reveal,
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 30,
                                height: 30,
                                decoration: BoxDecoration(
                                  color:
                                      widget.surfaceTint ??
                                      Color.lerp(
                                        AppPalette.cream,
                                        widget.color,
                                        .18,
                                      ),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  widget.icon,
                                  size: 18,
                                  color: widget.surfaceTint != null
                                      ? AppPalette.forest
                                      : widget.color,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.xs),
                              Flexible(
                                child: widget.error != null
                                    ? Icon(
                                        Icons.cloud_off_outlined,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                      )
                                    : formatted == null
                                    ? Text(
                                        '—',
                                        style: Theme.of(
                                          context,
                                        ).textTheme.headlineMedium,
                                      )
                                    : AnimatedSwitcher(
                                        duration: Duration(
                                          milliseconds: _reduceMotion ? 0 : 200,
                                        ),
                                        child: FittedBox(
                                          fit: BoxFit.scaleDown,
                                          key: ValueKey(formatted),
                                          child: Text(
                                            widget.money
                                                ? formatted
                                                : '$_count',
                                            style: Theme.of(context)
                                                .textTheme
                                                .headlineMedium
                                                ?.copyWith(
                                                  fontSize: widget.money
                                                      ? 26
                                                      : 36,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                          ),
                                        ),
                                      ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            ConstrainedBox(
              // Align ordinary one/two-line captions without clipping larger text.
              constraints: BoxConstraints(minHeight: captionLineHeight * 2),
              child: ExcludeSemantics(
                child: Text(
                  widget.error ?? widget.caption,
                  textAlign: TextAlign.center,
                  style: captionStyle,
                ),
              ),
            ),
            if (widget.retry != null)
              TextButton(
                onPressed: widget.retry,
                child: const Text('Retry plans'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _value(
    BuildContext context,
    String? formatted, {
    required double size,
    Color? color,
  }) {
    return Align(
      alignment: Alignment.centerLeft,
      child: AnimatedSwitcher(
        duration: Duration(milliseconds: _reduceMotion ? 0 : 200),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          key: ValueKey(formatted ?? widget.error ?? 'loading'),
          child: Text(
            widget.error != null
                ? '—'
                : formatted == null
                ? '—'
                : widget.money
                ? formatted
                : '$_count',
            style: Theme.of(context).textTheme.headlineLarge?.copyWith(
              fontFamily: AppTypography.bodyFamily,
              fontFeatures: const [FontFeature.tabularFigures()],
              fontSize: size,
              fontWeight: FontWeight.w700,
              letterSpacing: -.6,
              color: color,
            ),
          ),
        ),
      ),
    );
  }

  Widget _ring(double diameter, Color color, {bool hero = false}) {
    final ring = SizedBox.square(
      dimension: diameter,
      child: MetricRing(
        color: color,
        // A 40dp ring needs room for the full 18dp glyph, not an 8dp box.
        inset: hero ? AppSpacing.lg : AppSpacing.sm,
        reveal: widget.value == null || widget.error != null ? 0 : _reveal,
        child: Center(
          child: Icon(widget.icon, color: color, size: hero ? 28 : 18),
        ),
      ),
    );
    return !hero && widget.iconBackground != null
        ? DecoratedBox(
            decoration: BoxDecoration(
              color: widget.iconBackground,
              shape: BoxShape.circle,
            ),
            child: ring,
          )
        : ring;
  }

  Widget _hero(BuildContext context, String? formatted) {
    final theme = Theme.of(context);
    return SoftPanel(
      glass: true,
      glassOpacity: AppGlass.dashboard(theme.brightness),
      padding: EdgeInsets.zero,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: theme.colorScheme.primary, width: 3),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: ExcludeSemantics(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.title, style: theme.textTheme.titleMedium),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        widget.periodLabel ?? 'Loading selected period…',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      _value(
                        context,
                        formatted,
                        size: 36,
                        color: theme.colorScheme.onSurface,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        widget.error ?? widget.caption,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                _ring(64, theme.colorScheme.primary, hero: true),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _balance(BuildContext context, String? formatted) {
    final theme = Theme.of(context);
    final identity = Row(
      children: [
        _ring(40, widget.color),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.title, style: theme.textTheme.labelMedium),
              const SizedBox(height: AppSpacing.xs),
              _value(context, formatted, size: 26, color: widget.color),
              if (widget.error != null)
                Text(widget.error!, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ],
    );
    final action = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            'View dues',
            style: theme.textTheme.labelLarge?.copyWith(color: widget.color),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Icon(Icons.arrow_outward, size: 18, color: widget.color),
      ],
    );
    return SoftPanel(
      onTap: widget.onTap,
      tone: AppTone.pending,
      glass: true,
      backgroundColor: PendingColors.surfaceFor(theme.brightness),
      glassOpacity: .84,
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: ExcludeSemantics(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final stack =
                constraints.maxWidth < 300 ||
                MediaQuery.textScalerOf(context).scale(14) > 18.2;
            return stack
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      identity,
                      if (widget.onTap != null) ...[
                        const SizedBox(height: AppSpacing.md),
                        action,
                      ],
                    ],
                  )
                : Row(
                    children: [
                      Expanded(child: identity),
                      if (widget.onTap != null) ...[
                        const SizedBox(width: AppSpacing.md),
                        action,
                      ],
                    ],
                  );
          },
        ),
      ),
    );
  }

  Widget _compact(BuildContext context, String? formatted, Gradient gradient) {
    final theme = Theme.of(context);
    return SoftPanel(
      onTap: widget.onTap,
      gradient: gradient,
      glass: true,
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ring(40, widget.color),
                const SizedBox(height: AppSpacing.sm),
                ConstrainedBox(
                  // Reserve two label lines so values remain aligned when
                  // Pending Amount and Total Members wrap on smaller phones.
                  constraints: BoxConstraints(
                    minHeight:
                        MediaQuery.textScalerOf(
                          context,
                        ).scale(theme.textTheme.labelMedium!.fontSize!) *
                        (theme.textTheme.labelMedium!.height ?? 1.4) *
                        2,
                  ),
                  child: Text(
                    widget.title,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                _value(context, formatted, size: widget.money ? 22 : 28),
                if (widget.error != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    widget.error!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (widget.retry != null)
            TextButton(
              onPressed: widget.retry,
              child: const Text('Retry plans'),
            ),
        ],
      ),
    );
  }
}
