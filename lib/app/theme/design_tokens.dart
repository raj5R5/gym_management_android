import 'package:flutter/material.dart';

/// MuscleDesk "Carbon" design tokens: 60% carbon, 30% pearl, 10% red.
///
/// Ported value-for-value from the OneXhib visual system. Main actions are
/// pearl pills with carbon text; red ([AppPalette.live] and
/// [AppPalette.accentLight]) is kept for Live and warnings only. Widgets use
/// these names, never raw hex. The app is dark only.
abstract final class AppPalette {
  // Base greys.
  static const carbon = Color(0xFF141518);
  static const shade = Color(0xFF0C0D0F);
  static const surface = Color(0xFF1E2024);
  static const graphite = Color(0xFF2A2C31);
  static const steel = Color(0xFF3A3D44);
  static const silver = Color(0xFFC9CCD2);

  // Pearls.
  static const pearl = Color(0xFFF2F0EB);
  static const pearlDeep = Color(0xFFD6D3CB);
  static const pearlSide = Color(0xFF7E7C76);

  /// Main actions: pearl pills with carbon text.
  static const accent = pearl;
  static const accentDeep = pearlDeep;
  static const accentSide = pearlSide;

  /// Live, warnings and overdue money. Use for text and thin icons on carbon.
  static const accentLight = Color(0xFFFF5A5A);

  /// Filled Live/warning badges.
  static const live = Color(0xFFD40000);
  static const accentEdge = Color(0xFF2F3238);
  static const white = Color(0xFFFFFFFF);

  /// Text and icons on a filled pearl accent.
  static const onAccent = Color(0xFF141518);

  /// A dark red wash for warning panels; text on it uses [accentLight].
  static const warningWash = Color(0xFF3A1E20);

  /// "Expiring soon": time-sensitive but not yet overdue. Text/icons on carbon.
  static const amber = Color(0xFFF2B544);

  /// A dark amber wash behind [amber] text.
  static const amberWash = Color(0xFF3A3017);

  // Physical materials for the decorative gym-plate artwork.
  static const plateRubber = graphite;
  static const plateSide = shade;
  static const plateSteel = silver;

  // Compatibility names. Existing feature widgets keep compiling and pick up
  // the carbon/pearl system without changing their behaviour.
  static const canvas = carbon;
  static const darkCanvas = carbon;
  static const darkSurface = surface;
  static const raised = graphite;
  static const darkRaised = graphite;
  static const deepVolt = pearl;
  static const volt = pearl;
  static const signalTint = graphite;
  static const deepIce = pearl;
  static const ice = pearl;
  static const iceTint = graphite;
  static const ember = pearl;
  static const darkEmber = pearl;
  static const hero = surface;
  static const heroInk = white;
  static const heroMuted = silver;
  static const mint = graphite;
  static const mintInk = pearl;
  static const darkMint = graphite;
  static const darkMintInk = pearl;
  static const peach = graphite;
  static const coral = warningWash;
  static const softBlue = graphite;
  static const lavender = graphite;
  static const mutedGrey = steel;
  static const greyInk = silver;
  static const darkGrey = steel;
  static const forest = carbon;
  static const cream = carbon;
}

/// Semantic colours (OneXhib `colors`).
abstract final class AppColors {
  static const background = AppPalette.carbon;
  static const surface = AppPalette.surface;
  static const text = AppPalette.white;
  static const textMuted = Color.fromRGBO(255, 255, 255, .78);
  static const textSubtle = Color.fromRGBO(255, 255, 255, .72);
  static const label = AppPalette.silver;
  static const primary = AppPalette.accent;
  static const onPrimary = AppPalette.onAccent;
  static const link = AppPalette.pearl;
  static const live = AppPalette.accentLight;
  static const success = AppPalette.pearl;
  static const danger = AppPalette.accentLight;

  static const glass = Color.fromRGBO(255, 255, 255, .08);
  static const glassStrong = Color.fromRGBO(255, 255, 255, .12);
  static const glassSelected = Color.fromRGBO(255, 255, 255, .16);
  static const glassBorder = Color.fromRGBO(255, 255, 255, .18);
  static const glassBorderStrong = Color.fromRGBO(255, 255, 255, .25);
  static const glassHighlight = Color.fromRGBO(255, 255, 255, .15);
  static const sheet = Color.fromRGBO(30, 32, 36, .6);
  static const bar = Color.fromRGBO(30, 32, 36, .55);
  static const inset = Color.fromRGBO(20, 21, 24, .45);

