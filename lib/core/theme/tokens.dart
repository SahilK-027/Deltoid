import 'package:flutter/material.dart';

/// Semantic colours. Widgets read these, never raw hex.
///
/// Exposed as a [ThemeExtension] so the same widget tree renders correctly in
/// both themes without a single `isDark` check in feature code.
///
/// See THEME.md. Two things about this palette are deliberate and easy to undo
/// by accident:
///
/// * **The greys are pure neutrals.** No blue tint. A charcoal ramp with a hue
///   in it reads as "themed"; a neutral one reads as designed, and it lets the
///   data colours be the only thing on screen with a temperature.
/// * **[accent] is white** (black in the light theme). The primary action, the
///   selected chip, the active tab — all monochrome. Hue is reserved for things
///   that *mean* something: a chart series, a record, a deload, a delete.
@immutable
class DeltoidColors extends ThemeExtension<DeltoidColors> {
  const DeltoidColors({
    required this.bg,
    required this.surfaceSunken,
    required this.surface,
    required this.surfaceHigh,
    required this.surfaceHighest,
    required this.border,
    required this.borderStrong,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.accent,
    required this.onAccent,
    required this.accentMuted,
    required this.accentSurface,
    required this.deload,
    required this.deloadMuted,
    required this.positive,
    required this.negative,
    required this.data,
    required this.info,
    required this.series,
    required this.identity,
    required this.effort,
    required this.heatEmpty,
    required this.heatOn,
    required this.shadow,
  });

  /// Page background — the deepest layer.
  final Color bg;

  /// Wells: text fields, the keypad bed, inset tracks.
  final Color surfaceSunken;

  /// Cards, app bars, nav bar, sheets, header bands. The one lifted surface.
  final Color surface;

  /// Chips, secondary buttons, circular icon buttons, input fills.
  final Color surfaceHigh;

  /// Top of the stack: focused input, pressed chip, keypad utility keys.
  final Color surfaceHighest;

  /// Inset dividers inside a card, and outlined empty-state boxes.
  /// **Not** a card outline — cards have no border.
  final Color border;

  /// The strongest hairline: unfilled progress track, focused outline.
  final Color borderStrong;

  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;

  /// Primary action, selected chip, active tab. White here, black in light.
  final Color accent;
  final Color onAccent;

  /// A grey fill that reads as "selected" without going all the way to
  /// [accent] — the track behind a segmented control, a quiet chip.
  final Color accentMuted;

  /// A whole surface nudged one step towards the foreground. Used for the one
  /// card a screen is about, in place of the tint a coloured accent used to
  /// give it.
  final Color accentSurface;

  /// Deload identity. Amber, and the only hue in the cycle model — a light week
  /// has to be legible at a glance on the heatmap and in history.
  final Color deload;
  final Color deloadMuted;

  final Color positive;
  final Color negative;

  /// Default chart series. Not [accent]: a chart is information, not an action.
  final Color data;

  /// Second series, heatmap ramp, identity tiles.
  final Color info;

  /// Categorical series, in order.
  final List<Color> series;

  /// Identity marks for regimes and sessions — a colour per regime, so history
  /// rows and cards can be scanned by shape rather than read.
  final List<Color> identity;

  /// Effort / RIR ramp, index 0..6+: red at failure, blue at "plenty left".
  final List<Color> effort;

  /// Heatmap: unworked day, then increasing intensity.
  final Color heatEmpty;

  /// One tone for a day you trained, whatever it held.
  ///
  /// It was a four-step ramp on session count, which said the wrong thing
  /// twice: a day with one session — a full day's work — came out darkest and
  /// nearly indistinguishable from a rest day, and a day with three read as
  /// three times the achievement when it is usually just a Saturday. The grid
  /// answers "did I train", and that is a yes or a no.
  final Color heatOn;

  /// Kept for the rare surface that genuinely floats above the page (a snack
  /// bar, a dragged row). Cards, sheets and the nav bar do **not** use it:
  /// depth in this app is surface colour.
  final Color shadow;

