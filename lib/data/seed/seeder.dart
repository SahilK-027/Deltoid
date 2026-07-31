import 'package:drift/drift.dart';

import '../../core/ids.dart';
import '../../domain/enums.dart';
import '../db/database.dart';
import 'seed_data.dart';

/// Fills the exercise catalog on first launch and nothing else.
///
/// No regime is created: which split the user trains is theirs to decide, and
/// an app that invents one leaves them deleting somebody else's programme
/// before they can start. Idempotent — skipped entirely once any exercise
/// exists.
Future<void> ensureStarterCatalog(AppDatabase db) async {
  // Limited to one row: this runs before first paint on every launch, and
  // reading the whole catalog to ask whether it is empty put the entire
  // exercise table on the critical path forever.
  final existing = await (db.select(db.exercises)..limit(1)).get();
  if (existing.isNotEmpty) return;

  await db.transaction(() async {
    for (final e in starterExercises) {
      await db.into(db.exercises).insert(
            ExercisesCompanion.insert(
              id: Value(newId()),
              name: e.name,
              muscle: e.muscle,
              equipment: e.equipment,
              loadMode: e.loadMode,
              barKind: Value(e.barKind),
              starterKey: Value(e.key),
            ),
          );
    }
  });
}

/// Writes [template] as a real regime: ordinary sessions and slots, editable
/// like any other. Returns the new regime's id.
///
/// Catalog rows are matched on the starter key they were seeded with — falling
/// back to the name for rows that predate it — and created when missing. Name
/// matching alone meant renaming a starter exercise and then applying a
/// template created a duplicate under the old name.
Future<String> createRegimeFromTemplate(
  AppDatabase db,
  RegimeTemplate template, {
  String? name,
  bool activate = true,
}) async {
  final regimeId = newId();

  await db.transaction(() async {
    if (activate) {
      await db.update(db.regimes).write(
            RegimesCompanion(
              isActive: const Value(false),
              updatedAt: Value(nowMs()),
              dirty: const Value(true),
            ),
          );
    }

    await db.into(db.regimes).insert(
          RegimesCompanion.insert(
            id: Value(regimeId),
            name: name?.trim().isNotEmpty == true ? name!.trim() : template.name,
            isActive: Value(activate),
          ),
        );

    if (template.isBlank) return;

    final catalog = await db.select(db.exercises).get();
    final idByName = {for (final e in catalog) e.name: e.id};
    final idByStarterKey = {
      for (final e in catalog)
        if (e.starterKey != null) e.starterKey!: e.id,
    };
    final starterByKey = {for (final e in starterExercises) e.key: e};

    Future<String> exerciseIdFor(String key) async {
      final starter = starterByKey[key];
      if (starter == null) {
        throw StateError('Template "${template.key}" references unknown '
            'exercise key "$key"');
      }
      final existing = idByStarterKey[key] ?? idByName[starter.name];
      if (existing != null) return existing;

      final id = newId();
      await db.into(db.exercises).insert(
            ExercisesCompanion.insert(
              id: Value(id),
              name: starter.name,
              muscle: starter.muscle,
              equipment: starter.equipment,
              loadMode: starter.loadMode,
              barKind: Value(starter.barKind),
              starterKey: Value(key),
            ),
          );
      idByName[starter.name] = id;
      idByStarterKey[key] = id;
      return id;
    }

    for (var i = 0; i < template.sessions.length; i++) {
      final s = template.sessions[i];
      final sessionId = newId();
      await db.into(db.sessions).insert(
            SessionsCompanion.insert(
              id: Value(sessionId),
              regimeId: regimeId,
              name: s.name,
              orderIndex: i,
            ),
          );

      for (var j = 0; j < s.slots.length; j++) {
        final slot = s.slots[j];
        await db.into(db.sessionExercises).insert(
              SessionExercisesCompanion.insert(
                id: Value(newId()),
                sessionId: sessionId,
                exerciseId: await exerciseIdFor(slot.exerciseKey),
                orderIndex: j,
                targetSets: Value(slot.sets),
                targetRepLow: Value(slot.repLow),
                targetRepHigh: Value(slot.repHigh),
              ),
            );
      }
    }
  });

  return regimeId;
}

/// Gives the rows we seeded ourselves the bar they are normally loaded on.
///
/// Run once, by the v2 → v3 migration. Without it an existing install comes out
/// of the upgrade with `none` on all thirteen barbell movements — the column's
/// default, which is right for a *new* column on rows nobody has been asked
/// about, and useless for a catalog this app wrote itself and already knows the
/// answer for. The feature would be invisible until every one of them was
/// edited by hand.
///
/// Only touches rows still carrying the `starterKey` they were seeded with, and
/// only sets a bar where the seed names one. An exercise the user created, or
/// one whose bar they have already chosen, is theirs — this runs before either
/// is possible, but it is written to stay true if it is ever run again.
Future<void> backfillSeededBarKinds(AppDatabase db) async {
  for (final starter in starterExercises) {
    if (starter.barKind == BarKind.none) continue;
    await (db.update(db.exercises)
          ..where(
            (t) =>
                t.starterKey.equals(starter.key) &
                t.barKind.equalsValue(BarKind.none),
          ))
        .write(ExercisesCompanion(barKind: Value(starter.barKind)));
  }
}
