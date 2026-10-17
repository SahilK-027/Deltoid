/// How much stronger a regime has made you, cycle by cycle.
///
/// The Cycle progress card, the regime screen and the All time timeline all read
/// their numbers from here. Plain values in and plain values out, with no drift
/// row anywhere in the file, which is what makes the arithmetic testable
/// without a database (RULES § 7).
///
/// One rule governs the whole calculation: **every cycle is compared with the
/// first cycle of its own regime, and the comparison never resets.** Comparing
/// against the last deload was tried and rejected — the chart it produced fell
/// back to zero every fifth cycle and answered "am I stronger than five weeks
/// ago" rather than "has this programme worked".
library;

import 'dart:math' as math;

import '../core/ids.dart';
import 'enums.dart';
import 'metrics.dart';
import 'phases.dart';
import 'set_format.dart';

/// A lift: one exercise as it is trained in one session.
///
/// Not an exercise. Push 1 bench and Push 2 bench are two lifts carrying two
/// progressions, for the same reason prefill is scoped to the session
/// (CLAUDE.md rule 1). Collapsing them would average a heavy triple into a
/// back-off set and report neither.
class LiftId {
  const LiftId({required this.sessionId, required this.exerciseId});

  final String sessionId;
  final String exerciseId;

  @override
  bool operator ==(Object other) =>
      other is LiftId &&
      other.sessionId == sessionId &&
      other.exerciseId == exerciseId;

  @override
  int get hashCode => Object.hash(sessionId, exerciseId);

  @override
  String toString() => '$sessionId/$exerciseId';
}

/// One exercise performed once, reduced to what the score needs.
///
/// [dayKey] is carried because a bodyweight lift is only comparable across
/// months when the bodyweight of the day is part of the number; see
/// [bodyweightOnOrdered].
class LiftPerformance {
  const LiftPerformance({
    required this.lift,
    required this.dayKey,
    required this.load,
    required this.sets,
    this.measure = MeasureMode.reps,
    this.bodyweightPct = 100,
  });

  final LiftId lift;
  final int dayKey;
  final LoadMode load;
  final MeasureMode measure;

  /// How much of the bodyweight the movement moves, in per cent. Read under
  /// the two bodyweight load modes only.
  final int bodyweightPct;
  final List<ScoredSet> sets;
}

/// One cycle of one regime, with everything trained inside it.
class CycleInput {
  const CycleInput({
    required this.cycleId,
    required this.index,
    required this.performances,
    this.isDeload = false,
    this.isOpen = false,
    this.startDayKey,
    this.endDayKey,
    this.sessionDays = const [],
  });

  final String cycleId;

  /// The day of each session completed in the cycle, one entry per session,
  /// which is what the cycle's phase tint is counted over.
  final List<int> sessionDays;

  /// The regime's own cycle number, which continues across a spell on another
  /// regime rather than restarting when this one is picked up again.
  final int index;

  final bool isDeload;

  /// Whether the cycle is still being trained. Its point is real but partial,
  /// and the chart draws it hollow and dashed to say so.
  final bool isOpen;

  final int? startDayKey;
  final int? endDayKey;

  final List<LiftPerformance> performances;
}

/// A lift's strength in one cycle, against the first cycle it appeared in.
class LiftChange {
  const LiftChange({
    required this.lift,
    required this.baseline,
    required this.baselineCycleIndex,
    required this.latest,
    this.load = LoadMode.total,
    this.measure = MeasureMode.reps,
    this.baselineSet,
    this.latestSet,
  });

  final LiftId lift;

  /// The best score in the lift's first non-deload cycle.
  final double baseline;

  final int baselineCycleIndex;

  /// The best score in the cycle being reported on.
  final double latest;

  /// How the two sets below are to be read — the same pair the log was
  /// entered under, so a screen prints `22.5 kg each × 8` rather than the 45 kg
  /// the comparison was actually made on.
  final LoadMode load;
  final MeasureMode measure;

  /// The set the score came from, at each end. Null on a lift whose sets did
  /// not survive — nothing in the app produces one, and a row that cannot name
  /// the set says nothing rather than inventing it.
  final ScoredSet? baselineSet;
  final ScoredSet? latestSet;

