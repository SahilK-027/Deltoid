import 'enums.dart';

/// How far back a weekly set count looks: today and the six days before it.
///
/// A rolling week rather than a calendar one, and deliberately unlike
/// `Consistency.thisWeek`, which is calendar-bound. That number answers "how am
/// I doing this week" and would be dishonest if it slid; this one answers "have
/// I trained this muscle enough lately", and lately does not reset on a Monday
/// morning. A Sunday chest session is chest volume on the following Wednesday
/// whatever the calendar says.
const volumeWindowDays = 7;

/// The six rows a volume bar list draws, and the twelve [MuscleGroup] values
/// folded into them.
///
/// The research this list exists to serve counts sets **per muscle directly
/// trained** — and the systems built on it track ten to fourteen muscles, not
/// six, because the two splits that catch under-training are biceps vs triceps
/// (both get large indirect load from rows and presses) and quads vs hamstrings
/// (the classic imbalance). Six rows is what a glance can read; twelve is what
/// is true. So six rows is what this draws, and each one **opens** onto its own
/// muscles — see [MuscleVolume.parts]. The fold is the honesty.
enum MuscleRegion { chest, back, shoulders, arms, legs, core }

extension MuscleRegionX on MuscleRegion {
  String get label => humanizeEnum(name);

  /// The muscles this row is the sum of, in [MuscleGroup] order.
  List<MuscleGroup> get parts => switch (this) {
    MuscleRegion.chest => const [MuscleGroup.chest],
    MuscleRegion.back => const [MuscleGroup.back],
    MuscleRegion.shoulders => const [MuscleGroup.shoulders],
    MuscleRegion.arms => const [
      MuscleGroup.biceps,
      MuscleGroup.triceps,
      MuscleGroup.forearms,
    ],
    MuscleRegion.legs => const [
      MuscleGroup.quads,
      MuscleGroup.hamstrings,
      MuscleGroup.glutes,
      MuscleGroup.calves,
    ],
    MuscleRegion.core => const [MuscleGroup.core],
  };

  /// True where the row is more than one muscle, and therefore has something to
  /// say when it is opened. A `Chest` row that unfolds to one line called
  /// `Chest` is a control that does nothing.
  bool get isCompound => parts.length > 1;
}

/// The region a muscle counts toward, or null for [MuscleGroup.other].
///
/// `other` is filed nowhere on purpose: it is the muscle you picked when none
/// of the twelve fit, and `Other · 4 sets` answers no question about whether
/// you have trained enough of anything.
MuscleRegion? regionOf(MuscleGroup muscle) => switch (muscle) {
  MuscleGroup.chest => MuscleRegion.chest,
  MuscleGroup.back => MuscleRegion.back,
  MuscleGroup.shoulders => MuscleRegion.shoulders,
  MuscleGroup.biceps ||
  MuscleGroup.triceps ||
  MuscleGroup.forearms => MuscleRegion.arms,
  MuscleGroup.quads ||
  MuscleGroup.hamstrings ||
  MuscleGroup.glutes ||
  MuscleGroup.calves => MuscleRegion.legs,
  MuscleGroup.core => MuscleRegion.core,
  MuscleGroup.other => null,
};

/// Whether a set counts as volume.
///
/// **Not [SetTypeX.countsForProgress]**, and the difference is deliberate.
/// That rule protects a *comparison* — it keeps everything but a top working
/// set out of e1RM and "did I beat last time", because a backoff set at 80%
/// would read as a regression. This one counts *work done*, so a backoff set
/// counts: it is a hard set against the muscle, which is the only thing a set
/// count is about.
///
/// Warmups are out for the obvious reason. Drops and rest-pause legs are out
/// because they are continuations of the set above them ([SetTypeX.isContinuation])
/// — counting them turns one set taken to failure into three.
bool countsAsVolume(SetType type) => switch (type) {
  SetType.working || SetType.amrap || SetType.backoff => true,
  SetType.warmup || SetType.drop || SetType.restPause => false,
};

/// One row of the bar list: a region, its total, and the muscles under it.
class MuscleVolume {
  const MuscleVolume({
    required this.region,
    required this.sets,
    required this.parts,
  });

  final MuscleRegion region;

  /// Hard sets against this region inside the window.
  final int sets;

  /// Every constituent muscle, in [MuscleGroup] order, zeros included — the
  /// zero is the point. A `Legs 18` row that opens onto `Hamstrings 0` is the
  /// one thing this list can say that a total cannot.
  final List<({MuscleGroup muscle, int sets})> parts;

  bool get isEmpty => sets == 0;
}

/// A week of set counts, ready to draw.
class WeeklyVolume {
  const WeeklyVolume({required this.rows, required this.windowDays});

  /// All six regions, always, in [MuscleRegion] order and never re-sorted: a
  /// list whose rows move is one you have to read rather than glance at, and a
  /// muscle you skipped has to keep its place or its absence is invisible.
  final List<MuscleVolume> rows;

  final int windowDays;

  /// The biggest row, which every bar is drawn against. Zero on an empty week.
  ///
  /// Normalised to your own maximum rather than to a target: this app has no
  /// business inventing a number of sets you are failing to hit (README →
  /// Non-goals).
  int get maxSets => rows.fold(0, (m, r) => r.sets > m ? r.sets : m);

  int get totalSets => rows.fold(0, (s, r) => s + r.sets);

  bool get isEmpty => maxSets == 0;
}

/// Folds counted sets into the six rows.
///
/// [setsByMuscle] is what the database counted — hard sets per muscle inside
/// the window. A muscle missing from the map is zero, and [MuscleGroup.other]
/// is dropped ([regionOf]).
WeeklyVolume computeWeeklyVolume({
  required Map<MuscleGroup, int> setsByMuscle,
  int windowDays = volumeWindowDays,
}) {
  return WeeklyVolume(
    windowDays: windowDays,
    rows: [
      for (final region in MuscleRegion.values)
        () {
          final parts = [
            for (final m in region.parts)
              (muscle: m, sets: setsByMuscle[m] ?? 0),
          ];
          return MuscleVolume(
            region: region,
            sets: parts.fold(0, (s, p) => s + p.sets),
            parts: parts,
          );
        }(),
    ],
  );
}
