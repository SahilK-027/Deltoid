# The plan to first real data

The order of work between here and trusting this app with a real training
history, and then with sync. Five stages, sequential, each with an exit
criterion that is a **check rather than a feeling**.

This exists because "is it ready yet" has no answer. Asking an AI — or yourself
— to find bugs is an unbounded generator: it can always produce one more, and a
different model produces a different subset, so no amount of reviewing ever
arrives. The way out is to decide *in advance* which properties must hold, make
each one executable, and treat everything else as documented rather than
blocking.

## The rules that make it terminate

1. **Only corruption blocks.** A finding that can lose, silently alter or
   misreport logged data stops the plan. Everything else — jank, an ugly axis, a
   slow query, a missing test — goes to [DEBT.md](DEBT.md) and ships. Most
   findings are the second kind, which is why the stream feels endless while
   nothing in it is actually stopping you.
2. **A finding is answered when it is executable, not when it is fixed.** A bug
   fixed by hand can regress and be re-found by the next reviewer. A bug turned
   into a test that failed first is answered permanently, for every future
   reviewer, for free. Judge a stage by the tests it added.
3. **Analysis and fixing are separate stages, deliberately.** Auditing and
   repairing in one pass means the list is never seen whole and the ranking is
   never argued with. Stage 2 produces documents and changes no code.
4. **No stage starts before the one above it has passed its exit criterion**,
   and no exit criterion is "it looks fine now".

## What this plan does not promise

It will not produce a review where nothing is found — nothing will, and holding
out for that is the trap this document exists to escape. What it produces is a
finite list of the properties that matter, an executable check for each, and
evidence in the form of a number rather than an opinion.

---

## Stage 1 — Make the gate real

**Why first**: it is an hour, and it protects every stage after it, including the
tests the later stages are about to write. [DEBT.md § 2](DEBT.md).

- A pre-push hook running `flutter analyze && flutter test`.
- Turn on the lints that are free enforcement: `unawaited_futures` above all —
  in a codebase this full of `Future`-returning repository calls, a dropped
  `await` is a write that silently does not happen — plus `prefer_final_locals`
  and `always_declare_return_types`.
- Fix whatever the new lints surface.

**Exit**: a deliberately broken test cannot be pushed, and `flutter analyze` is
clean under the new rules.

---

## Stage 2 — The two audits

Analysis only. **No fixes, no refactors.** Two documents come out of this stage
and nothing else. Together they are the real content of [DEBT.md § 1](DEBT.md) —
that entry says load-bearing rules need mechanisms but does not say *which*
rules, and this is what produces the list.

### 2a. `INVARIANTS.md` — can it corrupt or lose data

Atomicity, durability, consistency, isolation, deletion, backup/restore,
snapshot integrity. Every entry: the invariant stated so it can be checked
mechanically, where it is enforced today (`file:line`) or "nothing enforces
this", the action sequence that would violate it, the executable check that
would close it, and a severity of CORRUPTION / STALE / COSMETIC.

Start from the six methods that write more than once and may or may not be
inside a caller's transaction — verify each rather than assuming:
`ensureOpenCycle`, `_healDuplicateOpenCycles`, `logBodyweight`,
`completeWorkout`, `_tombstoneChildren`, `createExercise`.

### 2b. `INTERPRETATION.md` — are the numbers right

Different audit, different technique. Storage integrity says the row you wrote
is the row you read; this asks whether the number on the screen is the right
number. Cover `resolvePrefill`, `effectiveLoad` across all four load modes,
`scorePerformance`, `bodyweightOnOrdered`, `bucketize`, `foldWeeks`,
`countsAsVolume` and the muscle snapshot fallback, cycle and deload scheduling,
every day-key and week-boundary calculation, and the backup round-trip.

**And flag every existing test whose expected value is produced by calling the
function under test, or by re-implementing its formula.** Those prove the code
is self-consistent, not that it is correct. They are the quiet majority of
"covered" behaviour in most projects and there will be some here, including in
tests written recently.

