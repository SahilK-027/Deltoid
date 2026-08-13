# Hardening — the road to first real data

The order of work between here and trusting this app with a real training
history, and then with sync. Five stages, sequential, each with an exit
criterion that is a **check rather than a feeling**, and each with the prompt
that runs it.

**This document retires.** It is one campaign with an end, not a roadmap — when
stage 5 passes and DEBT.md is empty, delete it. What comes after lives in
[TODO.md](TODO.md), which is still the only place status lives.

This exists because "is it ready yet" has no answer. Asking an AI — or yourself
— to find bugs is an unbounded generator: it can always produce one more, and a
different model produces a different subset, so no amount of reviewing ever
arrives. The way out is to decide *in advance* which properties must hold, make
each one executable, and treat everything else as documented rather than
blocking.

**How to use it.** One stage at a time, each in a fresh session, by pasting the
prompt. They are written to stand alone — a new session reads `CLAUDE.md`
automatically and each prompt names whatever else it needs. Do not run two
stages in one session: the point of the split is that a stage's output gets
read before the next one starts.

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

**Why first**: it is an hour, and it protects every stage after it, including
the tests the later stages are about to write. [DEBT.md § 2](DEBT.md).

**Exit**: a deliberately broken test cannot be pushed, and `flutter analyze` is
clean under the new rules.

```
Read DEBT.md § 2, then close it.

1. Add a pre-push git hook that runs `flutter analyze && flutter test` and
   refuses the push on failure. Keep it in the repo (a `hooks/` directory plus
   a one-line install command in README.md), because .git/hooks is not
   version-controlled. Make it skippable only via --no-verify.

2. Turn on these lints in analysis_options.yaml: unawaited_futures,
   prefer_final_locals, always_declare_return_types, avoid_slow_async_io.
   unawaited_futures is the one that matters — in a codebase this full of
   Future-returning repository calls, a dropped await is a write that silently
   does not happen.

3. Fix every violation. Where `unawaited_futures` fires, decide case by case
   whether the await was genuinely missing (a bug — say so explicitly in your
   report) or whether the future is deliberately not awaited (then mark it
   `unawaited(...)` rather than silencing the lint).

Report separately: violations that were real bugs, versus ones that were
stylistic. Then prove the hook works by making a test fail and attempting a
push.
```

---

## Stage 2 — The two audits

Analysis only. **No fixes, no refactors.** Two documents come out of this stage
and nothing else. Together they are the real content of
[DEBT.md § 1](DEBT.md) — that entry says load-bearing rules need mechanisms but
does not say *which* rules, and this is what produces the list.

**Exit**: both documents exist; every claim carries `file:line` or is marked
unverified; every entry is ranked; the CORRUPTION tier is small enough to read
in one sitting and has been read.

### 2a — `INVARIANTS.md`: can it corrupt or lose data

```
Read CLAUDE.md, RULES.md, SYNC.md and DEBT.md first, then audit this codebase
for one thing only: can it lose, silently alter, or corrupt logged training
data?

ANALYSE ONLY. Do not fix anything. Do not refactor. The deliverable is a new
file, INVARIANTS.md, and nothing else.

Produce a finite, numbered catalogue of the data-integrity invariants this app
must hold. For each one give:
  - the invariant, stated so it can be mechanically checked
  - where it is enforced today: a schema CHECK, a transaction, a Dart assert,
    a test — with file:line — or "nothing enforces this"
  - the concrete sequence of user actions that would violate it if unenforced
  - the executable check that would close it (test name + what it asserts),
    and whether that check exists today
  - severity: CORRUPTION (data wrong or lost) / STALE (data right but shown
    wrong) / COSMETIC. Rank the catalogue by this.

Cover at least:
  - Atomicity: every multi-statement mutation that must be all-or-nothing.
    Start from these, which write 2+ times and may or may not be inside a
    caller's transaction — verify each, do not assume: ensureOpenCycle,
    _healDuplicateOpenCycles, logBodyweight, completeWorkout,
    _tombstoneChildren, createExercise.
  - Durability: what a kill -9 or a battery death mid-session can leave behind.
    Does an interrupted completeWorkout leave a half-finished workout? Is the
    open-workout recovery path correct after an unclean shutdown?
  - Consistency: the invariants the schema does NOT express. Every rule in
    RULES.md that is prose only, and every "never/always/must" comment in
    lib/data/. State whether SQLite would reject a violation or accept it.
  - Isolation: two writers to the same row. Today that is a double tap or a
    provider rebuild; after SYNC.md it is a second device. For each syncable
    table, what does the current write path do if the same row is written
    twice concurrently?
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

### 2b — `INTERPRETATION.md`: are the numbers right

A different audit with a different technique. Storage integrity says the row you
wrote is the row you read; this asks whether the number on the screen is the
right number.

```
Audit the correctness of every derived number this app displays. Not storage
integrity — arithmetic. ANALYSE ONLY; the deliverable is INTERPRETATION.md and
nothing else.

