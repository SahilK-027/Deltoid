import 'dart:io';

import 'package:deltoid/data/db/database.dart';
import 'package:deltoid/data/db/table_spec.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// The server schema against the local one, read off the migrations.
///
/// Two schemas that must agree forever will not, unless something reads both.
/// A column added to `tables.dart` and forgotten in `supabase/migrations` is
/// the quietest failure sync has: the push sends a key PostgREST does not know,
/// and depending on the day that is a rejected batch or a value that simply
/// never arrives — on a server holding the only cloud copy of a history.
///
/// This is a text check rather than a live one on purpose. `supabase test db`
/// proves the policies against a real Postgres and needs Docker; this proves
/// the *shape* and runs in `flutter test`, which is what makes it a gate rather
/// than something remembered before a release.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  /// Every migration, in the order Postgres would apply them.
  String migrations() {
    final dir = Directory('supabase/migrations');
    expect(dir.existsSync(), isTrue,
        reason: 'the server schema lives in the repo — SYNC.md § 16');
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.sql'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    return files.map((f) => f.readAsStringSync()).join('\n');
  }

  /// What the migrations say a table's columns are: `create table` plus any
  /// later `alter table … add column`, which is how a column arrives once the
  /// first migration has shipped.
  Map<String, String> declaredColumns(String sql, String table) {
    final columns = <String, String>{};

    final create = RegExp(
      'create table if not exists public\\.$table\\s*\\(([\\s\\S]*?)\\n\\);',
    ).firstMatch(sql);
    expect(create, isNotNull, reason: 'no create table for $table');

    for (final line in create![1]!.split('\n')) {
      final trimmed = line.trim().replaceAll(RegExp(r',$'), '');
      if (trimmed.isEmpty || trimmed.startsWith('--')) continue;
      if (trimmed.startsWith('primary key')) continue;
      final parts = trimmed.split(RegExp(r'\s+'));
      columns[parts.first] = parts.skip(1).join(' ');
    }

    final added = RegExp(
      'alter table public\\.$table\\s+add column (?:if not exists )?(\\S+) '
      '([^;]+);',
    );
    for (final match in added.allMatches(sql)) {
      columns[match[1]!] = match[2]!.trim();
    }
    return columns;
  }

  /// The Postgres type a drift column crosses the wire as.
  ///
  /// `bigint` for every integer because they are epoch milliseconds — `integer`
  /// overflows in 1970 + 24 days. `double precision` rather than `numeric`
  /// because the local column is a Dart double and a round trip through an
  /// exact type is a false promise.
  String postgresTypeOf(GeneratedColumn<Object> column) => switch (column.type) {
        DriftSqlType.string => 'text',
        DriftSqlType.int => 'bigint',
        DriftSqlType.bool => 'boolean',
        DriftSqlType.double => 'double precision',
        _ => throw StateError('no server type for ${column.type}'),
      };

  test('every syncable table is declared server-side, column for column', () {
    final sql = migrations();

    for (final spec in tableSpecs(db).where((s) => s.syncs)) {
      final declared = declaredColumns(sql, spec.name);

      for (final column in spec.table.$columns) {
        final definition = declared[column.name];
        expect(definition, isNotNull,
            reason: '${spec.name}.${column.name} exists locally and not on the '
                'server. A push sends every key of the row.');

        expect(definition, startsWith(postgresTypeOf(column)),
            reason: '${spec.name}.${column.name} is '
                '${postgresTypeOf(column)} locally');

        expect(definition!.contains('not null'), !column.$nullable,
            reason: '${spec.name}.${column.name} disagrees about nullability, '
                'and the server is the end that cannot be fixed by a rebuild');
      }

      // The two the server adds, and no others: a column the phone has never
      // heard of is ignored on the way in (SYNC § 14), but one the *server*
      // requires and the phone cannot supply rejects the row forever.
      expect(
        declared.keys.toSet().difference(
              spec.table.$columns.map((c) => c.name).toSet(),
            ),
        {'user_id', 'server_updated_at'},
        reason: '${spec.name} carries a server column the design does not name',
      );
    }
  });

  test('app_settings is not on the server, and cannot be', () {
    // SYNC § 4, and § 15 rule 8. It holds `device_id`, which is the tie-break
    // last-write-wins breaks on — two phones sharing one would make `deviceId`
    // name a history rather than a writer.
    expect(migrations(), isNot(contains('public.app_settings')));
    expect(tableSpecs(db).where((s) => !s.syncs).map((s) => s.name),
        ['app_settings']);
  });

  test('every syncable table is protected, indexed and stamped', () {
    final sql = migrations();

    for (final spec in tableSpecs(db).where((s) => s.syncs)) {
      expect(sql,
          contains('alter table public.${spec.name} enable row level security'),
          reason: '${spec.name} is readable by anyone holding the anon key');

      // `with check` as well as `using`, or a client can write rows it then
      // cannot read — SYNC § 3.
      final policy = RegExp(
        'create policy "own rows only" on public\\.${spec.name}[\\s\\S]*?;',
      ).firstMatch(sql);
      expect(policy, isNotNull, reason: '${spec.name} has no policy');
      expect(policy![0]!, contains('using (user_id = auth.uid())'));
      expect(policy[0]!, contains('with check (user_id = auth.uid())'));

      // Every pull query there will ever be.
      expect(
        sql,
        contains('on public.${spec.name} (user_id, server_updated_at)'),
        reason: '${spec.name} has no index for the one query a pull makes',
      );

      expect(
        sql,
        contains('before insert or update on public.${spec.name}'),
        reason: '${spec.name} would let a client forge the clock conflicts are '
            'decided on — SYNC § 8',
      );
    }
  });

  test('nothing is granted to anon', () {
    // The anon key is extractable from the APK. With no grant at all it reaches
    // nothing, rather than reaching a table whose policy happens to match no
    // rows — one of those survives a policy being dropped by accident.
    final sql = migrations();
    expect(sql, isNot(contains(' to anon')));
    expect(RegExp('grant [^;]+ to authenticated;').allMatches(sql).length, 10);
  });

  test('the server refuses nothing it cannot un-refuse', () {
    // SYNC § 17: the phone refuses bad rows, the server stores what it is
    // given. A server-side CHECK or foreign key strands the offending row dirty
    // forever, retried by every push, with nothing on the phone able to clear
    // it — the local constraints already refused what could be refused.
    // Comments stripped first: this file explains at length why it holds no
    // CHECK constraints, and the explanation must not read as one.
    final sql = migrations()
        .toLowerCase()
        .split('\n')
        .where((line) => !line.trimLeft().startsWith('--'))
        .join('\n');

    // `with check (…)` is the RLS policy and is required; a bare `check (…)` is
    // a constraint and is not.
    expect(RegExp(r'(?<!with )check \(').hasMatch(sql), isFalse,
        reason: 'a server-side CHECK strands the row it refuses');
    expect(sql, isNot(contains('references ')));
  });
}
