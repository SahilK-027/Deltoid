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
                   rest_alert.dart  end-of-rest buzz + tone (audio session)
  features/        today · log · history · progress · regime · settings

assets/
  audio/           rest_done.mp3 — the end-of-rest tone
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

**`formatWeight` also formats computed numbers.** An estimated 1RM is an
arbitrary double — `55.733333333333334 kg` shipped to the screen before it was
capped at two decimals.

---

## Status

### Done

Everything below is built, analyzer-clean and unit-tested where it has logic.
"Driven on the emulator" marks flows actually exercised end to end by hand;
the rest render correctly but their happy path has not been clicked through.

**Those marks predate the audit fixes.** Every screen was touched since and
none of it has been driven again, so treat them as evidence about the design,
not about the current build. What needs real hardware rather than a test:
anything with a plugin behind it (the end-of-rest tone and haptics, the
wakelock, audio ducking against music) and anything whose layout moved (Today,
the regime screen's cycle controls, the session list, the settings units
picker).

- **Logging** _(driven on the emulator)_ — one exercise per page, horizontal
  rail, typed sets (warmup / working / backoff / drop / rest-pause / AMRAP),
  custom gym keypad with a one-plate step and one-tap "Last: 22.5", auto rest timer, per-set
  notes, swap / skip-with-reason / move / add exercise mid-session. Resuming an
  interrupted session survives a force-stop.

  Rest ends out loud: a double haptic and a tone on the Android alarm stream
  (`core/rest_alert.dart`, audio focus `gainTransientMayDuck`, so music dips
  rather than stops), and the screen is held awake for the whole session. The
  bar then says "Rest done" and removes itself after five seconds — it never
  counts overtime, but the start time is kept, because actual rest is measured
  from it. _Not yet driven on the emulator: the tone and the wakelock want a
  real device._

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

137 tests: prefill rules (including a deload never re-scaling a light week),
cycle/deload timing and closing a cycle early, metrics, unit conversion, keypad
key handling, backup round-trip, history paging, deleting a workout (including
the cycle it reopens), swap-in-place, mid-session prefill, date and note
editing, rest targets, the multi-regime rules, the create-regime flow as a
widget test, and repository integration against a real in-memory SQLite.

### Not done

- **Supabase sync** — schema, RLS, magic-link auth, push dirty rows / pull since
  `last_pull_at`, LWW merge on `updated_at`, tombstones. **Blocked:** needs the
  user's project URL + anon key. Every table already carries the sync columns
  (`id`, `updated_at`, `deleted_at`, `device_id`, `dirty`), so this is additive —
  no migration required.
- **iOS** — needs Xcode installed. Codebase is cross-platform; nothing
  iOS-specific is known to be broken, but nothing is verified either.

### Planned, roughly in order

1. Drive the audit fixes on a device — see the section below for what is
   unverified, and reinstall first, because the schema changed.
2. Supabase sync (above).
3. iOS verification once Xcode exists.
4. Per-exercise deload overrides — the columns exist
   (`session_exercises.deload_set_delta` / `deload_weight_pct`), no UI yet.

---

## Non-goals

Deliberately absent, and should stay that way: social features, macros /
nutrition, AI coaching, an exercise GIF library, Apple Health / Google Fit,
plate calculators, 1RM testing protocols, volume dashboards, a PR feed.

The app should stay small enough to open mid-set and understand at a glance.
When in doubt, don't add the screen.