**Exit**: both documents exist; every claim carries `file:line` or is marked
unverified; every entry is ranked; the CORRUPTION tier is small enough to read
in one sitting and has been read.

---

## Stage 3 — Build the net

Now fix, in severity order, and only the CORRUPTION tier. Everything below it
moves to DEBT.md untouched.

- **Every check must fail before it passes.** A test that never failed proves
  nothing about the bug it claims to cover — write it, watch it go red against
  today's code, then fix.
- **Golden values are computed by hand**, in a spreadsheet or on paper, and
  typed in as literals. `80kg × 8` → Epley `80 × (1 + 8/30)` = `101.33`. Never
  `expect(f(x), f(x))`.
- Replace every UNVERIFIED test 2b found.

**Exit**: every CORRUPTION entry has a check that was demonstrably red first;
no UNVERIFIED tests remain in the derived-value paths.

### 3b. The fuzz harness

The one piece of work that generates evidence instead of opinion, and the reason
the cycle stops here rather than continuing forever.

`test/integrity/model_fuzz_test.dart`: a seeded random-operation harness driving
the real database and a plain in-memory model of what should be true. Start and
abandon and complete workouts, tick and untick sets, edit programmes, backdate,
delete, log and delete bodyweight, advance cycles, back up and restore. After
**every** operation, assert the model and the database agree and that every
`INVARIANTS.md` invariant holds. Seeded, so a failure replays exactly.

Add crash injection: kill the process mid-transaction, reopen, assert the
invariants survived. That is what durability means on a phone with a flat
battery.

**Exit**: a long run — millions of operations — with zero violations. This is
optional before stage 4 and **mandatory before 5b**, because two writers with no
property testing is exactly how histories get corrupted quietly.

---

## Stage 4 — The rest of the debt

[DEBT.md](DEBT.md) §3, §4, §5, §7, §8, §9 — the query rewrites, the provider
lifetimes, the painter bounds, the comment hygiene.

These come *after* stage 3 for one specific reason: §3 and §4 are **rewrites of
code that reads your data**, and a rewrite without invariant coverage is how
silent data bugs are introduced. The evidence is in this repository's own
history — the `setsByMuscleDaily` conversion shipped an ambiguous-column bug
caught only because two tests happened to cover it, and the `exerciseProgress`
conversion needed a throwaway harness comparing old and new output point for
point, because nothing in the suite would have caught a subtly different number.
Stage 3 makes that harness permanent and automatic. §3 asks for that same
conversion up to thirty-four more times.

**Exit**: DEBT.md is empty except § 6, which cannot close until the app is used.

---

## Stage 5 — Sync, in two halves

[SYNC.md](SYNC.md) makes two separate promises, and they carry very different
risk. Ship them separately.

### 5a. Push-only backup

*"A backup you do not have to remember to take"* — SYNC.md's own first line, and
the property that makes it safe to keep a real history here at all.

Auth, upload dirty rows, download-to-restore. **No merge and no conflict
resolution, because there is exactly one writer** — which means the entire
edge-case table in SYNC.md § 12 does not apply yet. Much of it exists already:
every syncable row carries `deviceId`, `updatedAt` and `dirty`, and
`BackupService` already serialises and restores the whole database with tests.

**Exit**: the restore drill, performed by hand on a second physical device —
back up, install clean, restore, compare. Not a test that says it works; you
doing it.

### 5b. The second writer

Bidirectional merge and SYNC.md § 12's rules, with the invariant catalogue in
hand and the fuzz harness extended to two simulated devices.

**Exit**: the two-device fuzz run is clean, and every row of § 12's edge-case
table is a passing test — which SYNC.md already asks for.

---

## Then

Start logging real data, keeping a parallel record for one training block. At
the end of the block, compare. That is ground truth, it costs no engineering,
and it ends the argument in whichever direction it goes.

§ 6 of DEBT.md closes as it is used, or by deleting what turns out not to be
worth using. That is the last entry, and using the app is the only thing that
can close it.
