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

| Invariant | Why |
|---|---|
| `WorkoutExercise` / `SetLog` are **snapshots** | Reordering or swapping mid-workout must never rewrite what you did in March. Same reason switching regimes creates a new `Regime` instead of editing sessions in place. |
| `_cyclesSinceDeload(beforeIndex:)` is **exclusive** | A `CycleStatus` describes a cycle by what came *before* it. Counting the cycle itself makes the deload land one cycle early. This was a real bug. |
| `LoadMode` decides what a number means | `22.5` on a dumbbell is 45kg of load; `73` on a pec deck is 73kg. Without it every comparison downstream is garbage. |
| Warmups / drops / rest-pause are excluded from progress | `scorePerformance` only counts `working` and `amrap`. Including the rest is how naive logs claim progress that isn't there. |
| `estimated1RM` caps reps at 12 | Right for the long-range chart. **Wrong** for "did I beat last time" — it makes 12 → 13 reps invisible. That comparison uses `beatsPrevious` instead, deliberately strict: more load at no cost in reps, or more reps at the same load. Heavier-for-fewer is a trade-off, not a win. |
| The log screen owns the **horizontal axis** | It's a `PageView`, one exercise per page. Nothing inside it may use a horizontal gesture. |

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
  features/        today · log · history · progress · regime · settings