  /// The change as a percentage of the baseline.
  double get percent => (latest / baseline - 1) * 100;

  /// The change as the screen prints it, to one decimal place.
  ///
  /// Grouping reads this rather than [percent] so that a lift 0.02 % off its
  /// baseline is filed under "No change" instead of under "Stronger" with
  /// `+0.0 %` printed beside it, which is a contradiction the reader has to
  /// resolve.
  double get rounded => (percent * 10).round() / 10;

  bool get isStronger => rounded > 0;
  bool get isWeaker => rounded < 0;
  bool get isUnchanged => rounded == 0;
}

/// One point on the cycle chart.
class CyclePoint {
  const CyclePoint({
    required this.cycleId,
    required this.index,
    required this.isDeload,
    required this.isOpen,
    required this.value,
    required this.lifts,
    this.startDayKey,
    this.endDayKey,
    this.sessions = const [],
  });

  final String cycleId;
  final int index;
  final bool isDeload;
  final bool isOpen;

  /// Each session the cycle holds so far, with the phase it ran in.
  ///
  /// Kept per session rather than as the one answer, because under `All` a
  /// block is tinted by every session of its cycles counted together.
  final List<SessionPhase> sessions;

  /// The mean change across the lifts trained in the cycle, as a percentage.
  ///
  /// Null on a deload, and null on a cycle whose lifts have no baseline yet.
  /// **A deload scores nothing rather than zero**: the weights are lighter on
  /// purpose, so a point drawn at the bottom of the chart would report a
  /// planned week as a collapse. The chart draws an orange band in its place.
  final double? value;

  /// The lifts the point was averaged over, strongest change first.
  final List<LiftChange> lifts;

  final int? startDayKey;
  final int? endDayKey;

  bool get isScored => value != null;

  /// The phase most of the cycle's sessions ran in, which tints its slot and
  /// is named in the readout. Null on a deload, which is never tinted, and on
  /// a cycle trained with no phase set.
  PhaseKind? get phase => isDeload ? null : mostCommonPhase(sessions);
}

/// The direction of the last few scored cycles, as the pill beside the figure.
enum ProgressTrend { progressing, holdingSteady, dropping }

extension ProgressTrendX on ProgressTrend {
  String get label => switch (this) {
        ProgressTrend.progressing => 'Progressing',
        ProgressTrend.holdingSteady => 'Holding steady',
        ProgressTrend.dropping => 'Dropping',
      };
}

/// How far the last scored cycle has to differ from the one three scored
/// cycles earlier before the pill calls it a direction, in percentage points.
///
/// Below this the reading is noise: one lift taken to a hard single in a good
/// week moves the mean by a few tenths on its own, and a pill that flips
/// between Progressing and Dropping on that is worse than one that says
/// nothing.
const trendThreshold = 0.5;

/// How many scored cycles back the trend looks.
const trendSpan = 3;

/// A regime's progress, computed once and read by all three surfaces.
class CycleProgress {
  const CycleProgress({
    required this.cycles,
    required this.latest,
    required this.trend,
    this.lifts = const [],
  });

  /// Every cycle in regime order, deloads included.
  final List<CyclePoint> cycles;

  /// The most recent scored cycle, open or not. Null before anything scores.
  final CyclePoint? latest;

  /// Null until two cycles have scored.
  final ProgressTrend? trend;

  /// Every lift the regime has scored, each on its most recent performance,
  /// biggest change first.
  ///
  /// Not the latest cycle's lifts, which is what the chart's last point
  /// averages. A cycle part way through holds only the sessions trained so far,
  /// and a list that emptied to two sessions' worth every Monday would answer
  /// "what did I train this week" — where the question this screen asks is what
  /// the programme has done to each lift.
  final List<LiftChange> lifts;

  bool get isEmpty => cycles.isEmpty;

  /// The percentage the card prints large.
  double? get percent => latest?.value;

  /// The lifts that beat their baseline.
  int get liftsImproved => lifts.where((l) => l.isStronger).length;

  /// How many lifts the regime has to compare.
  int get liftsCompared => lifts.length;

  /// Whether the regime is still inside the cycle everything is measured
  /// against, so there is no comparison to draw yet.
  bool get isFirstCycle =>
      cycles.where((c) => c.isScored).length < 2 && liftsCompared > 0;