  /// The simple (unblurred) glass card used inside scrolling lists.
  static const cardFill = Color.fromRGBO(255, 255, 255, .07);
  static const cardBorder = Color.fromRGBO(255, 255, 255, .16);
  static const cardTopEdge = Color.fromRGBO(255, 255, 255, .3);

  /// Inactive tab icons and labels.
  static const tabInactive = Color.fromRGBO(255, 255, 255, .68);
}

/// Pending balances use the warning role.
abstract final class PendingColors {
  static const surface = AppPalette.warningWash;
  static const accent = AppPalette.accentLight;
  static const onAccent = AppPalette.onAccent;

  static Color surfaceFor(Brightness brightness) => surface;
  static Color accentFor(Brightness brightness) => accent;
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

enum MemberCardTone { neutral, paid, due, expired }

abstract final class AppButtonStyles {
  static ButtonStyle primary(BuildContext context) => FilledButton.styleFrom(
    backgroundColor: AppColors.primary,
    foregroundColor: AppColors.onPrimary,
  );
  static ButtonStyle payment(BuildContext context) => primary(context);
  static ButtonStyle warning(BuildContext context) => FilledButton.styleFrom(
    backgroundColor: AppPalette.warningWash,
    foregroundColor: AppPalette.accentLight,
  );
}

abstract final class AppSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const xxl = 24.0;
  static const xxxl = 32.0;
  static const contentWidth = 840.0;
}

abstract final class AppRadii {
  static const sm = 12.0;
  static const md = 14.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const xxl = 24.0;
  static const sheet = 30.0;
  static const pill = 999.0;

  // Component roles.
  static const control = lg;
  static const card = xl;
  static const panel = xl;
  static const dialog = xxl;
}

/// Geist is the only family. Weights 400/500/600/700 are bundled.
abstract final class AppTypography {
  static const family = 'Geist';
  static const headingFamily = family;
  static const bodyFamily = family;
}

/// OneXhib `type`, as Flutter text styles. Line height is size-relative.
abstract final class AppType {
  static const display = TextStyle(
    fontFamily: AppTypography.family,
    fontWeight: FontWeight.w700,
    fontSize: 32,
    height: 38 / 32,
    letterSpacing: -.6,
  );
  static const title = TextStyle(
    fontFamily: AppTypography.family,
    fontWeight: FontWeight.w600,
    fontSize: 24,
    height: 30 / 24,
    letterSpacing: -.3,
  );
  static const heading = TextStyle(
    fontFamily: AppTypography.family,
    fontWeight: FontWeight.w600,
    fontSize: 17,
    height: 24 / 17,
  );
  static const body = TextStyle(
    fontFamily: AppTypography.family,
    fontWeight: FontWeight.w400,
    fontSize: 15,
    height: 22 / 15,
  );
  static const bodyStrong = TextStyle(
    fontFamily: AppTypography.family,
    fontWeight: FontWeight.w600,
    fontSize: 15,
    height: 22 / 15,
  );
  static const small = TextStyle(
    fontFamily: AppTypography.family,
    fontWeight: FontWeight.w400,
    fontSize: 13,
    height: 19 / 13,
  );
  static const caption = TextStyle(
    fontFamily: AppTypography.family,
    fontWeight: FontWeight.w500,
    fontSize: 12,
    height: 17 / 12,
  );
  static const overline = TextStyle(
    fontFamily: AppTypography.family,
    fontWeight: FontWeight.w600,
    fontSize: 12,
    height: 16 / 12,
    letterSpacing: .8,
  );
  static const tab = TextStyle(
    fontFamily: AppTypography.family,
    fontWeight: FontWeight.w500,
    fontSize: 11,
    height: 14 / 11,
  );
}

/// Blur strength for glass, as OneXhib intensities. [sigma] converts an
/// intensity to a Flutter blur sigma. Never animate blur; fade opacity.
abstract final class AppBlur {
  static const card = 40.0;
  static const bar = 60.0;
  static const sheet = 70.0;
  static double sigma(double intensity) => intensity / 4;
}

abstract final class AppMotion {
  static const easeOut = Cubic(.23, 1, .32, 1);
  static const easeInOut = Cubic(.77, 0, .175, 1);
  static const sheetCurve = Cubic(.32, .72, 0, 1);
  static const pop = Cubic(.34, 1.56, .64, 1);

  /// For looping, drawn motion (bob, drift).
  static const loopEaseInOut = Cubic(.45, 0, .55, 1);

  static const press = Duration(milliseconds: 120);
  static const small = Duration(milliseconds: 180);
  static const medium = Duration(milliseconds: 320);
  static const entrance = Duration(milliseconds: 550);

