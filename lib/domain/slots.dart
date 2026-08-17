/// One past the highest position in [indexes], and never negative.
///
/// The same arithmetic every append in the app already does — "one past the
/// highest live position, not the number of live rows" — named once so the
/// reorder path and the append path cannot drift apart.
///
/// It lives in `domain/` because a third caller arrived with the pull applier:
/// [SYNC.md § 9](SYNC.md#9-collision--two-rows-one-slot) resolves a slot two
/// devices both claimed by moving one of them to the next free position, and
/// that must be the *same* next free position a thumb would have been given. A
/// second copy of one line is how two answers to one question begin.
/// `data/db/renumber.dart` re-exports it, so every caller that had it before
/// still does.
int nextPosition(Iterable<int> indexes) =>
    indexes.fold<int>(-1, (m, i) => i > m ? i : m) + 1;
