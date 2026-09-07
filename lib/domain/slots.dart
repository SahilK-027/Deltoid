/// Returns one past the highest position in [indexes], and never a negative
/// value.
///
/// This is the arithmetic every append in the application performs: one past
/// the highest live position, rather than the count of live rows. It is defined
/// once so that the reorder path and the append path cannot diverge.
///
/// It belongs in `domain/` because a third caller was introduced with the pull
/// applier. [SYNC.md § 9](SYNC.md#9-collision--two-rows-one-slot) resolves a
/// slot claimed by two devices by moving one of them to the next free position,
/// and that must be the same position a local append would have produced. A
/// duplicated implementation is how two answers to one question arise.
/// `data/db/renumber.dart` re-exports this function, so existing callers are
/// unaffected.
int nextPosition(Iterable<int> indexes) =>
    indexes.fold<int>(-1, (m, i) => i > m ? i : m) + 1;
