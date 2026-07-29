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
