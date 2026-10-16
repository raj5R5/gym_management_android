import 'package:flutter/material.dart';
import 'design_tokens.dart';

abstract final class AppTheme {
  static final light = _build(Brightness.light);
  static final dark = _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final surfaces = AppSurfaces.forBrightness(brightness);
    final scheme =
        ColorScheme.fromSeed(
          seedColor: AppPalette.ember,
          brightness: brightness,
        ).copyWith(
          primary: dark ? AppPalette.darkEmber : AppPalette.ember,
          onPrimary: dark ? const Color(0xFF29150E) : AppPalette.surface,
          primaryContainer: dark ? const Color(0xFF3A2824) : AppPalette.peach,
          onPrimaryContainer: dark ? AppPalette.darkEmber : AppPalette.ember,
          secondary: dark ? const Color(0xFFA8C9FA) : const Color(0xFF355E9B),
          secondaryContainer: surfaces.accent(AppTone.member),
          onSecondaryContainer: surfaces.onAccent(AppTone.member),
          tertiary: dark ? AppPalette.darkMintInk : AppPalette.mintInk,
          onTertiary: dark ? AppPalette.carbon : AppPalette.surface,
          tertiaryContainer: surfaces.active,
          onTertiaryContainer: surfaces.onAccent(AppTone.positive),
          error: dark ? const Color(0xFFFFA9B5) : const Color(0xFFB42335),
          onError: dark ? AppPalette.carbon : AppPalette.surface,
          errorContainer: dark
              ? const Color(0xFF42252C)
              : const Color(0xFFFCE9ED),
          onErrorContainer: dark
              ? const Color(0xFFFFA9B5)
              : const Color(0xFFB42335),
          surface: dark ? AppPalette.darkSurface : AppPalette.surface,
          surfaceContainerLowest: dark
              ? AppPalette.darkCanvas
              : AppPalette.surface,
          surfaceContainerLow: dark
              ? AppPalette.darkSurface
              : AppPalette.canvas,
          surfaceContainer: dark ? AppPalette.darkSurface : AppPalette.raised,
          surfaceContainerHigh: dark
              ? AppPalette.darkRaised
              : AppPalette.raised,
          surfaceContainerHighest: dark
              ? AppPalette.darkGrey
              : AppPalette.mutedGrey,
          onSurface: dark ? AppPalette.heroInk : AppPalette.carbon,
          onSurfaceVariant: dark
              ? const Color(0xFFADB6C4)
              : const Color(0xFF5C6470),
          outline: dark ? const Color(0xFF8090A5) : const Color(0xFF77818D),
          outlineVariant: surfaces.border,
        );
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: 'Inter',
      scaffoldBackgroundColor: surfaces.canvasStart,
      extensions: [surfaces],
    );
    return base.copyWith(
      textTheme: base.textTheme.copyWith(
        displaySmall: base.textTheme.displaySmall?.copyWith(
          fontFamily: 'SpaceGrotesk',
          fontWeight: FontWeight.w600,
          letterSpacing: -1.2,
        ),
        headlineLarge: base.textTheme.headlineLarge?.copyWith(
          fontFamily: 'SpaceGrotesk',
          fontWeight: FontWeight.w600,
          letterSpacing: -1,
        ),
        headlineSmall: base.textTheme.headlineSmall?.copyWith(
          fontFamily: 'SpaceGrotesk',
          fontWeight: FontWeight.w600,
          letterSpacing: -.6,
        ),
        headlineMedium: base.textTheme.headlineMedium?.copyWith(
          fontFamily: 'SpaceGrotesk',
          fontWeight: FontWeight.w700,
          letterSpacing: -.7,
        ),
        titleLarge: base.textTheme.titleLarge?.copyWith(
          fontFamily: 'SpaceGrotesk',
          fontWeight: FontWeight.w600,
          letterSpacing: -.3,
        ),
        titleMedium: base.textTheme.titleMedium?.copyWith(
          fontFamily: 'SpaceGrotesk',
          fontWeight: FontWeight.w600,
        ),
        bodyMedium: base.textTheme.bodyMedium?.copyWith(height: 1.45),
        bodySmall: base.textTheme.bodySmall?.copyWith(height: 1.4),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleTextStyle: base.textTheme.titleLarge?.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        extendedTextStyle: base.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        iconColor: scheme.primary,
        selectedColor: scheme.primary,
        selectedTileColor: scheme.primaryContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      dividerTheme: DividerThemeData(
        color: surfaces.border,
        thickness: 1,
        space: 24,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.primaryContainer,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shadowColor: surfaces.shadow,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.card),
          side: BorderSide(color: surfaces.border),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xl,
            vertical: AppSpacing.md,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.control),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          foregroundColor: scheme.primary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.control),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          foregroundColor: scheme.primary,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.panel),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadii.panel),
          ),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primaryContainer,
        height: 64,
        surfaceTintColor: Colors.transparent,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 22,
            color: states.contains(WidgetState.selected)
                ? scheme.primary
                : scheme.onSurfaceVariant,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => base.textTheme.labelMedium!.copyWith(
            color: states.contains(WidgetState.selected)
                ? scheme.primary
                : scheme.onSurfaceVariant,
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surface,
        selectedColor: scheme.primaryContainer,
        labelStyle: base.textTheme.labelLarge?.copyWith(
          color: scheme.onSurface,
        ),
        checkmarkColor: scheme.primary,
        side: BorderSide(color: surfaces.border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.control),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        floatingLabelBehavior: FloatingLabelBehavior.always,
        errorMaxLines: 4,
        helperMaxLines: 4,
        filled: true,
        fillColor: scheme.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.lg,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.control),
          borderSide: BorderSide(color: scheme.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.control),
          borderSide: BorderSide(color: scheme.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.control),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
      ),
    );
  }
}
