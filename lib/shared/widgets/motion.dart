import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme/design_tokens.dart';

/// Content rising into view once, on first build: 16px up, scale 0.97 to 1
/// and a fade, over 600ms ease-out. Stagger lists with [delay] (about 50ms
/// per item, see [Rise.staggered]). Static when reduced motion is on.
class Rise extends StatefulWidget {
  const Rise({super.key, required this.child, this.delay = Duration.zero});

  /// The [index]th item of a staggered group.
  Rise.staggered({super.key, required this.child, required int index})
    : delay = AppMotion.stagger * index.clamp(0, 12);

  final Widget child;
  final Duration delay;

  @override
  State<Rise> createState() => _RiseState();
}

class _RiseState extends State<Rise> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: AppMotion.rise,
  );
  late final _curve = CurvedAnimation(
    parent: _controller,
    curve: AppMotion.easeOut,
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (AppMotion.reduced(context)) {
      _controller.value = 1;
    } else if (widget.delay == Duration.zero) {
      _controller.forward();
    } else {
      Future<void>.delayed(widget.delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _curve.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _curve,
    child: widget.child,
    builder: (context, child) {
      final t = _curve.value;
      return Opacity(
        opacity: _controller.value.clamp(0, 1),
        child: Transform.translate(
          offset: Offset(0, 16 * (1 - t)),
          child: Transform.scale(scale: .97 + .03 * t, child: child),
        ),
      );
    },
  );
}

/// Press feedback: shrinks to [pressedScale] on press-in in 120ms with a
/// strong ease-out, settles back on release. With reduced motion it dims
/// instead of moving. [haptic] adds a light impact when the press commits.
///
/// Wrap a button or card that owns its own tap handling with [onPressed]
/// null, or give [onPressed] to make the child tappable.
class PressableScale extends StatefulWidget {
  const PressableScale({
    super.key,
    required this.child,
    this.onPressed,
    this.enabled = true,
    this.pressedScale = .97,
    this.haptic = false,
  });

  final Widget child;
  final VoidCallback? onPressed;
  final bool enabled;
  final double pressedScale;
  final bool haptic;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _pressed = false;

  void _set(bool value) {
    if (_pressed != value && mounted) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final reduced = AppMotion.reduced(context);
    final active = widget.enabled && _pressed;
    Widget child = AnimatedOpacity(
      opacity: active && reduced ? .8 : 1,
      duration: AppMotion.press,
      curve: AppMotion.easeOut,
      child: AnimatedScale(
        scale: active && !reduced ? widget.pressedScale : 1,
        duration: AppMotion.press,
        curve: AppMotion.easeOut,
        child: widget.child,
      ),
    );
    if (widget.onPressed != null) {
      child = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.enabled
            ? () {
                if (widget.haptic) HapticFeedback.lightImpact();
                widget.onPressed!();
              }
            : null,
        child: child,
      );
    }
    return Listener(
      onPointerDown: widget.enabled ? (_) => _set(true) : null,
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: child,
    );
  }
}
