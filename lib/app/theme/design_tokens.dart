import 'package:flutter/material.dart';

/// The product palette. Screens use these tokens or semantic theme colors.
abstract final class AppPalette {
  static const carbon = Color(0xFF171D26);
  static const canvas = Color(0xFFF4F5F7);
  static const darkCanvas = Color(0xFF14181F);
  static const surface = Color(0xFFFFFFFF);
  static const darkSurface = Color(0xFF1C222B);
  static const raised = Color(0xFFECEFF3);
  static const darkRaised = Color(0xFF262E3A);
  static const ember = Color(0xFFB3472B);
  static const darkEmber = Color(0xFFFF9B7F);
  static const hero = Color(0xFF202630);
  static const heroInk = Color(0xFFF3F5F8);
  static const heroMuted = Color(0xFFBAC3CF);
  static const mint = Color(0xFFDCF2E8);
  static const mintInk = Color(0xFF145A42);
  static const darkMint = Color(0xFF213A30);
  static const darkMintInk = Color(0xFFA6E7C6);
  static const peach = Color(0xFFFAEAE3);
  static const coral = Color(0xFFFBE3DF);
  static const softBlue = Color(0xFFE7EFFB);
  static const lavender = Color(0xFFE7EFFB);
  static const mutedGrey = Color(0xFFE8EBEF);
  static const greyInk = Color(0xFF505B68);
  static const darkGrey = Color(0xFF303741);
  // Compatibility names for existing presentation widgets, now Carbon + Ember.
  static const forest = carbon;
  static const cream = canvas;
}

enum AppTone {
  neutral,
  positive,
  member,
  plan,
  payment,
  warning,
  pending,
  expired,
}

/// Pending balances use a separate warning role; ordinary payment controls
/// retain their peach styling.
abstract final class PendingColors {
  static const surface = AppPalette.coral;
  static const accent = Color(0xFFA72F35);
  static const onAccent = AppPalette.surface;

  static Color surfaceFor(Brightness brightness) =>
      brightness == Brightness.dark ? const Color(0xFF422A2A) : surface;
  static Color accentFor(Brightness brightness) =>
      brightness == Brightness.dark ? const Color(0xFFFFB4AE) : accent;
}

enum MemberCardTone { neutral, paid, due, expired }

abstract final class AppButtonStyles {
  static ButtonStyle primary(BuildContext context) => FilledButton.styleFrom(
    backgroundColor: Theme.of(context).colorScheme.primary,
    foregroundColor: Theme.of(context).colorScheme.onPrimary,
  );
  static ButtonStyle payment(BuildContext context) => primary(context);
  static ButtonStyle warning(BuildContext context) => FilledButton.styleFrom(
    backgroundColor: Theme.of(context).colorScheme.errorContainer,
    foregroundColor: Theme.of(context).colorScheme.onErrorContainer,
  );
}

abstract final class AppSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
  static const contentWidth = 840.0;
}

abstract final class AppRadii {
  static const control = 12.0;
  static const card = 20.0;
  static const panel = 24.0;
  static const pill = 100.0;
}

/// Decorative dashboard accents; they do not encode percentages or targets.
abstract final class DashboardAccents {
  static const revenue = AppPalette.ember;
  static const pending = PendingColors.accent;
  static const members = Color(0xFF355E9B);
  static const plans = AppPalette.ember;

  static Color revenueFor(Brightness brightness) =>
      brightness == Brightness.dark ? AppPalette.darkEmber : revenue;
  static Color membersFor(Brightness brightness) =>
      brightness == Brightness.dark ? const Color(0xFFA8C9FA) : members;
  static Color pendingFor(Brightness brightness) =>
      PendingColors.accentFor(brightness);
}

/// Derived surfaces keep light/dark contrast decisions out of screen widgets.
@immutable
class AppSurfaces extends ThemeExtension<AppSurfaces> {
  const AppSurfaces({
    this.brightness = Brightness.light,
    required this.canvasStart,
    required this.canvasEnd,
    required this.glass,
    required this.border,
    required this.shadow,
    required this.active,
    required this.inactive,
    required this.suspended,
    required this.onStatus,
  });

  factory AppSurfaces.forBrightness(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    return AppSurfaces(
      brightness: brightness,
      canvasStart: dark ? AppPalette.darkCanvas : AppPalette.canvas,
      canvasEnd: dark ? AppPalette.darkCanvas : AppPalette.canvas,
      glass: dark ? AppPalette.darkSurface : AppPalette.surface,
      border: dark ? const Color(0xFF384352) : const Color(0xFFDDE1E7),
      shadow: AppPalette.carbon.withValues(alpha: dark ? .18 : .04),
      active: dark ? AppPalette.darkMint : AppPalette.mint,
      inactive: dark ? AppPalette.darkGrey : AppPalette.mutedGrey,
      suspended: PendingColors.surfaceFor(brightness),
      onStatus: dark ? AppPalette.heroInk : AppPalette.carbon,
    );
  }