```

Four tabs: **Today** (next session, heatmap), **History**, **Progress** (one
exercise, one chart), **Regime** (sessions, exercise catalog, deload config).
Settings behind the gear on Today.

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

**`formatWeight` also formats computed numbers.** An estimated 1RM is an
arbitrary double — `55.733333333333334 kg` shipped to the screen before it was
capped at two decimals.

---

## Status

### Done

Everything below is built, analyzer-clean and unit-tested where it has logic.
"Driven on the emulator" marks flows actually exercised end to end by hand;
the rest render correctly but their happy path has not been clicked through.

- **Logging** _(driven on the emulator)_ — one exercise per page, horizontal
  rail, typed sets (warmup / working / backoff / drop / rest-pause / AMRAP),
  custom gym keypad with ±2.5 and one-tap "Last: 22.5", auto rest timer, per-set
  notes, swap / skip-with-reason / move / add exercise mid-session. Resuming an
  interrupted session survives a force-stop.

  Finishing with sets still open is allowed but never silent: the confirmation
  names every exercise and how far it got. Turning the page early is allowed
  too — supersets and busy racks are normal — and the page says how much is
  left behind. Starting a session twice in one tap-tap creates one workout, not
  two.
- **Session-scoped prefill** _(driven on the emulator)_ — ghost values,
  cross-session borrowing labelled, ghost adopted on completion, beat-last-time
  highlight.
- **Cycles + deload** _(driven on the emulator)_ — cycle completes when every
  session is trained; deload after N cycles cuts sets and scales weight %,
  configurable per regime, visually distinct (blue) everywhere including the
  resume path.
- **History** — three views (above). The Notion table was driven on the
  emulator; the paged session feed, the day detail and the per-exercise history
  are unit-tested against a real SQLite database but have not been clicked
  through by hand.
- **Progress** _(driven on the emulator)_ — e1RM over time, one line per session
  slot, 3M/1Y/All, stall detection. Deload weeks excluded so a light week isn't
  drawn as a regression.
- **Consistency heatmap** _(driven on the emulator)_ — auto-filled, deload days
  distinct, sessions/week.
- **Backup** — export / restore / auto-export. Round-trip is unit-tested against
  a second in-memory database, including enum and JSON-list columns. On device,
  only the restore file picker was opened; the share sheet and a real restore
  were not completed.
- **Bodyweight log** — schema, repository, interpolation and BW / BW+X load maths
  are unit-tested; the Settings entry renders, but no weight has been logged
  through the UI.
- **Regime editor** _(driven on the emulator)_ — create a regime blank or from a
  template, rename it, add/reorder/delete sessions, edit slots, deload config.
  Deleting a session asks first; removing a slot offers an undo.
- **Multiple regimes** _(driven on the emulator)_ — a full list under the Regime
  tab: switch the active one, rename, delete. Deleting shows how many workouts
  were logged under it, keeps them in History, and hands the active flag to
  another regime rather than dropping the app to its first-launch state.
- **Exercise catalog** — searchable, create / edit / archive, reachable from the
  Regime tab as well as mid-session. Archive rather than delete: past workouts
  point at these rows. Archived entries have their own list and can be restored
  long after the undo snackbar is gone.
- Light / dark / system theme, adaptive launcher icon.

102 tests: prefill rules, cycle/deload timing, metrics, backup round-trip,
history paging, deleting a workout (including the cycle it reopens), the
multi-regime rules, the create-regime flow as a widget test, and repository
integration against a real in-memory SQLite.

### Not done

- **Supabase sync** — schema, RLS, magic-link auth, push dirty rows / pull since
  `last_pull_at`, LWW merge on `updated_at`, tombstones. **Blocked:** needs the
  user's project URL + anon key. Every table already carries the sync columns
  (`id`, `updated_at`, `deleted_at`, `device_id`, `dirty`), so this is additive —
  no migration required.
- **iOS** — needs Xcode installed. Codebase is cross-platform; nothing
  iOS-specific is known to be broken, but nothing is verified either.

### Planned, roughly in order

1. The audit backlog below, in the order given at the end of it.
2. Supabase sync (above).
3. iOS verification once Xcode exists.
4. Per-exercise deload overrides — the columns exist
   (`session_exercises.deload_set_delta` / `deload_weight_pct`), no UI yet.

---

## Audit backlog

Found by reading the code and driving the app on the emulator, 2026-07-29.
**Nothing in this section is fixed.** Findings that were fixed, and behaviour
that was checked and turned out to be correct, are deliberately absent — this
is only what is still wrong. Numbers are stable; cite them when fixing.

**Development phase: there is no real data to protect.** The only databases
that exist are on test devices. That matters for how these are costed, because
`schemaVersion` is 1 and the migration strategy has `onCreate` and nothing else
(`data/db/database.dart:34`) — there is no `onUpgrade` path, so a schema change
today does not migrate, it breaks the install, and the fix is to uninstall and
reinstall. Free now. The starter catalog re-seeds itself and no programme is
baked in, so a wipe costs one template tap.

This inverts the usual ordering: anything that touches `tables.dart` is cheapest
**now** and gets permanently more expensive at the first install that holds
training you care about — that install is when `onUpgrade` has to start
existing. Of the findings below only **26** touches the schema; do it before
the app carries real history, not after. Everything else is behavioural and can
land in any order.

**`schemaVersion` stays 1 — including at launch.** It is not the app version
(`pubspec.yaml` carries that, currently `1.0.0+1`) and the two move
independently. Every fresh install runs `onCreate`, so a new database is born at
whatever shape `tables.dart` describes and never migrates; whatever ships is v1
for everyone. Bump it only on the first schema change made *after* a database
exists that you are unwilling to recreate — and note that the relevant database
is the one on your own phone, not an app-store release, because this is a tool
for one person. It is also stamped into every backup file and restore rejects
anything written by a newer schema (`backup/backup_service.dart:148`), so a
later bump invalidates old exports unless that path is handled too.

For the record, four things were checked and are **right as they stand**, so
nobody re-opens them: session-scoped prefill skips a skipped week and falls back
correctly; a deload week is stepped over so the next normal week resumes at real
weights; past workouts are immutable snapshots; and the "up next" queue is
order-based on purpose, so training out of order never strands the programme.

### Correctness — these change stored data

**1. Swapping an exercise sends it to the end of the workout**
`log/widgets/exercise_sheets.dart:120`, `repositories/training_repository.dart:1048`

- **Bug** — swap is implemented as remove-then-add, and `addExerciseToWorkout`
  sets `orderIndex` to the count of live rows. Swap exercise 2 of 6 and the
  replacement lands at position 6; the page you were standing on jumps
  elsewhere mid-session. It also arrives with a flat three sets, ignoring both
  the slot's target and last time's set structure.
- **Good UX** — a swap is a substitution, not a deletion plus an append. The
  replacement takes the old one's place in the order, inherits its target sets,
  and the page you are on does not move.
- **Fix** — add `replaceExerciseInWorkout(workoutExerciseId, newExerciseId)` to
  the repository: reuse the old row's `orderIndex` and `targetSets`, build the
  set shape from the new exercise's prefill (see 2), tombstone the old row in
  the same transaction.

**2. Prefill is resolved once and never refreshed**
`log/log_providers.dart:16`

- **Bug** — `workoutPrefillProvider` is a `FutureProvider` computed when the log
  opens and invalidated by nothing. Any exercise added or swapped in mid-session
  reads "First time — no previous log" even with a year of history behind it,
  and because there is no ghost, `_adoptGhost` has nothing to adopt: tapping ✓
  after typing only reps stores reps against a null weight. That is exactly the
  failure the "adopt ghost values" trap warns about, reached by another door.
  In a deload week it is worse — the set *shape* also comes from prefill, so the
  new exercise gets full-weight sets in a light week.
- **Good UX** — an exercise added at 19:40 knows the same history it would have
  known at 19:00.
- **Fix** — recompute when the workout's exercise list changes. Either watch
  `workoutDetailProvider` and re-resolve for exercise ids not yet in the map, or
  invalidate the provider from `addExerciseToWorkout` / the new replace method.
  Resolve per exercise, not per workout, so one addition doesn't re-walk history
  for all six.

**3. `completeWorkout` hard-deletes set rows**
`repositories/training_repository.dart:1093`

- **Bug** — the un-done sets are removed with `db.delete` rather than a
  tombstone. Correct locally, wrong the moment Supabase sync lands: rows deleted
  on this device have no `deleted_at` to push, so the next pull from another
  device resurrects them. Every other delete in the app tombstones.
- **Good UX** — invisible; this is about not corrupting history later.
- **Fix** — set `deletedAt`/`updatedAt`/`dirty` instead of deleting, and confirm
  every read path already filters `deletedAt.isNull()` (they do).

**4. Changing an exercise's load mode silently rewrites history's meaning**
`log/widgets/exercise_sheets.dart:594`

- **Bug** — flipping "total load" to "per dumbbell" doubles the effective load
  of every set ever logged for that movement. e1RM, the progress chart, the
  "beat last time" highlight and prefill comparisons all move, with no warning
  and no record of what changed.
- **Good UX** — the app should say what the change costs before making it:
  "42 logged sets will be re-read as per-dumbbell, doubling their load."
- **Fix** — when `loadMode` changes on an exercise that has history, count the
  affected sets and confirm with that number. No data migration — the
  interpretation is the point — but the user must choose it knowingly.

**5. Deleting a session can strand an open cycle**
`repositories/training_repository.dart` (`_sessionIds`, `completeWorkout`)

- **Bug** — `_sessionIds` excludes deleted sessions, but only `completeWorkout`
  ever closes a cycle. Delete the last untrained day of a cycle and the cycle
  sits complete-but-open: Today shows "UP NEXT: Push 1" over a full row of
  filled dots. It self-heals on the next logged workout.
- **Good UX** — the cycle closes the moment it is satisfied, whatever satisfied
  it.
- **Fix** — re-evaluate and close the cycle inside `deleteSession` when the
  remaining sessions are all trained. Finding 11's "Close this cycle" control
  also covers it manually.

**6. The resume card mislabels a cross-regime session**
`today/today_screen.dart:179`

- **Bug** — the card resolves the session name from the *active* regime's
  sessions. Start a workout, switch regimes, and the card reads "Workout".
- **Good UX** — the card names the session and the regime it belongs to, since
  finishing it will advance that regime's cycle, not the one you are looking at.
- **Fix** — look the session up by id directly rather than filtering
  `activeSessionsProvider`, and add the regime name when it isn't the active one.

**7. `applyDeload` can scale an already-scaled week**
`domain/prefill.dart:143`

- **Bug** — if the only history for a slot is itself a deload, loop 2 picks it
  (`sameSessionDeload`) and `applyDeload` then scales it again: 80% of 80% =
  64%. Not reachable today, because a scheduled deload never immediately follows
  another — it becomes reachable the moment finding 12 wires up the manual
  deload override.
- **Good UX** — a deload is 80% of your working weight, never 80% of a light
  week.
- **Fix** — skip the transform when `pick.isDeload` is already true, and cover
  it in `prefill_test.dart`. Cheap now, load-bearing after 12.

**8. A partially-skipped exercise is invisible in history but drives everything else**
`repositories/training_repository.dart:341`, `history/workout_detail_screen.dart:207`

- **Bug** — log two sets, then mark the exercise skipped. The sets stay
  `isDone`, survive `completeWorkout`, and are used for prefill and plotted on
  the progress chart — while all three history views hide them behind a
  "Skipped" pill. `pastPerformances` never looks at `skipReason`; the
  empty-sets check is doing the filtering by accident, not the flag.
- **Good UX** — one story everywhere. Either the sets happened, and history
  shows them next to the skip reason, or they didn't, and nothing downstream
  uses them.
- **Fix** — show logged sets under the skip pill ("Skipped after 2 sets —
  shoulder"), and decide explicitly in `pastPerformances` whether a skipped
  performance is prefill-eligible rather than leaving it to a side effect.

**9. History counts a skipped week as a session performed**
`repositories/training_repository.dart` (`exercisesWithHistory`)

- **Bug** — the index counts `workout_exercises` rows regardless of
  `skip_reason`, so History › Exercises says "2 sessions" when one was skipped.
- **Good UX** — the count means times trained.
- **Fix** — exclude skipped rows from the count, or show "2 sessions · 1
  skipped". Note the existing test asserts blank-but-present slots *do* count;
  keep that, change only the skipped case.

**10. Prefill's candidate window can drop the performance it needs**
`repositories/training_repository.dart` (`pastPerformances(limit: 30)`)

- **Bug** — candidates are the 30 most recent performances of the exercise
  across *all* sessions. Fan one movement across many training days and a slot
  left untrained for 30+ performances elsewhere falls out of the window; prefill
  silently drops to another session and labels it "From Push 2".
- **Good UX** — the same-session lookup should not have a horizon at all.
- **Fix** — query the most recent same-session performance directly in SQL
  instead of filtering an in-memory window, and keep the limit only for the
  cross-session fallback.

### Cycle control — built, tested, unreachable

**11. `advanceCycle` has no UI**
`repositories/training_repository.dart:302`

- **Bug** — the method closes the current cycle early and opens the next. Its
  own comment calls it "the escape hatch for *I'm skipping leg 2 this round* —
  without it a single missed session would stall the programme forever." Nothing
  in `lib/` calls it, and no test covers it. So the stall is real: permanently
  skip one session and the cycle never closes, the cycle index never increments,
  `cyclesSinceDeload` never grows, and **the deload you configured never
  arrives**. The only ways out are to eventually train that session or delete it
  from the regime.
- **Good UX** — when a cycle is partly done, the app offers to call it finished
  and move on, and says what that costs ("Leg 2 won't be trained this cycle").
- **Fix** — a "Close this cycle" action on the Regime screen's cycle header, or
  under Today's cycle dots when at least one session is done and one is missing.
  UI only; the repository method is complete.

**12. `setCycleDeload` has no UI**
`repositories/training_repository.dart:316`

- **Bug** — the override that makes the current cycle a deload, or cancels a
  scheduled one, is called from one test as setup and from nowhere in the app.
  The README's "the app suggests; it never forces" is currently false: the
  schedule is binding.
- **Good UX** — "Make this cycle a deload" / "Skip the deload this time" next
  to the deload countdown, because whether you need a light week is a decision
  you make in the gym, not six cycles in advance.
- **Fix** — a toggle on the Regime screen's cycle header wired to
  `setCycleDeload(status.cycleId, …)`. Do finding 7 first, or forced deloads can
  compound to 64%.

**13. "UP NEXT" reads as an obligation**
`today/today_screen.dart`

- **Bug** — not a defect, a presentation problem. The queue head gets a large
  card and a full-width Start button; the way to train something else is the
  "This cycle" list below the heatmap, off the first screen. Users conclude the
  app won't let them train Pull before Push. It will.
- **Good UX** — the headline says what it is — the first session not yet done —
  and the alternatives are visible without scrolling.
- **Fix** — label it "First unfinished" rather than "Up next", move the session
  list above the heatmap, and let the card's session name itself open the list.

### Logging ease — friction with chalky hands

**14. The rest timer never tells you rest is over**
`log/widgets/rest_timer.dart`

- **Bug** — no sound, no haptic, no notification. The bar turns green and counts
  up. `HapticFeedback` fires only when a set is completed, and there is no
  wakelock, audio or notifications package in `pubspec.yaml`. So the one app
  built to be opened mid-set requires you to hold it and watch it.
- **Good UX** — put the phone down, get a buzz at zero, pick it up.
- **Fix** — haptic plus an optional short sound when `remaining` crosses zero,
  and keep the screen awake while a workout is open. Two small packages.
  Biggest felt improvement in the app.

**15. `+2.5` starts from zero instead of last time's weight**
`log/widgets/keypad.dart:267`

- **Bug** — `applyKey` reads the buffer, which is empty until you type. The most
  common intent in the gym — "22.5 last week, 25 today" — costs three taps:
  field, "Last: 22.5", "+2.5". Tapping `+2.5` on an empty field gives `2.5`, a
  dead end nobody wants.
- **Good UX** — one tap. `+` means "a plate more than last time" when you
  haven't typed anything.
- **Fix** — pass the hint into `applyKey` and seed `+`/`−` from it when the
  buffer is empty. Pure function, already unit-tested — extend those tests.

**16. Ghost values look almost exactly like entered values**
`log/widgets/set_row.dart:197`

- **Bug** — the only difference is `textTertiary` vs `textPrimary`: same size,
  same position, no marker. Then tapping ✓ writes the ghost into the row
  (`_adoptGhost`, which is correct and necessary), so numbers you never typed
  become logged data with grey-turning-white as the only feedback. In gym
  lighting that is not a signal.
- **Good UX** — a suggestion never looks like a record. Adoption is visible.
- **Fix** — italicise ghosts or prefix them with a small dot, and animate the
  cell on adoption so the row visibly commits.

**17. A weight-only entry never completes the set, and doesn't say so**
`log/log_screen.dart:317`

- **Bug** — `_advance` marks a set done only when the typed reps are > 0. Enter
  a weight, press the key now labelled "Done", and nothing completes; the keypad
  just closes.
- **Good UX** — either the button completes what it says it completes, or it
  explains what's missing.
- **Fix** — when reps are empty on the last field, keep focus and label the key
  "Reps?" rather than "Done"; or complete the set using the ghost's reps, which
  is what `_adoptGhost` would do anyway.

**18. Rest is promised, measured, and thrown away**
`repositories/training_repository.dart` (`updateSet`), `log/log_screen.dart`

- **Bug** — `set_logs.rest_seconds` exists and is never written, despite the
  timer's doc comment claiming the number is "captured without asking for a
  single extra tap". The target also resets to 120 s every time the log opens
  and is not per-exercise.
- **Good UX** — rest is recorded because it was already measured, and heavy
  compounds remember three minutes while cable work remembers sixty seconds.
- **Fix** — write the elapsed rest onto the set being completed, persist the
  target per `session_exercises` row, and default from last time.

**19. A database write and a full re-query on every keystroke**
`log/log_screen.dart:295`

- **Bug** — `_commit` calls `updateSet` for each digit; each write fires
  `watchWorkoutDetail`, which re-runs three queries for the whole workout. On
  top of that a one-second `Timer.periodic` calls `setState` on the entire log
  screen — PageView included — even when no rest timer is showing.
- **Good UX** — invisible on a Pixel, visible on an old phone, and it burns
  battery for a session that lasts an hour.
- **Fix** — debounce the commit to ~300 ms with a flush on Next/dismiss, and
  scope the tick to the two widgets that need a clock.

**20. No "last time" summary for the exercise as a whole**
`log/log_screen.dart` (`_PrefillCaption`)

- **Bug** — you get per-set ghosts and a date, never the shape of last time's
  work.
- **Good UX** — before set 1 you want "last time: 22.5×8, 22.5×8, 20×7" in one
  line. That's the question the whole app exists to answer.
- **Fix** — render the prefill sets as a single line under the caption. The data
  is already in `PrefillResult.sets`.

**21. The keypad may push the row you're typing into off-screen** — *unverified*
`log/log_screen.dart`

- **Bug** — the keypad is a sibling in the Column, so opening it shrinks the
  page; nothing scrolls the active row back into view. Suspected on exercises
  with five or more sets. Reproduce before fixing.
- **Good UX** — the number you are typing is always visible.
- **Fix** — `Scrollable.ensureVisible` on the active `SetRow` when `_editing`
  changes.

### Editing what is already logged

**22. A logged workout's date cannot be changed, and a past session cannot be logged**
`repositories/training_repository.dart` (`startWorkout`)

- **Bug** — `dayKey` is written once from `DateTime.now()` at start and never
  again. Forget to log Monday and Wednesday's entry is permanently wrong;
  delete-and-redo doesn't help, because the redo is also stamped today. The
  biggest functional hole now that history can be deleted.
- **Good UX** — a training log lets you write down Monday's session on
  Wednesday, and correct a date you got wrong.
- **Fix** — an editable date on the workout detail screen, and a "log a past
  session" entry point that passes a date into `startWorkout`. Both must also
  rewrite `dayKey` so the heatmap and history ordering follow. Watch the keyset
  cursor: it pages on `startedAt`, so decide whether backdating moves that too.

**23. Workout notes are read-only**
`history/workout_detail_screen.dart:97`

- **Bug** — `workouts.notes` is rendered in the day detail and writable nowhere.
- **Good UX** — "slept badly, everything felt heavy" is the context that
  explains a bad week when you look back in six months.
- **Fix** — an editable notes field on the workout detail screen, and a note
  action in the log screen's overflow.

**24. Bodyweight is today-only, uneditable, undeletable**
`settings/settings_screen.dart:183`

- **Bug** — the logger always passes `DateTime.now()`. There is no date picker,
  no edit and no delete, so a typo is permanent — and bodyweight silently scales
  every bodyweight and BW+ lift score through `scorePerformance`.
- **Good UX** — a weight log you can correct, since it is an input to your
  numbers rather than a diary.
- **Fix** — date picker on entry, tap a row to edit, swipe or long-press to
  delete. `logBodyweight` already upserts by day, so editing is a re-log.

### Reorder

**25. Session reorder on the Regime tab loses the drag to the page**
`regime/regime_screen.dart` (`_SessionList`)

- **Bug** — the `ReorderableListView` is nested inside the tab's outer
  `ListView` with `NeverScrollableScrollPhysics`. `ReorderableDragStartListener`
  is an immediate vertical drag, so it competes with the parent scrollable and
  loses: a normal-speed drag scrolls the page instead of reordering. Verified on
  the emulator — a fast drag did nothing and scrolled; a slow 2.5 s drag moved
  Leg 2 from index 5 to 3. There is also no auto-scroll while dragging, so with
  more sessions than fit on screen you cannot drag one past the fold at all.
  Exercise reorder inside the session editor is fine — that list is the page's
  own scrollable.
- **Good UX** — a drag either reorders or it doesn't; it never depends on how
  fast you move your thumb.
- **Fix** — make the session list the page's primary scrollable (move the
  header and deload card into it as slivers, or give the list its own screen),
  or swap the drag handle for an explicit move up / move down control like the
  log screen already uses.

### Smaller UI and data-hygiene items

**26. Dead schema.** `set_logs.rpe`, `set_logs.parent_set_id`,
`exercises.is_unilateral` and `HeatDay.sets` are referenced nowhere outside
their definitions. Drop and rest-pause sets never actually link to the set they
extend — the indent in history is cosmetic. **Fix:** either wire them up (RPE is
the only one with obvious value) or delete the columns; a schema that lies about
what it stores misleads the next reader. **The only schema-touching item here,
so decide it while a wipe is still free** — see the note at the top of this
section. Regenerate with `dart run build_runner build`, then reinstall on the
test device; `onUpgrade` does not exist yet and does not need to.

**27. Progress can strand on an archived exercise.** The selector reads the
archived-filtered catalog, so the header falls back to "Pick one" while a chart
renders below it. **Fix:** fall back to the default exercise when the selected
id is no longer in the catalog, the same way the history table now does.

**28. Duplicate exercise names are allowed, and templates match by name.**
`seed/seeder.dart:68` looks catalog rows up by name, so renaming a starter
exercise and then applying a template creates a duplicate. Two identically named
rows are also indistinguishable in the picker. **Fix:** warn on a duplicate name
at creation, and match template slots on the starter key rather than the name.

**29. Restore is not guarded, and backups are invisible.** A restore can be
started with a workout in progress, and Settings never shows when the last
auto-export ran even though one fires after every finished session. **Fix:**
block or warn on restore while a workout is open, and show "last backup" with
its timestamp under Data.

### Units

**30. The app is kilograms-only, hardcoded.** No unit setting exists; the
`units` key mentioned in `tables.dart` is aspirational. Every weight is a bare
`double` meaning kg, with "kg" hardcoded at eight UI sites (`keypad.dart:10`,
`set_row.dart:75`, both history screens, progress, settings).

- **Good UX** — if you train in pounds, the app speaks pounds everywhere,
  including the plate increment.
- **Fix** — store kg always and convert only at the edges; never store mixed
  units or every historical comparison silently breaks. It is more than a label
  swap: the keypad's ±2.5 step is a kilo plate and wants ±5 lb, and `roundLoad`
  snaps to 0.5 kg, which is the wrong granularity for pounds. Half a day's work,
  well isolated — worth doing only if you would actually train in lb.

### Order to fix

1. **14, 15, 16** — the gym-hands set. Cheapest change with the largest felt
   difference, and none of it touches stored data.
2. **11, 12** (+ **7** first) — wire the cycle escape hatches. UI only; both
   repository methods already exist.
3. **1, 2** — swap-in-place and prefill refresh. Correctness, and 2 is quietly
   writing bad rows today.
4. **22, 23, 24** — editing what is already logged. The largest functional gap.
5. **8, 9, 5, 6, 10** — consistency between what history shows and what the
   numbers use.
6. **3, 4** — before Supabase sync lands, not after.
7. **26** — settle the dead columns. Not urgent by impact, but it is the only
   schema change in the list and it is free until the first install you care
   about; after that it costs an `onUpgrade`.
8. **25, 27, 28, 29** — UI papercuts.
9. **17, 18, 19, 20, 21** — logging polish.
10. **30** — only if you would actually train in pounds. No schema change:
    weights stay kg and the preference is an `app_settings` row.

---

## Non-goals

Deliberately absent, and should stay that way: social features, macros /
nutrition, AI coaching, an exercise GIF library, Apple Health / Google Fit,
plate calculators, 1RM testing protocols, volume dashboards, a PR feed.

The app should stay small enough to open mid-set and understand at a glance.
When in doubt, don't add the screen.
