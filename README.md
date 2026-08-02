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
3. Only then borrow from another session — and the UI must say so out loud.
   It says it on the exercise's ⓘ: an amber dot on the button whenever the
   numbers are borrowed, and a sentence inside naming the session and date
   they came from. The channel may change; the disclosure may not.

Never "simplify" this to a plain most-recent lookup.

---

## Domain model

```
Regime  ──  the programme (PPL, Upper/Lower). Up to six exist at once;
            exactly one is active. Creating one never deletes another.
            Names are unique among live regimes (trimmed, case-insensitive):
            the name and the colour are all a History row has to identify it.
            Six is the size of the identity palette: a regime owns a hue
            (`identityIndex`), no two live regimes share one, and a deleted
            regime hands its slot back. The seventh create is refused.
  └─ Session  ──  one training day template, ordered ("Push 1" … "Leg 2")
       └─ SessionExercise  ──  an exercise slot: order, target sets, rep range

Cycle  ──  one full pass through every Session in the Regime.
           NOT a calendar week. Advances when the work is done.
           Deload fires after N complete cycles.

Workout  ──  one Session actually performed, on a day, inside a Cycle
  └─ WorkoutExercise  ──  a SNAPSHOT, not a pointer to the template
       └─ SetLog  ──  weight, reps, type, added weight, rest, note
```

**Three levels of note, and they never leak into each other:**

| Column | Scope | Written from |
| --- | --- | --- |
| `exercises.notes` | the movement, forever — a cue | catalog editor |
| `workout_exercises.notes` | this exercise on this day | log ⋯, summary, detail |
| `set_logs.note` | one set | the set sheet |

Editing the second must never reach the first: the snapshot row is a copy for
exactly this reason.

**Improvising is a snapshot edit, and staying that way is deliberate.** Adding
a movement mid-session, dropping one or running the day out of order changes
today and nothing else. The end-of-session screen then *offers* each change back
to the template (`domain/session_diff.dart`), one at a time, and
`applySessionChanges` writes `session_exercises` and only that — so keeping a
change never rewrites a logged workout.

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

Four tabs: **Workouts** (next session, heatmap — the landing screen the code
still calls `today`), **Regime** (the regime library, the programme editor, the
exercise catalog, deload config), **History** (the session feed, the
per-exercise index, and the charts Progress used to hold), **Settings**.

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

History has two readings of the same data, because "what did I do" means two
different things:

- **Sessions** — every finished workout, newest first, grouped by month and
  paged as you scroll. Tap a day to see exactly what was logged in it, set by
  set, from that workout's own snapshot rows. A day logged by mistake can be
  deleted from there; if it closed a cycle, the cycle reopens.
- **Exercises** — every movement that has actually been trained, each opening
  its own paged history with the session it belonged to on every row. Rows
  expand in place rather than opening the day they came from — drilling day →
  exercise → day → exercise was a loop with no destination.

There were three. The third was the old Notion layout — one session's
exercises down the side, one column per date — and it was deleted: the feed
answers "which day" better and the per-exercise history answers "how has this
moved" better. Re-creating the spreadsheet this app replaced, inside it, is not
a third reading of history.

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
- **`schemaVersion` is 6, and `onUpgrade` is real** — v2 added
  `set_logs.parent_set_id`, v3 `exercises.bar_kind`, v4 re-mapped a dropped
  `bar_kind` value, v5 added `regimes.identity_index`, v6 indexed
  `bodyweight_logs.day_key`. A **column** change means three edits, not one:
  the column in `tables.dart`, the `from < n` step in
  `data/db/database.dart`, and **a default in the backup codec** for that table.
  The last one is the easy one to miss and the expensive one to get wrong:
  `Exercise.fromJson` is generated against today's columns and reads every one
  of them unconditionally, so a file exported before the column existed throws
  a null cast on restore — with the user's only copy of their history in the
  file picker. `backup/backup_service.dart` spreads a default map under each
  restored exercise row for exactly this reason, and
  `test/data/backup_service_test.dart` restores a payload with the column
  stripped out to keep it honest. An **index-only** migration (v6) is the one
  case that skips the third edit: nothing new is stored, so nothing can be
  missing from a file exported before it.

---

## Traps already hit (don't re-learn these)

**drift dedupes watched queries.** The common "invalidate on write" trick —
`db.customSelect('SELECT 1', readsFrom: {...}).watch()` — emits **once** and
then never again, because `SELECT 1` never changes. Writes land in SQLite
correctly and the UI freezes forever, with no error anywhere. Use
`db.watchQuery(...)` from `lib/data/db/watch.dart`, which is built on
`tableUpdates`.

**Never capture a `WidgetRef` in a callback that outlives its widget.** A sheet
that closes itself before opening the next one — the regime settings sheet does
exactly this — leaves its `ref` disposed, and `ref.read` from the second
sheet's Save button then throws `Cannot use "ref" after the widget was
disposed`. It surfaces as an exception from a gesture handler, so the visible
symptom is a button that does nothing at all. Read the repository *before*
popping and pass that: a repository is a plain object and outlives the widget
that looked it up.

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

**A rate needs the weeks to have happened.** Sessions-per-week was
`sessionsInTheLast29Days / 4`, which told a two-day-old install it trained
"0.3 / week" — divided by three weeks that did not exist.
`domain/consistency.dart` divides by the weeks it actually has and prints a
plain count below a fortnight of history. Any change belongs in that file,
tested without a database.

**`Isolate.run` inside a class captures `this`.** Moving the backup's
`jsonEncode` off the UI isolate failed at the *send*, not the JSON:
`Isolate.run(() => jsonEncode(payload))` written inside `BackupService` sends
the whole enclosing context, and that holds an `AppDatabase` wrapping a sqlite3
FFI handle — "object is unsendable". The two helpers are top-level functions in
`backup_service.dart` for that reason; keep them there.

**A signed delta has to be computed from what is shown.** Two bodyweights 0.2
apart differ in kilograms, so the row printed a sign, and then `formatInUnit`
snapped the difference to the 0.5 the app displays and it read `+0`. Compare
`unit.display(a)` against `unit.display(b)`, not the raw values —
`formatDeltaInUnit` does, and returns null when both round to the same figure.

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
1RM testing protocols, streaks, levels, muscle maps, motivational copy, and
**effort / RIR ratings** — a number you rate yourself with after the set, which
is one more thing to answer at the bar and nothing downstream reads.

**A volume dashboard** was on that list and has come off it, under the same test
the plate view passed: no new screen, no question asked. Weekly sets per muscle
is one bar list on a page you already open, normalised to your own biggest
muscle rather than to a target this app has no business inventing. What stays
ruled out is the thing that made it a non-goal — a dashboard you navigate *to*,
a feed to scroll, targets to fail against. **A PR feed stays out**, and so does
a PR badge: a record is a number you can already read on the day it was set, and
`beatsPrevious` already says "you beat last time" where it matters, at the bar.

The app should stay small enough to open mid-set and understand at a glance.
When in doubt, don't add the screen.

**Plate calculators used to be on that list**, and the plate view (THEME §6,
`domain/plates.dart`) is the one thing taken off it. The reason it does not
break the rule: it is not a screen and it asks no questions. It appears inside
the keypad you are already typing a weight into, for a movement that already
knows its bar, and disappears the moment either is untrue. What was ruled out —
and stays ruled out — is a plate *screen*: a per-gym plate inventory, a
"what can I load" solver, or a tool you navigate to rather than one that is
simply there while you type. `olympicPlatesKg` is a constant for that reason.
