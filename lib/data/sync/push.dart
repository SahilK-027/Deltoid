import 'package:drift/drift.dart';

import '../db/database.dart';
import '../db/table_spec.dart';
import 'sync_backend.dart';

/// `app_settings` key holding when the last drain finished, in UTC ms.
///
/// Local, like everything in that table: *when this phone last got its rows
/// out* is a fact about this phone. It is written only after a drain finds
/// nothing left owed, so `Synced` means what it says.
const lastPushKey = 'last_push_at';

/// What one drain moved.
typedef PushReport = ({int rows, int batches});

/// Drains `dirty`.
///
/// [SYNC.md § 6](SYNC.md#6-push), which is the whole of this file:
///
/// * Every row where `dirty = true`, oldest `updatedAt` first.
/// * Parents before children, in registry order, which a restore already
///   depends on — so foreign keys hold server-side at every intermediate point.
///   The server declares none, deliberately, but a pull on the *other* phone
///   applies what it finds and a child that arrives before its parent is a row
///   `healOrphanedSnapshots` then tombstones.
/// * Batched upserts on `id`. These are idempotent, so a device terminated
///   mid-push
///   retries for free — edge case 12.
/// * `dirty` is cleared only against an unchanged `updatedAt`. A row edited
///   while its own push was in flight is still owed, and clearing it on the
///   response would strand that edit on the phone forever — invisibly, because
///   nothing downstream ever looks at a row that is not dirty.
///
/// Three transactions rather than one
/// ([SYNC.md § 17](SYNC.md#17-the-architecture)).
/// Read the batch and close; call the network holding nothing; write the result
/// and close. There is one connection with `busy_timeout = 5000`, and a
/// transaction held across a round trip is a screen frozen on a background job
/// — the exact thing offline-first exists to prevent, arriving through the back
/// door.
class PushService {
  PushService(this._db, this._backend, {this.batchSize = 400});

  final AppDatabase _db;
  final SyncBackend _backend;

  /// Rows per request. Small enough that a failure re-sends little and a
  /// half-finished drain leaves most of the queue untouched; large enough that
  /// a first push of a decade of training is hundreds of requests rather than
  /// hundreds of thousands.
  final int batchSize;

  Future<PushReport> drain() async {
    var rows = 0;
    var batches = 0;

    // Forwards down the registry: parents before children.
    for (final spec in tableSpecs(_db).where((s) => s.syncs)) {
      _Cursor? after;
      while (true) {
        final batch = await _owed(spec, after: after);
        if (batch.isEmpty) break;

        await _backend.upsert(
          spec.name,
          [for (final row in batch) wireRow(row.json)],
        );
        await _clearDirty(spec, batch);

        rows += batch.length;
        batches++;
        // Keyset paging rather than re-reading from the start. A row cleared
        // by this pass
        // leaves the `dirty` set, but one edited mid-flight does not — and
        // re-reading from the beginning would hand it back forever while the
        // user kept typing. The cursor only ever moves forward, so a drain
        // ends whatever else is happening to the database.
        after = batch.last.cursor;
        if (batch.length < batchSize) break;
      }
    }

    if (rows > 0) await _stampLastPush();
    return (rows: rows, batches: batches);
  }

  /// One page of owed rows, oldest `updatedAt` first, `id` breaking the tie so
  /// the keyset is total.
  ///
  /// Generic over the table by column name rather than by generated accessor:
  /// nine typed copies of this query is nine places for the next syncable table
  /// to be forgotten.
  Future<List<_Owed>> _owed(TableSpec spec, {_Cursor? after}) async {
    final columns = spec.table.columnsByName;
    final dirty = columns['dirty']! as GeneratedColumn<bool>;
    final updatedAt = columns['updated_at']! as GeneratedColumn<int>;
    final id = columns['id']! as GeneratedColumn<String>;

    var filter = dirty.equals(true);
    if (after != null) {
      filter = filter &
          (updatedAt.isBiggerThanValue(after.updatedAt) |
              (updatedAt.equals(after.updatedAt) &
                  id.isBiggerThanValue(after.id)));
    }

    final query = _db.select(spec.table)
      ..where((_) => filter)
      ..orderBy([
        (_) => OrderingTerm(expression: updatedAt),
        (_) => OrderingTerm(expression: id),
      ])
      ..limit(batchSize);

    final rows = await query.get();
    return [
      for (final row in rows) _owedOf((row as DataClass).toJson()),
    ];
  }

  _Owed _owedOf(Map<String, dynamic> json) => (
        json: json,
        cursor: (
          updatedAt: json['updatedAt'] as int,
          id: json['id'] as String,
        ),
      );

  /// Clears `dirty` for the rows that have not moved since they were read.
  ///
  /// One statement per row rather than an `IN` list, because the condition is
  /// per row: the id *and* the `updatedAt` it was read at. A single batch, so
  /// it is one round trip to SQLite whatever the page holds.
  ///
  /// This write does not stamp anything. `dirty` is bookkeeping about the
  /// server, not an edit, and bumping `updatedAt` here would make every push
  /// generate the next one ([SYNC.md § 17](SYNC.md#17-the-architecture) — what
  /// must never be re-stamped).
  Future<void> _clearDirty(TableSpec spec, List<_Owed> batch) {
    return _db.batch((b) {
      for (final row in batch) {
        b.customStatement(
          'UPDATE ${spec.name} SET dirty = 0 WHERE id = ? AND updated_at = ?',
          [row.cursor.id, row.cursor.updatedAt],
        );
      }
    });
  }

  Future<void> _stampLastPush() {
    return _db.into(_db.appSettings).insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: lastPushKey,
            value: '${DateTime.now().toUtc().millisecondsSinceEpoch}',
          ),
        );
  }
}

/// Where a page resumes: the last row's `(updatedAt, id)`.
typedef _Cursor = ({int updatedAt, String id});

typedef _Owed = ({Map<String, dynamic> json, _Cursor cursor});
