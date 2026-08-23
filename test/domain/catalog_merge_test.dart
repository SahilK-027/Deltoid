import 'package:deltoid/domain/catalog_merge.dart';
import 'package:flutter_test/flutter_test.dart';

/// Two seeded catalogs into one, as arithmetic and no database.
///
/// [SYNC.md § 10](SYNC.md#10-adoption). The rule that matters is not *oldest
/// wins* but *both phones reach the same answer without asking each other*: a
/// dedup that disagrees with itself across two devices tombstones both
/// survivors and empties the catalog.
void main() {
  CatalogRow row(String id, String? key, {int? deleted}) =>
      (id: id, starterKey: key, deletedAt: deleted);

  test('the same starter key twice folds onto the smaller id', () {
    final plan = planCatalogMerge([
      row('01a', 'bench_press'),
      row('02b', 'bench_press'),
    ]);

    expect(plan.repoint, {'02b': '01a'});
    expect(plan.tombstone, ['02b']);
  });

  test('a survivor is never repointed at itself, and no chain forms', () {
    final plan = planCatalogMerge([
      row('01a', 'squat'),
      row('02b', 'squat'),
      row('03c', 'squat'),
    ]);

    expect(plan.repoint, {'02b': '01a', '03c': '01a'});
    expect(plan.repoint.keys, isNot(contains('01a')));
    for (final target in plan.repoint.values) {
      expect(plan.repoint.containsKey(target), isFalse);
    }
  });

  test("rows the user made carry no key and are never merged by name", () {
    final plan = planCatalogMerge([
      row('01a', null),
      row('02b', null),
    ]);

    expect(plan.repoint, isEmpty);
    expect(plan.tombstone, isEmpty);
  });

  test('a tombstone is not a duplicate of the live row beside it', () {
    final plan = planCatalogMerge([
      row('01a', 'row', deleted: 1000),
      row('02b', 'row'),
    ]);

    expect(plan.repoint, isEmpty);
  });

  test('two phones over the same union reach the same answer', () {
    final union = [
      row('03c', 'curl'),
      row('01a', 'curl'),
      row('02b', 'press'),
      row('04d', 'press'),
    ];
    final a = planCatalogMerge(union);
    final b = planCatalogMerge(union.reversed);

    expect(a.repoint, b.repoint);
    expect(a.tombstone.toSet(), b.tombstone.toSet());
  });

  test('one of a kind is left alone', () {
    expect(planCatalogMerge([row('01a', 'dip')]).repoint, isEmpty);
  });
}
