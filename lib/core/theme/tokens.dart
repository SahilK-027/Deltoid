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
/// * The greys are pure neutrals, with no blue tint. A charcoal ramp carrying a
///   hue reads as themed rather than as designed, and a neutral ramp leaves the
///   data colours as the only elements on screen with a colour temperature.
/// * [accent] is white, and black in the light theme. The primary action, the
///   selected chip and the active tab are all monochrome. Hue is reserved for
///   elements that carry meaning: a chart series, a record, a deload, a
///   deletion.
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
    required this.deload,
    required this.deloadMuted,
    required this.warning,
    required this.warningMuted,
    required this.positive,
    required this.negative,
    required this.seriesPrimary,
    required this.seriesSecondary,
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

  /// Inset dividers within a card, and outlined empty-state boxes. Not a card
  /// outline: cards have no border.
  final Color border;

  /// The strongest hairline: unfilled progress track, focused outline.
  final Color borderStrong;

  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;

  /// Primary action, selected chip, active tab. White here, black in light.
  final Color accent;
  final Color onAccent;

  /// Deload identity. Orange, and the only hue in the cycle model — a light
  /// week has to be legible at a glance on the heatmap and in history.
  ///
  /// Orange rather than amber, which sits one notch from the yellow in
  /// `series[]` and the yellow identity mark: this separates the one state the
  /// cycle model has from the palette information is drawn from.
  final Color deload;
  final Color deloadMuted;

  /// A rule the app is stating: a limit reached, a consequence worth reading
  /// before acting. Yellow, and its own token rather than a second use of
  /// [deload] — a light week and a refused action are different facts, and a
  /// token shared between them means neither can be retuned without moving the
  /// other. [warningMuted] is the ground it sits on.
  final Color warning;
  final Color warningMuted;

  final Color positive;
  final Color negative;

  /// The first line on a chart, and the only one when there is just one. Not
  /// [accent]: a chart is information, not an action.
  ///
  /// Named for the role rather than the category: `data` would distinguish
  /// nothing from `info` sitting next to it, since every one of these is
  /// data.
  final Color seriesPrimary;

  /// The second line, the heatmap ramp and identity tiles.
  final Color seriesSecondary;

  /// Categorical series, in order.
  final List<Color> series;

  /// Identity marks for regimes and sessions — a colour per regime, so history
  /// rows and cards can be scanned by shape rather than read.
  ///
  /// A step darker than the six hues, because these are filled shapes with a
  /// white glyph on them rather than colour on charcoal.
  final List<Color> identity;

  /// An untrained day, and the unfilled portion of a volume bar's track.
  ///
  /// Deliberately the same grey as [surfaceHighest], retained under its own
  /// name because it serves a distinct purpose. The heatmap grid and the muscle
  /// bars are positioned one above the other on the landing screen and are read
  /// together, so an untrained day and an untrained muscle must represent the
  /// same absence. Two greys eight points apart would indicate otherwise.
  final Color heatEmpty;

  /// A single tone for any trained day, whatever it contained.
  ///
  /// A four-step ramp on session count says the wrong thing twice: a day with
  /// one session — a full day's work — comes out darkest and nearly
  /// indistinguishable from a rest day, and a day with three reads as three
  /// times the achievement when it is usually just a Saturday. The grid answers
  /// "did I train", and that is a yes or a no.
  final Color heatOn;

  /// Kept for the rare surface that genuinely floats above the page (a snack
  /// bar, a dragged row). Cards, sheets and the navigation bar do not use it:
  /// depth in this application is conveyed by surface colour.
  final Color shadow;

  /// The six hues, defined once and identical in both themes.
  ///
  /// Every semantic colour that is not red is one of these, so a chart series,
  /// a regime's mark and the deload orange are the same tones wherever they
  /// turn up rather than near-misses chosen one screen at a time.
  ///
  /// Two tempting replacements are both wrong. A saturated set (`#FF6535`,
  /// `#F9AC0E` …) reads as shouting. A set solved for equal contrast on
  /// charcoal fixes the evenness and turns yellow into an ochre — `#A0812B` is
  /// a number satisfying a constraint, not a yellow. Sampling the app we take
  /// the language from lands within a few points of these, on every hue.
  /// A hue must remain recognisable as that hue. Equal contrast is worth having
  /// only where it does not compromise this.
  ///
  /// One set, both themes, for the same reason our reference does it: an
  /// identity mark is the same mark whichever theme it is drawn in, and a
  /// colour that varies with the device's theme must be learned twice.
  /// Two sets appear necessary only under a white glyph on the fill, which
  /// these are too light to carry. The glyph is the fill's own hue taken down
  /// (`IconTile.glyphOn`), so the fills are free to be light.
  ///
  /// The cost, stated: on a white card `yellow` is 1.4:1 and `orange` 1.9:1.
  /// They are fills and marks on the light theme, never text and never a
  /// hairline — see the note in THEME → Colour.
  ///
  /// Red has no entry: `negative` is the one signal that must never be mistaken
  /// for information, and it stays out of the palette everything else is drawn
  /// from.
  static const orange = Color(0xFFFF8660);
  static const blue = Color(0xFF689FFA);
  static const yellow = Color(0xFFFFD15E);
  static const green = Color(0xFF5DBA86);
  static const lavender = Color(0xFFB28DF7);
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
    deload: orange,
    deloadMuted: Color(0xFF3A2318),
    warning: yellow,
    warningMuted: Color(0xFF3A3117),
    positive: green,
    negative: red,
    seriesPrimary: cyan,
    seriesSecondary: blue,
    series: [cyan, blue, yellow, green, lavender],
    identity: [orange, blue, yellow, green, lavender, cyan],
    // A rest day has to be visible *as a cell* on `surface` (#1F1F1F). At
    // #222222 the grid dissolves into the card and the pattern — the whole
    // point of the section — can only be read where it is filled.
    // `surfaceHighest` clears that, and is the grey the app already uses for an
    // inert fill.
    heatEmpty: Color(0xFF3A3A3A),
    // The palette's blue, not a lighter cousin of it: something like #6FA8F5,
    // one nudge off `info`, is a bug waiting to be noticed.
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
    deload: orange,
    deloadMuted: Color(0xFFFBE4D6),
    warning: yellow,
    warningMuted: Color(0xFFFBEED2),
    positive: green,
    negative: red,
    seriesPrimary: cyan,
    seriesSecondary: blue,
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
  /// A stored slot rather than a hash of the regime id: a hash is stable but
  /// not unique — with six colours, two regimes collide about a third of the
  /// time — and the mark is what History and Today are scanned by. Slots are
  /// assigned on create and handed back on delete; see
  /// `Regimes.identityIndex`.
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
    Color? deload,
    Color? deloadMuted,
    Color? warning,
    Color? warningMuted,
    Color? positive,
    Color? negative,
    Color? seriesPrimary,
    Color? seriesSecondary,
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
      deload: deload ?? this.deload,
      deloadMuted: deloadMuted ?? this.deloadMuted,
      warning: warning ?? this.warning,
      warningMuted: warningMuted ?? this.warningMuted,
      positive: positive ?? this.positive,
      negative: negative ?? this.negative,
      seriesPrimary: seriesPrimary ?? this.seriesPrimary,
      seriesSecondary: seriesSecondary ?? this.seriesSecondary,
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
      deload: c(deload, other.deload),
      deloadMuted: c(deloadMuted, other.deloadMuted),
      warning: c(warning, other.warning),
      warningMuted: c(warningMuted, other.warningMuted),
      positive: c(positive, other.positive),
      negative: c(negative, other.negative),
      seriesPrimary: c(seriesPrimary, other.seriesPrimary),
      seriesSecondary: c(seriesSecondary, other.seriesSecondary),
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
  /// it is the only thing separating them, cards having no borders.
  static const section = 28.0;
}

