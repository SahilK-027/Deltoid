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
