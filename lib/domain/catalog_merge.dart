/// Consolidation of two independently seeded exercise catalogs.
///
/// See [SYNC.md § 10](SYNC.md#10-adoption). A device installed without network
/// access seeds a catalog of its own before it first contacts the account,
/// whose catalog was seeded earlier on another device. The two share
/// `starterKey` values but not ids, producing roughly 120 duplicated exercises,
/// "Bench Press" under two ids, and a training history divided between them.
/// The divided history is the significant consequence: per-session progression
/// is keyed to an exercise id.
///
/// Only rows seeded by the application are deduplicated. A row created by the
/// user carries no `starterKey` and is never matched by name, because two
/// exercises both named `Cable fly` may be distinct movements and only the user
/// can determine that.
library;

/// The fields of a catalog row required by the deduplication.
typedef CatalogRow = ({String id, String? starterKey, int? deletedAt});

/// The planned outcome: which duplicates map to which survivor, and which rows
/// are to be tombstoned.
typedef CatalogMerge = ({
  /// A map from each duplicate exercise id to the id every reference to it is
  /// moved to.
  ///
  /// No key is also a value: a survivor is never repointed at itself, so chains
  /// cannot form.
  Map<String, String> repoint,

  /// The duplicate ids, in discovery order. Each is tombstoned once its
  /// references have been moved.
  List<String> tombstone,
});

/// Plans the consolidation of a catalog containing each starter movement twice.
///
/// The survivor is the smallest id among the live rows sharing a key, which
/// under UUID v7 is the oldest and therefore the one more history is likely to
/// reference. Determinism rather than age is the essential property: both
/// devices run this over the same union and must reach the same result
/// independently, otherwise each tombstones the other's survivor and the
/// catalog is emptied.
///
/// Tombstoned rows are excluded from consideration. A movement deleted on one
/// device is not a duplicate of the live row on the other; it is the same row's
/// own deletion, which
/// [SYNC.md § 8](SYNC.md#8-conflict--two-versions-of-one-row) has already
/// resolved on `id`.
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