  /// The cycles the chart plots when the range is All and the regime is long
  /// enough that one point per cycle is a smear: the last scored cycle before
  /// each deload, plus the most recent one.
  ///
  /// A block is what a training year is actually remembered in — a run of
  /// cycles ending in a deload — so thinning to blocks loses the week-to-week
  /// wobble and keeps the shape.
  List<CyclePoint> get blockPoints {
    final out = <CyclePoint>[];
    for (var i = 0; i < cycles.length; i++) {
      if (!cycles[i].isScored) continue;
      final isLast = i == cycles.length - 1;
      if (isLast || !cycles[i + 1].isScored) out.add(cycles[i]);
    }
    return out;
  }
}

/// The best qualifying score of one performance.
///
/// Everything about *which* sets count lives in [scorePerformance], so this is
/// deliberately thin: a second scoring path is how two screens come to disagree
/// about the same session. A hold scores its longest hold, because a plank has
/// no estimated 1RM and the whole progression is in the clock.
({double value, ScoredSet? set})? _score(
  LiftPerformance p,
  List<({int dayKey, double weightKg})> bodyweight,
) {
  final score = scorePerformance(
    sets: p.sets,
    mode: p.load,
    measure: p.measure,
    bodyweightKg: bodyweightOnOrdered(p.dayKey, bodyweight),
    bodyweightPct: p.bodyweightPct,
  );
  if (score.isEmpty) return null;

  final value = p.measure.isHold ? (score.topSetReps ?? 0).toDouble() : score.best1RM;
  if (value == null || value <= 0) return null;
  return (value: value, set: _representativeSet(p));
}

/// The set a screen names when it says what the score came from.
///
/// [heaviestLogged] does the ranking, over the pool [scorePerformance] scores —
/// working and AMRAP only. Ranking it here instead would be a second opinion on
/// a question that file already answers, and the two would disagree the first
/// time either changed.
ScoredSet? _representativeSet(LiftPerformance p) {
  final counted = [
    for (final s in p.sets)
      if (s.type.countsForProgress) s,
  ];
  final i = heaviestLogged(
    sets: [
      for (final s in counted)
        (setType: s.type, weight: s.weight, addedWeight: s.addedWeight, reps: s.reps),
    ],
    measureMode: p.measure,
    loadMode: p.load,
  );
  return i == null ? null : counted[i];
}

/// What one lift did in one cycle: the score, the set behind it, and how both
/// are to be read.
typedef _Best = ({
  double value,
  ScoredSet? set,
  LoadMode load,
  MeasureMode measure,
});

/// The best score each lift reached in [cycle].
Map<LiftId, _Best> _strengths(
  CycleInput cycle,
  List<({int dayKey, double weightKg})> bodyweight,
) {
  final out = <LiftId, _Best>{};
  for (final p in cycle.performances) {
    final s = _score(p, bodyweight);
    if (s == null) continue;
    final best = out[p.lift];
    if (best == null || s.value > best.value) {
      out[p.lift] = (
        value: s.value,
        set: s.set,
        load: p.load,
        measure: p.measure,
      );
    }
  }
  return out;
}

