/// How an entered weight relates to the load actually moved.
///
/// Without this distinction, `22.5` denoting one of a pair of dumbbells and
/// `73` denoting a machine stack are the same value, and every comparison
/// downstream is meaningless.
enum LoadMode {
  /// The entered number is the whole load. Machines, cable stacks, barbells.
  total,

  /// Entered per hand/side; two are being moved. Dumbbells.
  perSide,

  /// No external load. Reps only.
  bodyweight,

  /// Bodyweight plus an optional added load (belt, dumbbell between feet).
  bodyweightPlus,
}

/// What the second number on a set counts.
///
/// A plank is `load × seconds`, not `load × reps`, and the difference is not a
/// set type: a movement is one or the other for its whole life. Held on the
/// **exercise** for the same reason [LoadMode] is — a plank is never sometimes
/// reps, and a set typed under one meaning must never be read back under the
/// other.
///
/// The `reps` column carries both. That column has always meant "the count, as
/// entered, interpreted by the exercise" the way `weight` means "the number, as
/// entered, interpreted by [LoadMode]" — so a hold's seconds live there and
/// every comparison that already worked on reps (last time's ghost, the
/// beats-previous check, prefill) works on seconds unchanged. What does *not*
/// carry over is arithmetic that assumes reps: kg × seconds is not volume, and
/// a plank has no estimated 1RM. See [scorePerformance].
enum MeasureMode {
  /// Repetitions. The default, and what almost everything is.
  reps,

  /// Seconds held. Planks, hangs, L-sits, wall sits.
  hold,
}

extension MeasureModeX on MeasureMode {
  /// For the picker on the exercise screen.
  String get label => switch (this) {
        MeasureMode.reps => 'Reps',
        MeasureMode.hold => 'Timed hold',
      };

  /// The set table's second column heading.
  String get columnLabel => switch (this) {
        MeasureMode.reps => 'Reps',
        MeasureMode.hold => 'Time',
      };

  bool get isHold => this == MeasureMode.hold;
}

