import 'package:drift/drift.dart' hide Column, Table;
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/enums.dart';

import '../data/db/database.dart';
import '../data/repositories/training_repository.dart';
import '../data/seed/seeder.dart';
import '../domain/cycle_engine.dart';
import '../domain/units.dart';

/// Single database instance for the app's lifetime.
final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

/// Resolves once the schema exists and the exercise catalog has its starting
/// rows. No programme is created here — the user picks or builds their own.
/// The UI waits on this before rendering anything data-driven.
final appInitProvider = FutureProvider<void>((ref) async {
  final db = ref.watch(databaseProvider);
  await ensureStarterCatalog(db);
});

/// The regime being trained. Exactly one row is active at a time, but the query
/// is limited rather than assuming it: `watchSingleOrNull` throws on two rows,
/// and a half-applied restore would take the whole app down with it.
final activeRegimeProvider = StreamProvider<Regime?>((ref) {
  final db = ref.watch(databaseProvider);
  final query = db.select(db.regimes)
    ..where((t) => t.isActive.equals(true) & t.deletedAt.isNull())
    ..orderBy([
      (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc)
    ])
    ..limit(1);
  return query.watchSingleOrNull();
});

/// Sessions of the active regime, in programme order.
final activeSessionsProvider = StreamProvider<List<Session>>((ref) {
  final db = ref.watch(databaseProvider);
  final regime = ref.watch(activeRegimeProvider).valueOrNull;
  if (regime == null) return Stream.value(const []);

  final query = db.select(db.sessions)
    ..where((t) => t.regimeId.equals(regime.id) & t.deletedAt.isNull())
    ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)]);
  return query.watch();
});

final trainingRepositoryProvider = Provider<TrainingRepository>(
  (ref) => TrainingRepository(ref.watch(databaseProvider)),
);

const themeModeKey = 'theme_mode';

/// Appearance preference, stored locally and never synced — which theme suits
/// a phone is a property of the phone, not the account.
final themeModeProvider = StreamProvider<ThemeMode>((ref) {
  final db = ref.watch(databaseProvider);
  final query = db.select(db.appSettings)
    ..where((t) => t.key.equals(themeModeKey));

  return query.watch().map((rows) {
    final value = rows.isEmpty ? null : rows.first.value;
    return switch (value) {
      'light' => ThemeMode.light,
      'system' => ThemeMode.system,
      _ => ThemeMode.dark,
    };
  });
});

Future<void> setThemeMode(AppDatabase db, ThemeMode mode) {
  return db.into(db.appSettings).insertOnConflictUpdate(
        AppSettingsCompanion.insert(key: themeModeKey, value: mode.name),
      );
}

const unitsKey = 'units';

/// The unit weights are shown and typed in.
///
/// Storage stays kilograms whatever this says — mixed units in the database
/// would break every historical comparison with no way to tell afterwards
/// which rows meant what. This is a display setting, applied at the edges.
final weightUnitProvider = StreamProvider<WeightUnit>((ref) {
  final db = ref.watch(databaseProvider);
  final query = db.select(db.appSettings)..where((t) => t.key.equals(unitsKey));
  return query.watch().map(
        (rows) =>
            WeightUnitX.parse(rows.isEmpty ? null : rows.first.value),
      );
});

Future<void> setWeightUnit(AppDatabase db, WeightUnit unit) {
  return db.into(db.appSettings).insertOnConflictUpdate(
        AppSettingsCompanion.insert(key: unitsKey, value: unit.name),
      );
}

/// Recomputed whenever a workout or cycle row changes, so Today reflects a
/// finished session the moment it is saved.
final cycleStatusProvider = StreamProvider<CycleStatus?>((ref) {
  final repo = ref.watch(trainingRepositoryProvider);
  final regime = ref.watch(activeRegimeProvider).valueOrNull;
  if (regime == null) return Stream.value(null);

  return repo.watchCycleStatus(regime.id);
});

/// The unfinished workout, if any. Drives the "resume" affordance on Today.
final openWorkoutProvider = StreamProvider<Workout?>((ref) {
  final db = ref.watch(databaseProvider);
  final query = db.select(db.workouts)
    ..where((t) =>
        t.status.equalsValue(WorkoutStatus.inProgress) & t.deletedAt.isNull())
    ..orderBy([
      (t) => OrderingTerm(expression: t.startedAt, mode: OrderingMode.desc)
    ])
    ..limit(1);
  return query.watchSingleOrNull();
});

/// Whether anything has ever been finished. Separates "brand new install" from
/// "regime set up, nothing logged yet" on Today.
final hasCompletedWorkoutProvider = StreamProvider<bool>((ref) {
  final db = ref.watch(databaseProvider);
  final query = db.select(db.workouts)
    ..where((t) =>
        t.status.equalsValue(WorkoutStatus.completed) & t.deletedAt.isNull())
    ..limit(1);
  return query.watch().map((rows) => rows.isNotEmpty);
});

/// Exercise names for a session template, used for the preview on Today.
final sessionPreviewProvider =
    StreamProvider.family<List<String>, String>((ref, sessionId) {
  final db = ref.watch(databaseProvider);
  final query = db.select(db.sessionExercises).join([
    innerJoin(db.exercises, db.exercises.id.equalsExp(db.sessionExercises.exerciseId)),
  ])
    ..where(db.sessionExercises.sessionId.equals(sessionId) &
        db.sessionExercises.deletedAt.isNull())
    ..orderBy([OrderingTerm(expression: db.sessionExercises.orderIndex)]);

  return query.watch().map(
        (rows) => rows.map((r) => r.readTable(db.exercises).name).toList(),
      );
});