/// Computes a regime's progress from its cycles.
///
/// [cycles] may arrive in any order and is read in cycle-index order.
/// [bodyweightLog] need not be sorted; ordering it once here is what keeps a
/// long history of chin-ups from re-sorting the series on every set.
///
/// [rotations] maps a session to the rotation it alternates in. Where one day
/// of a rotation was trained in a cycle, the days resting are counted at their
/// most recent reading. A cycle's point is the mean of its lifts, and a regime
/// that trains Leg 1 and Leg 2 in turn would otherwise be averaged over a
/// different set of lifts every cycle: with the squat 40 per cent up and the
/// deadlift 10, the figure would swing between the two for ever, and the trend
/// would report a programme standing still as rising and falling by turns.
///
/// What is carried is what the resting day held the last time it was trained,
/// outside a deload. A movement it has since dropped is left behind with it,
/// and a light week is not brought forward as though it were the day's
/// strength. Nothing is carried into a cycle that has not trained the
/// position at all, which is a cycle part way through, and that point is
/// partial in the way every open cycle's is.
CycleProgress computeCycleProgress({
  required List<CycleInput> cycles,
  List<({int dayKey, double weightKg})> bodyweightLog = const [],
  Map<String, String> rotations = const {},
  List<PhaseSpan> phases = const [],
}) {
  if (cycles.isEmpty) {
    return const CycleProgress(cycles: [], latest: null, trend: null);
  }

  final ordered = [...cycles]..sort((a, b) => a.index.compareTo(b.index));
  final bodyweight = orderedByDay(bodyweightLog);

  // A lift's baseline is its first non-deload cycle. Taking it from a deload
  // would measure every later cycle against a week that was lighter on
  // purpose, and every regime would look like a triumph.
  final baselines = <LiftId, ({_Best best, int cycleIndex})>{};
  final strengthsByCycle = <String, Map<LiftId, _Best>>{};
  for (final c in ordered) {
    final strengths = _strengths(c, bodyweight);
    strengthsByCycle[c.cycleId] = strengths;
    if (c.isDeload) continue;
    for (final entry in strengths.entries) {
      baselines.putIfAbsent(
        entry.key,
        () => (best: entry.value, cycleIndex: c.index),
      );
    }
  }

  // What each alternating day held the last time it was trained outside a
  // deload, keyed by session. Read by the cycles after it, never by its own.
  final lastTrained = <String, Map<LiftId, _Best>>{};

  final points = <CyclePoint>[];
  for (final c in ordered) {
    final strengths = strengthsByCycle[c.cycleId]!;
    final lifts = <LiftChange>[];
    if (!c.isDeload) {
      final trained = {for (final lift in strengths.keys) lift.sessionId};
      final spent = {
        for (final session in trained) ?rotations[session],
      };
      final counted = {
        ...strengths,
        for (final resting in lastTrained.entries)
          if (!trained.contains(resting.key) &&
              spent.contains(rotations[resting.key]))
            ...resting.value,
      };

      for (final entry in counted.entries) {
        final base = baselines[entry.key];
        if (base == null || base.best.value <= 0) continue;
        lifts.add(
          LiftChange(
            lift: entry.key,
            baseline: base.best.value,
            baselineCycleIndex: base.cycleIndex,
            latest: entry.value.value,
            load: entry.value.load,
            measure: entry.value.measure,
            baselineSet: base.best.set,
            latestSet: entry.value.set,
          ),
        );
      }
      lifts.sort((a, b) => b.percent.compareTo(a.percent));

      for (final session in trained) {
        if (rotations[session] == null) continue;
        lastTrained[session] = {
          for (final entry in strengths.entries)
            if (entry.key.sessionId == session) entry.key: entry.value,
        };
      }
    }

    final value = lifts.isEmpty
        ? null
        : lifts.map((l) => l.percent).reduce((a, b) => a + b) / lifts.length;

    points.add(
      CyclePoint(
        cycleId: c.cycleId,
        index: c.index,
        isDeload: c.isDeload,
        isOpen: c.isOpen,
        value: value,
        lifts: lifts,
        startDayKey: c.startDayKey,
        endDayKey: c.endDayKey,
        sessions: sessionPhases(c.sessionDays, phases),
      ),
    );
  }

  CyclePoint? latest;
  for (final p in points) {
    if (p.isScored) latest = p;
  }

  // The most recent reading of each lift, whichever cycle it came from. A lift
  // trained in the first session of a four-session cycle is as current as one
  // trained in the last.
  final byLift = <LiftId, LiftChange>{};
  for (final p in points) {
    for (final l in p.lifts) {
      byLift[l.lift] = l;
    }
  }
  final lifts = byLift.values.toList()
    ..sort((a, b) => b.percent.compareTo(a.percent));

  return CycleProgress(
    cycles: points,
    latest: latest,
    trend: computeTrend(points),
    lifts: lifts,
  );
}

/// The pill's reading: the last **closed** scored cycle against the one
/// [trendSpan] scored cycles before it.
///
/// The open cycle is left out on purpose. Its point is partial — two sessions
/// of four — so a strong first day would read as a jump and the pill would
/// change its mind by the weekend.
ProgressTrend? computeTrend(List<CyclePoint> points) {
  final values = [
    for (final p in points)
      if (p.isScored && !p.isOpen) p.value!,
  ];
  if (values.length < 2) return null;

  final recent = values.last;
  final before = values[math.max(0, values.length - 1 - trendSpan)];
  final change = recent - before;
  if (change >= trendThreshold) return ProgressTrend.progressing;
  if (change <= -trendThreshold) return ProgressTrend.dropping;
  return ProgressTrend.holdingSteady;
}