  static const dark = DeltoidColors(
    bg: Color(0xFF131313),
    surfaceSunken: Color(0xFF0D0D0D),
    surface: Color(0xFF1F1F1F),
    surfaceHigh: Color(0xFF2B2B2B),
    surfaceHighest: Color(0xFF3A3A3A),
    border: Color(0xFF2E2E2E),
    borderStrong: Color(0xFF4A4A4A),
    textPrimary: Color(0xFFFFFFFF),
    textSecondary: Color(0xFF9A9A9A),
    textTertiary: Color(0xFF6E6E6E),
    accent: Color(0xFFFFFFFF),
    onAccent: Color(0xFF121212),
    accentMuted: Color(0xFF2B2B2B),
    accentSurface: Color(0xFF242424),
    deload: Color(0xFFFFD15E),
    deloadMuted: Color(0xFF3A3117),
    positive: Color(0xFF5DBA87),
    negative: Color(0xFFF83446),
    data: Color(0xFF5EC8D8),
    info: Color(0xFF2F7BFF),
    series: [
      Color(0xFF5EC8D8),
      Color(0xFF2F7BFF),
      Color(0xFFFFD15E),
      Color(0xFF5DBA87),
      Color(0xFFB98CFF),
    ],
    identity: [
      Color(0xFFF83446),
      Color(0xFFFF7A45),
      Color(0xFFFFC53D),
      Color(0xFF5DBA87),
      Color(0xFF2F7BFF),
      Color(0xFF9254DE),
      Color(0xFF13A8A8),
    ],
    effort: [
      Color(0xFFF83446),
      Color(0xFFF83446),
      Color(0xFFFFAA33),
      Color(0xFFFFAA33),
      Color(0xFF5DBA87),
      Color(0xFF5DBA87),
      Color(0xFF2F7BFF),
    ],
    // A rest day has to be visible *as a cell* on `surface` (#1F1F1F). At
    // #222222 the grid dissolved into the card and the pattern — the whole
    // point of the section — could only be read where it was filled.
    heatEmpty: Color(0xFF2F2F2F),
    // Light, not saturated: a year of these is most of the screen, and a wall
    // of full-strength `info` blue is a wall. This reads as "on" against the
    // rest days without shouting.
    heatOn: Color(0xFF6FA8F5),
    shadow: Color(0x66000000),
  );

  static const light = DeltoidColors(
    bg: Color(0xFFF4F4F4),
    surfaceSunken: Color(0xFFE8E8E8),
    surface: Color(0xFFFFFFFF),
    surfaceHigh: Color(0xFFEDEDED),
    surfaceHighest: Color(0xFFE0E0E0),
    border: Color(0xFFE4E4E4),
    borderStrong: Color(0xFFC4C4C4),
    textPrimary: Color(0xFF111111),
    textSecondary: Color(0xFF5F5F5F),
    textTertiary: Color(0xFF8C8C8C),
    accent: Color(0xFF111111),
    onAccent: Color(0xFFFFFFFF),
    accentMuted: Color(0xFFE0E0E0),
    accentSurface: Color(0xFFF7F7F7),
    deload: Color(0xFFB07206),
    deloadMuted: Color(0xFFFBEED2),
    positive: Color(0xFF12855F),
    negative: Color(0xFFC33A2E),
    data: Color(0xFF0E8FA6),
    info: Color(0xFF2563EB),
    series: [
      Color(0xFF0E8FA6),
      Color(0xFF2563EB),
      Color(0xFFB07206),
      Color(0xFF12855F),
      Color(0xFF7C4DD1),
    ],
    identity: [
      Color(0xFFD32F3D),
      Color(0xFFDD6B20),
      Color(0xFFB07206),
      Color(0xFF12855F),
      Color(0xFF2563EB),
      Color(0xFF7C4DD1),
      Color(0xFF0E8FA6),
    ],
    effort: [
      Color(0xFFC33A2E),
      Color(0xFFC33A2E),
      Color(0xFFB07206),
      Color(0xFFB07206),
      Color(0xFF12855F),
      Color(0xFF12855F),
      Color(0xFF2563EB),
    ],
    heatEmpty: Color(0xFFE7E7E7),
    heatOn: Color(0xFF3B7BE0),
    shadow: Color(0x1A000000),
  );

  /// The identity colour for a stable string (a regime id). Deterministic, so a
  /// regime keeps its mark across launches without storing anything.
  Color identityFor(String seed) {
    var hash = 0;
    for (final unit in seed.codeUnits) {
      hash = (hash * 31 + unit) & 0x7FFFFFFF;
    }
    return identity[hash % identity.length];
  }

  /// Colour for a reps-in-reserve rating. Null (unrated) stays neutral.
  Color effortFor(int? rir) {
    if (rir == null) return surfaceHighest;
    return effort[rir.clamp(0, effort.length - 1)];
  }

