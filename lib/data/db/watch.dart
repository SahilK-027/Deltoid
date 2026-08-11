import 'dart:async';

import 'package:drift/drift.dart';

extension WatchTables on GeneratedDatabase {
  /// Re-runs [load] once immediately, then again after every write to [tables].
  ///
  /// Deliberately built on `tableUpdates` rather than a sentinel
  /// `customSelect('SELECT 1', readsFrom: ...).watch()`: drift only re-emits a
  /// watched query when its *result* changes, and a constant sentinel never
  /// does — so that approach fires exactly once and then goes silent forever.
  ///
  /// **A write that lands while [load] is running is not lost, and a burst of
  /// them costs one extra pass.** This used to be an `async*` loop with an
  /// `await for` over `tableUpdates`, which has both problems: `tableUpdates`
  /// is a broadcast stream, so pausing it — which is exactly what `await for`
  /// does while it waits on `load` — drops whatever arrives in the meantime.
  /// A write that landed during a read therefore left the screen showing the
  /// state from *before* it, with no further event coming to correct it, until
  /// something else happened to write to the same table. Rare with one phone
  /// writing; not rare at all once a sync pull can land a batch of rows in the
  /// middle of a read.
  ///
  /// The subscription here is never paused. Overlapping writes set a flag and
  /// are answered by one more pass after the current one, so a hundred rows
  /// arriving together re-read the screen twice rather than a hundred times.
  Stream<T> watchQuery<T>(
    Iterable<ResultSetImplementation<dynamic, dynamic>> tables,
    Future<T> Function() load,
  ) {
    late StreamController<T> controller;
    StreamSubscription<void>? updates;
    var running = false;
    var again = false;
    var cancelled = false;

    Future<void> run() async {
      // Already reading: let the pass in flight answer for this write too.
      if (running) {
        again = true;
        return;
      }
      running = true;
      try {
        do {
          again = false;
          final value = await load();
          if (cancelled) return;
          controller.add(value);
        } while (again);
      } catch (error, stack) {
        // Reported rather than fatal. The old loop ended the stream on the
        // first failure, which left the screen stuck on whatever it had:
        // a screen that can say "that went wrong" can also recover on the
        // next write.
        if (!cancelled) controller.addError(error, stack);
      } finally {
        running = false;
      }
    }

    controller = StreamController<T>(
      onListen: () {
        updates = tableUpdates(TableUpdateQuery.onAllTables(tables))
            .listen((_) => run());
        run();
      },
      onCancel: () async {
        cancelled = true;
        await updates?.cancel();
      },
    );

    return controller.stream;
  }
}
