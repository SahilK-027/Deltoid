import 'package:drift/drift.dart';

extension WatchTables on GeneratedDatabase {
  /// Re-runs [load] once immediately, then again after every write to [tables].
  ///
  /// Deliberately built on `tableUpdates` rather than a sentinel
  /// `customSelect('SELECT 1', readsFrom: ...).watch()`: drift only re-emits a
  /// watched query when its *result* changes, and a constant sentinel never
  /// does — so that approach fires exactly once and then goes silent forever.
  Stream<T> watchQuery<T>(
    Iterable<ResultSetImplementation<dynamic, dynamic>> tables,
    Future<T> Function() load,
  ) async* {
    yield await load();
    await for (final _
        in tableUpdates(TableUpdateQuery.onAllTables(tables))) {
      yield await load();
    }
  }
}
