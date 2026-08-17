import 'package:deltoid/data/db/table_spec.dart';
import 'package:deltoid/data/sync/sync_backend.dart';

/// The server, in memory, with its own monotonic clock and a way to misbehave.
///
/// [SYNC.md § 17](SYNC.md#17-the-architecture) calls this the point of putting
/// the transport behind an interface: *drop the response after committing the
/// write, hand back a row from a newer build, fail every third call* is what
/// makes [SYNC.md § 12](SYNC.md#12-every-edge-case-and-what-it-does) testable at
/// all. No test in this repo talks to a real Supabase.
class FakeBackend implements SyncBackend {
  /// table → id → row, exactly as it was sent, plus the stamp this clock put on
  /// it.
  final rows = <String, Map<String, Map<String, dynamic>>>{};

  /// Every upsert, in the order it arrived, holding exactly what was sent —
  /// before this fake stamps the two columns a server adds. Parents before
  /// children is read off this, and so is what the wire did not carry.
  final calls = <({String table, List<Map<String, dynamic>> rows})>[];

  /// Thrown instead of the next request, whatever it is.
  Object? failWith;

  /// Thrown on every request until it is cleared.
  Object? failEverything;

  /// Runs after a batch has been stored and before [upsert] returns, so a test
  /// can write to the database mid-flight — or throw, which is a phone killed
  /// after the server committed.
  Future<void> Function(String table, List<Map<String, dynamic>> rows)?
      onStored;

  int _clock = 0;

  int get storedRows =>
      rows.values.fold(0, (total, table) => total + table.length);

  List<Map<String, dynamic>> table(String name) =>
      rows[name]?.values.toList() ?? const [];

  DateTime _stamp() =>
      DateTime.fromMillisecondsSinceEpoch(++_clock * 1000, isUtc: true);

  void _maybeFail() {
    final one = failWith;
    if (one != null) {
      failWith = null;
      throw one;
    }
    final always = failEverything;
    if (always != null) throw always;
  }

  @override
  Future<void> upsert(String table, List<Map<String, dynamic>> batch) async {
    _maybeFail();
    calls.add((
      table: table,
      rows: [for (final row in batch) Map<String, dynamic>.from(row)],
    ));
    final store = rows.putIfAbsent(table, () => {});
    for (final row in batch) {
      store[row['id'] as String] = {
        ...row,
        serverUpdatedAtColumn: _stamp().toIso8601String(),
        'user_id': 'the-account',
      };
    }
    await onStored?.call(table, batch);
  }

  @override
  Future<List<Map<String, dynamic>>> since(
    String table,
    DateTime? cursor, {
    required int limit,
  }) async {
    _maybeFail();
    final all = this.table(table).toList()
      ..sort(
        (a, b) => (a[serverUpdatedAtColumn] as String)
            .compareTo(b[serverUpdatedAtColumn] as String),
      );
    final stamp = cursor?.toUtc().toIso8601String();
    // `gte`, not `gt` — SYNC.md § 17.
    final since = stamp == null
        ? all
        : all
            .where((r) => (r[serverUpdatedAtColumn] as String).compareTo(stamp) >= 0)
            .toList();
    return since.take(limit).toList();
  }

  @override
  Future<int> count(String table) async {
    _maybeFail();
    return this.table(table).length;
  }
}
