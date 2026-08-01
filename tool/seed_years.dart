// Generates a Deltoid backup file holding N years of plausible training, so a
// screen can be looked at with a real amount of data behind it rather than the
// three sessions you can be bothered to log by hand.
//
//   dart run tool/seed_years.dart 3                  # writes a file
//   dart run tool/seed_years.dart 3 --push           # …and adb pushes it
//   dart run tool/seed_years.dart 50 --seed=7        # deterministic
//
// Then: Settings → Restore, pick the file. Restore is destructive by design —
// it clears every table first — so this replaces whatever is on the device.
//
// It writes a **backup file**, not the database, on purpose. The importer is
// the one path into this app's tables that is tested and version-checked; a
// generator that wrote SQLite directly would have to keep pace with every
// migration, and would happily produce rows the app itself could never make.
//
// What it fakes, and how honestly:
//
//   * A real cycle structure — one pass through every session is a cycle, and
//     the deload lands after N of them, exactly as the app counts it.
//   * Per-session progression. The same movement in Push 1 and Push 2 runs its
//     own numbers, which is the one rule the app exists for and the thing most
//     worth having data for.
//   * Plateaus, missed weeks, the occasional skipped exercise and abandoned
//     day. A dataset where every session beats the last is not a test of a
//     progress chart, it is a test of a straight line.
//   * Bodyweight logged most weeks, because every bodyweight-load score in the
//     app depends on it.

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:deltoid/data/seed/seed_data.dart';
import 'package:deltoid/domain/enums.dart';

const _formatVersion = 1;

/// Must match `AppDatabase.schemaVersion`, or the importer refuses the file.
const _schemaVersion = 4;

void main(List<String> args) async {
  final positional = args.where((a) => !a.startsWith('--')).toList();
  final years = int.tryParse(positional.isEmpty ? '' : positional.first);
  if (years == null || years < 1) {
    stderr.writeln('usage: dart run tool/seed_years.dart <years> '
        '[--push] [--seed=N] [--out=path]');
    exit(64);
  }

  final seed = _intFlag(args, 'seed') ?? 42;
  final out = _stringFlag(args, 'out') ??
      'build/deltoid-seed-${years}y.json';

  final payload = buildSeedPayload(years: years, seed: seed);

  final file = File(out);
  await file.parent.create(recursive: true);
  await file.writeAsString(jsonEncode(payload));

  final counts = payload['counts'] as Map<String, int>;
  stdout.writeln('Wrote ${file.path}');
  for (final entry in counts.entries) {
    stdout.writeln('  ${entry.value.toString().padLeft(7)}  ${entry.key}');
  }

  if (args.contains('--push')) {
    const dest = '/sdcard/Download/';
    final result = await Process.run('adb', ['push', file.path, dest]);
    stdout.write(result.stdout);
    stderr.write(result.stderr);
    if (result.exitCode != 0) exit(result.exitCode);
    stdout.writeln('\nPushed to $dest — on the phone: '
        'Settings → Restore from a file → Downloads.');
  }
}

/// The generator as a function, so a test can restore what it writes rather
/// than trusting that the shape is still the one the importer accepts.
Map<String, dynamic> buildSeedPayload({required int years, int seed = 42}) =>
    _Generator(years: years, random: Random(seed)).build();

int? _intFlag(List<String> args, String name) {
  final raw = _stringFlag(args, name);
  return raw == null ? null : int.tryParse(raw);
}

String? _stringFlag(List<String> args, String name) {
  for (final a in args) {
    if (a.startsWith('--$name=')) return a.substring(name.length + 3);
  }
  return null;
}

class _Generator {
  _Generator({required this.years, required this.random});

  final int years;
  final Random random;

  final _exercises = <Map<String, dynamic>>[];
  final _sessions = <Map<String, dynamic>>[];
  final _sessionExercises = <Map<String, dynamic>>[];
  final _cycles = <Map<String, dynamic>>[];
  final _workouts = <Map<String, dynamic>>[];
  final _workoutExercises = <Map<String, dynamic>>[];
  final _setLogs = <Map<String, dynamic>>[];
  final _bodyweight = <Map<String, dynamic>>[];

