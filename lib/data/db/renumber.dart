/// Rewriting a run of positions without ever holding two rows on one.
///
/// Sessions, session slots, workout slots and sets all carry an `orderIndex`
/// that is unique among the live rows of their parent, enforced by a partial
/// index in `tables.dart`. That constraint is what stops an append from landing
/// on a position a tombstoned row left behind — and it is checked on every
/// statement, not at the end of the transaction, so the obvious way to apply a
/// new order breaks against it.
///
/// The obvious way is one pass: walk the list, write `i` to the row that should
/// end up at `i`. Move the second row to the front and the very first write puts
/// it on position 0 while the row already there still holds it. SQLite refuses,
/// mid-transaction, and the reorder rolls back — for a permutation that is
/// perfectly legal once it has finished.
///
/// So it goes in two passes through a range nothing is standing in. The scratch
/// range starts one past the highest live position in the scope, so the first
/// pass lands every row somewhere free, and the second brings them down to
/// `0..n-1` over ground the first pass has just vacated. Twice the writes,
/// inside one transaction, for a list the length of a training day.
///
/// [scope] is every live row under the parent — id to current position — read
/// inside the same transaction as the writes. It is not a convenience: both
/// passes depend on it. The first needs the highest position in the *whole*
/// scope to clear, and the second writes `0..n-1`, which belongs to the caller
/// only if [orderedIds] is the whole scope. A partial list is not a permutation,
/// so one that does not name exactly [scope] is refused here rather than
/// several writes later.
///
/// Both halves of that used to be the caller's problem, stated in prose. Handing
/// a short list to the old signature failed one of two ways: on the unique index
/// with a message about nothing the caller did wrong, or — when the omitted row
/// sat above everything the second pass wrote — not at all, reporting success
/// for a scope it only partly knew about.
Future<void> renumber(
  List<String> orderedIds, {
  required Map<String, int> scope,
  required Future<void> Function(String id, int orderIndex) write,
}) async {
  if (orderedIds.length != scope.length ||
      !orderedIds.toSet().containsAll(scope.keys)) {
    throw StateError(
      'renumber was handed ${orderedIds.length} of ${scope.length} live rows; '
      'a reorder must name every row in its scope. '
      'Missing: ${scope.keys.where((id) => !orderedIds.contains(id)).toList()}',
    );
  }

  final from = nextPosition(scope.values);
  for (var i = 0; i < orderedIds.length; i++) {
    await write(orderedIds[i], from + i);
  }
  for (var i = 0; i < orderedIds.length; i++) {
    await write(orderedIds[i], i);
  }
}

/// One past the highest position in [indexes], and never negative.
///
/// The same arithmetic every append in the app already does — "one past the
/// highest live position, not the number of live rows" — named once so the
/// reorder path and the append path cannot drift apart.
int nextPosition(Iterable<int> indexes) =>
    indexes.fold<int>(-1, (m, i) => i > m ? i : m) + 1;
