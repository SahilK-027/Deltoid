import 'package:flutter/material.dart';

/// Semantic colours. Widgets read these, never raw hex.
///
/// Exposed as a [ThemeExtension] so the same widget tree renders correctly in
/// both themes without a single `isDark` check in feature code.
@immutable
class DeltoidColors extends ThemeExtension<DeltoidColors> {
  const DeltoidColors({
    required this.bg,
    required this.surface,
    required this.surfaceHigh,
    required this.border,
    required this.borderStrong,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.accent,
    required this.onAccent,
    required this.accentMuted,
    required this.deload,
    required this.deloadMuted,
    required this.positive,
    required this.negative,
    required this.heatEmpty,
    required this.heatScale,
  });

  /// Page background — the deepest layer.
  final Color bg;

  /// Cards and grouped rows.
  final Color surface;

  /// Raised elements: sheets, the active set row, pressed states.
  final Color surfaceHigh;

  /// Hairline dividers.
  final Color border;

  /// Emphasised outlines: focused inputs, selected chips.
  final Color borderStrong;

  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;

  /// Primary action and "you beat last time" highlight.
  final Color accent;
  final Color onAccent;
  final Color accentMuted;

  /// Deload identity. Deliberately a different hue from [accent] so a deload
  /// week is legible at a glance on the heatmap.
  final Color deload;
  final Color deloadMuted;

  final Color positive;
  final Color negative;

  /// Heatmap: unworked day, then increasing intensity.
  final Color heatEmpty;
  final List<Color> heatScale;

  static const dark = DeltoidColors(
    bg: Color(0xFF0A0A0B),
    surface: Color(0xFF131316),
    surfaceHigh: Color(0xFF1C1C21),
    border: Color(0xFF26262C),
    borderStrong: Color(0xFF3A3A42),
    textPrimary: Color(0xFFF4F4F5),
    textSecondary: Color(0xFFA1A1AA),
    textTertiary: Color(0xFF6C6C76),
    accent: Color(0xFFC2F04B),
    onAccent: Color(0xFF16200A),
    accentMuted: Color(0xFF3A4718),
    deload: Color(0xFF7DA2FF),
    deloadMuted: Color(0xFF22304F),
    positive: Color(0xFF6EE7A8),
    negative: Color(0xFFF0715A),
    heatEmpty: Color(0xFF1A1A1E),
    heatScale: [
      Color(0xFF33401A),
      Color(0xFF5A7327),
      Color(0xFF8FBB34),
      Color(0xFFC2F04B),
    ],
  );

  static const light = DeltoidColors(
    bg: Color(0xFFF7F7F8),
    surface: Color(0xFFFFFFFF),
    surfaceHigh: Color(0xFFF1F1F3),
    border: Color(0xFFE3E3E7),
    borderStrong: Color(0xFFC5C5CC),
    textPrimary: Color(0xFF17171A),
    textSecondary: Color(0xFF5E5E68),
    textTertiary: Color(0xFF91919B),
    accent: Color(0xFF4C6B0F),
    onAccent: Color(0xFFF7FFE8),
    accentMuted: Color(0xFFDCF0AE),
    deload: Color(0xFF2C5BD1),
    deloadMuted: Color(0xFFD9E3FC),
    positive: Color(0xFF17795A),
    negative: Color(0xFFC0392B),
    heatEmpty: Color(0xFFEAEAEE),
    heatScale: [
      Color(0xFFDCF0AE),
      Color(0xFFB3D96B),
      Color(0xFF7DA82F),
      Color(0xFF4C6B0F),
    ],
  );

  @override
  DeltoidColors copyWith({
    Color? bg,
    Color? surface,
    Color? surfaceHigh,
    Color? border,
    Color? borderStrong,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? accent,
    Color? onAccent,
    Color? accentMuted,
    Color? deload,
    Color? deloadMuted,
    Color? positive,
    Color? negative,
    Color? heatEmpty,
    List<Color>? heatScale,
  }) {
    return DeltoidColors(
      bg: bg ?? this.bg,
      surface: surface ?? this.surface,
      surfaceHigh: surfaceHigh ?? this.surfaceHigh,
      border: border ?? this.border,
      borderStrong: borderStrong ?? this.borderStrong,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      accent: accent ?? this.accent,
      onAccent: onAccent ?? this.onAccent,
      accentMuted: accentMuted ?? this.accentMuted,
      deload: deload ?? this.deload,
      deloadMuted: deloadMuted ?? this.deloadMuted,
      positive: positive ?? this.positive,
      negative: negative ?? this.negative,
      heatEmpty: heatEmpty ?? this.heatEmpty,
      heatScale: heatScale ?? this.heatScale,
    );
  }

  @override
  DeltoidColors lerp(ThemeExtension<DeltoidColors>? other, double t) {
    if (other is! DeltoidColors) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return DeltoidColors(
      bg: c(bg, other.bg),
      surface: c(surface, other.surface),
      surfaceHigh: c(surfaceHigh, other.surfaceHigh),
      border: c(border, other.border),
      borderStrong: c(borderStrong, other.borderStrong),
      textPrimary: c(textPrimary, other.textPrimary),
      textSecondary: c(textSecondary, other.textSecondary),
      textTertiary: c(textTertiary, other.textTertiary),
      accent: c(accent, other.accent),
      onAccent: c(onAccent, other.onAccent),
      accentMuted: c(accentMuted, other.accentMuted),
      deload: c(deload, other.deload),
      deloadMuted: c(deloadMuted, other.deloadMuted),
      positive: c(positive, other.positive),
      negative: c(negative, other.negative),
      heatEmpty: c(heatEmpty, other.heatEmpty),
      heatScale: [
        for (var i = 0; i < heatScale.length; i++)
          c(heatScale[i], other.heatScale[i]),
      ],
    );
  }
}

/// 4pt spacing scale. Use the named steps, not raw numbers.
abstract final class Space {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const xxl = 24.0;
  static const xxxl = 32.0;
  static const huge = 40.0;
}

abstract final class Radii {
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const pill = 999.0;
}

abstract final class Motion {
  static const fast = Duration(milliseconds: 120);
  static const base = Duration(milliseconds: 180);
  static const slow = Duration(milliseconds: 260);
  static const curve = Curves.easeOutCubic;
}

/// Tabular figures everywhere a number can change — weights, reps, dates,
/// timers. Without this, digits jitter as you type and the whole log feels
/// cheap.
const tabular = <FontFeature>[FontFeature.tabularFigures()];

extension DeltoidThemeX on BuildContext {
  DeltoidColors get c => Theme.of(this).extension<DeltoidColors>()!;
  TextTheme get t => Theme.of(this).textTheme;
}
