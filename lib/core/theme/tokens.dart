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
  ///
  /// A step darker than the six hues, because these are filled shapes with a
  /// white glyph on them rather than colour on charcoal.
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

  /// The six hues, named once.
  ///
  /// Every semantic colour on the dark theme that is not red is one of these,
  /// so a chart series, a regime's mark and the deload amber are the same six
  /// tones wherever they turn up rather than six near-misses that happened to
  /// be picked one screen at a time. They are tuned for charcoal — the light
  /// theme keeps its own darker set, because a #fdd35f on white is not a
  /// colour, it is a smudge.
  ///
  /// Red has no entry: `negative` and the failure end of the effort ramp are
  /// the one signal that must never be mistaken for information, and it stays
  /// out of the palette everything else is drawn from.
  static const orange = Color(0xFFFF8B66);
  static const blue = Color(0xFF689FFA);
  static const yellow = Color(0xFFFDD35F);
  static const green = Color(0xFF5DBA86);
  static const lavender = Color(0xFFBE8CFF);
  static const cyan = Color(0xFF77D4E3);

  /// The same six, one step down, for anything that fills a shape and knocks a
  /// **white glyph** out of it — the identity tile on a regime, a session, a
  /// history row.
  ///
  /// The six above are tuned to sit *on* charcoal, where a light tone is the
  /// point. Fill a 44pt tile with one and put a white icon on top and the icon
  /// is gone: they are the brightest thing on the screen and white is barely
  /// brighter. A fifth off each keeps the hue — a regime's mark is still
  /// recognisably "the orange one" — and gives the glyph something to sit
  /// against.
  ///
  /// Kept as their own constants rather than computed with `withValues` at the
  /// call site, so the darker set is a decision written down once and not a
  /// multiplication that drifts screen by screen.
  /// A fifth off is enough for five of them. Yellow and cyan are the two the
  /// eye reads as brightest to begin with, and at a fifth they left white at
  /// 2.3:1 and 2.7:1 — a glyph you can see is there and cannot name. They go
  /// down about a third instead, which puts every mark past 3:1 against white
  /// and keeps the seven distinguishable from each other, which is the only
  /// job an identity colour has.
  static const orangeDeep = Color(0xFFCC6F52);
  static const blueDeep = Color(0xFF537FC8);
  static const yellowDeep = Color(0xFFAE8B37);
  static const greenDeep = Color(0xFF4A956B);
  static const lavenderDeep = Color(0xFF9870CC);
  static const cyanDeep = Color(0xFF4A8F9B);
  static const redDeep = Color(0xFFC82A38);

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
    deload: yellow,
    deloadMuted: Color(0xFF3A3117),
    positive: green,
    negative: Color(0xFFF83446),
    data: cyan,
    info: blue,
    series: [cyan, blue, yellow, green, lavender],
    identity: [
      redDeep,
      orangeDeep,
      yellowDeep,
      greenDeep,
      blueDeep,
      lavenderDeep,
      cyanDeep,
    ],
    effort: [
      Color(0xFFF83446),
      Color(0xFFF83446),
      orange,
      orange,
      green,
      green,
      blue,
    ],
    // A rest day has to be visible *as a cell* on `surface` (#1F1F1F). At
    // #222222 the grid dissolved into the card and the pattern — the whole
    // point of the section — could only be read where it was filled.
    heatEmpty: Color(0xFF2F2F2F),
    // The palette's blue, not a lighter cousin of it. This used to be #6FA8F5
    // precisely because `info` was a saturated #2F7BFF and a year of those is a
    // wall; the blue is light enough now to read as "on" without shouting, and
    // a token one nudge off another token is a bug waiting to be noticed.
    heatOn: blue,
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