  final _idsByKey = <String, String>{};
  var _counter = 0;

  /// Ids only have to be unique and stable within the file.
  String _id(String prefix) => '$prefix-${(_counter++).toString().padLeft(6, '0')}';

  Map<String, dynamic> build() {
    final template = regimeTemplates.firstWhere((t) => t.key == 'ppl6');
    final start = DateTime.now().subtract(Duration(days: 365 * years));
    final regimeId = _id('regime');

    _buildCatalog();
    _buildRegime(regimeId, template, start);
    _train(regimeId, template, start);
    _logBodyweight(start);

    final data = {
      'exercises': _exercises,
      'regimes': [_regime],
      'sessions': _sessions,
      'session_exercises': _sessionExercises,
      'cycles': _cycles,
      'workouts': _workouts,
      'workout_exercises': _workoutExercises,
      'set_logs': _setLogs,
      'bodyweight_logs': _bodyweight,
    };

    return {
      'format': _formatVersion,
      'schemaVersion': _schemaVersion,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'counts': {
        for (final e in data.entries) e.key: (e.value as List).length,
      },
      'data': data,
    };
  }

  late Map<String, dynamic> _regime;

  Map<String, dynamic> _sync(int at) => {
        'updatedAt': at,
        'deletedAt': null,
        'deviceId': 'seed-script',
        'dirty': false,
      };

