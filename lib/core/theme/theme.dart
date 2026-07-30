import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tokens.dart';

/// Bundled in `assets/fonts/` (Inter 4.1, SIL OFL). Declared in pubspec.yaml
/// with static instances at 400/500/600 — the only weights this scale uses.
const kFontFamily = 'Inter';

/// Type scale. Numeric styles carry tabular figures so digits never reflow.
TextTheme _textTheme(DeltoidColors c) {
  TextStyle base(double size, double height, FontWeight w, Color color) =>
      TextStyle(
        fontFamily: kFontFamily,
        fontSize: size,
        height: height / size,
        fontWeight: w,
        color: color,
        letterSpacing: size >= 28 ? -0.6 : (size >= 20 ? -0.3 : 0),
      );

  return TextTheme(
    // Big numbers: cycle counters, chart readouts, timers.
    displaySmall: base(34, 40, FontWeight.w600, c.textPrimary)
        .copyWith(fontFeatures: tabular),
    // Screen titles.
    titleLarge: base(22, 28, FontWeight.w600, c.textPrimary),
    // Card headers, exercise names.
    titleMedium: base(17, 22, FontWeight.w600, c.textPrimary),
    titleSmall: base(15, 20, FontWeight.w600, c.textPrimary),
    // Body copy.
    bodyLarge: base(16, 22, FontWeight.w400, c.textPrimary),
    bodyMedium: base(15, 20, FontWeight.w400, c.textSecondary),
    bodySmall: base(13, 18, FontWeight.w400, c.textSecondary),
    // Set-row values.
    labelLarge: base(17, 22, FontWeight.w500, c.textPrimary)
        .copyWith(fontFeatures: tabular),
    labelMedium: base(13, 16, FontWeight.w500, c.textSecondary)
        .copyWith(fontFeatures: tabular),
    // Section eyebrows — uppercase, tracked out.
    labelSmall: TextStyle(
      fontFamily: kFontFamily,
      fontSize: 11,
      height: 14 / 11,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.8,
      color: c.textTertiary,
    ),
  );
}

ThemeData buildTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final c = isDark ? DeltoidColors.dark : DeltoidColors.light;
  final text = _textTheme(c);

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    // Covers the Material widgets that build styles off Typography rather than
    // off `textTheme` (dialogs, menus, tooltips, text fields).
    fontFamily: kFontFamily,
    scaffoldBackgroundColor: c.bg,
    canvasColor: c.bg,
    extensions: [c],
    textTheme: text,
    colorScheme: ColorScheme.fromSeed(
      seedColor: c.accent,
      brightness: brightness,
    ).copyWith(
      surface: c.surface,
      primary: c.accent,
      onPrimary: c.onAccent,
      error: c.negative,
      outline: c.border,
    ),
    splashFactory: InkSparkle.splashFactory,
    dividerTheme: DividerThemeData(color: c.border, thickness: 1, space: 1),
    appBarTheme: AppBarTheme(
      backgroundColor: c.bg,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: text.titleLarge,
      iconTheme: IconThemeData(color: c.textSecondary, size: 22),
      // Let the page background run edge to edge instead of sitting under
      // Android's default grey scrim.
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: c.surface,
        systemNavigationBarIconBrightness:
            isDark ? Brightness.light : Brightness.dark,
        systemNavigationBarDividerColor: c.border,
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.xl)),
      ),
      showDragHandle: true,
      dragHandleColor: c.borderStrong,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.accent,
        foregroundColor: c.onAccent,
        minimumSize: const Size.fromHeight(52),
        textStyle: text.titleMedium,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.md),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: c.textSecondary,
        textStyle: text.titleSmall,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: c.textPrimary,
        minimumSize: const Size.fromHeight(48),
        side: BorderSide(color: c.border),
        textStyle: text.titleSmall,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.md),
        ),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: c.surfaceHigh,
      contentTextStyle: text.bodyMedium?.copyWith(color: c.textPrimary),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.md),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: Colors.transparent,
      height: 64,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(
          size: 24,
          color: s.contains(WidgetState.selected) ? c.accent : c.textTertiary,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => text.labelSmall!.copyWith(
          letterSpacing: 0.2,
          color: s.contains(WidgetState.selected) ? c.accent : c.textTertiary,
        ),
      ),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      },
    ),
  );
}