/// The ranges the card's `SegmentedPill` offers.
///
/// Every one of them is always selectable, even on a regime with four cycles
/// to its name. A chip that would draw a perfectly good short chart and is
/// greyed out instead is a worse answer than the short chart.
enum CycleRange { last12, last24, all }

extension CycleRangeX on CycleRange {
  String get label => switch (this) {
        CycleRange.last12 => 'Last 12',
        CycleRange.last24 => 'Last 24',
        CycleRange.all => 'All',
      };

  int? get cycles => switch (this) {
        CycleRange.last12 => 12,
        CycleRange.last24 => 24,
        CycleRange.all => null,
      };
}

/// What a range chip asks the chart for.
class CycleWindow {
  const CycleWindow({
    required this.points,
    required this.plotted,
    required this.isBlocks,
  });

  /// Every cycle the chart lays out, deloads included.
  ///
  /// Deloads are in the list even though they carry no point: they occupy a
  /// position on the axis, and dropping them would close the gap a light week
  /// leaves and draw five cycles of training as four.
  final List<CyclePoint> points;

  /// The cycles that carry a marker, by cycle id.
  ///
  /// The same as every scored cycle, except under [isBlocks] — where the
  /// cycles between the blocks still hold their place on the axis but are not
  /// drawn, so the spacing stays honest while the line stays readable.
  final Set<String> plotted;

  /// Whether the chart is drawing one point per block rather than one per
  /// cycle, which it says in its caption and draws deloads as hairlines for.
  final bool isBlocks;
}

/// The cycles [range] draws, out of [progress].
///
/// All thins to blocks past [blockThreshold] cycles rather than drawing four
/// hundred points into three hundred pixels. The cycles it stops drawing keep
/// their place on the axis — see [CycleWindow.points].
CycleWindow cycleWindow(CycleProgress progress, CycleRange range) {
  final all = progress.cycles;
  final n = range.cycles;
  if (n == null) {
    final blocks = all.length > blockThreshold;
    return CycleWindow(
      points: all,
      plotted: {
        for (final c in blocks ? progress.blockPoints : all)
          if (c.isScored) c.cycleId,
      },
      isBlocks: blocks,
    );
  }
  final from = all.length > n ? all.length - n : 0;
  final window = all.sublist(from);
  return CycleWindow(
    points: window,
    plotted: {
      for (final c in window)
        if (c.isScored) c.cycleId,
    },
    isBlocks: false,
  );
}

/// The number of cycles above which All draws one point per block.
const blockThreshold = 24;

/// Whether the line from cycle [from] to cycle [to] jumps, and is therefore
/// dashed at 60% rather than drawn solid.
///
/// A solid line between two points claims the training between them, so a
/// segment jumps whenever a cycle lies between its ends that it does not draw:
/// a deload, which holds its place and scores nothing, or a spell on another
/// regime, which leaves no place at all. The second is why this reads the cycle
/// numbers and not the positions on the axis. Cycles are evenly spaced, so 3
/// and 9 of a resumed regime sit side by side, and a rule written in positions
/// drew six cycles of another programme as a solid line.
///
/// Under [isBlocks] no segment jumps: every one spans a block, and dashing
/// them all says "broken" about the one thing that is normal there
/// ([THEME → The cycle axis](THEME.md#the-cycle-axis)).
bool cycleSegmentJumps(
  CyclePoint from,
  CyclePoint to, {
  required bool isBlocks,
}) =>
    !isBlocks && (to.index - from.index).abs() > 1;

