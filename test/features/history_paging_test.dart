import 'package:deltoid/core/providers.dart';
import 'package:deltoid/data/db/database.dart';
import 'package:deltoid/data/repositories/training_repository.dart';
import 'package:deltoid/data/seed/seed_data.dart';
import 'package:deltoid/data/seed/seeder.dart';
import 'package:deltoid/features/history/history_providers.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// `hasMore` has to mean "there is another row", and `items.length >= limit`
/// does not: it is also exactly what the last page of history looks like. The
/// feed offered a `load more` that fetched nothing and then took itself away,
/// on the one screen where the end of the list is a fact worth stating.
void main() {
  late AppDatabase db;
  late TrainingRepository repo;
  late ProviderContainer container;

  final ppl = regimeTemplates.firstWhere((t) => t.key == 'ppl6');

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = TrainingRepository(db);
    await ensureStarterCatalog(db);
    await createRegimeFromTemplate(db, ppl);
    container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
  });

  tearDown(() {
    container.dispose();
    return db.close();
  });

  /// The movement that actually got the set in [logDays] — the first slot of
  /// the session. The others are on the workout and were never worked, and
  /// since they hold no sets they are not performances of anything.
  late String workedExerciseId;

  /// Trains [count] days, one set each, oldest first.
  Future<void> logDays(int count) async {
    final regime = await (db.select(db.regimes)
          ..where((t) => t.isActive.equals(true)))
        .getSingle();
    final session = await (db.select(db.sessions)
          ..where((t) => t.regimeId.equals(regime.id))
          ..limit(1))
        .getSingle();

    for (var i = 0; i < count; i++) {
      final id = await repo.startWorkout(
        regimeId: regime.id,
        sessionId: session.id,
        at: DateTime.now().subtract(Duration(days: count - i)),
      );
      final detail = (await repo.workoutDetail(id))!;
      workedExerciseId = detail.entries.first.exercise.id;
      await repo.updateSet(
        detail.entries.first.sets.first.id,
        weight: const Value(60),
        reps: const Value(8),
        isDone: const Value(true),
      );
      await repo.completeWorkout(id);
    }
  }

  test('a full first page with nothing behind it is the end of history',
      () async {
    await logDays(historyPageSize);

    final page = await container.read(workoutFeedProvider.future);
    expect(page.items, hasLength(historyPageSize));
    expect(page.hasMore, isFalse);
  });

  test('a full first page with one row behind it is not', () async {
    await logDays(historyPageSize + 1);

    final page = await container.read(workoutFeedProvider.future);
    expect(page.items, hasLength(historyPageSize));
    expect(page.hasMore, isTrue);
  });

  test('the last page loaded ends the feed rather than offering another',
      () async {
    await logDays(historyPageSize + 3);

    final notifier = container.read(workoutFeedProvider.notifier);
    await container.read(workoutFeedProvider.future);
    await notifier.loadMore();

    final page = container.read(workoutFeedProvider).value!;
    expect(page.items, hasLength(historyPageSize + 3));
    expect(page.hasMore, isFalse);
  });

  test('one exercise\'s history pages on the same rule', () async {
    await logDays(historyPageSize);

    final page =
        await container.read(exerciseHistoryProvider(workedExerciseId).future);

    expect(page.items, hasLength(historyPageSize));
    expect(page.hasMore, isFalse);
  });

  test('a set ticked in a live session cannot change the feed', () async {
    await logDays(3);
    final before = await container.read(workoutFeedProvider.future);
    expect(before.items, hasLength(3));

    // The feed reloads on `historyShapeChanges` rather than on every write, so
    // the whole scrolled window is not re-queried once per keystroke. That is
    // only safe while this holds: a session being logged is `inProgress` and
    // the feed shows completed days, so nothing written into it is in this
    // list. If a set ever becomes editable from history, the narrow stream
    // stops being enough and this test is where it says so.
    final regime = await (db.select(db.regimes)
          ..where((t) => t.isActive.equals(true)))
        .getSingle();
    final session = await (db.select(db.sessions)
          ..where((t) => t.regimeId.equals(regime.id))
          ..limit(1))
        .getSingle();
    final open =
        await repo.startWorkout(regimeId: regime.id, sessionId: session.id);
    final detail = (await repo.workoutDetail(open))!;
    await repo.updateSet(
      detail.entries.first.sets.first.id,
      weight: const Value(80),
      reps: const Value(5),
      isDone: const Value(true),
    );

    final during = await repo.workoutFeed(limit: historyPageSize + 1);
    expect(during.map((w) => w.workout.id), before.items.map((w) => w.workout.id));

    // And finishing it does — that write lands on `workouts`, which the narrow
    // stream watches.
    await repo.completeWorkout(open);
    final after = await repo.workoutFeed(limit: historyPageSize + 1);
    expect(after, hasLength(4));
    expect(after.first.workout.id, open);
  });

  test('a slot that was never worked is not a performance of anything',
      () async {
    await logDays(3);

    // Every other slot of the session was on screen for three days and holds
    // no sets. It still counts as a session trained — you turned up and the row
    // was there — but there is nothing to draw a card from, and one printed
    // "Nothing logged" over a dash where the weight goes.
    final untouched = (await repo.exercisesWithHistory())
        .firstWhere((e) => e.exercise.id != workedExerciseId);
    expect(untouched.timesPerformed, 3);

    final page = await container
        .read(exerciseHistoryProvider(untouched.exercise.id).future);
    expect(page.items, isEmpty);
    expect(page.hasMore, isFalse);
  });
}
