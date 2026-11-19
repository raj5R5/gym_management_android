import 'package:flutter/material.dart';
import '../../app/theme/design_tokens.dart';
import 'glass.dart';
import 'motion.dart';
import 'card_reveal.dart';

/// The base of every screen: a flat carbon background that glass frosts.
/// [animated] is accepted for existing callers; the base never moves.
class TitaniumCanvas extends StatelessWidget {
  const TitaniumCanvas({super.key, required this.child, this.animated = false});
  final Widget child;
  final bool animated;

  @override
  Widget build(BuildContext context) =>
      ColoredBox(color: AppColors.background, child: child);
}

/// Frosted glass for bars and hero surfaces; see [Glass]. [opacity],
/// [blur] and [highlightOpacity] are accepted for existing callers, but the
/// look comes from the shared glass tokens.
class TitaniumGlass extends StatelessWidget {
  const TitaniumGlass({
    super.key,
    required this.child,
    this.radius = AppRadii.panel,
    this.opacity,
    this.blur = 16,
    this.highlightOpacity,
  });
  final Widget child;
  final double radius;
  final double? opacity;
  final double blur;
  final double? highlightOpacity;

  @override
  Widget build(BuildContext context) => Glass(
    radius: radius,
    intensity: radius == 0 ? AppBlur.bar : AppBlur.card,
    borderColor: radius == 0 ? Colors.transparent : AppColors.glassBorder,
    borderWidth: radius == 0 ? 0 : 1,
    highlight: radius != 0,
    shadow: radius == 0 ? null : AppShadow.card,
    child: child,
  );
}

/// Content rising into view; see [Rise].
class TitaniumEntrance extends StatelessWidget {
  const TitaniumEntrance({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Rise(child: child);
}

/// Native navigation keeps its routes and guards; only the visual transition changes.
///
/// A page opened from a card (see [CardOrigin]) grows out of that card and
/// shrinks back into it; any other page fades and slides in. [fallback]
/// replaces the fade on platforms with their own gestures, such as iOS
/// swipe-back.
class TitaniumPageTransitions extends PageTransitionsBuilder {
  const TitaniumPageTransitions({this.fallback});

  final PageTransitionsBuilder? fallback;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final origin = cardOriginFor(route);
    final media = MediaQuery.of(context);
    if (media.disableAnimations || media.accessibleNavigation) return child;
    if (origin != null) {
      return CardReveal(animation: animation, origin: origin, child: child);
    }
    if (fallback case final fallback?) {
      return fallback.buildTransitions(
        route,
        context,
        animation,
        secondaryAnimation,
        child,
      );
    }
    final eased = animation.drive(CurveTween(curve: AppMotion.easeOut));
    return FadeTransition(
      opacity: eased,
      child: SlideTransition(
        position: eased.drive(
          Tween(begin: const Offset(.035, .025), end: Offset.zero),
        ),
        child: child,
      ),
    );
  }
}

/// Press feedback without owning the action, focus or enabled semantics;
/// see [PressableScale].
class TitaniumPress extends StatelessWidget {
  const TitaniumPress({super.key, required this.child, this.enabled = true});
  final Widget child;
  final bool enabled;

  @override
  Widget build(BuildContext context) =>
      PressableScale(enabled: enabled, child: child);
}
