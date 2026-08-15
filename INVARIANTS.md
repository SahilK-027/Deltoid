# Deltoid — can it corrupt or lose data

## What an invariant is, in this project

A statement about stored data that must be true after every operation, whatever
order the operations came in and whatever was interrupted.

Not a feature, not a preference, not a style. The test is whether a violation
means **the log is wrong** — a set that was performed and is not in the
database, a set that is in the database and was never performed, a number
silently changed under a row nobody edited.

This file asks one question: **can this app lose, silently alter, or corrupt
logged training data?** Its sibling [INTERPRETATION.md](INTERPRETATION.md) asks
whether the number computed *from* that data is the right number. *The row you
wrote is the row you read* is this file. The two share no findings, and a
finding that seems to fit both belongs in whichever one owns the fix.

Anything that cannot corrupt or lose data is not an invariant and belongs in
[DEBT.md](DEBT.md).

## How an entry works

Every entry is numbered, carries `file:line` evidence, is ranked by severity —
**CORRUPTION** (data wrong or lost) / **STALE** (data right, shown wrong) /
**COSMETIC** — and names the executable check that would close it.

**An entry leaves this file when the check it names passes**, not when it feels
handled. Closing one means writing a banner saying how it closed, what the
evidence was, and — the part worth the most — **what the entry itself got wrong**
about its own severity, reachability or evidence. In the round just finished
that happened on twelve of nineteen entries, and those corrections were the
single most valuable output of the exercise.

A closed entry keeps its number. Numbers are cross-referenced from other entries
and from [HARDENING.md](HARDENING.md); renumbering on close breaks all of them.

## The rules the fixing round runs under

From [HARDENING.md § 3](HARDENING.md#stage-3--build-the-net). Not optional.

1. **Every check must fail first.** A test that was green the moment it was
   written proves nothing about the bug it claims to cover. Show the red output
   before the fix. Where a check is genuinely green on arrival — an invariant
   held by inspection, an absence of coverage over correct code — say so, and
   pay the debt with a **perturbation**: break the code deliberately, record
   what the test then said, put it back by re-applying the reverse edit.
2. **Golden values are computed by hand**, never read off a run.
3. **A fixture that cannot feel the bug is not a test.** A hand-computed literal
   over a fixture where an off-by-one changes no number is an assertion, not a
   check. Perturb the code and watch the value move.
4. **One item, one commit**, with `flutter analyze && flutter test` clean before
   each.

---

## The prompt that regenerates this file

Run it after a change large enough to move the storage layer. **The online sync
layer is exactly that change**: it adds a second writer to every syncable table
and turns *two writers to one row* from a double tap into two phones. The
previous round deliberately left its isolation entries open against that day —
they could not be made red until a pull applier existed to make them fail.

```
Read CLAUDE.md, RULES.md, SYNC.md and DEBT.md first, then audit this codebase
for one thing only: can it lose, silently alter, or corrupt logged training
data?

ANALYSE ONLY. Do not fix anything. Do not refactor. The deliverable is
INVARIANTS.md and nothing else.

Produce a finite, numbered catalogue of the data-integrity invariants this app
must hold. For each one give:
  - the invariant, stated so it can be mechanically checked
  - where it is enforced today: a schema CHECK, a partial unique index, a
    transaction, a Dart assert, a test — with file:line — or "nothing enforces
    this"
  - the concrete sequence of user actions that would violate it if unenforced
  - the executable check that would close it (test name + what it asserts),
    and whether that check exists today
  - severity: CORRUPTION (data wrong or lost) / STALE (data right but shown
    wrong) / COSMETIC. Rank the catalogue by this.

Cover at least:
  - Atomicity: every multi-statement mutation that must be all-or-nothing.
    Walk each write path and verify whether it is inside a transaction — do
    not assume it is because it looks like it should be.
  - Durability: what a kill -9 or a battery death mid-session can leave
    behind. Does an interrupted completeWorkout leave a half-finished workout?
    Is the open-workout recovery path correct after an unclean shutdown? Note
    that an in-memory sqlite is always journal_mode = memory, so a durability
    claim has to be read off a real file.
  - Consistency: the invariants the schema does NOT express. Every rule in
    RULES.md that is prose only, and every "never/always/must" comment in
    lib/data/. State whether SQLite would reject a violation or accept it.
  - Isolation: two writers to the same row — a double tap, a provider rebuild,
    a pull applier landing rows while a session is being logged, and a second
    device. For each syncable table, what does the write path do if the same
    row is written twice concurrently?
  - Deletion: soft delete is the rule. Find every hard delete, every read path
    that forgets `deletedAt IS NULL`, and every parent tombstone that does not
    tombstone its children.
  - Backup/restore: can a restore produce a state the app's own invariants
    reject? Does it round-trip exactly — including nulls, enums added later,
    and rows the current schema version does not know about?
  - Snapshot integrity: RULES says WorkoutExercise and SetLog are snapshots.
    Find every write path that could mutate a logged row from programme data.

Rules for the report:
  - Every claim needs file:line evidence. If you cannot point at code, say
    "unverified" rather than asserting it.
  - Distinguish what you PROVED from what you SUSPECT. Mark each.
  - No speculative or stylistic findings. If it cannot corrupt or lose data,
    it belongs in DEBT.md, not here.
  - Where an invariant is already enforced, say so plainly. A short catalogue
    of real holes is worth more than a long one padded with things that are
    fine.

End with: the smallest set of executable checks that, if all passing, would
justify trusting this app with real training data.
```

## Traps this audit has already walked into

Carried forward so the next round does not pay for them twice.

- **Adding a unique index breaks any existing test that constructs the state it
  forbids.** Reuse `test/data/write_integrity_test.dart`'s drop-index / write /
  heal / rebuild-index shape, where the rebuild succeeding *is* the assertion.
- **drift does not emit `customConstraints` into `database.g.dart`.** Prove a
  constraint exists with red→green, never with a grep.
- **A new required column turns every companion that omits it into an analyzer
  error.** That is the feature, not the problem. Fix by deriving the value from
  something already on the row, not by inventing one.
- **No transaction around a backup export.** drift serialises on one connection,
  so a long read inside a transaction blocks the session being logged. Page by
  keyset instead.
- **An in-memory sqlite is always `journal_mode = memory`.** A durability check
  has to open a real file.
- **`Platform.resolvedExecutable` inside `flutter test` is `flutter_tester`, not
  `dart`.** Spawning it with `['run', file]` boots an engine and hangs forever.
- **Never `git checkout -- <file>` to undo a perturbation.** It reverts every
  other uncommitted change in that file too. Re-apply the reverse edit instead.
