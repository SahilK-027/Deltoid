# Deltoid — the rules

This file collects every rule the app is held to. It carries no status and no
description of any screen, because those belong in [TODO.md](TODO.md) and
[THEME.md](THEME.md) respectively. When one of the rules below is broken,
something that used to work is now quietly wrong, and usually nothing raises an
error to say so.

The rules are grouped by what they protect:

1. [The one rule](#1-the-one-rule) — why the app exists
2. [Data](#2-data) — what a row means, and what must never be rewritten
3. [Schema and migrations](#3-schema-and-migrations)
4. [Code](#4-code)
5. [Interface](#5-interface)
6. [Scope](#6-scope) — the non-goals
7. [Working on it](#7-working-on-it)

---

## 1. The one rule

**Last-time numbers are scoped to the _session_, never to the exercise.**

Incline DB press opens Push 1 at 22.5kg and sits second in Push 2 at 20kg. Each
session keeps its own progression. Every off-the-shelf tracker scopes history
per exercise and collapses those into one number — that is precisely why this
app exists.

`resolvePrefill` in `lib/domain/prefill.dart` enforces it, in order:

1. Most recent **completed, non-deload** workout **with the same `sessionId`**.
2. Failing that, a **deload** performance of the same session — a light week in
   this slot still reflects this slot's progression.
3. Nothing. A session with no history of its own **opens blank**.

Step 3 used to borrow the most recent performance from any session, labelled in
amber. A label is not enough to make that number mean what a prefill means:
"borrowed from Leg 1" reads as *where this movement was last done*, and it is
not — it is the most recent performance anywhere, which for a movement trained
in two sessions is whichever came round last. Train Leg 1 for the first time on
Monday and Leg 2 for the first time on Friday, and every plate in Friday's
session arrived filled from Monday's, from a day that says nothing about what
belongs here. That is the failure the one rule exists to prevent, reintroduced
by its own fallback.

What survives is the knowledge, not the number. The other session's performance
still comes back as `PrefillSource.otherSession` with a `reference` and **no
sets**, so `hasSuggestion` is false and every reader downstream — the ghosts,
the shape a workout opens with, the deload scaling, adoption on tick — treats it
as the first time it is. **The ⓘ must still name where the movement was last
done**, and it does: "First time in this session · Last done in Leg 1 · 12 Jul.
This day starts blank." The channel may change; that disclosure may not.

Never "simplify" this to a plain most-recent lookup, and never let a suggestion
in through step 3.

---

## 2. Data

| Rule                                                            | Why                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| --------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `WorkoutExercise` / `SetLog` are **snapshots**, not pointers    | Reordering or swapping mid-workout must never rewrite what you did in March. Same reason switching regimes creates a new `Regime` rather than editing sessions in place.                                                                                                                                                                                                                                                                                                                                                                                      |
| **What a set trained is snapshotted too**                       | `workout_exercises.muscle`, copied at log time. Counting through a join onto `exercises.muscle` is fine over seven days and a lie over years: refiling one movement rewrote every week it had ever appeared in. **Nullable, and null is not `other`** — it means the row predates the column, so readers coalesce onto the catalog. `other` belongs to no region, so defaulting to it would drop every pre-existing set out of every chart instead of saying "unknown".                                                                                       |
| `LoadMode` decides what the **weight** means                    | `22.5` on a dumbbell is 45kg of load; `73` on a pec deck is 73kg. Without it every comparison downstream is garbage.                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| `MeasureMode` decides what the **count** means                  | `set_logs.reps` holds reps _or_ seconds, read through the exercise's mode exactly as `weight` is read through `LoadMode`. Comparisons carry over unchanged; arithmetic that assumes reps does not — a hold has **no e1RM** and adds **nothing to session volume**, because kg × seconds is a different unit. It sits on the exercise, not the set: a plank is never sometimes reps.                                                                                                                                                                           |
| `set_logs.partialReps` is **recorded, never arithmetic**        | A partial is a fact about how the set went, not a rep. Nothing that adds up may read it — out of session volume, out of `estimated1RM`, out of `beatsPrevious` — or grinding halves read as a record. **Shown from the ghost, never adopted from it**: `_adoptGhost` fills blanks with a plan for today, and prefilling partials would log halves nobody did. The ghost opens the split only on an unfinished set: a ticked set with no partials of its own was all full reps. Printed as a suffix (`8+3`) or as the second half of the log's split cell, never inside the count, so the two can never be summed by accident. Meaningless on a hold — there is no half-second. |
| Warm-ups, drops and rest-pause are **excluded from progress**   | `scorePerformance` counts `working` and `amrap` only. Including the rest is how naive logs claim progress that isn't there.                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| A **backoff set is volume**, though it is not progress          | `countsForProgress` protects a comparison; `countsAsVolume` counts work done. Two questions, two answers.                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| `estimated1RM` caps reps at 12                                  | Right for the long-range chart. **Wrong** for "did I beat last time" — it makes 12 → 13 reps invisible. That comparison is `beatsPrevious`, deliberately strict: more load at no cost in reps, or more reps at the same load. Heavier-for-fewer is a trade-off, not a win.                                                                                                                                                                                                                                                                                    |
| `_cyclesSinceDeload(beforeIndex:)` is **exclusive**             | A `CycleStatus` describes a cycle by what came _before_ it. Counting the cycle itself lands the deload one cycle early. This was a real bug.                                                                                                                                                                                                                                                                                                                                                                                                                  |
| History paging is **keyset, not offset**                        | `HistoryCursor` on `startedAt` + id. Finishing a session while the list is open must not shift the page boundary under it. Filters go in the query, never over the loaded page, or paging stops holding.                                                                                                                                                                                                                                                                                                                                                      |
| Home loads through **one** snapshot                             | `todaySnapshot` + `homeProvider`. A per-card provider brings back the staged reveal: watched queries resolving a frame or two apart, and a frame where "no sessions" is indistinguishable from "sessions haven't loaded". Everything is on local disk — the screen should arrive whole.                                                                                                                                                                                                                                                                   |
| **No programme is hardcoded**                                   | `seed/` ships an exercise catalog and _optional_ templates. Never seed a regime, and never put personal numbers, cues or video links in `seed_data.dart` — those are the user's, added through the UI.                                                                                                                                                                                                                                                                                                                                                        |
| A rate needs the weeks to have happened                         | Sessions-per-week was `sessionsInTheLast29Days / 4`, which told a two-day-old install it trained "0.3 / week". `domain/consistency.dart` divides by the weeks it actually has and prints a plain count below a fortnight of history.                                                                                                                                                                                                                                                                                                                          |
| **A position is unique among live rows**                        | `sessions`, `session_exercises`, `workout_exercises` and `set_logs` all carry a partial unique index on their parent plus `orderIndex`. Every append takes one past the highest live position rather than the live count — a tombstone leaves a gap and nothing renumbers behind it — and the index is what holds when the writer is a restore rather than a tap. **A reorder therefore cannot renumber in place**: see `renumber` in [§ 4](#4-code).                                                                                                         |
| **One session is open at a time**                               | A partial unique index on `workouts (status) WHERE status = 'inProgress'`, the same shape as the single-active-regime one. `startWorkout`'s check reads outside the transaction that writes, so Start and the backfill sheet could both find nothing running — and `openWorkout` then hides the loser behind the newer one: unreachable, in progress forever, counted by nothing.                                                                                                                                                                             |
| **A day answers to one name in its regime**                     | `idx_sessions_name_live`, keyed on `lower(trim(name))`. The prefill disclosure names the day a movement was last done in, History filters by it, and the chart labels its lines with it — two live `Push 1`s makes all three ambiguous. Across regimes is fine, which is why `LoggedSession` carries the regime name.                                                                                                                                                                                                                                                    |
| **Which day a rotation is due is derived, never counted**        | `sessions.rotation_id` says which days share a position in the cycle, and nothing stores whose turn it is. `dueInRotation` reads it off the workouts already logged: the member after the one last trained. A counter, or the cycle number taken modulo the rotation, skips a day whenever a cycle is closed early without the position trained, and gives two phones a second number to disagree about. A rotation left with one live member is a day trained every cycle, since that is what a delete or a merge leaves behind. **Two days in one position are still two days**: each keeps its own prefill, and the one rule is not softened by their sharing a turn. |
| **A bodyweight movement moves a share of the body, not all of it** | `exercises.bodyweight_pct`, read through `bodyweightMoved` under the two bodyweight load modes. A push-up is a lever on the toes, and the hands carry bodyweight times the distance from toes to centre of mass over the distance from toes to hands: 64 per cent across lifters. Scored on the whole body it read half as heavy again as it is, and a plate added to it counted for less than the same plate on a pull-up. **On the movement and read live, as `LoadMode` is**, since it says how every set of the movement is read. Added weight is added whole, never scaled. Fixed for a movement the catalog seeded, asked for on one the user creates. |
| **A bodyweight never logged is assumed, and the log says so**    | `bodyweightOn` answers `assumedBodyweightKg`, 60 kg, on an empty log, and returns a `double` so no caller can score a bodyweight lift on nothing. Scored on nothing, a weighted dip was read on its added weight alone, and 10 kg to 12.5 kg came out a quarter stronger where the load rose by about three per cent. An assumed figure is exact for the change in a bodyweight-only lift and close for a weighted one; what it cannot give is a true total in kilograms. So it is never silent: `bodyweightBasis` reports `assumed`, or `stale` past a week, and the log's chip prints which. Nothing stores it, so the first weigh-in replaces it on every day ever logged. |
| **Where a phase ends is derived, never written**                 | A phase runs from its `day_key` until the next live phase starts, or to its own `end_day_key` if `Clear phase` came first, and `phaseSpans` in `domain/phases.dart` is the one place that says so. Starting a phase writes one row and never edits the one before it, so no decision spans two rows for last-write-wins to split ([SYNC.md § 4](SYNC.md#4-what-the-server-holds)). Clearing is an end day on the cleared row rather than a row meaning "no phase": the cleared phase goes on tinting the cycles it covered, and a marker row would be a phase with no kind for every reader to special-case. |
| **An enum column is checked in the database**                   | `textEnum` throws on a string no member answers to, and takes the **whole result set** with it — one bad row blanks the log, history and the chart together. Every enum column carries a hand-written `CHECK … IN (…)`, and `schema_constraints_test` walks every member of every enum, so a value added to one and not the other fails a test rather than a screen.                                                                                                                                                                                          |
| **A number that cannot mean anything is refused at the column** | Deload percentages, backwards rep ranges, a `dayKey` of 0, a session ending before it started, a set that is a leg of itself, a bodyweight of 850. Each is reachable only through a restore or a merged row — the writer that does not pass the repository, which is what a server becomes. **The column is the backstop, never the gate**: every one is also bounded at the input, or a slip becomes a failed write instead of a refused keystroke.                                                                                                          |

**Cloud backup has its own invariants, and they live in
[SYNC.md § 13](SYNC.md#15-what-sync-may-never-do).** The four that are really
about data rather than about protocol are repeated here, because this is the
list people read:

| Rule                                                                    | Why                                                                                                                                                                                                                                                                                                                                                                                     |
| ----------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **No screen waits on the network**                                      | Offline-first is the architecture, not a stage. A read comes from local disk and a write returns when SQLite returns; the cloud is drained behind it. A screen that awaits a radio between a thumb and a set is the one change that cannot be walked back.                                                                                                                              |
| **Two histories are never merged silently**                             | They share no ids, so a merge is not a reconciliation — it is a union claiming you trained twice as often as you did. `backup_service` already refuses this for restore; signing in asks the same question, with counts, and exports the losing side first.                                                                                                                             |
| **Deletes stay tombstones**                                             | A hard delete has no `deleted_at` to push and is resurrected by the next pull. Every delete in the app is already a tombstone; sync is the reason it had to be.                                                                                                                                                                                                                         |
| **A pulled row is written by the same code that writes a restored row** | Same constraints, same transaction discipline, same repairs. A second write path is a second set of bugs, and it is the path with no screen watching it. _Through the repositories_ is the thing this cannot be: they are shaped like intentions, there is no `upsertSession(row)`, and a repository that took a whole row would be the second path.                                    |
| **No merge deletes logged work**                                        | The twelve unique indexes are correct for one device and eleven are reachable by two doing something ordinary — appending is the commonest action in the app, and two devices appending to one parent both compute `max + 1`. A collision is two _different_ rows claiming one slot, which last-write-wins cannot resolve, so the rule is re-slot, re-flag or re-number. Never discard. |
| **A conflict is decided on the server's clock**                         | `updatedAt` is a phone's wall clock, and two phones do not agree. The disagreement does not average out: a device running ten minutes fast wins every conflict it is ever in, and the other device's edits vanish silently. `nowMs` being monotonic is the half of this that is local; `server_updated_at` is the other half.                                                           |

**Three levels of note, and they never leak into each other:**

| Column                    | Scope                         | Written from           |
| ------------------------- | ----------------------------- | ---------------------- |
| `exercises.notes`         | the movement, forever — a cue | catalog editor         |
| `workout_exercises.notes` | this exercise on this day     | log ⋯, summary, detail |
| `set_logs.note`           | one set                       | the set sheet          |

Editing the second must never reach the first: the snapshot row is a copy for
exactly this reason.

**A finished session can be corrected, and only corrected.** A set on a logged
day takes a new load, count, partial count or type, or is removed, through
`correctLoggedSet` and `deleteLoggedSets`. Neither takes `isDone` or a time, and
both refuse a session still in progress. The write is to `set_logs` alone, which
the readers of the log's shape leave unwatched, so each announces a change to
`workout_exercises` rather than stamping a row that has not changed. Adding an
exercise or a set to a finished day is logging, and stays on the log screen.

**Improvising is a snapshot edit, and stays one.** Adding a movement
mid-session, dropping one, running the day out of order or ticking fewer working
sets than the day programmes changes today and nothing else. The end-of-session screen then _offers_ each change back to the
template (`domain/session_diff.dart`), one at a time, and `applySessionChanges`
writes `session_exercises` and only that — so keeping a change never rewrites a
logged workout.

A lower set count is offered because the next workout cannot tell a plan
changed from a session cut short: it mirrors last time's shape and pads to the
template's count as a floor. The floor stays, since removing it lets one short
session shrink the exercise for good, and the question at the end of the
session is how the other case is answered. It is never asked in a deload, for a
skip, for a movement with no working set ticked, or for one the day runs twice.

---

## 3. Schema and migrations

Drift code has to be regenerated after any edit to `lib/data/db/tables.dart`:

```bash
dart run build_runner build
```

**The ladder is running.** `schemaVersion` is 7 and `MigrationStrategy` has an
`onUpgrade`, in `lib/data/db/migrations.dart`. So a schema change is:

1. the column or `@TableIndex` in `tables.dart`,
2. `dart run build_runner build`,
3. **a default in `lib/data/db/table_spec.dart`** for that table,
4. **a rung**: `schemaVersion` up one, and a step in `upgradeSchema` guarded by
   the version it was added at,
5. and, for a **syncable** table, a rung in `supabase/migrations` as well. A
   push sends every key of the row, so a column the server has not heard of is
   a rejected batch on the machine holding the only cloud copy of a history.
   `test/data/server_schema_test.dart` reads both schemas and fails on a
   mismatch, which is what makes this a gate rather than something remembered
   before a release. **The server rung is applied first, and the build that
   needs it second.**

**Every step is idempotent.** `addColumnIfMissing`, `createIndexesIfMissing`,
never a bare `m.addColumn` or `m.createIndex`: a device given an earlier build
comes back with the structure already in place and the stamp behind it, and the
bare form throws on launch before any screen is drawn.
`test/data/migrations_test.dart` runs a full upgrade over a database that
already has everything, and compares a database created fresh against one walked
up the ladder.

This carried a v2..v8 ladder once, each step migrating a shape that only ever
existed on a test device, and that was thrown away with nothing released. It
started again at 2 because **sync is the day this section named, and it arrives
before any second phone does** — it lets two devices running _different builds_
exchange rows, which needs an upgrade path for the local file and a wire format
that survives a row carrying one column more or fewer than the reader knows.
Both exist now: the ladder above, and the shared registry step 3 points at.

Step 3 is the easy one to miss and the expensive one to get wrong, and it has
**two** readers now rather than one — a restore and a sync pull — which is why
the defaults live in one registry rather than beside each of them.
`Exercise.fromJson` is generated against _today's_ columns and reads every one
unconditionally, so a file exported before a column existed throws a null cast
on restore — with the only copy of a history in the file picker. `db/table_spec.dart` spreads a default map under each parsed row for
this reason, and `test/data/table_spec_test.dart` walks every column of every
table asking each parser what it does with that column missing.

**Index-only** changes skip step 3, since nothing new is stored; so do
**constraint-only** ones — but a constraint cannot be altered in place (SQLite has no `ALTER … DROP CHECK`), so
changing one is a table rebuild, and a step re-mapping a retired value must run
_before_ the rebuild that narrows the column.

A backup also carries the `schemaVersion` it was written against, and import
refuses anything **newer** than the running build can read rather than clearing
the tables and failing halfway. Collapsing the version to 1 therefore made every
previously exported file unrestorable, which was acceptable exactly once, while
the only data anywhere was test data. It is not available again.

**Backfill wherever the app already knows the answer.** A new column's default
is the honest value for a row nobody has been asked about, and the wrong value
for a row the app seeded itself. Version 3 backfilled bar kinds onto the
thirteen barbell movements, and version 7 backfilled the seeded Plank onto
`hold`. A backfill must only ever touch rows still carrying their `starterKey`,
because anything else belongs to the user.

The schema history so far: version 2 added `set_logs.parent_set_id`, version 3
added `exercises.bar_kind`, version 4 re-mapped a dropped `bar_kind` value,
version 5 added `regimes.identity_index`, version 6 indexed
`bodyweight_logs.day_key`, and version 7 added `exercises.measure_mode`.

The ladder running _today_, the one that started again at 2: **1 → 2** created
the nine `dirty` indexes, and **2 → 3** added `regimes.activated_at` and
backfilled it onto whichever regime was active at the time. That backfill is the
rule above doing its job — the honest default for this column is null, meaning
_never activated_, and null on every row of an existing phone would leave the
derivation with no candidate and deactivate the programme the user is training.

**3 → 4** added `session_exercises.bar_kind` and `workout_exercises.bar_kind`,
and backfilled neither — the same rule reaching the opposite answer. Null here
means _no answer, follow the catalog_, which is precisely what every existing
row meant when it was written; copying today's catalog value onto them would
freeze a guess as though it had been a decision at the time.

**4 → 5** added `exercises.bodyweight_pct`, 100 by default, and backfilled the
movements the app seeded itself: a push-up to 64, a pull-up, a chin-up and a
dip to 95. Both halves of the backfill rule at once. A movement the user
created stays on 100, which is what it meant when it was written, and a seeded
one takes the figure the app already knows. This backfill marks its rows
`dirty`, which the earlier ones did not, because it runs on phones that may be
signed in and a value held only on the phone is lost to the next restore from
the account.

**5 → 6** added `sessions.rotation_id` and backfilled nothing. Null means the
day is trained every cycle, which is what every existing day meant when it was
written, and no regime holds an answer the app could know better than the
person who built it.

**6 → 7** created the `phases` table with its two indexes, one live phase per
start day and the partial index on `dirty`, and backfilled nothing: no
existing install has declared a phase, and the app never infers one
([§ 6](#6-scope)). A new table is the one schema change a column guard cannot
cover, so the step is `createTable`, which writes `CREATE TABLE IF NOT
EXISTS`, followed by `createIndexesIfMissing`. The `1 → 2` step leaves
`idx_phases_dirty` alone for the same reason: on a database that old the table
does not exist yet, and an index on a missing table throws at open.

---

## 4. Code

**Pure logic lives in `lib/domain/`** and is tested without a database. Extend
those tests whenever behaviour changes, because that is where a rule is actually
held. Domain files take **plain values, never a drift row** — that is what keeps
them testable without a database.

**Anything that turns data into a string is domain, not a screen.** A formatter
written where it is first needed gets copied to the next screen, and the copies
drift silently: `_load` and `_loadLabel` were byte-identical, while two
functions picking a day's top set disagreed about every hold ever logged — one
ranked by weight, the other by duration, both commented as matching.
`formatWeight` had settled in `history_screen.dart`, so six screens imported a
screen to render a number. These live in `lib/domain/set_format.dart`.

**Never watch a constant query.** The "invalidate on write" trick —
`db.customSelect('SELECT 1', readsFrom: {…}).watch()` — emits **once** and then
never again, because `SELECT 1` never changes. Writes land in SQLite correctly
and the UI freezes forever, with no error anywhere. Use `db.watchQuery(...)`
from `lib/data/db/watch.dart`.

**`ref.read` on a provider nobody watches returns nothing.** The regime switcher
read `allRegimesProvider` on demand, got `AsyncLoading` every time and rendered
an empty list — so creating a regime looked like it deleted the old one. Watch
it, or go through the repository.

**Never capture a `WidgetRef` in a callback that outlives its widget.** A sheet
closing itself before opening the next leaves its `ref` disposed, and the second
sheet's `ref.read` throws `Cannot use "ref" after the widget was disposed` — from
a gesture handler, so the symptom is a button that does nothing. Read the
repository _before_ popping and pass that: a plain object outlives the widget
that looked it up.

**Don't hold a `WidgetRef` across an `await` that changes the screen.** Starting
a workout swaps the "up next" card for the resume card, disposing the widget
that started it; clearing a flag through that dead ref throws inside `finally`,
leaving the button disabled forever. Capture `ProviderScope.containerOf(context)`
before the first await.

**`valueOrNull ?? const []` turns "loading" into "empty".** Loading and empty
are different states; a screen with more than one query needs them told apart,
or it needs one query.

**`Isolate.run` inside a class captures `this`.** Moving the backup's
`jsonEncode` off the UI isolate failed at the _send_, not the JSON: the closure
carried an `AppDatabase` wrapping a sqlite3 FFI handle — "object is unsendable".
Both helpers are top-level functions in `backup_service.dart`; keep them there.

**Every per-second rebuild goes through `core/widgets/ticking.dart`**, wrapping
the clock and never the screen around it.

**`CrossAxisAlignment.stretch` in an unbounded Row** is a layout error that
silently blanks the screen with nothing in logcat. Use `IntrinsicHeight`.

**A signed delta is computed from what is shown.** Two bodyweights 0.2 apart
differ in kilograms, so the row printed a sign — and display rounding then
snapped the difference to `+0`. Compare `unit.display(a)` against
`unit.display(b)`, as `formatDeltaInUnit` does; it returns null when both round
to the same figure.

**`formatWeight` also formats computed numbers.** An estimated 1RM is an
arbitrary double; `55.733333333333334 kg` shipped to a screen once.

**Adopt ghost values when completing a set.** Typing only the reps is the normal
case — same weight, one more rep. Without `_adoptGhost` the set stores reps
against a null weight: invisible to the chart, useless as next week's prefill.

**A write that is not awaited still has to report.** The log screen cannot await
its writes — `_flushWrite` runs from a `Timer` and from `dispose`, neither of
which can wait on a disk — so a throw used to land on the floor: the tick stayed
on screen (it came from the local buffer), the summary counted the set, and the
number was not in the database. You found out weeks later, looking at a hole in
a chart. `core/failure.dart` is the channel — `reportOnError` on anything
deliberately not awaited, `reportFailure` everywhere else — and `main` installs
`FlutterError.onError` and `PlatformDispatcher.onError`, so an uncaught error in
a gesture handler reaches the same place. A toast under `MaterialApp` says it,
above the log rather than inside a tab.

**A reorder is two passes, not one.** A position is unique among live rows (§ 2)
and SQLite checks that on every statement, so writing `i` to the row that should
end up at `i` collides with whoever is standing there and rolls the whole reorder
back — for a permutation that is legal once finished. `renumber` in
`data/db/renumber.dart` moves everything to a free range first (one past the
highest live position, computed in the same transaction), then brings it down to
`0..n-1`.

**`nowMs` never goes backwards.** It is what last-write-wins compares, and a
clock moved back — a network correction after a flat battery, a manual change —
made a row lose to the version written to replace it. Clamped to the last stamp
issued, which is the local half; agreeing on time with another device is a
server's job.

**Every update stamps `deviceId`, not just the insert.** `clientDefault` fires
once, so the column used to name the row's creator for the rest of its life —
and it exists to break a same-millisecond tie between two devices, which it
cannot do if both copies carry the same originating id.

**`dirty` is cleared only against an unchanged `updatedAt`, and `last_pull_at`
advances only after its batch commits.** The same mistake in two directions:
acknowledging work that has not landed. A row edited while its own push was in
flight is still owed, and clearing it on the response strands that edit forever —
invisibly, because nothing downstream looks at a row that is not dirty. A cursor
advanced before the write loses every row in the batch it did not finish. See
[SYNC.md](SYNC.md).

**Comments are written as documentation, not as narration.** The reasoning
stays — density is the point, and [§ 7](#a-rule-that-matters-is-a-rule-something-checks)
says why — but it is written in the register a reader outside this project would
expect. Four rules:

- **Third person, never second.** A comment describes the code and the caller,
  not the reader: _"the page currently open does not move mid-session"_, not
  _"the page you are standing on does not move out from under you"_. The one
  exception is a **string literal the user reads**, where the second person is
  the app's own voice ([THEME → The words](THEME.md#the-words)) — `loadBlurb`
  returns _"The weight you type is the whole load"_ and should. Document the
  distinction on the function rather than changing the string.
- **Present tense, and no changelog.** State what the code does and what the
  alternative would cost, not what a previous build did: _"counting rows hands a
  new slot a position a surviving one still holds"_, not _"counting rows handed
  the new slot a position…"_. A comment is not a commit message, and the git
  history is where a superseded design is recorded.
- **A full sentence, not an emphasised fragment.** No `**bold**` mid-prose
  standing in for a topic sentence. _"Raw SQL, because the query is unbounded."_
  is the same fact as _"**Raw, and unbounded is why.**"_ and survives being read
  aloud.
- **A doc comment opens with a summary line.** One sentence naming what the
  thing is or does, then a blank `///`, then the reasoning — the shape every
  Dart API doc has, so that the first line is usable on its own.

None of this licenses shortening. A comment that loses the reason it existed has
been damaged, not tidied: rewrite the sentence, keep the argument.

**Never copy the project to keep an old version around.** No `old-*/`, no
`*.bak`, no second checkout, no `git worktree` for "reference". Git holds every
previous state; a copy goes stale the moment it is made, gets edited by mistake,
and shows up in searches as a second answer to every question. One was found at
99 MB, nine commits back, holding a test file two revisions out of date. Read
history instead:

```bash
git show <commit>:lib/features/home/home_screen.dart
git log --oneline -- <path>
git diff <commit> -- <path>
```

---

## 5. Interface

The design system is [THEME.md](THEME.md), and it decides everything visual:
the tokens, the type roles, the component vocabulary, and the six rules that
settle a close call. Read it before drawing anything.

These belong here rather than there, because breaking them breaks behaviour
rather than looks:

- **The log screen owns the horizontal axis.** It is a `PageView` with one
  exercise per page. The set row is the single exception, and only to uncover
  its own delete. Nothing else inside the log may claim a horizontal gesture.
- **Never invent a component in a feature folder.** If a card, row, button or
  sheet is not already in the design system, it gets added there first.
  Anything else drifts within a week and leaves two answers to one question.
- **The screen is ahead of the row it is drawing.** Writes are debounced and
  come back through a watched query, so for a few frames after a keystroke the
  `SetLog` in `build` still holds the old number. Anything that re-reads a
  value it has just written — refocusing a field, adopting a ghost, reopening
  the half of a split cell — has to read what the screen last had, not the row,
  or it writes the stale value straight back over the new one. `_adoptGhost`'s
  `skipCount`, the keypad's stashes and `_partialClosedFor` all exist for this.
- **A rest that has to ring on time is an OS alarm, not a `Timer`.** Android
  freezes Dart timers the moment the process is suspended, so a phone put down
  between sets buzzed when it was picked back up rather than when the rest was
  up. `_armRestAlert` hands the end of every rest to
  `WorkoutNotifications.scheduleRestDone` **as the rest starts**, and
  `_preFire` cancels it 400 ms before it is due so a phone you are holding
  gets the in-app tone instead — exactly one alert fires either way. The same
  rule covers anything else that must happen at a wall-clock moment.

  **Arming it on the way to the background is not enough**, which is what this
  used to do. Backgrounding is one of several ways a process stops running and
  the only one that gets a callback, so every other way left nothing scheduled
  at all: the alert went off when the phone was picked back up, or never, and
  which of the two it was looked random from the gym floor.
- **Anything the system draws for you, the system has to be told to stop.** The
  ongoing notification's countdown is an Android chronometer, which is the only
  reason it can be trusted while this process is asleep — and the reason it
  keeps counting past zero into `-1:23` unless something replaces it. Nothing
  in this app is awake at that moment by definition, so `showSession` queues a
  second, chronometer-less copy of the line under the same id, timed to land as
  the rest ends.
- **Loading and empty are different states.** A screen with more than one query
  either tells them apart or is rebuilt around a single query. Collapsing them
  renders "nothing here" at data that is merely late.
- **A painter never clamps to a bound it computed.** `clamp(lower, upper)`
  throws when `lower > upper`, and a bound computed from a layout that got
  small or a list that got long inverts exactly that way — inside `paint`, on
  every repaint, which is not a frame you can navigate away from. One instance
  killed the volume screen. Write `max(a, min(b, c))`, which cannot throw and
  says what it means, and keep `clamp` for a pair of literals. Enforced by
  `test/core/clamp_bounds_test.dart`, which reads `lib/` and fails on a
  `.clamp(` whose bounds are arithmetic rather than constants.
- **A widget laid out in a row of siblings may not contain a `LayoutBuilder`.**
  It cannot report an intrinsic dimension, so any parent that asks for one —
  `IntrinsicHeight`, a `Row` sizing itself to its tallest child — throws at
  layout rather than at compile time, and only on the screen that composes it.
  A widget that needs its own width in a gesture reads `context.size`, which is
  there by the time any gesture can arrive.

---

## 6. Scope

This is a single-user personal tool, not a product. Scope discipline is a
requirement, and the answer to "should we add…" is usually no.

**Deliberately absent, and staying that way:** social features, macros /
nutrition, AI coaching, an exercise GIF or video library, Apple Health /
Google Fit, 1RM testing protocols, levels, muscle maps, motivational
copy, programme sharing or marketplaces, and **effort / RIR ratings** — a
number you rate yourself with after the set, which is one more thing to answer
at the bar and nothing downstream reads.

**A PR feed and a PR badge stay out.** A record is a number you can already read
on the day it was set, and `beatsPrevious` says "you beat last time" where it
matters — at the bar.

Two things came _off_ that list, and the test they passed is the test anything
else has to pass: **no new screen, and no new question asked.**

- **The plate view** appears inside the keypad you are already typing a weight
  into, for a movement that already knows its bar, and disappears the moment
  either is untrue. What stays ruled out is a plate _screen_ — a per-gym
  inventory, a "what can I load" solver, a tool you navigate to.
  `olympicPlatesKg` is a constant for that reason.
- **Weekly muscle volume** is one bar list on a page you already open,
  normalised to your own biggest muscle rather than to a target this app has no
  business inventing. What stays ruled out is the thing that made it a non-goal:
  a dashboard you navigate to, a feed to scroll, targets to fail against.

- **Cycle progress** is the third, and it takes two pushed screens rather than
  none — so the test it passed has to be written down. It asks no new question:
  every number on it is computed from sets already logged, and nothing on any of
  the three surfaces prompts for anything. What it replaced is the point. The
  Workouts card took the place of Last session, which repeated the masthead above
  it and the History tab beside it, so the screen gained an answer without
  gaining a section. The two screens behind it are the Weekly volume shape
  exactly: a card on a page you already open, with the detail one tap behind it
  — the regime's lifts, and the timeline of which programme ran in which week.
  What stays ruled out is what stayed ruled out there: a dashboard as a
  destination, targets to fail against, and a score the app invents rather than
  derives.

- **The bodyweight pill** is the fourth, and the one that comes nearest to a
  new question. It adds no screen: a pill on the log page of a movement that is
  already open, and a sheet whose one button opens the weigh-in sheet the app
  already has. It does ask, but only when the answer is missing or more than a
  week old, only on a movement whose score reads the answer, and it never
  stands between the thumb and a set. What stays ruled out is the reminder as
  a feature: no notification, no badge on a tab, no prompt on opening the app.

- **Days that alternate** are the fifth. A regime that trains Leg 1 in one
  cycle and Leg 2 in the next could not be said at all: listed as two days it
  asked for both in every cycle, and the only way to finish a cycle was to
  close it by hand each time. It adds no pushed screen. The regime editor
  gains a Cycle tab ahead of its days, which draws the order the programme
  already had and is where two days are made to share a position. It asks
  nothing of a regime that does not use it, and such a regime reads exactly as
  it did. What stays ruled out is everything a schedule usually drags with it:
  no calendar, no weekdays, no rest days to place, no periodised blocks, and
  no week-by-week editor in which every week is its own programme.

- **Habit counts** are the sixth, and they took streaks off the list with them.
  Each habit tile on Home states how many days of this calendar week the habit
  was kept, `3/7 this week`, and a count of weeks or days kept in a row may be
  stated the same way. They ask no new question: every figure is counted from
  workouts and weigh-ins already logged. They are here because the two things
  the app reads most depend on being done regularly. A missed weigh-in is what
  turns the bodyweight pill yellow, and a month of training was visible only as
  a grid to be read cell by cell. What stays ruled out is everything a streak
  usually drags with it: a flame or any other mark of a run, a warning that a
  run is about to break, a reward at the end of one, a target the app sets, a
  notification, and any copy that praises or scolds. A count is stated, and the
  person reading it decides what it means.

- **The Progress tab** is the seventh, and it fails the test outright: it is a
  new destination on the nav bar. It holds nothing new. Cycle progress and
  Weekly volume moved there from Workouts unchanged, because Workouts had
  become two screens in one, a place to enter a session and a place to read
  the training, and Home is the first of those only. Moving the two cards adds
  no number to the app and asks nothing. What stays ruled out is what stayed
  ruled out for each card on its own: a dashboard of figures the app invents,
  targets to fail against, and a feed. Anything else proposed for Progress
  passes the same test Cycle progress did, and is written down here before it
  is built.

- **Bodyweight's move out of Settings** is the eighth. Settings held the
  fourth tab partly because bodyweight lived in it, and bodyweight is not a
  setting: it is data, entered every few days, that every bodyweight lift in
  the app is scored on. Behind a tab named for configuration it was two taps
  from the person asked to enter it, which is how a weigh-in goes unlogged. It
  now has a habit tile on Home with its own `+`, and a Weigh-ins screen behind
  the tile in place of the Bodyweight screen behind Settings, so the screen
  count is unchanged and the question is the one the weigh-in sheet always
  asked. The tile states and never asks: no notification, no badge, and no
  prompt on opening the app, as the bodyweight pill already promises.

- **Phases** are the ninth, and they fail the test on its second half: they
  are a new question. A Phase card on Home and the sheet behind it ask
  whether the person is in a bulk, a cut or maintenance, from which day, and
  for how long if they have decided. No screen is added, since the card sits
  on a page already open and the sheet is one question. They are here because
  every strength number in the app is read without the one fact that changes
  what it means. Cycle progress flat for eight weeks is a stall during a bulk
  and a success during a cut, and the chart could not tell the two apart.
  With the phase recorded, each cycle is tinted by the phase it ran in, and
  the reading is left to the person, as it always was. What stays ruled out
  is everything that would turn a phase into a diet: no calories, no macros,
  no target weight, no meal or food of any kind, all of which stay on the list
  above. The phase is declared and never inferred, so the app does not guess
  a bulk from a rising line. And the one place it may ask whether the phase
  still holds is the Phase card itself, when the planned length has passed or
  the weigh-ins have run against the phase for about three weeks: no
  notification, no reminder badge on any tab, no toast, and no prompt
  anywhere else, on opening the app or otherwise.

**Accounts came off it too, and did _not_ pass that test — so the reason has to
be written down rather than assumed.** Sync across your own phones needs an
identity to sync to, and an identity needs somewhere to say who you are, which
is a new screen and a new question. It is here because the alternative is worse
than the cost: this app is the only copy of a training history that takes years
to accumulate, and a lost phone currently loses it. A backup file is a real
answer and an unreliable one, because it depends on the user remembering.

What that decision opens is **one account, for one person, to reach their own
data from their own devices.** What it does not open is everything the word
usually drags with it, all of which stays on the list above: no other people, no
sharing, no profiles, no feed, no account as a _feature_ — a login you see once
and never again is the whole of it. The rules that follow from this live in
[§ 2](#2-data) and [§ 3](#3-schema-and-migrations); the work it needs is in
[TODO.md](TODO.md).

**Offline-first is not softened by it.** Every screen reads local disk, no read
waits on a server, and the app is fully usable with the radio off — a sync is a
background reconciliation of tables the screens already read. A change that
makes a screen wait on the network is a change that breaks this rule, whatever
sync needs.

The app should stay small enough to open mid-set and understand at a glance.
When in doubt, don't add the screen.

---

## 7. Working on it

Run both of these before saying anything is done, and make sure both come back
clean every time:

```bash
flutter analyze && flutter test
```

A change to `tables.dart` needs `dart run build_runner build` before either
command will pass.

**The device belongs to the user.** Screens are driven on real hardware by the
person who owns the phone, and are never launched from a session on their
behalf. Six things still need hardware before they can be trusted: the rest
tone, the haptics, the wakelock, audio ducking, the share sheet, and the two
halves of the rest alert — that the OS alarm rings on time with the phone
asleep, and that the hand-back leaves exactly one sound behind.

**Make one commit per coherent change**, and put the reasoning in the body. Say
why the change was made rather than what it changed, because the diff already
says what.

### The shape of a commit subject

`<emoji> <type>(<scope>): <imperative clause>`, at most 50 characters after the
emoji, no full stop. The clause completes _"if applied, this commit will …"_ —
`fix(prefill): treat a session's first set as a first time`, not
`fix(prefill): a first time in a session is a first time`. A subject that
states a conclusion instead of a change can only be verified by opening the
diff, which is the body's job and not the subject's. This is
[CLAUDE.md rule 11](CLAUDE.md#the-rules-most-easily-broken); it applies to the
body and to `CHANGELOG.md` as well.

**The type is authoritative and the emoji follows it.** The emoji is there to
be scanned in `git log --oneline` and nothing more, so it must never disagree
with the type beside it — `📝 fix(log):` and `💄 fix(log):` are both in the
history, and one of them is wrong. One emoji per type:

| Type       | Emoji | For                                                    |
| ---------- | ----- | ------------------------------------------------------ |
| `feat`     | ✨    | Something the app did not do before                    |
| `fix`      | 🐛    | Behaviour that was wrong                               |
| `fix`      | 💄    | Behaviour that was wrong **and only visual**           |
| `perf`     | ⚡️    | Same behaviour, less work                              |
| `refactor` | ♻️    | Same behaviour, different shape                        |
| `test`     | ✅    | Tests only                                             |
| `docs`     | 📝    | Documents only                                         |
| `build`    | 🔐    | Signing, flavours, the manifest                        |
| `chore`    | 🔧    | Tooling and configuration                              |
| `chore`    | 🔖    | A release: the version bump and nothing else           |

A release commit carries `chore(release): <version>+<build>` and a body saying
what kind of release it is and why. `CHANGELOG.md` is written in the same
commit, to the template in its own header — Keep a Changelog sections, an
`**Area:**` on every user-facing bullet, one line per bullet — and states what
changed in behaviour rather than what the diff touched. It is the record a
person reads; the release commit's body is the record a maintainer reads.

The GitHub release is the changelog entry, never a second text written beside
it:

```bash
dart tool/release_notes.dart <version> > notes.md
gh release create v<version> <apk> --title v<version> --notes-file notes.md
```

### A rule that matters is a rule something checks

A comment cannot fail a build. Every rule that lives only in prose holds exactly
as long as everyone reads the prose, and the record says they do not: the volume
query documented its own bound, an `All` range was added, and the screen took
380ms a rebuild with the comment still sitting there being correct.

So a load-bearing rule gets a mechanism, in this order of preference: a **type**
that makes the violation unstateable, a **schema constraint**, an **assert** at
the boundary (free in release), or a **test** where the rule is about behaviour
rather than shape. Where the checks live now:

| Rule                                                                                    | Mechanism                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          |
| --------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **The one rule** — a session's numbers are its own                                       | `test/domain/prefill_test.dart` and `test/data/training_repository_test.dart`. Step 3 is the one that erodes: it is the path a first-ever session takes, so a suggestion leaking through it is invisible until the week it teaches you the wrong weight. Two tests hold it shut — one on `resolvePrefill` directly, one through the repository on the ad-hoc add, where an exercise arrives with no plan behind it and another session's numbers are the only ones there are |
| The structural invariants of the database                                               | `lib/data/db/invariants.dart` — twenty-two rules re-derived in SQL, nineteen structural and three about the sync columns, each with a perturbation test in `test/integrity/invariant_oracle_test.dart`. **It ships**: a restore refuses a file breaking a rule no repair can fix, and reports what the repairs could not reach; a pull reports rather than refuses, because § 15 rule 9. The three sync-column rules are advisory everywhere — a log stamped by a broken clock is still the whole log |
| Those invariants under arbitrary use                                                    | `test/integrity/model_fuzz_test.dart`                                                                                                                                                                                                                                                                                                                                                                                                                                                              |
| Every derived number                                                                    | `test/domain/` — hand-computed literals, never `expect(f(x), f(x))`                                                                                                                                                                                                                                                                                                                                                                                                                                |
| A query's row count is bounded                                                          | an `assert` at the boundary, or a comment saying why it does not grow — `training_repository.dart`                                                                                                                                                                                                                                                                                                                                                                                                 |
| A painter never clamps to a bound it computed                                           | `test/core/clamp_bounds_test.dart`                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| Every sheet opens through one route, with the safe area on it                           | `test/core/sheet_safe_area_test.dart` — any other call to `showModalBottomSheet` fails                                                                                                                                                                                                                                                                                                                                                                                                             |
| Every changelog entry follows the one template                                          | `test/tools/changelog_format_test.dart` — headings, section order, area prefixes, no hard wraps, link references                                                                                                                                                                                                                                                                                                                                                                                   |
| A screen you left stops querying                                                        | `test/features/volume_provider_lifetime_test.dart`                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| An exception to THEME or RULES is written into the document                             | `test/core/documented_exceptions_test.dart`                                                                                                                                                                                                                                                                                                                                                                                                                                                        |
| The light ramp is legible                                                               | `test/core/light_theme_test.dart`                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| Blue means progress and orange a deload, and nothing else borrows either                | `test/core/palette_test.dart` — no identity colour, chart line after the first, set type or weigh-in day equals `progress`, `deload` or `negative`                                                                                                                                                                                                                                                                                                                                                               |
| A rewritten query returns what the old one did                                          | `test/data/query_conversion_test.dart`                                                                                                                                                                                                                                                                                                                                                                                                                                                             |
| Every column has a default, or has always been written                                  | `test/data/table_spec_test.dart` — walks every column of every table                                                                                                                                                                                                                                                                                                                                                                                                                               |
| Every rung of the ladder can be replayed                                                | `test/data/migrations_test.dart` — a full upgrade over a database that already has everything                                                                                                                                                                                                                                                                                                                                                                                                      |
| The server schema is the local one                                                      | `test/data/server_schema_test.dart` — every column of every syncable table, read off `supabase/migrations`                                                                                                                                                                                                                                                                                                                                                                                         |
| Nothing above `data/sync/` knows which backend this is                                  | `test/features/no_supabase_in_features_test.dart`                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| `dirty` is cleared only against an unchanged `updatedAt`                                | `test/data/sync/push_test.dart` — a row edited while its own push is in flight is still owed                                                                                                                                                                                                                                                                                                                                                                                                       |
| A pulled row is never re-stamped, and `last_pull_at` moves only after its batch commits | `test/data/sync/pull_test.dart`                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| A pull that has nothing to do writes nothing                                            | `test/data/sync/pull_test.dart` — a second pull applies zero, or the rewrite wakes every stream on the table and calls the engine back                                                                                                                                                                                                                                                                                                                                                             |
| `(updated_at, device_id)` is not treated as a version identity                          | `test/data/sync/cloned_device_test.dart` — two installs under one `device_id`, which the manifest now refuses to let Android create                                                                                                                                                                                                                                                                                                                                                                |
| The merge order never runs out of discriminators                                        | `test/domain/sync_merge_test.dart` — two versions on one stamp and one device id still pick one winner, swapped                                                                                                                                                                                                                                                                                                                                                                                    |
| The connection opens on the pragmas the durability claim rests on                       | `test/data/connection_pragmas_test.dart` — read off a real file, because in-memory sqlite is always `journal_mode = memory`                                                                                                                                                                                                                                                                                                                                                                        |
| A backup file is never half a file                                                      | `test/data/backup_service_test.dart` — the rows go to a `.part` and the backup arrives by rename                                                                                                                                                                                                                                                                                                                                                                                                   |
| A logged set keeps the bar it was trained on                                             | `test/data/bar_kind_test.dart` — the day's bar or the catalog's bar changes, the open session follows and the finished session does not; and the two push days holding one movement keep separate answers                                                                                                                                                                                                                                                                                                           |
| A rest duration is decided by a slot then by More, and by nothing else                    | `test/domain/rest_test.dart` and `test/data/training_repository_test.dart` — including a stored value from outside the dialable range, which the column has to accept and the timer must not                                                                                                                                                                                                                                                                                                       |
| A stamp handed out is never handed out again, across a restart                          | `test/data/stamp_floor_test.dart` — the mark is seeded from `app_settings` at open, leased ahead of the clock, and written down at close                                                                                                                                                                                                                                                                                                                                                           |
| Every merge rule is deterministic **and symmetric**                                     | `test/domain/sync_merge_test.dart` — each two-row rule is asserted with the arguments swapped                                                                                                                                                                                                                                                                                                                                                                                                      |
| Two devices converge                                                                    | `TwoDevices.converge` in `test/data/sync/two_devices.dart`, used by every collision test                                                                                                                                                                                                                                                                                                                                                                                                           |
| Two devices under arbitrary use converge, and lose nothing                              | `test/integrity/sync_fuzz_test.dart` — the oracle on both phones after every operation                                                                                                                                                                                                                                                                                                                                                                                                             |
| The catalog is seeded once, whichever order sign-in and first use arrive in             | `test/data/sync/adoption_test.dart` — no `starterKey` is live twice after any of the three shapes                                                                                                                                                                                                                                                                                                                                                                                                  |
| Two seeded catalogs fold the same way on both phones                                    | `test/domain/catalog_merge_test.dart` — the plan over one union and its reverse                                                                                                                                                                                                                                                                                                                                                                                                                    |
| The losing side of a sign-in is on disk before anything is overwritten                  | `test/data/sync/adoption_test.dart` — the file is read back and the history checked in it                                                                                                                                                                                                                                                                                                                                                                                                          |
| A duplicate catalog is folded however it arrived, not only at sign-in                   | `test/data/sync/sync_engine_test.dart` — a drain folds one planted between pull and push                                                                                                                                                                                                                                                                                                                                                                                                           |
| Pending says how long it has been pending, and why                                      | `test/features/backup_state_test.dart`, `test/data/sync/sync_state_test.dart`                                                                                                                                                                                                                                                                                                                                                                                                                      |
| Removing the history from this phone leaves no tombstone to push                        | `test/data/sync/forget_test.dart`                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| A progress bar never goes backwards, past its end, or invents a denominator             | `test/data/sync/pull_test.dart` — the steps of a first pull                                                                                                                                                                                                                                                                                                                                                                                                                                        |
| Every derived number in cycle progress                                                  | `test/domain/cycle_progress_test.dart` — a deload, a switch away and back, a lift added part way, a hold, a bodyweight lift, all against hand-worked literals                                                                                                                                                                                                        |
| A regime's whole history is read through its cycles, never by scanning every workout    | `test/data/query_planning_test.dart` — the plan for the cycle-progress read finds `idx_cycles_regime` and never scans `workouts`                                                                                                                                                                                                                                    |
| A correction to a finished session reaches every reader, and changes what was lifted and never when | `test/data/logged_set_correction_test.dart` — the cycle card re-reads on the correction alone though it does not watch `set_logs`, `completedAt` and the exercise row's stamp are untouched, and a session still in progress is refused |
| A bodyweight lift is never scored on nothing, and an assumed or old bodyweight is said | `test/domain/metrics_test.dart` — an empty log is 60 kg, a weigh-in is current for seven days counted in days, and a day before the newest entry is not stale; `test/features/bodyweight_pill_test.dart` — the three faces of the pill, and none on a hold or a loaded movement |
| A bodyweight movement is scored on its share, and a seeded one's share cannot be moved | `test/domain/metrics_test.dart` — 64 per cent of 75 kg is 48, added weight is added whole, a loaded movement ignores the share; `test/features/exercise_screen_test.dart` — the row is inert on a seeded movement, required before a created one can be made, and refused outside 1 to 100; `test/data/regime_repository_test.dart` — the backfill reaches the seeded rows only |
| A cycle with alternating days closes on one of them, and the rotation follows what was trained | `test/domain/cycle_engine_test.dart` — positions, the day due, a member since deleted, both trained in one cycle; `test/data/training_repository_test.dart` — two cycles through the repository, a cycle closed early leaving the same day due, the day not due spending the position, and each of the two keeping its own prefill |
| A regime with alternating days is scored on every lift of the position, the resting day at its last reading | `test/domain/cycle_progress_test.dart` — the figure holds steady where scoring the trained day alone swings between two values, a movement the resting day dropped is left behind, a deload reading is never carried, and a cycle that has not reached the position carries nothing |
| A rotation reaches the other phone as a column, and the turn is derived there            | `test/data/sync/rotation_test.dart` — a cycle trained on one phone moves the rotation on the other, and two phones pairing a day differently settle on one answer with every day still placed                                                                                                                                                                                                                                                                                                        |
| A phase is read off the rows that declare it, and every phone reads the same answer | `test/domain/phases_test.dart` — a phase ending where the next starts or where it was cleared, the phase most of a cycle ran in with ties going to the one it ended in, the weekly rate from the first day's bodyweight, the planned length up on its 85th day for 12 weeks, and the weigh-in prompt at the edges of its 18-day span, three readings and its kilogram thresholds; `test/data/sync/phases_sync_test.dart` — two phones starting a phase on one day keep one, on two days keep both, and a clear against an edit settles on one whole row |
| The phase is asked about on the Phase card alone, and `Keep going` is not asked twice | `test/features/phase_card_test.dart` — the panel appears past the planned length and when the weigh-ins run against the phase, says nothing on track, holds one question when both stand, `Change phase` opens the sheet, and `Keep going` leaves the phase open-ended or records the day on its own row |
| A cycle is tinted by the phase most of its sessions ran in, and a deload never is | `test/domain/cycle_tints_test.dart` — a cycle takes its sessions' phase, the open one the sessions it has, a deload none whatever it ran in, and under blocks every cycle of a block the phase most of the block's sessions ran in; `test/core/cycle_axis_chart_test.dart` — one phase is one stretch, the tints stop at a deload band's edges and the band, its number and its missing point are unchanged, gridlines over a tint are `textTertiary`, and the sparkline carries none; `test/features/strength_card_test.dart` — the readout names the phase after the days and nothing for a cycle with none, keeps to one line at a 1.3 font, and joins a range with an en dash naming a shared month once, and the legend names only the phases on screen |
| Every chart's value axis comes from one function, and every label is the value of its gridline | `test/domain/value_axis_test.dart` — one value draws three gridlines, no label repeats or rounds its gridline, the cycle band holds every point up to +1000% and draws three or four gridlines, a bar axis prints at most three labels, and one isolated wild value goes off-scale where a run of two or an end point never does; `test/core/value_axis_charts_test.dart` — the trend chart, the cycle axis and the volume chart draw exactly those gridlines, labels and carets |
| Every time-based chart's date labels come from one measured ladder, ending today | `test/domain/date_axis_test.dart` — the last label is today on every rolling range, no two labels collide or repeat at any span, width or font scale up to 1.3, long ranges fall evenly mid-year counted back from this year, the first and last labels stand equally far from the plot edges, bar labels sit on whole-bar steps with equal gaps, and five years of weeks fold monthly rather than yearly |
| A line breaks at two or more empty buckets in a row (a week of empty days on a daily line) and a dotted bridge joins the readings either side, a bar keeps its zero, and the cycle line is dashed across any cycle it does not draw | `test/domain/chart_buckets_test.dart` — `lineBuckets` turns a run of two or more empty buckets between two readings into one break, crosses a single empty bucket, and drops empty buckets at either end, `crossableEmpty` lets a daily line cross up to six empty days and break at a week, `gapBridges` joins the readings either side of each break and nothing at either end, while the summed fold keeps an empty month in place; `test/domain/cycle_progress_test.dart` — a segment jumps across a deload or a spell on another regime and never under blocks; `test/core/chart_gaps_test.dart` — the trend chart breaks at a null spot and bridges it with a dotted line at 60% that carries no marker and answers no touch, draws no bridge on an unbroken line, scales to the readings, keeps the caret on the right point and the marker on a lone reading, the volume chart draws an untrained month as an empty bar in its place, and the cycle line is dashed at 60% across a resumed regime and solid under blocks |
| A chart's density is decided in pixels: markers while neighbours are 10px apart, bars at most 24px wide in slots that span the plot, and a tile folds its weeks coarser below a 4px slot | `test/domain/chart_density_test.dart` — the closest pair of a series decides its markers and a pinch brings them back, no bar is wider than the cap or its slot, and `foldForWidth` draws a year of weeks as months in a tile and as weeks across the page; `test/core/chart_density_widgets_test.dart` — two series keep or drop their markers each on its own, five capped bars are each picked by a touch in their fifth of the plot, and a tile at a year draws and names months while its chart keeps weeks |
| Changing range zooms one frame and cross-fades the two lines; new data in the same range does not | `test/core/chart_range_zoom_test.dart` — while the frame travels the trend chart draws the old and new range together in identical bounds part way between the two, each line keeps its own points, neither chart animates on its own, and once arrived only the new one remains; a change of data within one range draws a single chart |
| A deload is quiet at any length, a sparkline draws none, and a sparkline breaks where its full chart would | `test/domain/cycle_progress_test.dart` — `deloadMark` gives a full chart a band, blocks a hairline and a sparkline nothing, and `deloadNumberColoured` colours a deload's number only where every cycle is numbered and never under blocks; `test/core/cycle_axis_chart_test.dart` — the hairlines are one pixel at 20%, the sparkline draws no gridline, band or hairline, blocks or not, and a thinned ladder prints no orange number; `test/domain/phases_test.dart` — the Phase card's weekly bodyweight crosses a single week with no weigh-in, breaks at two or more, and trims empty weeks at either end |
| An exercise's change is read along one session, a drop is not red, and equalling the best is the best | `test/domain/metrics_test.dart` — `latestSessionChange` compares Push 2 with Push 2 when Push 1 is heavier, `formatChangePercent` prints `0%` unsigned and a change of 100% or more whole, `stalledSessions` counts a tie as the best; `test/features/exercise_trend_change_test.dart` — `Change in Push 2` in the text colour, a flat year is `0%` and `Peak` |
| Bodyweight draws one weigh-in, leaves an empty range uncaptioned on the log's scale, and states its change with a unit | `test/features/weigh_ins_screen_test.dart` — one weigh-in is a `TrendChart`, an empty month is an `EmptyTrendChart` with no message scaled 80 to 84, `−3.2 kg over the range`, and `Log weight` is the `+` in the app bar |
| Chart text grows with the system font and is never cut short or shrunk below 11 sp | `test/features/chart_text_scale_test.dart` — at 1.3 in Inter, the bar list fits `410 sets` and every name, a volume tile prints `sets/wk` whole, the year map's strip grows with the font, the cycle chart's top value stays in its box, a stat tile sets a long figure smaller rather than cutting it, and twenty years of an exercise print `+181%` whole; `test/domain/date_axis_test.dart` — `monthLabelsFor` thins the month names rather than shrinking them |
| Chart cards share one spacing: a line chart is 220 or 150 tall with its labels, every plot keeps its top value inside it, line and bar share one measured label strip and one measured gutter, and figures in a row are 12 apart | `test/core/chart_spacing_test.dart` — a drawn and an empty trend chart are `chartHeightFull`, the volume chart is `chartHeightCard` with every label inside it at 1.0 and 1.3, its gutter is `axisGutter` over the axis it draws, no value label rises out of the chart, and `StatRow` tiles stand `Space.md` apart |
| A legend never passes two rows, names the rest, and keys lines drawn on top of each other once | `test/domain/chart_legend_test.dart` — `legendFit` keeps any count of entries at any width to two rows with room for `and N more`, and `identicalSeries` groups a line hidden under a later one but not one seen past its end or across a break; `test/core/chart_spacing_test.dart` — nine sessions at 1.0 and 1.3, and two coinciding lines keyed as `Push 2 and Push 1` |
| A deleted regime on All time is named from its tombstone, in grey, and only one with no name to read is `Deleted programme` | `test/domain/cycle_progress_test.dart` — `timelineKeyOf` names a deleted regime `<name> (deleted)` without an identity slot and falls back on a missing or blank name, and `timelineLegendKeys` keys two deleted regimes by name, folds those of one name into one entry and those with no name into one `Deleted programme`; `test/features/all_time_screen_test.dart` — a programme deleted through `deleteRegime` is still named on the strip's legend |
| An empty chart draws the band a drawn one would, the year chip names only a year in force, and a selected open cycle stays grey | `test/core/chart_spacing_test.dart` — the same values give both trend charts the same bounds and step, the chip reads `Year` on a rolling range or `All` and `2025` on that year, and the open cycle's selected marker is filled and stroked in `textTertiary` |
| Consistency counts a year in Monday weeks clipped to the year, and leaves the week under way out of its figures | `test/domain/consistency_year_test.dart` — the first week starts at the first session, a week across New Year counts only its own year's days, a clock change loses no week, today's week is drawn but not averaged, and the years run from the first session to this one; `test/features/consistency_screen_test.dart` — the year sheet lists years newest first and switches the year, and a pressed bar names its week until pressed again |
| A volume span past about a year is named in months, then years | `test/domain/volume_history_test.dart` — `spanOfWeeks` counts weeks to 56, then reads `13 months`, `2 years`, `5 years` and `20 years`, and never a count of weeks past 56 |
| A day with no exercises is still owed by the cycle                                      | `test/data/training_repository_test.dart` — six days trained of seven leaves the cycle open on the empty one                                                                                                                                                                                                                                                                                                                                                                                         |
| A habit is counted in days kept this calendar week, and both tiles count it as Consistency does | `test/domain/habits_test.dart` — two entries on one day are one day, last Sunday and tomorrow do not count, the figure never passes seven, and `Consistency.thisWeek` is the same function; `test/features/home_screen_test.dart` — the two tiles read `1/7` over two weigh-ins and two sessions on one day |
| Reading a regime's order never starts it                                                | `test/data/training_repository_test.dart` — the positions of a regime that is not active are read with no cycle opened                                                                                                                                                                                                                                                                                                                                                                              |
| A control that is busy does not look disabled                                           | `test/features/welcome_screen_test.dart` — the two answers' fills must differ mid-sign-in                                                                                                                                                                                                                                                                                                                                                                                                          |

**A comment that states a fact about other code is the kind that rots** — how
many rows a query returns, what another provider does, what a caller
guarantees. When you write one, either move the fact into an assert or a test,
or make it a reference rather than a copy: _"bounded by the range control — see
the assert below"_ beats _"nothing ever asks for more than a year"_. Comments
that say why this code is shaped this way do not rot, because the reasoning
outlives the numbers, and those are worth their density. How that reasoning is
written down — third person, present tense, a summary line first — is
[§ 4](#4-code).
