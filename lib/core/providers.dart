import 'package:drift/drift.dart' hide Column, Table;
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../data/backup/backup_service.dart';
import '../data/db/database.dart';
import '../data/repositories/repairs.dart';
import '../data/repositories/training_repository.dart';
import '../domain/cycle_engine.dart';
import '../domain/rest.dart';
import '../domain/session_prefs.dart';
import '../domain/units.dart';
import 'sync_providers.dart';

/// The version of the build actually installed, `1.3.1`.
///
/// Read from the package rather than written down in Dart. A number typed into
/// a Settings screen is a number that stops matching `pubspec.yaml` at the
/// first release nobody remembers to update it for, and the one thing an About
/// section exists to answer is which build this is.
///
/// The build number is deliberately not displayed. `--split-per-abi` adds an
/// ABI offset to `versionCode` when it packages — 1000 for armeabi-v7a, 2000
/// for arm64 — so `1.3.1+6` installs as 2006 and About read "1.3.1 (2006)".
/// That number is a packaging artefact: it identifies the APK rather than the
/// release, it does not match the tag, and it cannot be looked up anywhere.
///
/// Null while it is being read, and on the rare platform that cannot answer —
/// About draws the name without it rather than a placeholder.
final appVersionProvider = FutureProvider<String?>((ref) async {
  try {
    final info = await PackageInfo.fromPlatform();
    return info.version.isEmpty ? null : info.version;
  } on Object {
    // A missing platform channel is not worth a red screen on Settings.
    return null;
  }
});

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
/// The catalog is seeded only once the welcome screen has been answered.
/// Seeding here, before first paint, would give a phone that then signs in two
/// catalogs and a history split across both
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
/// regime that was tapped rather than the one currently being trained. Emits
/// null
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
/// session has been finished*. Settings would then say "no automatic backup
/// yet" over a file written an hour earlier, and go on saying it until the app
/// restarted. Whoever writes a backup invalidates this.
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

/// Everything Settings decides about rest, read as one row.
///
/// The keys are in `domain/rest.dart` with the parsing, because the repository
/// reads two of them without Riverpod. They sit in `app_settings` with the
/// theme and unit preferences, which is to say local and never synchronised.
/// Rest duration and whether the device produces an audible alert are
/// properties of a particular device rather than of the account.
///
/// One provider rather than three: the log screen wants all of it at once, and
/// three `StreamProvider`s over the same table would be three watches on one
/// query for the sake of looking tidy.
typedef RestPrefs = ({
  int defaultSeconds,
  int betweenExercises,
  bool sound,
  bool vibrate,
});

const restPrefsDefaults = (
  defaultSeconds: kDefaultRestSeconds,
  betweenExercises: kDefaultRestSeconds,
  sound: true,
  vibrate: true,
);

final restPrefsProvider = StreamProvider<RestPrefs>((ref) {
  final db = ref.watch(databaseProvider);
  final query = db.select(db.appSettings)
    ..where(
      (t) => t.key.isIn([
        restDefaultKey,
        restBetweenExercisesKey,
        restSoundKey,
        restVibrateKey,
      ]),
    );
  return query.watch().map((rows) {
    final byKey = {for (final row in rows) row.key: row.value};
    return (
      defaultSeconds: parseRestSeconds(byKey[restDefaultKey]),
      betweenExercises: parseRestSeconds(byKey[restBetweenExercisesKey]),
      sound: parseRestSound(byKey[restSoundKey]),
      vibrate: parseRestVibrate(byKey[restVibrateKey]),
    );
  });
});

Future<void> setRestDefaultSeconds(AppDatabase db, int seconds) {
  return db.into(db.appSettings).insertOnConflictUpdate(
        AppSettingsCompanion.insert(
          key: restDefaultKey,
          value: '${clampRest(seconds)}',
        ),
      );
}

Future<void> setRestBetweenExercisesSeconds(AppDatabase db, int seconds) {
  return db.into(db.appSettings).insertOnConflictUpdate(
        AppSettingsCompanion.insert(
          key: restBetweenExercisesKey,
          value: '${clampRest(seconds)}',
        ),
      );
}

Future<void> setRestSound(AppDatabase db, bool on) {
  return db.into(db.appSettings).insertOnConflictUpdate(
        AppSettingsCompanion.insert(
          key: restSoundKey,
          value: on ? 'on' : 'off',
        ),
      );
}

Future<void> setRestVibrate(AppDatabase db, bool on) {
  return db.into(db.appSettings).insertOnConflictUpdate(
        AppSettingsCompanion.insert(
          key: restVibrateKey,
          value: on ? 'on' : 'off',
        ),
      );
}

/// What the app does to the phone while a session is open. Same shape and the
/// same table as [restPrefsProvider], and read together for the same reason:
/// the log screen wants both at once.
typedef SessionPrefs = ({bool notification, bool keepScreenOn});

const sessionPrefsDefaults = (notification: true, keepScreenOn: true);

final sessionPrefsProvider = StreamProvider<SessionPrefs>((ref) {
  final db = ref.watch(databaseProvider);
  final query = db.select(db.appSettings)
    ..where((t) => t.key.isIn([sessionNotificationKey, keepScreenOnKey]));
  return query.watch().map((rows) {
    final byKey = {for (final row in rows) row.key: row.value};
    return (
      notification: parseSessionNotification(byKey[sessionNotificationKey]),
      keepScreenOn: parseKeepScreenOn(byKey[keepScreenOnKey]),
    );
  });
});

Future<void> setSessionNotification(AppDatabase db, bool on) {
  return db.into(db.appSettings).insertOnConflictUpdate(
        AppSettingsCompanion.insert(
          key: sessionNotificationKey,
          value: on ? 'on' : 'off',
        ),
      );
}

Future<void> setKeepScreenOn(AppDatabase db, bool on) {
  return db.into(db.appSettings).insertOnConflictUpdate(
        AppSettingsCompanion.insert(
          key: keepScreenOnKey,
          value: on ? 'on' : 'off',
        ),
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
// are part of the Today snapshot rather than three more watched queries here —
// see `todaySnapshot` in the repository for why.
