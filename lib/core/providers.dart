import 'package:drift/drift.dart' hide Column, Table;
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/backup/backup_service.dart';
import '../data/db/database.dart';
import '../data/repositories/repairs.dart';
import '../data/repositories/training_repository.dart';
import '../domain/cycle_engine.dart';
import '../domain/units.dart';
import 'sync_providers.dart';

/// Single database instance for the app's lifetime.
final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

/// Resolves once the schema exists and the database has been looked over. No
/// programme is created here — the user picks or builds their own. The UI waits
/// on this before rendering anything data-driven.
///
/// The list itself is [repairDatabase], shared with `BackupService.restore` so
/// a launch and a restore cannot check different things.
///
/// **The catalog is seeded only once the welcome screen has been answered.**
/// It used to be seeded here, before first paint, which is what would give a
/// phone that then signs in two catalogs and a history split across both
/// ([SYNC.md § 10](SYNC.md#10-adoption)). The welcome screen renders perfectly
/// well over an unseeded database — it asks about accounts, not exercises — and
/// `answerWelcome` seeds before it records the answer, so nothing downstream
/// ever sees the gap.
final appInitProvider = FutureProvider<void>((ref) async {
  final db = ref.watch(databaseProvider);
  await repairDatabase(db, seed: await welcomeAnswered(db));
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

/// One regime by id.
///
/// The editor is reached by pushing a row off the Regime index, so it edits the
/// regime you tapped rather than the one you happen to be training. Emits null
/// when that regime is deleted from under the screen.
final regimeByIdProvider = StreamProvider.family<Regime?, String>((ref, id) {
  final db = ref.watch(databaseProvider);
  final query = db.select(db.regimes)
    ..where((t) => t.id.equals(id) & t.deletedAt.isNull())
    ..limit(1);
  return query.watchSingleOrNull();
});

/// Sessions of any regime, in programme order.
final sessionsForRegimeProvider =
    StreamProvider.family<List<Session>, String>((ref, id) {
  final db = ref.watch(databaseProvider);
  final query = db.select(db.sessions)
    ..where((t) => t.regimeId.equals(id) & t.deletedAt.isNull())
    ..orderBy([(t) => OrderingTerm(expression: t.orderIndex)]);
  return query.watch();
});

/// Sessions of the active regime, in programme order. What Today and the log
/// run on; the editor uses the family above.
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

/// When the last automatic export ran, or null if none has.
///
/// Here rather than on the Settings screen because the screen is not what
/// changes it. The four tabs live in one `IndexedStack` and are all built at
/// launch, so a provider read only on first build is read *once, before any
/// session has been finished* — Settings then said "no automatic backup yet"
/// over a file that had been written an hour earlier, and went on saying it
/// until the app was restarted. Whoever writes a backup invalidates this.
final lastBackupProvider = FutureProvider<DateTime?>((ref) {
  return BackupService(ref.watch(databaseProvider)).lastAutoExportAt();
});

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

// The open workout, the "anything ever finished" flag and the session preview
// used to live here as three more watched queries. They are part of the Today
// snapshot now — see `todaySnapshot` in the repository for why.