/// Seconds as a clock: `0:02`, `0:24`, `2:25`.
///
/// A hold is stored as a count of seconds and displayed as a time. `145`
/// requires mental conversion, whereas `2:25` is the value the stopwatch
/// displayed when it was stopped. The two must correspond, or the log
/// contradicts the clock that produced it.
String formatClock(int seconds) {
  final m = seconds ~/ 60;
  final s = seconds % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

/// A count in the form its exercise is measured in: `8` reps, `2:25` held.
///
/// Partials ride along as a suffix — `8+3` — and never inside the count. They
/// are not reps: nothing that adds up (volume, e1RM, beating last time) may
/// read them, and printing them apart is what keeps that true everywhere the
/// number is read.
String formatCount(int? count, MeasureMode mode, {int? partial}) {
  final n = count ?? 0;
  final base = mode.isHold ? formatClock(n) : '$n';
  return (partial ?? 0) > 0 && !mode.isHold ? '$base+$partial' : base;
}

enum Equipment { barbell, dumbbell, machine, cable, bodyweight, band, other }

/// The bar a movement is loaded on, and what it weighs empty.
///
/// Per exercise rather than per equipment type: curls and skullcrushers are
/// both "barbell" and are both done on the EZ bar, while the bench in the same
/// gym is an Olympic bar. A single weight for all barbells would be wrong for
/// half of them, and being wrong about the bar makes every plate on the screen
/// wrong.
///
/// [BarKind.none] is the default and denotes a movement not loaded on a bar:
/// machines, cables, dumbbells and every bodyweight movement. It is also the
/// correct value for a barbell whose weight has not yet been specified, giving
/// no bar weight and no plate calculation rather than plates derived from an
/// assumed value.
enum BarKind { none, olympic, womens, ez, trap }

extension BarKindX on BarKind {
  /// Empty bar weight in kilograms. Storage is kg everywhere (see
  /// [WeightUnit]); the display unit converts at the edge.
  ///
  /// These are the bars in *this* gym, weighed rather than looked up: the EZ is
  /// 9kg and the women's bar 16kg, neither of which is the catalogue figure. A
  /// bar weight that is right in general and wrong here would put a number on
  /// the screen that no plate can fix.
  double? get kg => switch (this) {
        BarKind.none => null,
        BarKind.olympic => 20,
        BarKind.womens => 16,
        BarKind.ez => 9,
        BarKind.trap => 25,
      };

  String get label => switch (this) {
        BarKind.none => 'No bar',
        BarKind.olympic => 'Olympic bar',
        BarKind.womens => "Women's bar",
        BarKind.ez => 'EZ curl bar',
        BarKind.trap => 'Trap bar',
      };
}

/// Turns an enum's `name` into something fit for the UI:
/// `bodyweightPlus` → `Bodyweight plus`.
String humanizeEnum(String name) {
  final spaced = name.replaceAllMapped(
    RegExp('([a-z])([A-Z])'),
    (m) => '${m[1]} ${m[2]!.toLowerCase()}',
  );
  return spaced[0].toUpperCase() + spaced.substring(1);
}

extension EquipmentX on Equipment {
  String get label => humanizeEnum(name);
}

enum MuscleGroup {
  chest,
  back,
  shoulders,
  biceps,
  triceps,
  forearms,
  quads,
  hamstrings,
  glutes,
  calves,
  core,
  other,
}

extension MuscleGroupX on MuscleGroup {
  String get label => humanizeEnum(name);
}

/// Set classification. Keeping warmups and drop sets out of the working-set
/// pool is what makes progress math trustworthy.
enum SetType {
  warmup,
  working,
  backoff,
  drop,
  restPause,
  amrap,
}

extension SetTypeX on SetType {
  /// Only these count toward top set, e1RM and progression checks.
  bool get countsForProgress => this == SetType.working || this == SetType.amrap;

  /// Rendered indented beneath its parent set.
  bool get isContinuation => this == SetType.drop || this == SetType.restPause;

  String get label => switch (this) {
        SetType.warmup => 'Warm-up',
        SetType.working => 'Working',
        SetType.backoff => 'Back-off',
        SetType.drop => 'Drop',
        SetType.restPause => 'Rest-pause',
        SetType.amrap => 'AMRAP',
      };

  String get shortLabel => switch (this) {
        SetType.warmup => 'W',
        SetType.working => '',
        SetType.backoff => 'B',
        SetType.drop => 'D',
        SetType.restPause => 'RP',
        SetType.amrap => 'A',
      };
}

enum WorkoutStatus { planned, inProgress, completed, abandoned }

/// A skipped exercise is recorded data rather than an absence. Recording the
/// reason converts a gap in the log into an observable pattern.
enum SkipReason { none, failed, equipmentBusy, shortOnTime, injury, other }

extension SkipReasonX on SkipReason {
  String get label => switch (this) {
        SkipReason.none => '',
        SkipReason.failed => 'Failed',
        SkipReason.equipmentBusy => 'Equipment busy',
        SkipReason.shortOnTime => 'Short on time',
        SkipReason.injury => 'Injury or pain',
        SkipReason.other => 'Other',
      };
}

/// What the person is eating for over a stretch of days.
///
/// Declared, never inferred: the app does not guess a bulk from a rising line
/// ([RULES § 6](RULES.md#6-scope)). Its only reader is the reading of a chart
/// — the same eight weeks of flat strength are a stall in a bulk and a success
/// in a cut — so it carries no target, no calories and no rate to meet.
///
/// Stored by name in `phases.kind`, which carries a hand-written CHECK, so a
/// member added here and not there fails `schema_constraints_test` rather than
/// a restore.
enum PhaseKind { bulk, cut, maintenance }

/// The planned lengths the phase sheet offers, in weeks.
///
/// Held as data rather than as a free number because `phases.planned_weeks`
/// carries a CHECK naming exactly these, and a length the sheet cannot offer
/// is a row only a restore or a merge could have written. Null, open-ended,
/// is the fourth answer and is not a member.
const phasePlannedWeeks = [8, 12, 16];

/// How many identity hues exist, and therefore how many regimes can be live at
/// once.
///
/// The mark on a regime is what History and Today are scanned by, so two
/// programmes must never wear the same one. That makes the palette a hard
/// limit rather than a wrap-around: six slots, one per live regime, handed back
/// when a regime is deleted. Kept here rather than in the theme so the
/// repository can enforce it without importing a colour.
const identitySlots = 6;
