# Deltoid

A personal, offline-first training log. Flutter + SQLite.

Built to replace a Notion setup — one table per session — that worked well for
progressive overload but couldn't answer "where was I last year", couldn't show
consistency, and had no concept of a deload.

**No programme is baked in.** A fresh install has an exercise catalog and
nothing else: you build your own split, or start from one of the templates
(PPL 6-day / 3-day, Upper/Lower, Full body) and edit it into shape. Templates
write ordinary sessions and slots — nothing about them is special afterwards.

**This is a single-user personal tool, not a product.** Scope discipline is a
requirement. Read [Non-goals](#non-goals) before adding anything.

---

## The one rule that matters

**Last-time numbers are scoped to the _session_, never to the exercise.**

Incline DB press is the opener in Push 1 at 22.5kg, and sits second in Push 2 at
20kg. Each session keeps its own progression. Every off-the-shelf tracker scopes
history per exercise and collapses those into one number — that is precisely why
this app exists.

`resolvePrefill` in `lib/domain/prefill.dart` enforces it:

1. Most recent **completed, non-deload** workout **with the same `sessionId`**.
2. Failing that, a **deload** performance of the same session (still this slot's
   progression).
3. Only then borrow from another session — and the UI must say so out loud
   ("From Push 2 · 12 Jul").

Never "simplify" this to a plain most-recent lookup.

---

## Domain model

```
Regime  ──  the programme (PPL, Upper/Lower). Any number of them exist at
            once; exactly one is active. Creating one never deletes another.
  └─ Session  ──  one training day template, ordered ("Push 1" … "Leg 2")
       └─ SessionExercise  ──  an exercise slot: order, target sets, rep range

Cycle  ──  one full pass through every Session in the Regime.
           NOT a calendar week. Advances when the work is done.
           Deload fires after N complete cycles.

Workout  ──  one Session actually performed, on a day, inside a Cycle
  └─ WorkoutExercise  ──  a SNAPSHOT, not a pointer to the template
       └─ SetLog  ──  weight, reps, type, added weight, rest, note
```

### Invariants that are easy to break

| Invariant                                               | Why                                                                                                                                                                                                                                                                                  |
| ------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `WorkoutExercise` / `SetLog` are **snapshots**          | Reordering or swapping mid-workout must never rewrite what you did in March. Same reason switching regimes creates a new `Regime` instead of editing sessions in place.                                                                                                              |
| `_cyclesSinceDeload(beforeIndex:)` is **exclusive**     | A `CycleStatus` describes a cycle by what came _before_ it. Counting the cycle itself makes the deload land one cycle early. This was a real bug.                                                                                                                                    |
| `LoadMode` decides what a number means                  | `22.5` on a dumbbell is 45kg of load; `73` on a pec deck is 73kg. Without it every comparison downstream is garbage.                                                                                                                                                                 |
| Warmups / drops / rest-pause are excluded from progress | `scorePerformance` only counts `working` and `amrap`. Including the rest is how naive logs claim progress that isn't there.                                                                                                                                                          |
| `estimated1RM` caps reps at 12                          | Right for the long-range chart. **Wrong** for "did I beat last time" — it makes 12 → 13 reps invisible. That comparison uses `beatsPrevious` instead, deliberately strict: more load at no cost in reps, or more reps at the same load. Heavier-for-fewer is a trade-off, not a win. |
| The log screen owns the **horizontal axis**             | It's a `PageView`, one exercise per page. The **set row** is the one exception: a drag that starts on a row slides it left to uncover that row's delete, and the page turns from everywhere else. Nothing else inside the log may claim a horizontal gesture. |
| Today loads through **one** snapshot                     | `todaySnapshot` + `todayProvider`. Adding a per-card provider brings back the staged reveal: a layer of watched queries resolving a frame or two apart, and a frame where "no sessions" is indistinguishable from "sessions haven't loaded". Everything is local — the screen should arrive whole. |

---

## Layout

```
lib/
  domain/          Pure Dart. No Flutter, no database. Heavily unit-tested.
    prefill.dart      resolvePrefill + applyDeload      ← the core rule
    cycle_engine.dart CycleStatus, planNextCycle        ← cycles + deload timing
    metrics.dart      e1RM, effective load, beatsPrevious, stall detection
    enums.dart        LoadMode, SetType, SkipReason, …

  data/
    db/              drift schema (tables.dart), database.dart, watch.dart
    repositories/    training_repository (logging, cycles, history, progress)
                     regime_repository  (programme editing)
    seed/            starter exercise catalog + optional regime templates
    backup/          whole-DB JSON export / restore

  core/            theme tokens, shared providers, primitives, id generation
                   rest_alert.dart  end-of-rest buzz + tone (audio session)
                   widgets/ticking.dart  every per-second rebuild goes through
                                         this, wrapping the clock and never the
                                         screen around it
  features/        today · log · history · progress · regime · settings

assets/
  audio/           rest_done.mp3 — the end-of-rest tone
```

Four tabs: **Today** (next session, heatmap), **History**, **Progress** (one
exercise, one chart), **Regime** (sessions, exercise catalog, deload config).
Settings behind the gear on Today.

Today reads top to bottom as one thought: how long since the last session, the
one session to start, then the record. Three rules about it, all learned the
hard way:

- **Nothing on it is drawn twice.** The cycle has appeared as labelled bars in
  the hero, as a tappable list under it, and as both at once — which pushed the
  heatmap off the bottom of the screen and needed a scroll-to-anchor to
  compensate. The hero's hairline track is the only rendering of cycle progress;
  the `n of m done` beside the cycle number is the only summary of it.
- **A cycle is not a week, and Today must not imply it is.** The full session
  list used to sit under the hero. Six full-width rows on a screen called Today
  read as "here is your plan for today" — but a cycle advances when the work is
  done, not when the calendar turns, and the list was the loudest thing making
  that false promise. It is a sheet now, behind *Train another session*.
- **The queue head is a description, not an instruction.** The hero names the
  first session not yet trained. Any other session is two taps away — open the
  sheet, pick it — and it opens with every session marked done / next / neither,
  because an out-of-order session is normal, not an error.

A session left open for more than 24 hours stops being "in progress" and
becomes a decision. Two different things get called that, and they are not
treated the same:

- **Nothing logged in it** — a mis-tap on Start. Swept at launch
  (`sweepAbandonedWorkouts`), silently, because it blocks every other session
  behind "finish the one you are in" and there is nothing in it to lose.
- **Sets logged in it** — trained it, never pressed Finish. Kept. The card says
  *Left open*, gives the date and the set count instead of a 51-hour stopwatch,
  and offers **Finish it** (saved to the day it was started, since `dayKey` was
  stamped at Start) or **Discard**, both behind a confirmation. The app never
  deletes a real day's work on its own.

Both sheets on Today list session names, so both are titled and subtitled:
*Start a session* is about now, *Log a past session* is about a day already
gone. The backfill sheet asks for the day **first** and keeps it on screen while
you pick — the day is the only thing that makes it different from starting a
session, and a bare calendar dialog after the fact gave no sign the two
questions were one answer.

History has three readings of the same data, because "what did I do" means
three different things:

- **Sessions** — every finished workout, newest first, grouped by month and
  paged as you scroll. Tap a day to see exactly what was logged in it, set by
  set, from that workout's own snapshot rows. A day logged by mistake can be
  deleted from there; if it closed a cycle, the cycle reopens.
- **Exercises** — every movement that has actually been trained, each opening
  its own paged history with the session it belonged to on every row. Rows
  expand in place rather than opening the day they came from — drilling day →
  exercise → day → exercise was a loop with no destination.
- **Table** — the old Notion layout for one session: exercises down the side,
  one column per date, pulling in older columns as it scrolls right. Lists
  every session ever trained, including regimes you have since switched away
  from.

Paging is keyset (`startedAt`, then id) rather than offset, so finishing a
session while scrolling can't push an unread row past the cursor. See
`HistoryCursor` and `workoutFeed` in `training_repository.dart`.

---

## Running it

```bash
export ANDROID_HOME=$HOME/Library/Android/sdk
export PATH=$ANDROID_HOME/emulator:$ANDROID_HOME/platform-tools:$PATH
```

```bash
flutter pub get && dart run build_runner build
```

```bash
flutter test && flutter analyze
```

### Environment notes (as of 2026-07-29, this Mac)

- **No Xcode** — only CommandLineTools. iOS cannot be built or run here.
  Android is the only verified target.
- The emulator **crashes when given a window** on macOS 26. Run it headless:

```bash
emulator -avd Pixel_3a_API_31_arm64-v8a -no-window -no-snapshot -gpu swiftshader_indirect
```

- Screenshot it with `adb exec-out screencap -p > out.png`.
- Inspect on-device data (quote the whole command or the shell mangles it):

```bash
adb shell "run-as com.deltoid.deltoid sqlite3 /data/data/com.deltoid.deltoid/app_flutter/deltoid.sqlite 'select count(*) from workouts'"
```

- `file_picker` resolves to an ancient 3.0.4 that breaks the Gradle build
  (missing namespace). `file_selector` is used instead — don't swap it back.
- Regenerate drift code after **any** change to `tables.dart`:
  `dart run build_runner build`.
- **`schemaVersion` is 1 and there is no `onUpgrade`** (`data/db/database.dart`
  has `onCreate` and nothing else). A schema change does not migrate an install
  — it breaks it, and the fix is uninstall and reinstall. Free while the only
  databases are on test devices, which is still true: the catalog re-seeds
  itself and no programme is baked in, so a wipe costs one template tap. The
  first install holding training you care about is when `onUpgrade` has to
  start existing. Note the version is also stamped into every backup and
  restore rejects anything newer (`backup/backup_service.dart`), so a bump
  invalidates old exports unless that path is handled too.

---

## Traps already hit (don't re-learn these)

**drift dedupes watched queries.** The common "invalidate on write" trick —
`db.customSelect('SELECT 1', readsFrom: {...}).watch()` — emits **once** and
then never again, because `SELECT 1` never changes. Writes land in SQLite
correctly and the UI freezes forever, with no error anywhere. Use
`db.watchQuery(...)` from `lib/data/db/watch.dart`, which is built on
`tableUpdates`.

**`CrossAxisAlignment.stretch` in an unbounded Row.** Inside a `ListView` a
Row's cross axis is unbounded; `stretch` there is a layout error that silently
blanked most of the Progress screen with nothing in logcat. Use
`IntrinsicHeight`.

**Adopt ghost values when completing a set.** Typing only the reps is the normal
case (same weight as last week, one more rep). Without `_adoptGhost` the set
stores reps against a null weight: invisible to the chart, and unable to
register as a PR.

**`ref.read` on a provider nobody watches returns nothing.** The regime switcher
read `allRegimesProvider` on demand, got `AsyncLoading` every time, and rendered
an empty list — which is why creating a regime looked like it deleted the old
one. Watch the provider, or go through the repository.

**Don't hold a `WidgetRef` across an `await` that changes the screen.** Starting
a workout swaps the "up next" card for the resume card, disposing the widget
that started it; clearing a flag through that dead ref throws inside `finally`
and leaves the button disabled forever. Capture
`ProviderScope.containerOf(context)` before the first await.

**`valueOrNull ?? const []` turns "loading" into "empty".** Today read five
providers that way. The frame after the regime arrived but before its sessions
did rendered the "no sessions in this regime" empty state at a regime with six —
and every card below appeared a frame or two apart, so an app whose data is on
local disk still looked like it was fetching. Loading and empty are different
states; a screen with more than one query needs them told apart, or one query.

**`formatWeight` also formats computed numbers.** An estimated 1RM is an
arbitrary double — `55.733333333333334 kg` shipped to the screen before it was
capped at two decimals.

---

## Status

Tracked in **[TODO.md](TODO.md)** — what is built, what isn't, and the order of
the work in flight. It moved out of here on purpose: this file is for what stays
true, and a status list is out of date the day after it is written.

The design language every screen implements is **[THEME.md](THEME.md)**.

---

## Non-goals

Deliberately absent, and should stay that way: social features, macros /
nutrition, AI coaching, an exercise GIF library, Apple Health / Google Fit,
plate calculators, 1RM testing protocols, volume dashboards, a PR feed.

The app should stay small enough to open mid-set and understand at a glance.
When in doubt, don't add the screen.
