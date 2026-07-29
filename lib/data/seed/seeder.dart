import 'package:drift/drift.dart';

import '../../core/ids.dart';
import '../db/database.dart';
import 'seed_data.dart';

/// Fills the exercise catalog on first launch and nothing else.
///
/// No regime is created: which split the user trains is theirs to decide, and
/// an app that invents one leaves them deleting somebody else's programme
/// before they can start. Idempotent — skipped entirely once any exercise
/// exists.
Future<void> ensureStarterCatalog(AppDatabase db) async {
  final existing = await db.select(db.exercises).get();
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
            ),
          );
    }
  });
}

/// Writes [template] as a real regime: ordinary sessions and slots, editable
/// like any other. Returns the new regime's id.
///
/// Catalog rows are matched by name and created when missing, so a template
/// picked after the user has already renamed or archived things doesn't
/// duplicate half the catalog.
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
    final starterByKey = {for (final e in starterExercises) e.key: e};

    Future<String> exerciseIdFor(String key) async {
      final starter = starterByKey[key];
      if (starter == null) {
        throw StateError('Template "${template.key}" references unknown '
            'exercise key "$key"');
      }
      final existing = idByName[starter.name];
      if (existing != null) return existing;

      final id = newId();
      await db.into(db.exercises).insert(
            ExercisesCompanion.insert(
              id: Value(id),
              name: starter.name,
              muscle: starter.muscle,
              equipment: starter.equipment,
              loadMode: starter.loadMode,
            ),
          );
      idByName[starter.name] = id;
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
