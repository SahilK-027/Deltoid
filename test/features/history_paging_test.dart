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

    final exercise = (await repo.exercisesWithHistory()).first.exercise;
    final page =
        await container.read(exerciseHistoryProvider(exercise.id).future);

    expect(page.items, hasLength(historyPageSize));
    expect(page.hasMore, isFalse);
  });
}
