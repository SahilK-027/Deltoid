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
| `LoadMode` decides what the **weight** means                  | `22.5` on a dumbbell is 45kg of load; `73` on a pec deck is 73kg. Without it every comparison downstream is garbage.                                                                                                                                                                                                                                                                |
| `MeasureMode` decides what the **count** means                | `set_logs.reps` holds reps _or_ seconds, read through the exercise's mode exactly as `weight` is read through `LoadMode`. Comparisons carry over unchanged; arithmetic that assumes reps does not — a hold has **no e1RM** and adds **nothing to session volume**, because kg × seconds is a different unit. It sits on the exercise, not the set: a plank is never sometimes reps. |
| `set_logs.partialReps` is **recorded, never arithmetic**       | A partial is a fact about how the set went, not a rep. Nothing that adds up may read it — it is out of session volume, out of `estimated1RM` and out of `beatsPrevious` — or a set of grinding halves reads as a personal record. It is shown from the ghost but **never adopted from it** — `_adoptGhost` fills blanks with a plan for today, and partials are a note on what happened, so prefilling them would log halves nobody did. In the log it is the second half of a split count cell, and everywhere else it prints as a suffix (`8+3`) — never inside the count, which is what keeps the two numbers from ever being summed by accident. Meaningless on a hold: there is no half-second. |
| Warm-ups, drops and rest-pause are **excluded from progress** | `scorePerformance` counts `working` and `amrap` only. Including the rest is how naive logs claim progress that isn't there.                                                                                                                                                                                                                                                         |
| A **backoff set is volume**, though it is not progress        | `countsForProgress` protects a comparison; `countsAsVolume` counts work done. Two questions, two answers.                                                                                                                                                                                                                                                                           |
| `estimated1RM` caps reps at 12                                | Right for the long-range chart. **Wrong** for "did I beat last time" — it makes 12 → 13 reps invisible. That comparison is `beatsPrevious`, deliberately strict: more load at no cost in reps, or more reps at the same load. Heavier-for-fewer is a trade-off, not a win.                                                                                                          |
| `_cyclesSinceDeload(beforeIndex:)` is **exclusive**           | A `CycleStatus` describes a cycle by what came _before_ it. Counting the cycle itself lands the deload one cycle early. This was a real bug.                                                                                                                                                                                                                                        |
| History paging is **keyset, not offset**                      | `HistoryCursor` on `startedAt` + id. Finishing a session while the list is open must not shift the page boundary under it. Filters go in the query, never over the loaded page, or paging stops holding.                                                                                                                                                                            |
| Today loads through **one** snapshot                          | `todaySnapshot` + `todayProvider`. A per-card provider brings back the staged reveal: watched queries resolving a frame or two apart, and a frame where "no sessions" is indistinguishable from "sessions haven't loaded". Everything is on local disk — the screen should arrive whole.                                                                                            |
| **No programme is hardcoded**                                 | `seed/` ships an exercise catalog and _optional_ templates. Never seed a regime, and never put personal numbers, cues or video links in `seed_data.dart` — those are the user's, added through the UI.                                                                                                                                                                              |
| A rate needs the weeks to have happened                       | Sessions-per-week was `sessionsInTheLast29Days / 4`, which told a two-day-old install it trained "0.3 / week". `domain/consistency.dart` divides by the weeks it actually has and prints a plain count below a fortnight of history.                                                                                                                                                |

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

**Nothing is released, so there is no migration ladder.** `schemaVersion` is 1
and `MigrationStrategy` has an `onCreate` and no `onUpgrade`. Every database
that exists is one we made and can throw away, so a schema change is:

1. the column or `@TableIndex` in `tables.dart`,
2. `dart run build_runner build`,
3. **a default in the backup codec** for that table,
4. reinstall the app on every device, because there is no upgrade path and
   the old database will not be migrated onto the new shape.

This carried a v2..v8 ladder, one step per schema change made during the build,
each migrating a database shape that only ever existed on a test device. Every
future change would have had to keep all of them working forever, for installs
that will never exist. It went, and it starts again — properly, one step per
released change, with `schemaVersion` climbing from 1 — the day a build reaches
a phone that is not ours. **Once that happens this section is wrong and has to
be rewritten before the next schema change**, along with the rules the ladder
needs: every step idempotent (`addColumnIfMissing`, `CREATE INDEX IF NOT
EXISTS`, never bare `m.addColumn` / `m.createIndex`, because a device given an
earlier build comes back with the structure in place and the stamp behind it,
and the bare form throws on launch before any screen), and a test that runs a
full upgrade over a database that already has everything.