For each derived value state: the rule it should implement (in words), where it
is implemented (file:line), the inputs that would expose it being wrong, and
whether a test asserts the value against a HAND-COMPUTED expectation.

Cover at minimum:
  - resolvePrefill: session-scoped progression. The app's reason to exist.
  - effectiveLoad across all four LoadModes, including addedWeight and a null
    bodyweight.
  - scorePerformance: top set, e1RM (Epley, reps capped at 12), volume, and
    which SetTypes count.
  - bodyweightOnOrdered: interpolation, and behaviour outside the series.
  - bucketize: mean vs sum, empty buckets, rows on a boundary day.
  - foldWeeks: sets-per-week across granularities.
  - countsAsVolume and the workout_exercises.muscle snapshot fallback.
  - cycle advance and deload scheduling.
  - dayKey <-> DateTime, week starts, and every calculation crossing a DST
    boundary or a leap day.
  - backup round-trip: does every field survive exactly.

Flag every test whose expected value is computed by calling the same function
under test, or by re-implementing its formula in the test. Those prove the code
is self-consistent, not that it is right. List them as UNVERIFIED — they are the
quiet majority of "covered" behaviour in most projects and there will be some
here, including in tests written recently.

Rank by: how wrong the displayed number could be, and how long it would take a
user to notice.
```

---

## Stage 3 — Build the net

Fix, in severity order, and only the CORRUPTION tier. Everything below it moves
to DEBT.md untouched.

**Exit**: every CORRUPTION entry has a check that was demonstrably red first; no
UNVERIFIED tests remain in the derived-value paths.

```
Read INVARIANTS.md and INTERPRETATION.md.

Implement the checks for every CORRUPTION-severity entry, highest first, and
nothing below that tier. If you believe a lower-severity entry is misranked,
say so and stop — do not promote it yourself.

Two rules, both absolute:

1. EVERY CHECK MUST FAIL FIRST. Write the test, run it against the current
   code, and show me the failure output before you change any lib/ code. A test
   that was green the moment it was written proves nothing about the bug it
   claims to cover. If a check passes immediately, that entry was wrong about
   there being a hole — record that in INVARIANTS.md and move on.

2. GOLDEN VALUES ARE COMPUTED BY HAND. Work the arithmetic out yourself, show
   the working in a comment, and type the result in as a literal:
   80kg x 8 reps -> Epley 80 * (1 + 8/30) = 101.33. Never
   expect(f(x), f(x)), and never re-implement the formula in the test.

Then replace every test INTERPRETATION.md marked UNVERIFIED with a
hand-computed literal, same rules.

Work in small commits, one entry per commit, each naming the invariant it
closes. Update INVARIANTS.md as you go: an entry leaves the CORRUPTION tier
when its check is passing, not when the fix feels done.
```

### 3b — The fuzz harness

The one piece of work that generates evidence instead of opinion, and the reason
the cycle stops here rather than continuing forever.

**Exit**: a long run — millions of operations — with zero violations. Optional
before stage 4; **mandatory before 5b**, because two writers with no property
testing is exactly how histories get corrupted quietly.

```
Read INVARIANTS.md.

Build test/integrity/model_fuzz_test.dart: a seeded random-operation harness
driving the real database and a plain in-memory model of what should be true.

Operations: start / abandon / complete a workout, tick and untick sets, add and
remove sets, swap and skip an exercise, edit a programme, backdate a workout,
delete a workout, log and delete bodyweight, advance a cycle, back up and
restore.

