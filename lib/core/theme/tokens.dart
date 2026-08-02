import 'package:flutter/material.dart';

import '../../domain/enums.dart';
import '../../domain/muscle_volume.dart';

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
    required this.warning,
    required this.warningMuted,
    required this.positive,
    required this.negative,
    required this.data,
    required this.info,
    required this.series,
    required this.identity,
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

  /// Deload identity. Orange, and the only hue in the cycle model — a light
  /// week has to be legible at a glance on the heatmap and in history.
  ///
  /// It was amber, which sat one notch from the yellow in `series[]` and the
  /// yellow identity mark; orange separates the one state the cycle model has
  /// from the palette information is drawn from.
  final Color deload;
  final Color deloadMuted;

  /// A rule the app is stating: a limit reached, a consequence worth reading
  /// before you act. Yellow, and its own token rather than a second use of
  /// [deload] — a light week and a refused action are different facts, and a
  /// token shared between them means neither can be retuned without moving the
  /// other. [warningMuted] is the ground it sits on.
  final Color warning;
  final Color warningMuted;

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

  /// A day you did not train, and the empty part of a volume bar's track.
  ///
  /// **The same grey as [surfaceHighest], on purpose**, and kept as its own name
  /// because it is its own job: the heatmap grid and the muscle bars sit one
  /// above the other on the landing screen and are read as one answer, so a
  /// rest day and an untrained muscle have to be the same absence. Two greys
  /// eight points apart there say they are not.
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

  /// The six hues, named once, and **the same six in both themes**.
  ///
  /// Every semantic colour that is not red is one of these, so a chart series,
  /// a regime's mark and the deload orange are the same tones wherever they
  /// turn up rather than near-misses chosen one screen at a time.
  ///
  /// These are back where they started, and the round trip is the useful part
  /// of the record. They were replaced by a saturated set (`#FF6535`, `#F9AC0E`
  /// …), which read as shouting; then by a set solved for equal contrast on
  /// charcoal, which fixed the evenness and turned yellow into an ochre —
  /// `#A0812B` is a number satisfying a constraint, not a yellow. Sampling the
  /// app we take the language from landed within a few points of this original
  /// six, on every hue. **A hue has to stay the hue.** Equal contrast is worth
  /// having only where it does not cost that; yellow is bright because yellow
  /// is bright.
  ///
  /// One set, both themes, for the same reason our reference does it: an
  /// identity mark is the same mark whichever theme it is drawn in, and a
  /// colour that changes with the phone's setting is a colour you learn twice.
  /// What made two sets look necessary was a **white** glyph on the fill, which
  /// these are too light to carry. The glyph is the fill's own hue taken down
  /// now (`IconTile.glyphOn`), so the fills are free to be light.
  ///
  /// The cost, stated: on a white card `yellow` is 1.4:1 and `orange` 1.9:1.
  /// They are fills and marks on the light theme, never text and never a
  /// hairline — see the note in THEME → Colour.
  ///
  /// Red has no entry: `negative` is the one signal that must never be mistaken
  /// for information, and it stays out of the palette everything else is drawn
  /// from.
  static const orange = Color(0xFFFF8B66);
  static const blue = Color(0xFF689FFA);
  static const yellow = Color(0xFFFDD35F);
  static const green = Color(0xFF5DBA86);
  static const lavender = Color(0xFFBE8CFF);
  static const cyan = Color(0xFF77D4E3);

  /// The one red, for the one thing red means — and the one place a hue is
  /// allowed to shout.
  static const red = Color(0xFFF83446);

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
    deload: orange,
    deloadMuted: Color(0xFF3A2318),
    warning: yellow,
    warningMuted: Color(0xFF3A3117),
    positive: green,
    negative: red,
    data: cyan,
    info: blue,
    series: [cyan, blue, yellow, green, lavender],
    identity: [orange, blue, yellow, green, lavender, cyan],
    // A rest day has to be visible *as a cell* on `surface` (#1F1F1F). At
    // #222222 the grid dissolved into the card and the pattern — the whole
    // point of the section — could only be read where it was filled. It was
    // #2F2F2F for that reason and is `surfaceHighest` now, which is a step
    // clearer again and the grey the app already uses for an inert fill.
    heatEmpty: Color(0xFF3A3A3A),
    // The palette's blue, not a lighter cousin of it. It used to be #6FA8F5,
    // one nudge off `info`, which is a bug waiting to be noticed.
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
    deload: orange,
    deloadMuted: Color(0xFFFBE4D6),
    warning: yellow,
    warningMuted: Color(0xFFFBEED2),
    positive: green,
    negative: red,
    data: cyan,
    info: blue,
    series: [cyan, blue, yellow, green, lavender],
    identity: [orange, blue, yellow, green, lavender, cyan],
    heatEmpty: Color(0xFFE0E0E0),
    heatOn: blue,
    shadow: Color(0x1A000000),
  );

  /// The hue a muscle region owns: the six, in `MuscleRegion` order.
  ///
  /// The same closed set the Regimes screen hands out, used here for the same
  /// reason — six fixed categories, one apiece, and the colour *is* the
  /// category. The two never share a screen (a regime's mark is on the Regimes
  /// screen and nowhere else, THEME → Colour), so nothing claims a hue means a
  /// programme. `series` will not do: it holds five, and the sixth region would
  /// wrap onto a colour already spoken for.
  Color forRegion(MuscleRegion region) =>
      identity[region.index % identity.length];

  /// The hue a *muscle* carries, which is its region's — biceps, triceps and
  /// forearms are all the colour of the arms bar they roll into, because that
  /// is the bar they are read against.
  ///
  /// Null for [MuscleGroup.other], which belongs to no region and therefore
  /// carries no colour rather than borrowing one.
  Color? forMuscle(MuscleGroup muscle) {
    final region = regionOf(muscle);
    return region == null ? null : forRegion(region);
  }

  /// The hue a regime owns, by the slot stored on its row.
  ///
  /// This replaced a hash of the regime id. A hash is stable but not unique —
  /// with six colours, two regimes collide about a third of the time — and the
  /// mark is what History and Today are scanned by. Slots are assigned on
  /// create and handed back on delete; see `Regimes.identityIndex`.
  ///
  /// The modulo is for a row that predates the column or came back from a
  /// restore written against a longer palette. It never fires in normal use.
  Color identityAt(int slot) => identity[slot.abs() % identity.length];

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
    Color? warning,
    Color? warningMuted,
    Color? positive,
    Color? negative,
    Color? data,
    Color? info,
    List<Color>? series,
    List<Color>? identity,
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
      warning: warning ?? this.warning,
      warningMuted: warningMuted ?? this.warningMuted,
      positive: positive ?? this.positive,
      negative: negative ?? this.negative,
      data: data ?? this.data,
      info: info ?? this.info,
      series: series ?? this.series,
      identity: identity ?? this.identity,
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
      warning: c(warning, other.warning),
      warningMuted: c(warningMuted, other.warningMuted),
      positive: c(positive, other.positive),
      negative: c(negative, other.negative),
      data: c(data, other.data),
      info: c(info, other.info),
      series: l(series, other.series),
      identity: l(identity, other.identity),
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