/// Corner radii, named for the component that carries them rather than by
/// size.
///
/// Not `xs … xxl`, the ladder [Space] uses, because the two scales are not the
/// same numbers: `Space.md` is 12 against a 14 radius, `Space.lg` is 16 against
/// an 18. Two scales sharing one set of suffixes in one file is a trap — it
/// invites pairing `Space.md` padding with a `md` corner on the assumption they
/// were drawn together.
/// The heights and glyph sizes a control is built from.
///
/// Named once rather than left as literals at each control, which is the same
/// decision made four times over. A button is 54 tall because that is the
/// height a thumb aims at; the compact one is 46 because it sits in a row with
/// something else; a glyph beside `titleMedium` is 20.
abstract final class Sizes {
  /// A full-width button, and anything that has to line up beside one.
  static const control = 54.0;

  /// The same button where it shares a row: a sheet's footer, a header action.
  static const controlCompact = 46.0;

  /// A glyph inside a control, beside a `titleMedium` label.
  static const glyph = 20.0;
}

abstract final class Radii {
  /// Small marks: a checkbox, a done square, the delete chip on a set row.
  static const mark = 6.0;

  /// Table cells, keypad keys, rail tiles — a control inside a control.
  static const cell = 10.0;

  /// Buttons and input fields (THEME → Space, radius).
  static const control = 14.0;

  /// A panel that holds a message: the notice, the empty box, illustrations.
  static const panel = 18.0;

  /// Cards.
  static const card = 20.0;

  /// Sheets, dialogs and the day picker — anything that arrives over the page.
  static const sheet = 24.0;

  /// Chips and pills. Large enough that the height decides the shape.
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
  ///
  /// Named for what it does, not for a spring: nothing here is physical, and a
  /// name promising simulated motion is one someone reaches for expecting mass
  /// and damping to come with it.
  static const overshoot = Curves.easeOutBack;
}

/// Tabular figures everywhere a number can change — weights, reps, dates,
/// timers. Without this, digits shift horizontally during entry.
const tabular = <FontFeature>[FontFeature.tabularFigures()];

extension DeltoidThemeX on BuildContext {
  DeltoidColors get c => Theme.of(this).extension<DeltoidColors>()!;
  TextTheme get t => Theme.of(this).textTheme;
}