Step 3 stays true whether or not a ladder exists, and it is the easy one to
miss and the expensive one to get wrong. `Exercise.fromJson` is generated
against _today's_ columns and reads every one of them unconditionally, so a
file exported before the column existed throws a null cast on restore — with
the only copy of a user's history in the file picker. `backup/backup_service.dart`
spreads a default map under each restored row for exactly this reason, and
`test/data/backup_service_test.dart` restores a payload with a column stripped
out to keep it honest. An **index-only** change is the one case that skips it:
nothing new is stored, so nothing can be missing from an older file.

A backup also carries the `schemaVersion` it was written against, and import
refuses anything **newer** than the running build can read rather than clearing
the tables and failing halfway. Collapsing the version to 1 therefore made every
previously exported file unrestorable, which was acceptable exactly once, while
the only data anywhere was test data.

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
held.

**Never watch a constant query.** The "invalidate on write" trick —
`db.customSelect('SELECT 1', readsFrom: {…}).watch()` — emits **once** and then
never again, because `SELECT 1` never changes. Writes land in SQLite correctly
and the UI freezes forever, with no error anywhere. Use `db.watchQuery(...)`
from `lib/data/db/watch.dart`.

**`ref.read` on a provider nobody watches returns nothing.** The regime switcher
read `allRegimesProvider` on demand, got `AsyncLoading` every time and rendered
an empty list — which is why creating a regime looked like it deleted the old
one. Watch it, or go through the repository.

**Never capture a `WidgetRef` in a callback that outlives its widget.** A sheet
that closes itself before opening the next one leaves its `ref` disposed, and
`ref.read` from the second sheet then throws `Cannot use "ref" after the widget
was disposed`. It surfaces from a gesture handler, so the visible symptom is a
button that does nothing at all. Read the repository _before_ popping and pass
that — a repository is a plain object and outlives the widget that looked it up.

**Don't hold a `WidgetRef` across an `await` that changes the screen.** Starting
a workout swaps the "up next" card for the resume card, disposing the widget
that started it; clearing a flag through that dead ref throws inside `finally`
and leaves the button disabled forever. Capture
`ProviderScope.containerOf(context)` before the first await.

**`valueOrNull ?? const []` turns "loading" into "empty".** Loading and empty
are different states; a screen with more than one query needs them told apart,
or it needs one query.

**`Isolate.run` inside a class captures `this`.** Moving the backup's
`jsonEncode` off the UI isolate failed at the _send_, not the JSON: the closure
carried an `AppDatabase` wrapping a sqlite3 FFI handle — "object is
unsendable". Both helpers are top-level functions in `backup_service.dart`; keep
them there.

**Every per-second rebuild goes through `core/widgets/ticking.dart`**, wrapping
the clock and never the screen around it.

**`CrossAxisAlignment.stretch` in an unbounded Row** is a layout error that
silently blanks the screen with nothing in logcat. Use `IntrinsicHeight`.

**A signed delta is computed from what is shown.** Two bodyweights 0.2 apart
differ in kilograms, so the row printed a sign, and then the display rounding
snapped the difference and it read `+0`. Compare `unit.display(a)` against
`unit.display(b)` — `formatDeltaInUnit` does, and returns null when both round
to the same figure.

**`formatWeight` also formats computed numbers.** An estimated 1RM is an
arbitrary double; `55.733333333333334 kg` shipped to a screen once.

**Adopt ghost values when completing a set.** Typing only the reps is the normal
case — same weight as last week, one more rep. Without `_adoptGhost` the set
stores reps against a null weight: invisible to the chart, useless as next
week's prefill.

**Never copy the project to keep an old version around.** No `old-*/` folders,
no `*.bak`, no second checkout, no `git worktree` for "reference". Git holds
every previous state; a copy is 100 MB of build output that goes stale the
moment it is made, gets edited by mistake, and shows up in searches as a second
answer to every question. One was found at 99 MB, nine commits back, holding a
test file two revisions out of date. Read history instead:

```bash
git show <commit>:lib/features/today/today_screen.dart
git log --oneline -- <path>
git diff <commit> -- <path>
```

---

## 5. Interface

The design system is [THEME.md](THEME.md), and it decides everything visual:
the tokens, the type roles, the component vocabulary, and the six rules that
settle a close call. Read it before drawing anything.

Three rules belong here rather than there, because breaking them breaks
behaviour rather than looks:

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

---

## 6. Scope

This is a single-user personal tool, not a product. Scope discipline is a
requirement, and the answer to "should we add…" is usually no.

**Deliberately absent, and staying that way:** social features, macros /
nutrition, AI coaching, an exercise GIF or video library, Apple Health /
Google Fit, 1RM testing protocols, streaks, levels, muscle maps, motivational
copy, programme sharing or marketplaces, accounts, and **effort / RIR
ratings** — a number you rate yourself with after the set, which is one more
thing to answer at the bar and nothing downstream reads.

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