  void _buildCatalog() {
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final e in starterExercises) {
      final id = _id('ex');
      _idsByKey[e.key] = id;
      _exercises.add({
        'id': id,
        ..._sync(now),
        'name': e.name,
        'muscle': e.muscle.name,
        'equipment': e.equipment.name,
        'loadMode': e.loadMode.name,
        'barKind': e.barKind.name,
        'starterKey': e.key,
        'formVideoUrls': '[]',
        'notes': null,
        'archived': false,
      });
    }
  }

  void _buildRegime(String regimeId, RegimeTemplate template, DateTime start) {
    final at = start.millisecondsSinceEpoch;
    _regime = {
      'id': regimeId,
      ..._sync(at),
      'name': template.name,
      'isActive': true,
      'deloadEnabled': true,
      'deloadAfterCycles': 6,
      'deloadSetDelta': -1,
      'deloadWeightPct': 80,
      'createdAt': at,
    };

    for (var i = 0; i < template.sessions.length; i++) {
      final session = template.sessions[i];
      final sessionId = _id('sess');
      _sessionIds.add(sessionId);
      _sessions.add({
        'id': sessionId,
        ..._sync(at),
        'regimeId': regimeId,
        'name': session.name,
        'orderIndex': i,
      });

      for (var j = 0; j < session.slots.length; j++) {
        final slot = session.slots[j];
        _sessionExercises.add({
          'id': _id('slot'),
          ..._sync(at),
          'sessionId': sessionId,
          'exerciseId': _idsByKey[slot.exerciseKey],
          'orderIndex': j,
          'targetSets': slot.sets,
          'targetRepLow': slot.repLow,
          'targetRepHigh': slot.repHigh,
          'notes': null,
          'restSeconds': null,
          'deloadSetDelta': null,
          'deloadWeightPct': null,
        });
      }
    }
  }

  final _sessionIds = <String>[];

  /// The working weight each *slot* is on, keyed session+exercise — never by
  /// exercise alone. Bench in Push 1 and bench in Push 2 progress separately,
  /// and collapsing them here would generate exactly the data that hides the
  /// bug this app was written to avoid.
  final _working = <String, double>{};

  void _train(String regimeId, RegimeTemplate template, DateTime start) {
    var day = start;
    final end = DateTime.now();
    var cycleIndex = 1;
    var sessionInCycle = 0;
    var cyclesSinceDeload = 0;
    String? cycleId;
    var cycleStart = day;

    while (day.isBefore(end)) {
      // A rest day, a busy week, a holiday. Training every other day with the
      // occasional gap is what a real log looks like, and gaps are what make
      // the x-axis worth plotting against time rather than against an index.
      final skipWeek = random.nextInt(28) == 0;
      if (skipWeek) {
        day = day.add(Duration(days: 5 + random.nextInt(6)));
        continue;
      }

      if (sessionInCycle == 0) {
        cycleId = _id('cycle');
        cycleStart = day;
      }

      final isDeload = cyclesSinceDeload >= 6;
      final session = template.sessions[sessionInCycle];
      final sessionId = _sessionIds[sessionInCycle];

      // Roughly one day in twenty-five is started and abandoned — the app has
      // a sweep for exactly this and it should have something to sweep.
      final abandoned = random.nextInt(25) == 0;

      _logWorkout(
        regimeId: regimeId,
        cycleId: cycleId!,
        sessionId: sessionId,
        session: session,
        day: day,
        isDeload: isDeload,
        abandoned: abandoned,
      );

      sessionInCycle++;
      if (sessionInCycle == template.sessions.length) {
        _cycles.add({
          'id': cycleId,
          ..._sync(day.millisecondsSinceEpoch),
          'regimeId': regimeId,
          'cycleIndex': cycleIndex,
          'startedAt': cycleStart.millisecondsSinceEpoch,
          'completedAt': day.millisecondsSinceEpoch,
          'isDeload': isDeload,
        });
        cycleIndex++;
        sessionInCycle = 0;
        cyclesSinceDeload = isDeload ? 0 : cyclesSinceDeload + 1;
      }

      day = day.add(Duration(days: 1 + random.nextInt(2)));
    }

    // The cycle in progress on the last day stays open, which is the state the
    // app is actually in most of the time.
    if (sessionInCycle != 0 && cycleId != null) {
      _cycles.add({
        'id': cycleId,
        ..._sync(cycleStart.millisecondsSinceEpoch),
        'regimeId': regimeId,
        'cycleIndex': cycleIndex,
        'startedAt': cycleStart.millisecondsSinceEpoch,
        'completedAt': null,
        'isDeload': false,
      });
    }
  }

  void _logWorkout({
    required String regimeId,
    required String cycleId,
    required String sessionId,
    required TemplateSession session,
    required DateTime day,
    required bool isDeload,
    required bool abandoned,
  }) {
    final startedAt = DateTime(day.year, day.month, day.day, 18, 5)
        .millisecondsSinceEpoch;
    final workoutId = _id('wo');

    _workouts.add({
      'id': workoutId,
      ..._sync(startedAt),
      'regimeId': regimeId,
      'sessionId': sessionId,
      'cycleId': cycleId,
      'dayKey': day.year * 10000 + day.month * 100 + day.day,
      'startedAt': startedAt,
      'endedAt': abandoned ? null : startedAt + (55 + random.nextInt(25)) * 60000,
      'isDeload': isDeload,
      'status': abandoned
          ? WorkoutStatus.abandoned.name
          : WorkoutStatus.completed.name,
      'notes': random.nextInt(12) == 0 ? _note() : null,
    });

    for (var i = 0; i < session.slots.length; i++) {
      final slot = session.slots[i];
      final exercise = starterExercises
          .firstWhere((e) => e.key == slot.exerciseKey);
      final weId = _id('we');

      // One exercise in forty is skipped with a reason. A skip is data in this
      // app, not an absence, so there should be some.
      final skipped = random.nextInt(40) == 0;

      _workoutExercises.add({
        'id': weId,
        ..._sync(startedAt),
        'workoutId': workoutId,
        'exerciseId': _idsByKey[slot.exerciseKey],
        'orderIndex': i,
        'targetSets': slot.sets,
        'notes': random.nextInt(30) == 0 ? _exerciseNote() : null,
        'skipReason': skipped
            ? SkipReason.values[1 + random.nextInt(SkipReason.values.length - 1)]
                .name
            : SkipReason.none.name,
      });

      if (skipped || abandoned && random.nextBool()) continue;

      _logSets(
        weId: weId,
        slotKey: '$sessionId:${slot.exerciseKey}',
        exercise: exercise,
        slot: slot,
        startedAt: startedAt,
        isDeload: isDeload,
        stopEarly: abandoned,
      );
    }
  }

  void _logSets({
    required String weId,
    required String slotKey,
    required StarterExercise exercise,
    required TemplateSlot slot,
    required int startedAt,
    required bool isDeload,
    required bool stopEarly,
  }) {
    final bodyweightOnly = exercise.loadMode == LoadMode.bodyweight;
    final base = _working[slotKey] ?? _startingLoad(exercise);

    // Progress, but not on rails: a rep added most sessions, weight when the
    // top of the rep range is reached, and a plateau every so often that lasts
    // a few sessions. A dataset that only goes up tests nothing.
    final stalling = random.nextInt(6) == 0;
    final next = stalling ? base : base + _increment(exercise);
    if (!isDeload) _working[slotKey] = next;

    final load = isDeload ? _round(next * 0.8) : next;
    final targetSets = isDeload ? (slot.sets - 1).clamp(1, 10) : slot.sets;
    final sets = stopEarly ? 1 + random.nextInt(targetSets) : targetSets;
    final repLow = slot.repLow ?? 8;
    final repHigh = slot.repHigh ?? 12;

    for (var i = 0; i < sets; i++) {
      // Reps fall off across sets, the way they do when the weight is real.
      final reps = (repHigh - i - random.nextInt(2)).clamp(repLow - 2, repHigh);
      _setLogs.add({
        'id': _id('set'),
        ..._sync(startedAt),
        'workoutExerciseId': weId,
        'setIndex': i,
        'setType': SetType.working.name,
        'weight': bodyweightOnly ? null : load,
        'reps': reps,
        'addedWeight':
            exercise.loadMode == LoadMode.bodyweightPlus && load > 0
                ? load
                : null,
        'parentSetId': null,
        'restSeconds': 90 + random.nextInt(90),
        'completedAt': startedAt + (i + 1) * 4 * 60000,
        'note': random.nextInt(60) == 0 ? _setNote() : null,
        'isDone': true,
      });
    }
  }

  double _startingLoad(StarterExercise e) => switch (e.loadMode) {
        LoadMode.bodyweight => 0,
        LoadMode.bodyweightPlus => 0,
        LoadMode.perSide => 10 + random.nextInt(6) * 2.5,
        LoadMode.total => e.equipment == Equipment.barbell
            ? 40 + random.nextInt(8) * 2.5
            : 20 + random.nextInt(8) * 2.5,
      };

  /// Small, and smaller on isolation work — a year of 2.5kg jumps on a lateral
  /// raise would end at a number no human has ever lifted.
  double _increment(StarterExercise e) {
    if (e.loadMode == LoadMode.bodyweight) return 0;
    final base = switch (e.muscle) {
      MuscleGroup.quads || MuscleGroup.glutes || MuscleGroup.hamstrings => 1.25,
      MuscleGroup.chest || MuscleGroup.back => 0.6,
      _ => 0.3,
    };
    return random.nextInt(3) == 0 ? 0 : base;
  }

  double _round(double kg) => (kg * 2).round() / 2;

  void _logBodyweight(DateTime start) {
    var day = start;
    var kg = 74.0;
    final end = DateTime.now();
    while (day.isBefore(end)) {
      // A slow drift with weekly noise, because every bodyweight-load score in
      // the app interpolates between these and a flat line hides that.
      kg += (random.nextDouble() - 0.45) * 0.4;
      kg = kg.clamp(66.0, 92.0);
      if (random.nextInt(8) != 0) {
        _bodyweight.add({
          'id': _id('bw'),
          ..._sync(day.millisecondsSinceEpoch),
          'dayKey': day.year * 10000 + day.month * 100 + day.day,
          'weightKg': (kg * 10).round() / 10,
        });
      }
      day = day.add(const Duration(days: 7));
    }
  }

  String _note() => const [
        'Slept badly, everything felt heavy.',
        'Gym was empty for once.',
        'Rushed — 40 minutes and out.',
        'Best session in weeks.',
        'Shoulder grumbling on presses.',
      ][random.nextInt(5)];

  String _exerciseNote() => const [
        'Left side weaker today.',
        'Bench was the wide one.',
        'Dropped a notch on the seat.',
        'Elbows flaring, slowed it down.',
      ][random.nextInt(4)];

  String _setNote() => const [
        'Grinder.',
        'Two in reserve.',
        'Form went on the last rep.',
        'Felt light.',
      ][random.nextInt(4)];
}