/// The phase each of [points] is tinted by, position for position.
///
/// A cycle takes the phase most of its sessions ran in. Under [isBlocks] a
/// block — the run of cycles between two deloads — takes the phase most of
/// the sessions of all its cycles ran in, and every cycle of the run wears it,
/// so a block reads as one stretch the way its one point does. A deload is
/// never tinted either way: a light week is not part of a cut
/// ([THEME → The cycle axis](THEME.md#the-cycle-axis)).
List<PhaseKind?> cycleTints(List<CyclePoint> points, {bool isBlocks = false}) {
  if (!isBlocks) return [for (final p in points) p.phase];

  final out = List<PhaseKind?>.filled(points.length, null);
  var from = 0;
  while (from < points.length) {
    if (points[from].isDeload) {
      from++;
      continue;
    }
    var to = from;
    while (to + 1 < points.length && !points[to + 1].isDeload) {
      to++;
    }
    final kind = mostCommonPhase([
      for (var i = from; i <= to; i++) ...points[i].sessions,
    ]);
    for (var i = from; i <= to; i++) {
      out[i] = kind;
    }
    from = to + 1;
  }
  return out;
}

/// One session, as the All time timeline reads it.
class TrainedDay {
  const TrainedDay({
    required this.dayKey,
    required this.regimeId,
    this.isDeload = false,
    this.cycleIndex,
  });

  final int dayKey;
  final String regimeId;
  final bool isDeload;

  /// The regime's own cycle number on that day. Null on a session logged
  /// before the regime had a cycle to belong to — see `cycleOpenOn`.
  final int? cycleIndex;
}

/// One week of the timeline strip.
class TimelineWeek {
  const TimelineWeek({
    required this.week,
    required this.start,
    required this.regimeId,
    required this.isDeload,
    required this.sessions,
    this.firstCycle,
    this.lastCycle,
  });

  /// The ISO week number within its year.
  final int week;

  /// The Monday the week begins on, in UTC, matching [isoWeekStart].
  final DateTime start;

  /// The regime the week belongs to, or null for a week off.
  final String? regimeId;

  /// Whether the week's training was a deload.
  final bool isDeload;

  final int sessions;

  /// The cycle numbers trained in the week, lowest and highest.
  ///
  /// A week is usually one cycle and sometimes two — a cycle closes on a
  /// Wednesday and the next one opens on the Thursday — so the run beneath the
  /// timeline names a span rather than a number.
  final int? firstCycle;
  final int? lastCycle;

  /// A week with no training in it. Drawn as an empty cell, and legended under
  /// Weeks rather than under Regimes: a week off is not a programme.
  bool get isOff => regimeId == null;
}

/// Which regime was trained in each ISO week of [year].
///
/// A week belongs to whichever regime was trained most in it, because a week
/// straddling a switch is one cell and has to choose. Ties go to the regime
/// trained latest in the week, which is the one the user moved to.
///
/// Every week of the year is returned, trained or not, so the strip keeps its
/// shape and an untrained week is visible as a gap rather than as an absence.
List<TimelineWeek> computeTimelineWeeks({
  required int year,
  required Iterable<TrainedDay> days,
}) {
  final counts = <int, Map<String, int>>{};
  final latest = <int, Map<String, int>>{};
  final deloads = <int, Set<String>>{};
  final cycles = <int, Map<String, List<int>>>{};

  for (final d in days) {
    final date = dateFromDayKey(d.dayKey);
    final iso = isoWeekOf(date);
    if (iso.year != year) continue;
    (counts[iso.week] ??= {}).update(
      d.regimeId,
      (n) => n + 1,
      ifAbsent: () => 1,
    );
    (latest[iso.week] ??= {}).update(
      d.regimeId,
      (k) => d.dayKey > k ? d.dayKey : k,
      ifAbsent: () => d.dayKey,
    );
    if (d.isDeload) (deloads[iso.week] ??= {}).add(d.regimeId);
    final index = d.cycleIndex;
    if (index != null) {
      ((cycles[iso.week] ??= {})[d.regimeId] ??= []).add(index);
    }
  }

  final weeks = <TimelineWeek>[];
  for (var w = 1; w <= isoWeeksInYear(year); w++) {
    final byRegime = counts[w];
    String? winner;
    if (byRegime != null) {
      for (final id in byRegime.keys) {
        if (winner == null ||
            byRegime[id]! > byRegime[winner]! ||
            (byRegime[id]! == byRegime[winner]! &&
                latest[w]![id]! > latest[w]![winner]!)) {
          winner = id;
        }
      }
    }
    final trained = winner == null ? null : cycles[w]?[winner];
    weeks.add(
      TimelineWeek(
        week: w,
        start: isoWeekStart(year, w),
        regimeId: winner,
        isDeload: winner != null && (deloads[w]?.contains(winner) ?? false),
        sessions: winner == null ? 0 : byRegime![winner]!,
        firstCycle: trained == null || trained.isEmpty
            ? null
            : trained.reduce(math.min),
        lastCycle: trained == null || trained.isEmpty
            ? null
            : trained.reduce(math.max),
      ),
    );
  }
  return weeks;
}

