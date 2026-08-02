/// How the number you type relates to the load actually moved.
///
/// Without this, `22.5` (one dumbbell, two of them) and `73` (a pec deck stack)
/// are the same value and every comparison downstream is meaningless.
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

enum Equipment { barbell, dumbbell, machine, cable, bodyweight, band, other }

/// The bar a movement is loaded on, and what it weighs empty.
///
/// Per exercise rather than per equipment type: curls and skullcrushers are
/// both "barbell" and are both done on the EZ bar, while the bench in the same
/// gym is an Olympic bar. A single weight for all barbells would be wrong for
/// half of them, and being wrong about the bar makes every plate on the screen
/// wrong.
///
/// [BarKind.none] is the default and means "not loaded on a bar" — machines,
/// cables, dumbbells and every bodyweight movement. It is also the right answer
/// for a barbell whose weight you have not said yet: no bar weight, no plate
/// maths, rather than plates computed off a guess.
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
        SetType.warmup => 'Warmup',
        SetType.working => 'Working',
        SetType.backoff => 'Backoff',
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

/// A skipped exercise is data, not an absence. Recording why turns a gap into
/// a pattern you can actually see.
enum SkipReason { none, failed, equipmentBusy, shortOnTime, injury, other }

extension SkipReasonX on SkipReason {
  String get label => switch (this) {
        SkipReason.none => '',
        SkipReason.failed => 'Failed',
        SkipReason.equipmentBusy => 'Equipment busy',
        SkipReason.shortOnTime => 'Short on time',
        SkipReason.injury => 'Injury / pain',
        SkipReason.other => 'Other',
      };
}

/// How many identity hues exist, and therefore how many regimes can be live at
/// once.
///
/// The mark on a regime is what History and Today are scanned by, so two
/// programmes must never wear the same one. That makes the palette a hard
/// limit rather than a wrap-around: six slots, one per live regime, handed back
/// when a regime is deleted. Kept here rather than in the theme so the
/// repository can enforce it without importing a colour.
const identitySlots = 6;