After EVERY operation, assert:
  - the model and the database agree on every value the model tracks
  - every invariant in INVARIANTS.md still holds

Requirements:
  - Seeded, and the seed is printed on failure, so any failure replays exactly.
  - The failing operation SEQUENCE is printed, not just the final state.
  - Shrink if you can: on failure, retry the sequence with operations removed
    to find the shortest one that still fails.
  - The model is deliberately dumb — plain Dart maps and lists. If the model
    needs the repository's logic to stay correct, it is not an oracle, it is a
    second copy of the thing under test.

Then add crash injection: interrupt the process mid-transaction, reopen the
database, and assert the invariants survived. That is what durability means on
a phone with a flat battery.

Report the number of operations run and every violation found.
```

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

One entry per session:

```
Read DEBT.md § N and HARDENING.md stage 4, then close § N and nothing else.

Constraints:
  - The full suite, including test/integrity/, passes before and after. If a
    rewrite changes any number anywhere, that is a bug in the rewrite, not an
    improvement — stop and report it.
  - For § 3 specifically: before deleting an old query path, write a test that
    runs both the old and the new implementation over seeded data and asserts
    the outputs are identical field by field. Keep that test.
  - Do not fix anything else you notice. Add it to DEBT.md instead, with
    evidence and a check, in the style of the entries already there.

Update DEBT.md: delete the entry only when the check it names passes.
```

---

## Stage 5 — Sync, in two halves

[SYNC.md](SYNC.md) makes two separate promises, and they carry very different
risk. Ship them separately.

### 5a — Push-only backup

*"A backup you do not have to remember to take"* — SYNC.md's own first line, and
the property that makes it safe to keep a real history here at all. **No merge
and no conflict resolution, because there is exactly one writer**, which means
the entire edge-case table in SYNC.md § 12 does not apply yet.

**Exit**: the restore drill, performed by hand on a second physical device —
back up, install clean, restore, compare. Not a test that says it works; you
doing it.

```
Read SYNC.md in full, then implement ONLY the one-way half of it: this device
pushes, and can restore from what it pushed. No pulling of another device's
rows, no merge, no conflict resolution, no LWW decisions — there is exactly one
writer, and § 12 does not apply.

Scope:
  - Auth (Google via Supabase, per § 3).
  - A push loop over rows already marked dirty. Every syncable table already
    carries deviceId, updatedAt and dirty — use them, do not add a mechanism.
  - Restore into an empty database. BackupService already serialises and
    restores the whole database and is tested; reuse it rather than writing a
    second codec.
  - Settings UI: signed-in state, last successful push, and a manual "back up
    now".

Constraints:
  - § 5, the write path never changes: the app must behave identically with the
    radio off. No screen waits on a server. Nothing in the local write path
    learns that sync exists.
  - A failed push is retried later and never surfaces as an error mid-session.
  - Do not implement pull-and-merge even partially. If you find yourself
    writing a conflict rule, stop — that is 5b.

Then: tests for the push loop, the restore, and the offline path.
```

### 5b — The second writer

**Exit**: the two-device fuzz run is clean, and every row of § 12's edge-case
table is a passing test — which SYNC.md already asks for.

```
Read SYNC.md in full, and INVARIANTS.md. Implement the pull-and-merge half.

Non-negotiable: EVERY ROW of SYNC.md § 12's edge-case table becomes a test
before the merge code that handles it is written. § 12 exists precisely so that
these are decided in advance rather than discovered in production.

Then extend test/integrity/model_fuzz_test.dart to two simulated devices:
interleaved operations, arbitrary sync points, network failures mid-push,
and clock skew between devices. The invariants must hold on both devices and
on the server after every step.

A merge that loses a write, fabricates one, or refuses a valid row is a stop —
report it rather than working around it.
```

---

## Then

Start logging real data, keeping a parallel record for one training block. At
the end of the block, compare. That is ground truth, it costs no engineering,
and it ends the argument in whichever direction it goes.

§ 6 of DEBT.md closes as it is used, or by deleting what turns out not to be
worth using. That is the last entry, and using the app is the only thing that
can close it.
