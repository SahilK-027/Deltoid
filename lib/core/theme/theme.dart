import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tokens.dart';

/// Bundled in `assets/fonts/` (Inter 4.1, SIL OFL). Declared in pubspec.yaml
/// with static instances at 400/500/600/700/800.
const kFontFamily = 'Inter';

/// The type scale from THEME.md §3. Nine roles, and a screen uses a handful.
///
/// Nothing is larger than [TextTheme.displayLarge] (27, the page title) or
/// smaller than [TextTheme.labelSmall] (11, nav labels and units). Sizes below
/// 11 are unreadable at arm's length in a gym; sizes above 27 turn a utility
/// screen into a poster.
///
/// | role in THEME.md | slot here |
/// | --- | --- |
/// | pageTitle | `displayLarge` |
/// | pageEyebrow | `labelMedium` |
/// | section | `headlineSmall` |
/// | title | `titleMedium` |
/// | body | `bodyMedium` |
/// | value | `displaySmall` |
/// | valueSm | `labelLarge` |
/// | label | `bodySmall` |
/// | micro | `labelSmall` |
TextTheme _textTheme(DeltoidColors c) {
  TextStyle f(
    double size,
    double height,
    FontWeight weight,
    Color color, {
    double tracking = 0,
    bool figures = false,
  }) =>
      TextStyle(
        fontFamily: kFontFamily,
        fontSize: size,
        height: height / size,
        fontWeight: weight,
        color: color,
        letterSpacing: tracking,
        fontFeatures: figures ? tabular : null,
      );

  return TextTheme(
    // pageTitle — uppercased by the widget, never by the caller's string.
    displayLarge:
        f(27, 32, FontWeight.w800, c.textPrimary, tracking: -0.5),
    // Reserved for the rare full-screen number (a finished-session summary).
    displayMedium:
        f(24, 30, FontWeight.w700, c.textPrimary, tracking: -0.4, figures: true),
    // value — the number a card is about.
    displaySmall:
        f(22, 26, FontWeight.w700, c.textPrimary, tracking: -0.3, figures: true),
    // section — headings on the page background.
    headlineSmall: f(20, 26, FontWeight.w700, c.textPrimary, tracking: -0.3),
    // App bar titles.
    titleLarge: f(18, 24, FontWeight.w600, c.textPrimary, tracking: -0.2),
    // title — card titles, row titles, exercise names.
    titleMedium: f(16, 22, FontWeight.w600, c.textPrimary, tracking: -0.1),
    titleSmall: f(15, 20, FontWeight.w600, c.textPrimary),
    // Body copy that carries weight (a sheet's explanation).
    bodyLarge: f(15, 22, FontWeight.w400, c.textPrimary),
    // body — subtitles, descriptions, captions.
    bodyMedium: f(14, 20, FontWeight.w400, c.textSecondary),
    // label — table headers, chip labels, axis labels.
    bodySmall: f(13, 16, FontWeight.w500, c.textSecondary),
    // valueSm — set-row fields, inline stats.
    labelLarge: f(16, 20, FontWeight.w600, c.textPrimary, figures: true),
    // pageEyebrow — the date above a page title.
    labelMedium: f(13, 16, FontWeight.w600, c.textSecondary, tracking: 1.2),
    // micro — nav labels, units, badge text.
    labelSmall: f(11, 14, FontWeight.w600, c.textSecondary, tracking: 0.2),
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
      seedColor: c.info,
      brightness: brightness,
    ).copyWith(
      surface: c.surface,
      onSurface: c.textPrimary,
      surfaceContainerHighest: c.surfaceHigh,
      primary: c.accent,
      onPrimary: c.onAccent,
      secondary: c.data,
      error: c.negative,
      outline: c.border,
      outlineVariant: c.border,
      shadow: c.shadow,
    ),
    // No ink. Every pressable surface scales and dims instead (`Pressable`),
    // which is one press language rather than two.
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    splashColor: Colors.transparent,
    dividerTheme: DividerThemeData(color: c.border, thickness: 1, space: 1),
    iconTheme: IconThemeData(color: c.textPrimary, size: 20),
    appBarTheme: AppBarTheme(
      backgroundColor: c.surface,
      foregroundColor: c.textPrimary,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      // Centred, with the back arrow on the left — the reference pattern, and
      // it keeps a long screen title from colliding with trailing actions.
      centerTitle: true,
      titleTextStyle: text.titleLarge,
      iconTheme: IconThemeData(color: c.textPrimary, size: 22),
      actionsIconTheme: IconThemeData(color: c.textPrimary, size: 22),
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness:
            isDark ? Brightness.light : Brightness.dark,
        systemNavigationBarDividerColor: Colors.transparent,
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      modalBarrierColor: Colors.black.withValues(alpha: isDark ? 0.66 : 0.38),
      elevation: 0,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.xxl)),
      ),
      showDragHandle: true,
      dragHandleColor: c.surfaceHighest,
      dragHandleSize: const Size(36, 4),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.xxl),
      ),
      titleTextStyle: text.headlineSmall,
      contentTextStyle: text.bodyLarge?.copyWith(color: c.textSecondary),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.accent,
        foregroundColor: c.onAccent,
        disabledBackgroundColor: c.surfaceHigh,
        disabledForegroundColor: c.textTertiary,
        minimumSize: const Size.fromHeight(54),
        textStyle: text.titleMedium,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.md),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: c.textPrimary,
        textStyle: text.titleMedium,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.sm),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: c.textPrimary,
        backgroundColor: c.surfaceHigh,
        minimumSize: const Size.fromHeight(54),
        side: BorderSide.none,
        textStyle: text.titleMedium,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.md),
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.surfaceHigh,
      hintStyle: text.bodyMedium?.copyWith(color: c.textTertiary),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: Space.lg,
        vertical: Space.md,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.md),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.md),
        borderSide: BorderSide.none,
      ),
      // A focused field loses its fill and gains a white outline — the same
      // move the set-row fields make when the keypad opens.
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.md),
        borderSide: BorderSide(color: c.accent, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.md),
        borderSide: BorderSide(color: c.negative, width: 2),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: c.surfaceHighest,
      contentTextStyle: text.bodyLarge?.copyWith(color: c.textPrimary),
      actionTextColor: c.textPrimary,
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      insetPadding: const EdgeInsets.all(Space.md),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.md),
      ),
    ),
    listTileTheme: ListTileThemeData(
      titleTextStyle: text.titleMedium,
      subtitleTextStyle: text.bodyMedium,
      iconColor: c.textPrimary,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.md),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? c.onAccent : c.textSecondary,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? c.accent : c.surfaceHighest,
      ),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? c.accent : Colors.transparent,
      ),
      checkColor: WidgetStatePropertyAll(c.onAccent),
      side: BorderSide(color: c.textSecondary, width: 2),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.xs),
      ),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? c.accent : c.textTertiary,
      ),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: c.accent,
      inactiveTrackColor: c.surfaceHighest,
      thumbColor: c.accent,
      overlayColor: c.accent.withValues(alpha: 0.10),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: c.accent,
      linearTrackColor: c.surfaceHighest,
      circularTrackColor: c.surfaceHighest,
      linearMinHeight: 3,
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: c.textPrimary,
      unselectedLabelColor: c.textSecondary,
      labelStyle: text.titleMedium,
      unselectedLabelStyle: text.titleMedium,
      indicatorColor: c.accent,
      indicatorSize: TabBarIndicatorSize.tab,
      dividerColor: c.border,
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: c.surfaceHighest,
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
      textStyle: text.bodySmall?.copyWith(color: c.textPrimary),
    ),
    // The shell draws its own bar (see `AppShell`); this only covers any
    // Material NavigationBar that slips through.
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: Colors.transparent,
      height: 62,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: CupertinoPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      },
    ),
  );
}