  static AppSurfaces of(BuildContext context) =>
      Theme.of(context).extension<AppSurfaces>() ??
      AppSurfaces.forBrightness(Theme.of(context).brightness);

  final Color canvasStart, canvasEnd, glass, border, shadow;
  final Brightness brightness;
  bool get isDark => brightness == Brightness.dark;
  final Color active, inactive, suspended, onStatus;

  Color accent(AppTone tone) => switch (tone) {
    AppTone.neutral => isDark ? AppPalette.darkRaised : AppPalette.raised,
    AppTone.positive => isDark ? AppPalette.darkMint : AppPalette.mint,
    AppTone.member ||
    AppTone.plan => isDark ? const Color(0xFF233249) : AppPalette.softBlue,
    AppTone.payment => isDark ? const Color(0xFF3A2824) : AppPalette.peach,
    AppTone.warning => PendingColors.surfaceFor(brightness),
    AppTone.pending => PendingColors.accentFor(brightness),
    AppTone.expired => isDark ? AppPalette.darkGrey : AppPalette.mutedGrey,
  };

  Color onAccent(AppTone tone) => switch (tone) {
    AppTone.pending => isDark ? AppPalette.carbon : PendingColors.onAccent,
    AppTone.expired => isDark ? const Color(0xFFC2CBD6) : AppPalette.greyInk,
    AppTone.positive => isDark ? AppPalette.darkMintInk : AppPalette.mintInk,
    AppTone.warning => PendingColors.accentFor(brightness),
    AppTone.payment => isDark ? AppPalette.darkEmber : AppPalette.ember,
    AppTone.member ||
    AppTone.plan => isDark ? const Color(0xFFA8C9FA) : const Color(0xFF355E9B),
    _ => isDark ? AppPalette.heroInk : AppPalette.carbon,
  };

  Color statusBorder(AppTone tone) => switch (tone) {
    AppTone.pending => PendingColors.accent.withValues(alpha: .28),
    AppTone.expired => AppPalette.greyInk.withValues(alpha: .18),
    _ => border,
  };

  Color panel(AppTone tone, Brightness brightness) => tone == AppTone.neutral
      ? (brightness == Brightness.dark
            ? AppPalette.darkSurface
            : AppPalette.surface)
      : tone == AppTone.pending
      ? PendingColors.surfaceFor(brightness)
      : accent(tone);

  Color memberCard(MemberCardTone tone, Brightness brightness) {
    final tint = switch (tone) {
      MemberCardTone.neutral => AppPalette.surface,
      MemberCardTone.paid => AppPalette.mint,
      MemberCardTone.due => PendingColors.surface,
      MemberCardTone.expired => AppPalette.mutedGrey,
    };
    if (brightness == Brightness.dark && tone == MemberCardTone.expired) {
      return AppPalette.darkGrey;
    }
    return brightness == Brightness.dark
        ? switch (tone) {
            MemberCardTone.paid => AppPalette.darkMint,
            MemberCardTone.due => PendingColors.surfaceFor(brightness),
            _ => AppPalette.darkSurface,
          }
        : tint;
  }

  LinearGradient get canvasGradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [canvasStart, canvasEnd],
  );

  List<BoxShadow> get softShadow => [
    BoxShadow(color: shadow, blurRadius: 24, offset: const Offset(0, 8)),
  ];

  @override
  AppSurfaces copyWith({
    Brightness? brightness,
    Color? canvasStart,
    Color? canvasEnd,
    Color? glass,
    Color? border,
    Color? shadow,
    Color? active,
    Color? inactive,
    Color? suspended,
    Color? onStatus,
  }) => AppSurfaces(
    brightness: brightness ?? this.brightness,
    canvasStart: canvasStart ?? this.canvasStart,
    canvasEnd: canvasEnd ?? this.canvasEnd,
    glass: glass ?? this.glass,
    border: border ?? this.border,
    shadow: shadow ?? this.shadow,
    active: active ?? this.active,
    inactive: inactive ?? this.inactive,
    suspended: suspended ?? this.suspended,
    onStatus: onStatus ?? this.onStatus,
  );

  @override
  AppSurfaces lerp(covariant AppSurfaces? other, double t) {
    if (other == null) return this;
    return AppSurfaces(
      brightness: t < .5 ? brightness : other.brightness,
      canvasStart: Color.lerp(canvasStart, other.canvasStart, t)!,
      canvasEnd: Color.lerp(canvasEnd, other.canvasEnd, t)!,
      glass: Color.lerp(glass, other.glass, t)!,
      border: Color.lerp(border, other.border, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
      active: Color.lerp(active, other.active, t)!,
      inactive: Color.lerp(inactive, other.inactive, t)!,
      suspended: Color.lerp(suspended, other.suspended, t)!,
      onStatus: Color.lerp(onStatus, other.onStatus, t)!,
    );
  }
}
