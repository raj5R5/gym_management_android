import 'package:flutter/material.dart';

/// Presentation hosts can render static decorations without changing route,
/// form or financial animations. Platform reduced motion is still authoritative.
class AmbientMotionSettings extends InheritedWidget {
  const AmbientMotionSettings({
    super.key,
    required this.enabled,
    required super.child,
  });
  final bool enabled;

  static bool enabledOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<AmbientMotionSettings>()
          ?.enabled ??
      true;

  @override
  bool updateShouldNotify(AmbientMotionSettings oldWidget) =>
      enabled != oldWidget.enabled;
}

/// A repaint-only decorative loop. It never rebuilds operational content and
/// suspends when motion is disabled, its route is hidden or the app backgrounds.
class AmbientMotion extends StatefulWidget {
  const AmbientMotion({
    super.key,
    required this.duration,
    required this.builder,
    this.enabled = true,
  });

  final Duration duration;
  final bool enabled;
  final Widget Function(BuildContext, Animation<double>) builder;

  @override
  State<AmbientMotion> createState() => _AmbientMotionState();
}

class _AmbientMotionState extends State<AmbientMotion>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final _controller = AnimationController(vsync: this);
  bool _reduced = false, _visible = true;
  AppLifecycleState _lifecycle = AppLifecycleState.resumed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lifecycle =
        WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final media = MediaQuery.of(context);
    _reduced = media.disableAnimations || media.accessibleNavigation;
    _visible =
        TickerMode.of(context) && AmbientMotionSettings.enabledOf(context);
    _sync();
  }

  @override
  void didUpdateWidget(AmbientMotion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.duration != widget.duration) _controller.stop();
    _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
    _sync();
  }

  void _sync() {
    if (widget.enabled &&
        !_reduced &&
        _visible &&
        _lifecycle == AppLifecycleState.resumed) {
      if (!_controller.isAnimating) _controller.repeat(period: widget.duration);
    } else {
      _controller.stop();
      if (_reduced) _controller.value = 0;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _controller);
}
