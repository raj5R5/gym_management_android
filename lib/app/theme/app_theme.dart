import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../shared/widgets/titanium_surface.dart';
import 'design_tokens.dart';

/// The Carbon theme. MuscleDesk is dark only, so [light] and [dark] are the
/// same theme; both names remain for existing callers.
abstract final class AppTheme {
  static final dark = _build();
  static final light = dark;

  static ThemeData _build() {
    final surfaces = AppSurfaces.forBrightness(Brightness.dark);
    const scheme = ColorScheme(
      brightness: Brightness.dark,
      primary: AppColors.primary,
      onPrimary: AppColors.onPrimary,
      primaryContainer: AppPalette.graphite,
      onPrimaryContainer: AppPalette.pearl,
      secondary: AppPalette.pearl,
      onSecondary: AppPalette.onAccent,
      secondaryContainer: AppPalette.graphite,
      onSecondaryContainer: AppPalette.pearl,
      tertiary: AppPalette.silver,
      onTertiary: AppPalette.onAccent,
      tertiaryContainer: AppPalette.graphite,
      onTertiaryContainer: AppPalette.pearl,
      error: AppColors.danger,
      onError: AppPalette.onAccent,
      errorContainer: AppPalette.warningWash,
      onErrorContainer: AppColors.danger,
      surface: AppPalette.surface,
      onSurface: AppColors.text,
      surfaceContainerLowest: AppPalette.shade,
      surfaceContainerLow: AppPalette.carbon,
      surfaceContainer: AppPalette.surface,
      surfaceContainerHigh: AppPalette.graphite,
      surfaceContainerHighest: AppPalette.steel,
      onSurfaceVariant: AppColors.textMuted,
      outline: AppColors.glassBorderStrong,
      outlineVariant: AppColors.glassBorder,
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: AppPalette.pearl,
      onInverseSurface: AppPalette.onAccent,
      inversePrimary: AppPalette.carbon,
      surfaceTint: Colors.transparent,
    );
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      fontFamily: AppTypography.family,
      scaffoldBackgroundColor: Colors.transparent,
      splashFactory: NoSplash.splashFactory,
      highlightColor: AppColors.glass,
      extensions: [surfaces],
    );
    final t = base.textTheme;
    TextStyle? as(TextStyle? m, TextStyle s) =>
        m?.merge(s).copyWith(color: AppColors.text);
    final textTheme = t.copyWith(
      displayLarge: as(t.displayLarge, AppType.display.copyWith(fontSize: 44)),
      displayMedium: as(
        t.displayMedium,
        AppType.display.copyWith(fontSize: 38),
      ),
      displaySmall: as(t.displaySmall, AppType.display),
      headlineLarge: as(t.headlineLarge, AppType.display),
      headlineMedium: as(
        t.headlineMedium,
        AppType.title.copyWith(fontSize: 28, height: 34 / 28),
      ),
      headlineSmall: as(t.headlineSmall, AppType.title),
      titleLarge: as(t.titleLarge, AppType.title.copyWith(fontSize: 20)),
      titleMedium: as(t.titleMedium, AppType.heading),
      titleSmall: as(t.titleSmall, AppType.bodyStrong),
      bodyLarge: as(t.bodyLarge, AppType.body.copyWith(fontSize: 16)),
      bodyMedium: as(t.bodyMedium, AppType.body),
      bodySmall: as(
        t.bodySmall,
        AppType.small,
      )?.copyWith(color: AppColors.textMuted),
      labelLarge: as(t.labelLarge, AppType.bodyStrong),
      labelMedium: as(t.labelMedium, AppType.caption),
      labelSmall: as(t.labelSmall, AppType.caption.copyWith(fontSize: 11)),
    );
    final pill = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadii.pill),
    );
    final glassPill = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadii.pill),
      side: const BorderSide(color: AppColors.glassBorderStrong),
    );
    OutlineInputBorder field(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.lg),
          borderSide: BorderSide(color: color, width: width),
        );
    return base.copyWith(
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      iconTheme: const IconThemeData(color: AppColors.text, size: 22),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: TitaniumPageTransitions(),
          TargetPlatform.iOS: TitaniumPageTransitions(
            fallback: CupertinoPageTransitionsBuilder(),
          ),
          TargetPlatform.macOS: TitaniumPageTransitions(
            fallback: CupertinoPageTransitionsBuilder(),
          ),
        },
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.text,
        systemOverlayStyle: SystemUiOverlayStyle.light.copyWith(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarIconBrightness: Brightness.light,
        ),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: textTheme.titleMedium,
      ),
      drawerTheme: const DrawerThemeData(
        backgroundColor: AppPalette.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.horizontal(
            right: Radius.circular(AppRadii.sheet),
          ),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: AppPalette.graphite,
        surfaceTintColor: Colors.transparent,
        textStyle: textTheme.bodyMedium,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.lg),
          side: const BorderSide(color: AppColors.glassBorder),
        ),
      ),
      menuTheme: const MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(AppPalette.graphite),
          surfaceTintColor: WidgetStatePropertyAll(Colors.transparent),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        elevation: 8,
        highlightElevation: 8,
        shape: pill,
        extendedTextStyle: textTheme.labelLarge,
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        iconColor: AppColors.textMuted,
        textColor: AppColors.text,
        titleTextStyle: textTheme.bodyLarge,
        subtitleTextStyle: textTheme.bodySmall,
        selectedColor: AppColors.text,
        selectedTileColor: AppColors.glassSelected,
        minVerticalPadding: 10,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.lg),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.glassBorder,
        thickness: 1,
        space: 24,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.primary,
        linearTrackColor: AppColors.glassStrong,
        circularTrackColor: Colors.transparent,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppPalette.graphite,
        contentTextStyle: textTheme.bodyMedium,
        actionTextColor: AppPalette.pearl,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.lg),
          side: const BorderSide(color: AppColors.glassBorder),
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.cardFill,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.card),
          side: const BorderSide(color: AppColors.cardBorder),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onPrimary,
          disabledBackgroundColor: AppColors.glassStrong,
          disabledForegroundColor: AppColors.textSubtle,
          minimumSize: const Size(54, 54),
          elevation: 0,
          textStyle: textTheme.labelLarge?.copyWith(fontSize: 16),
          animationDuration: AppMotion.press,
          padding: const EdgeInsets.symmetric(horizontal: 22),
          shape: pill,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.glassStrong,
          foregroundColor: AppColors.text,
          minimumSize: const Size(54, 54),
          elevation: 0,
          shape: glassPill,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 54),
          backgroundColor: AppColors.glassStrong,
          foregroundColor: AppColors.text,
          textStyle: textTheme.labelLarge,
          side: const BorderSide(color: AppColors.glassBorderStrong),
          padding: const EdgeInsets.symmetric(horizontal: 22),
          shape: pill,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          foregroundColor: AppColors.link,
          textStyle: textTheme.labelLarge,
          shape: pill,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: AppColors.text,
          minimumSize: const Size(48, 48),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          backgroundColor: AppColors.glass,
          foregroundColor: AppColors.textMuted,
          selectedBackgroundColor: AppPalette.pearl,
          selectedForegroundColor: AppPalette.onAccent,
          side: const BorderSide(color: AppColors.glassBorder),
          minimumSize: const Size(48, 48),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? AppPalette.onAccent
              : AppPalette.silver,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? AppPalette.pearl
              : AppColors.glassStrong,
        ),
        trackOutlineColor: const WidgetStatePropertyAll(AppColors.glassBorder),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? AppPalette.pearl
              : Colors.transparent,
        ),
        checkColor: const WidgetStatePropertyAll(AppPalette.onAccent),
        side: const BorderSide(color: AppColors.glassBorderStrong, width: 1.5),
      ),
      radioTheme: const RadioThemeData(
        fillColor: WidgetStatePropertyAll(AppPalette.pearl),
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: AppPalette.surface,
        surfaceTintColor: Colors.transparent,
        headerBackgroundColor: AppPalette.graphite,
        headerForegroundColor: AppColors.text,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.xxl),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppPalette.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 12,
        titleTextStyle: textTheme.headlineSmall,
        contentTextStyle: textTheme.bodyMedium,
        // The same 24 points on every side of the text and buttons.
        actionsPadding: const EdgeInsets.fromLTRB(
          AppSpacing.xxl,
          0,
          AppSpacing.xxl,
          AppSpacing.xxl,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.dialog),
          side: const BorderSide(color: AppColors.glassBorder),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppPalette.surface,
        surfaceTintColor: Colors.transparent,
        modalBarrierColor: Color.fromRGBO(0, 0, 0, .6),
        dragHandleColor: AppColors.glassBorderStrong,
        elevation: 16,
        clipBehavior: Clip.antiAlias,
        showDragHandle: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadii.sheet),
          ),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.transparent,
        indicatorColor: AppColors.glassSelected,
        surfaceTintColor: Colors.transparent,
        height: 68,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 22,
            color: states.contains(WidgetState.selected)
                ? AppColors.text
                : AppColors.tabInactive,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => AppType.tab.copyWith(
            color: states.contains(WidgetState.selected)
                ? AppColors.text
                : AppColors.tabInactive,
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.glass,
        selectedColor: AppPalette.pearl,
        secondarySelectedColor: AppPalette.pearl,
        labelStyle: textTheme.labelLarge?.copyWith(fontSize: 14),
        secondaryLabelStyle: textTheme.labelLarge?.copyWith(
          fontSize: 14,
          color: AppPalette.onAccent,
        ),
        checkmarkColor: AppPalette.onAccent,
        side: const BorderSide(color: AppColors.glassBorder),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        shape: pill,
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: AppColors.text,
        unselectedLabelColor: AppColors.tabInactive,
        indicatorColor: AppPalette.pearl,
        dividerColor: AppColors.glassBorder,
        labelStyle: textTheme.labelLarge,
        unselectedLabelStyle: textTheme.labelLarge,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: AppPalette.graphite,
          borderRadius: BorderRadius.circular(AppRadii.sm),
          border: Border.all(color: AppColors.glassBorder),
        ),
        textStyle: textTheme.bodySmall?.copyWith(color: AppColors.text),
      ),
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: AppPalette.pearl,
        selectionColor: AppColors.glassSelected,
        selectionHandleColor: AppPalette.pearl,
      ),
      inputDecorationTheme: InputDecorationTheme(
        floatingLabelBehavior: FloatingLabelBehavior.always,
        errorMaxLines: 4,
        helperMaxLines: 4,
        filled: true,
        fillColor: AppColors.glass,
        labelStyle: textTheme.bodyMedium?.copyWith(color: AppColors.textMuted),
        floatingLabelStyle: textTheme.bodyStrong(AppColors.label),
        hintStyle: textTheme.bodyMedium?.copyWith(color: AppColors.textSubtle),
        helperStyle: textTheme.bodySmall,
        errorStyle: textTheme.bodySmall?.copyWith(color: AppColors.danger),
        prefixIconColor: AppColors.textMuted,
        suffixIconColor: AppColors.textMuted,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.lg,
        ),
        border: field(AppColors.glassBorder),
        enabledBorder: field(AppColors.glassBorder),
        disabledBorder: field(AppColors.glass),
        focusedBorder: field(AppPalette.pearl, 1.5),
        errorBorder: field(AppColors.danger),
        focusedErrorBorder: field(AppColors.danger, 1.5),
      ),
    );
  }
}

extension on TextTheme {
  TextStyle? bodyStrong(Color color) =>
      labelLarge?.copyWith(color: color, fontSize: 15);
}