/// The ISO week [date] falls in, and the year that week belongs to.
///
/// The year is the week's rather than the date's, and they differ: 1 January
/// 2026 is a Thursday, so 29 December 2025 is in week 1 of 2026 and belongs on
/// the 2026 strip. Naming the week by its own Thursday is what the ISO
/// definition is, and is what keeps a week from appearing on two years' strips
/// or on neither.
({int year, int week}) isoWeekOf(DateTime date) {
  final day = DateTime.utc(date.year, date.month, date.day);
  // The Thursday of this week. `weekday` is 1 on Monday, so this walks forward
  // three days from a Monday and back three from a Sunday.
  final thursday = DateTime.utc(day.year, day.month, day.day + (4 - day.weekday));
  final ordinal = thursday.difference(DateTime.utc(thursday.year, 1, 1)).inDays;
  return (year: thursday.year, week: 1 + ordinal ~/ 7);
}

/// The Monday ISO week [week] of [year] begins on, in UTC.
///
/// Built from 4 January, which is in week 1 by definition in every year.
DateTime isoWeekStart(int year, int week) {
  final jan4 = DateTime.utc(year, 1, 4);
  return DateTime.utc(year, 1, 4 - (jan4.weekday - 1) + (week - 1) * 7);
}

/// Whether [year] has 52 or 53 ISO weeks. 28 December is in the last week of
/// its own year in every year, which is the cheapest way to ask.
int isoWeeksInYear(int year) => isoWeekOf(DateTime.utc(year, 12, 28)).week;

/// One unbroken spell on a regime, as the timeline lists it.
class TimelineRun {
  const TimelineRun({
    required this.regimeId,
    required this.from,
    required this.to,
    this.firstCycle,
    this.lastCycle,
  });

  final String regimeId;

  /// The first and last weeks trained in the spell.
  final TimelineWeek from;
  final TimelineWeek to;

  final int? firstCycle;
  final int? lastCycle;
}

/// The spells behind a year's strip, in the order they were trained.
///
/// A week off does not end a spell. Leaving the gym for a fortnight and coming
/// back to the same programme is one run of that programme with a gap in it,
/// and splitting it in three would report a holiday as a change of plan. What
/// ends a spell is training something else.
List<TimelineRun> timelineRuns(List<TimelineWeek> weeks) {
  final runs = <TimelineRun>[];
  for (final w in weeks) {
    final id = w.regimeId;
    if (id == null) continue;
    final open = runs.isEmpty ? null : runs.last;
    if (open == null || open.regimeId != id) {
      runs.add(
        TimelineRun(
          regimeId: id,
          from: w,
          to: w,
          firstCycle: w.firstCycle,
          lastCycle: w.lastCycle,
        ),
      );
      continue;
    }
    runs[runs.length - 1] = TimelineRun(
      regimeId: id,
      from: open.from,
      to: w,
      firstCycle: open.firstCycle ?? w.firstCycle,
      lastCycle: w.lastCycle ?? open.lastCycle,
    );
  }
  return runs;
}

/// The ISO years a log spanning [firstDayKey] to [lastDayKey] covers, earliest
/// first.
///
/// ISO rather than calendar, because that is what the strip is drawn in: a
/// session on 29 December 2025 belongs to week 1 of 2026 and would otherwise
/// be trained in a year the stepper does not offer.
List<int> trainedYears({required int? firstDayKey, required int? lastDayKey}) {
  if (firstDayKey == null || lastDayKey == null) return const [];
  final first = isoWeekOf(dateFromDayKey(firstDayKey)).year;
  final last = isoWeekOf(dateFromDayKey(lastDayKey)).year;
  return [for (var y = first; y <= last; y++) y];
}
