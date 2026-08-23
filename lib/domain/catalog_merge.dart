/// Two seeded catalogs into one.
///
/// [SYNC.md § 10](SYNC.md#10-adoption). Install with no signal, train for a
/// month, sign in afterwards: the phone seeded a catalog of its own before it
/// ever met the account's, and the account's was seeded on another phone long
/// ago. Same `starterKey`s, different ids — roughly 120 exercises twice, "Bench
/// Press" under two ids, and a history split across both. That last part is not
/// cosmetic: per-session progression is keyed to an exercise id, which is the
/// one thing this app exists for.
///
/// **Only rows the app seeded are deduplicated.** A row the user created
/// carries no `starterKey` and is never matched by name: two exercises both
/// called `Cable fly` may be two different movements, and only the user knows.
library;

/// What the dedup needs to know about one catalog row.
typedef CatalogRow = ({String id, String? starterKey, int? deletedAt});

/// Which duplicate becomes which, and which rows are left tombstoned.
typedef CatalogMerge = ({
  /// Duplicate exercise id → the id every reference to it moves to.
  ///
  /// Never contains a key that is also a value: the survivor is not repointed
  /// at itself, and a chain cannot form.
  Map<String, String> repoint,

  /// The duplicates, in the order they were found. Each is tombstoned once its
  /// references have moved.
  List<String> tombstone,
});

/// Plans the merge of one catalog that holds each starter movement twice.
///
/// **The survivor is the smallest id among the live rows sharing a key**, which
/// under UUID v7 is the oldest — the one more history is likely already
/// pointing at. Deterministic is the load-bearing half, not oldest: both phones
/// run this over the same union and must reach the same answer without asking
/// each other, or each tombstones the other's survivor and the catalog empties.
///
/// Tombstones are ignored on the way in. A movement the user deleted on one
/// phone is not a duplicate of the live one on the other — it is the same row's
/// own delete, and [SYNC.md § 8](SYNC.md#8-conflict--two-versions-of-one-row)
/// has already decided that on `id`.
CatalogMerge planCatalogMerge(Iterable<CatalogRow> rows) {
  final byKey = <String, List<String>>{};
  for (final row in rows) {
    final key = row.starterKey;
    if (key == null || row.deletedAt != null) continue;
    byKey.putIfAbsent(key, () => []).add(row.id);
  }

  final repoint = <String, String>{};
  final tombstone = <String>[];
  for (final ids in byKey.values) {
    if (ids.length < 2) continue;
    final survivor = ids.reduce((a, b) => a.compareTo(b) <= 0 ? a : b);
    for (final id in ids) {
      if (id == survivor) continue;
      repoint[id] = survivor;
      tombstone.add(id);
    }
  }
  return (repoint: repoint, tombstone: tombstone);
}