  @override
  DeltoidColors copyWith({
    Color? bg,
    Color? surfaceSunken,
    Color? surface,
    Color? surfaceHigh,
    Color? surfaceHighest,
    Color? border,
    Color? borderStrong,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? accent,
    Color? onAccent,
    Color? accentMuted,
    Color? accentSurface,
    Color? deload,
    Color? deloadMuted,
    Color? positive,
    Color? negative,
    Color? data,
    Color? info,
    List<Color>? series,
    List<Color>? identity,
    List<Color>? effort,
    Color? heatEmpty,
    Color? heatOn,
    Color? shadow,
  }) {
    return DeltoidColors(
      bg: bg ?? this.bg,
      surfaceSunken: surfaceSunken ?? this.surfaceSunken,
      surface: surface ?? this.surface,
      surfaceHigh: surfaceHigh ?? this.surfaceHigh,
      surfaceHighest: surfaceHighest ?? this.surfaceHighest,
      border: border ?? this.border,
      borderStrong: borderStrong ?? this.borderStrong,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      accent: accent ?? this.accent,
      onAccent: onAccent ?? this.onAccent,
      accentMuted: accentMuted ?? this.accentMuted,
      accentSurface: accentSurface ?? this.accentSurface,
      deload: deload ?? this.deload,
      deloadMuted: deloadMuted ?? this.deloadMuted,
      positive: positive ?? this.positive,
      negative: negative ?? this.negative,
      data: data ?? this.data,
      info: info ?? this.info,
      series: series ?? this.series,
      identity: identity ?? this.identity,
      effort: effort ?? this.effort,
      heatEmpty: heatEmpty ?? this.heatEmpty,
      heatOn: heatOn ?? this.heatOn,
      shadow: shadow ?? this.shadow,
    );
  }

  @override
  DeltoidColors lerp(ThemeExtension<DeltoidColors>? other, double t) {
    if (other is! DeltoidColors) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    List<Color> l(List<Color> a, List<Color> b) => [
          for (var i = 0; i < a.length; i++) c(a[i], b[i]),
        ];
    return DeltoidColors(
      bg: c(bg, other.bg),
      surfaceSunken: c(surfaceSunken, other.surfaceSunken),
      surface: c(surface, other.surface),
      surfaceHigh: c(surfaceHigh, other.surfaceHigh),
      surfaceHighest: c(surfaceHighest, other.surfaceHighest),
      border: c(border, other.border),
      borderStrong: c(borderStrong, other.borderStrong),
      textPrimary: c(textPrimary, other.textPrimary),
      textSecondary: c(textSecondary, other.textSecondary),
      textTertiary: c(textTertiary, other.textTertiary),
      accent: c(accent, other.accent),
      onAccent: c(onAccent, other.onAccent),
      accentMuted: c(accentMuted, other.accentMuted),
      accentSurface: c(accentSurface, other.accentSurface),
      deload: c(deload, other.deload),
      deloadMuted: c(deloadMuted, other.deloadMuted),
      positive: c(positive, other.positive),
      negative: c(negative, other.negative),
      data: c(data, other.data),
      info: c(info, other.info),
      series: l(series, other.series),
      identity: l(identity, other.identity),
      effort: l(effort, other.effort),
      heatEmpty: c(heatEmpty, other.heatEmpty),
      heatOn: c(heatOn, other.heatOn),
      shadow: c(shadow, other.shadow),
    );
  }
}

/// 4pt spacing scale. Use the named steps, not raw numbers.
abstract final class Space {
  static const xxs = 2.0;
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const xxl = 24.0;
  static const xxxl = 32.0;
  static const huge = 40.0;

  /// The page gutter. Every screen's horizontal padding comes from here, so the
  /// left edge of a title lines up with the left edge of a card on every tab.
  static const gutter = 16.0;

  /// Between one section and the next. Sections are far apart on purpose —
  /// it is the only thing separating them, now that cards have no borders.
  static const section = 28.0;
}

abstract final class Radii {
  static const xs = 6.0;
  static const sm = 10.0;
  static const md = 14.0;
  static const lg = 18.0;
  static const xl = 20.0;
  static const xxl = 24.0;
  static const pill = 999.0;
}

abstract final class Motion {
  static const fast = Duration(milliseconds: 140);
  static const base = Duration(milliseconds: 220);
  static const slow = Duration(milliseconds: 340);

  /// Default easing: leaves fast, settles slowly.
  static const curve = Curves.easeOutCubic;

  /// For things that travel a distance — sheets, page pushes, a tab indicator.
  static const emphasized = Curves.easeOutQuint;

  /// Presses and toggles, where a hint of overshoot reads as responsive.
  static const spring = Curves.easeOutBack;
}

/// Tabular figures everywhere a number can change — weights, reps, dates,
/// timers. Without this, digits jitter as you type and the whole log feels
/// cheap.
const tabular = <FontFeature>[FontFeature.tabularFigures()];

extension DeltoidThemeX on BuildContext {
  DeltoidColors get c => Theme.of(this).extension<DeltoidColors>()!;
  TextTheme get t => Theme.of(this).textTheme;
}