  /// Content rising into view, and the per-item stagger.
  static const rise = Duration(milliseconds: 600);
  static const stagger = Duration(milliseconds: 50);

  static const lens = Duration(milliseconds: 380);
  static const float = Duration(seconds: 6);
  static const ringSpin = Duration(seconds: 18);
  static const auroraDrift = Duration(seconds: 14);
  static const plateLoop = Duration(seconds: 10);
  static const atmosphereLoop = auroraDrift;

  /// True when the platform asks for reduced motion: nothing moves then.
  static bool reduced(BuildContext context) {
    final media = MediaQuery.of(context);
    return media.disableAnimations || media.accessibleNavigation;
  }
}

abstract final class AppShadow {
  static const card = [
    BoxShadow(
      color: Color.fromRGBO(0, 0, 0, .45),
      blurRadius: 25,
      offset: Offset(0, 20),
    ),
  ];
  static const cta = [
    BoxShadow(
      color: Color.fromRGBO(0, 0, 0, .35),
      blurRadius: 15,
      offset: Offset(0, 10),
    ),
  ];
}

/// Glass values for the older shared surfaces.
abstract final class AppGlass {
  static double navigation(Brightness brightness) => 1;
  static double dashboard(Brightness brightness) => 1;
  static const navigationBlur = AppBlur.bar;
  static const navigationHighlight = .15;
}

/// Decorative dashboard accents; they do not encode percentages or targets.
abstract final class DashboardAccents {
  static const revenue = AppPalette.pearl;
  static const pending = PendingColors.accent;
  static const members = AppPalette.silver;
  static const plans = AppPalette.pearlDeep;

  static Color revenueFor(Brightness brightness) => revenue;
  static Color membersFor(Brightness brightness) => members;
  static Color pendingFor(Brightness brightness) => pending;
}

/// Derived surfaces, so contrast decisions stay out of screen widgets.
@immutable
class AppSurfaces extends ThemeExtension<AppSurfaces> {
  const AppSurfaces({
    this.brightness = Brightness.dark,
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

  /// The app is dark only; [brightness] is accepted for compatibility.
  factory AppSurfaces.forBrightness(Brightness brightness) => const AppSurfaces(
    canvasStart: AppColors.background,
    canvasEnd: AppColors.background,
    glass: AppColors.cardFill,
    border: AppColors.cardBorder,
    shadow: Color.fromRGBO(0, 0, 0, .45),
    active: AppColors.glassSelected,
    inactive: AppColors.glass,
    suspended: AppPalette.warningWash,
    onStatus: AppColors.text,
  );

  static AppSurfaces of(BuildContext context) =>
      Theme.of(context).extension<AppSurfaces>() ??
      AppSurfaces.forBrightness(Brightness.dark);

  final Color canvasStart, canvasEnd, glass, border, shadow;
  final Brightness brightness;
  bool get isDark => true;
  final Color active, inactive, suspended, onStatus;

  Color accent(AppTone tone) => switch (tone) {
    AppTone.neutral => AppColors.glassStrong,
    AppTone.positive => AppColors.glassSelected,
    AppTone.member || AppTone.plan || AppTone.payment => AppColors.glassStrong,
    AppTone.warning => AppPalette.warningWash,
    AppTone.pending => AppPalette.accentLight,
    AppTone.expired => AppColors.glass,
  };

  Color onAccent(AppTone tone) => switch (tone) {
    AppTone.pending => AppPalette.onAccent,
    AppTone.expired => AppPalette.silver,
    AppTone.warning => AppPalette.accentLight,
    AppTone.positive ||
    AppTone.payment ||
    AppTone.member ||
    AppTone.plan => AppPalette.pearl,
    AppTone.neutral => AppColors.text,
  };

  Color statusBorder(AppTone tone) => switch (tone) {
    AppTone.pending => AppPalette.accentLight.withValues(alpha: .4),
    _ => border,
  };

  Color panel(AppTone tone, Brightness brightness) => switch (tone) {
    AppTone.neutral => AppColors.cardFill,
    AppTone.pending || AppTone.warning => AppPalette.warningWash,
    _ => accent(tone),
  };

  Color memberCard(MemberCardTone tone, Brightness brightness) =>
      switch (tone) {
        MemberCardTone.neutral => AppColors.cardFill,
        MemberCardTone.paid => AppColors.glassStrong,
        MemberCardTone.due => AppPalette.warningWash,
        MemberCardTone.expired => AppColors.glass,
      };

  LinearGradient get canvasGradient => const LinearGradient(
    colors: [AppColors.background, AppColors.background],
  );

  List<BoxShadow> get softShadow => AppShadow.card;

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
