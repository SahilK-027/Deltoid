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
3. Only then borrow from another session, returned as
   `PrefillSource.otherSession` — **and the UI must say so out loud.** Today it
   says it on the exercise's ⓘ: an amber dot on the button whenever the numbers
   are borrowed, and a sentence inside naming the session and date they came
   from. The channel may change; the disclosure may not.

Never "simplify" this to a plain most-recent lookup.

---

## 2. Data

| Rule                                                          | Why                                                                                                                                                                                                                                                                                                                                                                                 |
| ------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `WorkoutExercise` / `SetLog` are **snapshots**, not pointers  | Reordering or swapping mid-workout must never rewrite what you did in March. Same reason switching regimes creates a new `Regime` rather than editing sessions in place.                                                                                                                                                                                                            |
| **What a set trained is snapshotted too**                     | `workout_exercises.muscle`, copied at log time. Counting through a join onto `exercises.muscle` is fine over seven days and a lie over years: refiling one movement rewrote every week it had ever appeared in. **Nullable, and null is not `other`** — it means the row predates the column, so readers coalesce onto the catalog. `other` belongs to no region, so defaulting to it would drop every pre-existing set out of every chart instead of saying "unknown". |
| `LoadMode` decides what the **weight** means                  | `22.5` on a dumbbell is 45kg of load; `73` on a pec deck is 73kg. Without it every comparison downstream is garbage.                                                                                                                                                                                                                                                                |
| `MeasureMode` decides what the **count** means                | `set_logs.reps` holds reps _or_ seconds, read through the exercise's mode exactly as `weight` is read through `LoadMode`. Comparisons carry over unchanged; arithmetic that assumes reps does not — a hold has **no e1RM** and adds **nothing to session volume**, because kg × seconds is a different unit. It sits on the exercise, not the set: a plank is never sometimes reps. |
| `set_logs.partialReps` is **recorded, never arithmetic**       | A partial is a fact about how the set went, not a rep. Nothing that adds up may read it — out of session volume, out of `estimated1RM`, out of `beatsPrevious` — or grinding halves read as a record. **Shown from the ghost, never adopted from it**: `_adoptGhost` fills blanks with a plan for today, and prefilling partials would log halves nobody did. Printed as a suffix (`8+3`) or as the second half of the log's split cell, never inside the count, so the two can never be summed by accident. Meaningless on a hold — there is no half-second. |
| Warm-ups, drops and rest-pause are **excluded from progress** | `scorePerformance` counts `working` and `amrap` only. Including the rest is how naive logs claim progress that isn't there.                                                                                                                                                                                                                                                         |
| A **backoff set is volume**, though it is not progress        | `countsForProgress` protects a comparison; `countsAsVolume` counts work done. Two questions, two answers.                                                                                                                                                                                                                                                                           |
| `estimated1RM` caps reps at 12                                | Right for the long-range chart. **Wrong** for "did I beat last time" — it makes 12 → 13 reps invisible. That comparison is `beatsPrevious`, deliberately strict: more load at no cost in reps, or more reps at the same load. Heavier-for-fewer is a trade-off, not a win.                                                                                                          |
| `_cyclesSinceDeload(beforeIndex:)` is **exclusive**           | A `CycleStatus` describes a cycle by what came _before_ it. Counting the cycle itself lands the deload one cycle early. This was a real bug.                                                                                                                                                                                                                                        |
| History paging is **keyset, not offset**                      | `HistoryCursor` on `startedAt` + id. Finishing a session while the list is open must not shift the page boundary under it. Filters go in the query, never over the loaded page, or paging stops holding.                                                                                                                                                                            |
| Workouts loads through **one** snapshot                          | `todaySnapshot` + `workoutsProvider`. A per-card provider brings back the staged reveal: watched queries resolving a frame or two apart, and a frame where "no sessions" is indistinguishable from "sessions haven't loaded". Everything is on local disk — the screen should arrive whole.                                                                                            |
| **No programme is hardcoded**                                 | `seed/` ships an exercise catalog and _optional_ templates. Never seed a regime, and never put personal numbers, cues or video links in `seed_data.dart` — those are the user's, added through the UI.                                                                                                                                                                              |
| A rate needs the weeks to have happened                       | Sessions-per-week was `sessionsInTheLast29Days / 4`, which told a two-day-old install it trained "0.3 / week". `domain/consistency.dart` divides by the weeks it actually has and prints a plain count below a fortnight of history.                                                                                                                                                |
| **A position is unique among live rows**                      | `sessions`, `session_exercises`, `workout_exercises` and `set_logs` all carry a partial unique index on their parent plus `orderIndex`. Every append takes one past the highest live position rather than the live count — a tombstone leaves a gap and nothing renumbers behind it — and the index is what holds when the writer is a restore rather than a tap. **A reorder therefore cannot renumber in place**: see `renumber` in [§ 4](#4-code). |
| **One session is open at a time**                             | A partial unique index on `workouts (status) WHERE status = 'inProgress'`, the same shape as the single-active-regime one. `startWorkout`'s check reads outside the transaction that writes, so Start and the backfill sheet could both find nothing running — and `openWorkout` then hides the loser behind the newer one: unreachable, in progress forever, counted by nothing. |
| **A day answers to one name in its regime**                   | `idx_sessions_name_live`, keyed on `lower(trim(name))`. The prefill disclosure names the day it borrowed from, History filters by it, and the chart labels its lines with it — two live `Push 1`s makes all three ambiguous. Across regimes is fine, which is why `LoggedSession` carries the regime name. |
| **An enum column is checked in the database**                 | `textEnum` throws on a string no member answers to, and takes the **whole result set** with it — one bad row blanks the log, history and the chart together. Every enum column carries a hand-written `CHECK … IN (…)`, and `schema_constraints_test` walks every member of every enum, so a value added to one and not the other fails a test rather than a screen. |
| **A number that cannot mean anything is refused at the column** | Deload percentages, backwards rep ranges, a `dayKey` of 0, a session ending before it started, a set that is a leg of itself, a bodyweight of 850. Each is reachable only through a restore or a merged row — the writer that does not pass the repository, which is what a server becomes. **The column is the backstop, never the gate**: every one is also bounded at the input, or a slip becomes a failed write instead of a refused keystroke. |

**Cloud backup has its own invariants, and they live in
[SYNC.md § 13](SYNC.md#15-what-sync-may-never-do).** The four that are really
about data rather than about protocol are repeated here, because this is the
list people read:

| Rule | Why |
| ---- | --- |
| **No screen waits on the network** | Offline-first is the architecture, not a stage. A read comes from local disk and a write returns when SQLite returns; the cloud is drained behind it. A screen that awaits a radio between a thumb and a set is the one change that cannot be walked back. |
| **Two histories are never merged silently** | They share no ids, so a merge is not a reconciliation — it is a union claiming you trained twice as often as you did. `backup_service` already refuses this for restore; signing in asks the same question, with counts, and exports the losing side first. |
| **Deletes stay tombstones** | A hard delete has no `deleted_at` to push and is resurrected by the next pull. Every delete in the app is already a tombstone; sync is the reason it had to be. |
| **A pulled row is written by the same code that writes a restored row** | Same constraints, same transaction discipline, same repairs. A second write path is a second set of bugs, and it is the path with no screen watching it. *Through the repositories* is the thing this cannot be: they are shaped like intentions, there is no `upsertSession(row)`, and a repository that took a whole row would be the second path. |
| **No merge deletes logged work** | The twelve unique indexes are correct for one device and eleven are reachable by two doing something ordinary — appending is the commonest action in the app, and two devices appending to one parent both compute `max + 1`. A collision is two *different* rows claiming one slot, which last-write-wins cannot resolve, so the rule is re-slot, re-flag or re-number. Never discard. |
| **A conflict is decided on the server's clock** | `updatedAt` is a phone's wall clock, and two phones do not agree. The disagreement does not average out: a device running ten minutes fast wins every conflict it is ever in, and the other device's edits vanish silently. `nowMs` being monotonic is the half of this that is local; `server_updated_at` is the other half. |

**Three levels of note, and they never leak into each other:**

| Column                    | Scope                         | Written from           |
| ------------------------- | ----------------------------- | ---------------------- |
| `exercises.notes`         | the movement, forever — a cue | catalog editor         |
| `workout_exercises.notes` | this exercise on this day     | log ⋯, summary, detail |
| `set_logs.note`           | one set                       | the set sheet          |

Editing the second must never reach the first: the snapshot row is a copy for
exactly this reason.

**Improvising is a snapshot edit, and stays one.** Adding a movement
mid-session, dropping one or running the day out of order changes today and
nothing else. The end-of-session screen then _offers_ each change back to the
template (`domain/session_diff.dart`), one at a time, and `applySessionChanges`
writes `session_exercises` and only that — so keeping a change never rewrites a
logged workout.

---

## 3. Schema and migrations

Drift code has to be regenerated after any edit to `lib/data/db/tables.dart`:

```bash
dart run build_runner build
```

**The ladder is running.** `schemaVersion` is 2 and `MigrationStrategy` has an
`onUpgrade`, in `lib/data/db/migrations.dart`. So a schema change is:

1. the column or `@TableIndex` in `tables.dart`,
2. `dart run build_runner build`,
3. **a default in `lib/data/db/table_spec.dart`** for that table,
4. **a rung**: `schemaVersion` up one, and a step in `upgradeSchema` guarded by
   the version it was added at.

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
before any second phone does** — it lets two devices running *different builds*
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
*before* the rebuild that narrows the column.

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

**Never copy the project to keep an old version around.** No `old-*/`, no
`*.bak`, no second checkout, no `git worktree` for "reference". Git holds every
previous state; a copy goes stale the moment it is made, gets edited by mistake,
and shows up in searches as a second answer to every question. One was found at
99 MB, nine commits back, holding a test file two revisions out of date. Read
history instead:

```bash
git show <commit>:lib/features/workouts/workouts_screen.dart
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
  up. The log screen schedules the end of the rest with
  `WorkoutNotifications.scheduleRestDone` as it goes to the background and
  cancels it on resume, so exactly one alert fires either way. The same rule
  covers anything else that must happen at a wall-clock moment.
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
Google Fit, 1RM testing protocols, streaks, levels, muscle maps, motivational
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
sharing, no profiles, no feed, no account as a *feature* — a login you see once
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
behalf. Five things still need hardware before they can be trusted: the rest
tone, the haptics, the wakelock, audio ducking and the share sheet.

**Make one commit per coherent change**, and put the reasoning in the body. Say
why the change was made rather than what it changed, because the diff already
says what.

### A rule that matters is a rule something checks

A comment cannot fail a build. Every rule that lives only in prose holds exactly
as long as everyone reads the prose, and the record says they do not: the volume
query documented its own bound, an `All` range was added, and the screen took
380ms a rebuild with the comment still sitting there being correct.

So a load-bearing rule gets a mechanism, in this order of preference: a **type**
that makes the violation unstateable, a **schema constraint**, an **assert** at
the boundary (free in release), or a **test** where the rule is about behaviour
rather than shape. Where the checks live now:

| Rule | Mechanism |
| --- | --- |
| The structural invariants of the database | `lib/data/db/invariants.dart` — sixteen rules re-derived in SQL, each with a perturbation test in `test/integrity/invariant_oracle_test.dart`. **It ships**: a restore refuses a file breaking a rule no repair can fix, and reports what the repairs could not reach; a pull reports rather than refuses, because § 15 rule 9. The three sync-column rules are advisory everywhere — a log stamped by a broken clock is still the whole log |
| Those invariants under arbitrary use | `test/integrity/model_fuzz_test.dart` |
| Every derived number | `test/domain/` — hand-computed literals, never `expect(f(x), f(x))` |
| A query's row count is bounded | an `assert` at the boundary, or a comment saying why it does not grow — `training_repository.dart` |
| A painter never clamps to a bound it computed | `test/core/clamp_bounds_test.dart` |
| A screen you left stops querying | `test/features/volume_provider_lifetime_test.dart` |
| An exception to THEME or RULES is written into the document | `test/core/documented_exceptions_test.dart` |
| The light ramp is legible | `test/core/light_theme_test.dart` |
| A rewritten query returns what the old one did | `test/data/query_conversion_test.dart` |
| Every column has a default, or has always been written | `test/data/table_spec_test.dart` — walks every column of every table |
| Every rung of the ladder can be replayed | `test/data/migrations_test.dart` — a full upgrade over a database that already has everything |
| The server schema is the local one | `test/data/server_schema_test.dart` — every column of every syncable table, read off `supabase/migrations` |
| Nothing above `data/sync/` knows which backend this is | `test/features/no_supabase_in_features_test.dart` |
| `dirty` is cleared only against an unchanged `updatedAt` | `test/data/sync/push_test.dart` — a row edited while its own push is in flight is still owed |
| A pulled row is never re-stamped, and `last_pull_at` moves only after its batch commits | `test/data/sync/pull_test.dart` |
| A pull that has nothing to do writes nothing | `test/data/sync/pull_test.dart` — a second pull applies zero, or the rewrite wakes every stream on the table and calls the engine back |
| `(updated_at, device_id)` is not treated as a version identity | `test/data/sync/cloned_device_test.dart` — two installs under one `device_id`, which the manifest now refuses to let Android create |
| The merge order never runs out of discriminators | `test/domain/sync_merge_test.dart` — two versions on one stamp and one device id still pick one winner, swapped |
| The connection opens on the pragmas the durability claim rests on | `test/data/connection_pragmas_test.dart` — read off a real file, because in-memory sqlite is always `journal_mode = memory` |
| A backup file is never half a file | `test/data/backup_service_test.dart` — the rows go to a `.part` and the backup arrives by rename |
| A stamp handed out is never handed out again, across a restart | `test/data/stamp_floor_test.dart` — the mark is seeded from `app_settings` at open, leased ahead of the clock, and written down at close |
| Every merge rule is deterministic **and symmetric** | `test/domain/sync_merge_test.dart` — each two-row rule is asserted with the arguments swapped |
| Two devices converge | `TwoDevices.converge` in `test/data/sync/two_devices.dart`, used by every collision test |
| Two devices under arbitrary use converge, and lose nothing | `test/integrity/sync_fuzz_test.dart` — the oracle on both phones after every operation |
| The catalog is seeded once, whichever order sign-in and first use arrive in | `test/data/sync/adoption_test.dart` — no `starterKey` is live twice after any of the three shapes |
| Two seeded catalogs fold the same way on both phones | `test/domain/catalog_merge_test.dart` — the plan over one union and its reverse |
| The losing side of a sign-in is on disk before anything is overwritten | `test/data/sync/adoption_test.dart` — the file is read back and the history checked in it |
| A duplicate catalog is folded however it arrived, not only at sign-in | `test/data/sync/sync_engine_test.dart` — a drain folds one planted between pull and push |
| Pending says how long it has been pending, and why | `test/features/backup_state_test.dart`, `test/data/sync/sync_state_test.dart` |
| Removing the history from this phone leaves no tombstone to push | `test/data/sync/forget_test.dart` |
| A progress bar never goes backwards, past its end, or invents a denominator | `test/data/sync/pull_test.dart` — the steps of a first pull |
| A control that is busy does not look disabled | `test/features/welcome_screen_test.dart` — the two answers' fills must differ mid-sign-in |

**A comment that states a fact about other code is the kind that rots** — how
many rows a query returns, what another provider does, what a caller
guarantees. When you write one, either move the fact into an assert or a test,
or make it a reference rather than a copy: *"bounded by the range control — see
the assert below"* beats *"nothing ever asks for more than a year"*. Comments
that say why this code is shaped this way do not rot, because the reasoning
outlives the numbers, and those are worth their density.
