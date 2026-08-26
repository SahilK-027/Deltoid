import 'package:drift/drift.dart';

import 'database.dart';

/// The ladder: one step per released schema change, and every step idempotent.
///
/// It starts here because **sync is what makes it necessary**
/// ([RULES.md § 3](RULES.md#3-schema-and-migrations),
/// [SYNC.md § 18](SYNC.md#18-the-phases)). Until now a schema change was an
/// edit, a regenerate and a reinstall, which is honest while the only phone
/// running the app is the one it is written on. Sync is precisely the feature
/// that lets a phone on one build exchange rows with a server another build
/// wrote, and a reinstall is not something to ask of a phone that is the only
/// copy of a history.
///
/// **Idempotent, every step, always.** A device handed an earlier
/// build and then the newer one again arrives with the structure already in
/// place and the version stamp behind it — drift replays the step, and
/// `CREATE INDEX` or `ALTER TABLE ADD COLUMN` on something that already exists
/// throws at open, before a single screen is drawn. So: [addColumnIfMissing],
/// never a bare `m.addColumn`; `IF NOT EXISTS`, never a bare `m.createIndex`.
Future<void> upgradeSchema(AppDatabase db, Migrator m, int from, int to) async {
  // 1 → 2 · What is owed, countable without a scan.
  //
  // Nine partial indexes on `dirty`, one per syncable table. Declared in
  // `tables.dart` so a fresh install gets them from `createAll`, and created
  // here for a database that already exists.
  if (from < 2) await createIndexesIfMissing(db, (name) => name.endsWith('_dirty'));

  // 2 → 3 · When a regime was made active, so two phones can agree which is.
  //
  // The flag itself could not be merged — it is one answer spread across every
  // row, and resolving it row by row let two phones settle on opposite ones
  // permanently. `regimes.activated_at` is the fact the flag is derived from;
  // see [Regimes.activatedAt] and `resolveActiveRegime`.
  //
  // **Backfilled onto the regime that is active right now**, because the app
  // already knows the answer and the honest default is only honest for a row
  // nobody has been asked about. Leaving every row null on an existing phone
  // would give the derivation no candidate at all, and the first sync would
  // deactivate the programme the user is in the middle of training.
  //
  // `updated_at` rather than the clock: the row was last written when it was
  // activated or edited, which is nearer the truth than "now", and it keeps the
  // step giving the same answer whenever it happens to run.
  if (from < 3) {
    await addColumnIfMissing(db, m, db.regimes, db.regimes.activatedAt);
    await db.customStatement(
      'UPDATE regimes SET activated_at = updated_at '
      'WHERE is_active = 1 AND deleted_at IS NULL AND activated_at IS NULL',
    );
  }
}

/// `CREATE INDEX IF NOT EXISTS` for every generated index whose name [where]
/// accepts.
///
/// The SQL comes from the generated schema rather than being written out a
/// second time. An index the ladder spells slightly differently from the one
/// `createAll` makes is a database whose shape depends on when it was installed
/// — and the only symptom is a query plan, on one of the two populations.
Future<void> createIndexesIfMissing(
  AppDatabase db,
  bool Function(String name) where,
) async {
  for (final index in db.allSchemaEntities.whereType<Index>()) {
    if (!where(index.entityName)) continue;
    final create = index.createStatementsByDialect[SqlDialect.sqlite]!;
    await db.customStatement(
      create.replaceFirstMapped(
        RegExp(r'^CREATE (UNIQUE )?INDEX '),
        (m) => 'CREATE ${m[1] ?? ''}INDEX IF NOT EXISTS ',
      ),
    );
  }
}

/// `ALTER TABLE … ADD COLUMN`, unless the column is already there.
///
/// SQLite has no `ADD COLUMN IF NOT EXISTS`, so the guard is a read of
/// `pragma_table_info` — cheap, and the alternative is a step that can only be
/// run once in a ladder that must survive being replayed.
Future<void> addColumnIfMissing(
  AppDatabase db,
  Migrator m,
  TableInfo<Table, dynamic> table,
  GeneratedColumn<Object> column,
) async {
  if (await hasColumn(db, table.actualTableName, column.name)) return;
  await m.addColumn(table, column);
}

/// Whether [table] already carries [column], asked of SQLite.
Future<bool> hasColumn(AppDatabase db, String table, String column) async {
  final rows = await db
      .customSelect(
        'SELECT 1 AS present FROM pragma_table_info(?) WHERE name = ?',
        variables: [Variable<String>(table), Variable<String>(column)],
      )
      .get();
  return rows.isNotEmpty;
}
