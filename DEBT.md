# Deltoid — known weaknesses

What is wrong with this codebase, why it is wrong, and how to tell when it has
been fixed. **Not status** — status is [TODO.md](TODO.md) and nowhere else.
This is the list of things that are *true right now* and would be found by
someone reviewing the app critically, written down so they can be argued with
rather than rediscovered.

Each entry says what to change and how to know it worked. An entry leaves this
file when the check it names passes, not when it feels handled.

---

## 1. The invariants live in prose

**The most serious one**, because it is the mechanism behind three of the bugs
below rather than a bug itself.

This codebase carries its rules in comments — and they are good comments, better
than most projects have. But a comment cannot fail a build. Every rule stated
only in prose is a rule that holds exactly as long as everyone reads the prose,
and the record shows they do not:

- `setsByMuscleDaily` said *"Bounded, never open-ended: … the range control means
  nothing ever asks for more than a year at once. That bound is why this is a
  day-level query"* — and then an `All` range was added, asked for fifty years,
  and the screen took 380ms per rebuild. The comment was correct and load-bearing
  and did nothing.
- `WeeklyBars` documented the bar geometry carefully and still shipped
  `clamp(1.0, slot)`, which throws when a slot is under a point wide. Latent
  until a range widened enough to reach it, then fatal on every repaint.
- `TrendChart` documented "one chart and one range control, both shared" in
  THEME. Three chart dialects grew anyway.

**What to do.** Pick the rules that are load-bearing and give each one a
mechanism. Roughly in order of value:

- An `assert` at the boundary is the cheapest and costs nothing in release.
  `assert(spanDays <= 400, 'this query is day-level and unbounded above a year')`
  would have caught the volume regression at the moment it was introduced.
- A type is better where one fits. A `BoundedSpan` that cannot be constructed
  wider than a year makes the rule unstateable rather than unenforced.
- A test is right where the rule is about behaviour rather than shape — the
  `nothing ever draws more marks than the ceiling` test in
  `test/domain/chart_buckets_test.dart` is the model: it asserts the *property*
  across a range of inputs rather than one example.

**Done when**: every comment in `lib/` containing the words *bounded*, *never*,
*must not* or *always* either has an assert/test beside it or has been rewritten
to stop making a promise nothing keeps.

---

## 2. Nothing enforces the gate

`CLAUDE.md` says to run `flutter analyze && flutter test` before calling a change
done. Nothing checks that anyone did.

- No CI: no `.github/workflows`, no pipeline of any kind.
- No git hooks — `.git/hooks` is stock samples only.
- `analysis_options.yaml` is the stock Flutter template with **zero** custom
  rules. Every lint in it is a default.

For a one-person project this is defensible right up until the day a broken
commit lands and the bisect that finds it has to build fifty revisions by hand.

**What to do.** A pre-push hook running `flutter analyze && flutter test` is ten
minutes of work and removes the whole class. If this ever gets a second
contributor or a release build, promote it to CI. Separately, the linter is
free enforcement being left on the table — `prefer_final_locals`,
`unawaited_futures`, `always_declare_return_types` and
`avoid_slow_async_io` would all pay for themselves here.

**Done when**: a deliberately broken test cannot be pushed.

---

## 3. Drift's row mapping is a performance trap, and it is still set

Reading rows through drift's `TypedResult.read` costs about **14µs per row** —
it resolves the expression to a column name on every call. Measured on this
project's own data, the same 5 496 rows cost:

| path | cost |
| --- | --- |
| `readTable` (whole row objects) | ~120ms |
| `TypedResult.read` (selected columns) | ~90ms |
| `QueryRow` read positionally (raw SQL) | **~16ms** |

Two hot paths have been converted — `exerciseProgress` and `setsByMuscleDaily`,
each about 5× — but **34 other call sites** of `selectOnly` / `readTable` remain
in `lib/data/repositories/` and `lib/features/`. Most are fine: they read tens of
rows, and raw SQL would trade compile-time column checking for speed nobody
needs. The dangerous ones are the queries whose row count grows with the size of
the log.

**What to do.** Audit by *growth*, not by frequency. For each query in
`training_repository.dart`, answer: does its row count grow with years of
training? If yes, it is on this list. Convert only those, and only with a test
asserting the output is identical to the drift version first — both conversions
so far were verified that way before the old path was deleted.

Note the trade being made: raw SQL gives up compile-time column names, so a
renamed column compiles and fails on a device. Both converted queries have a
test that reads every column back for exactly this reason. Keep that rule.

**Done when**: every unbounded query in the repository is either converted or has
a comment saying why it does not need to be — with an assert enforcing the bound
it claims (see §1).

---

## 4. `volumeHistoryProvider` recomputes on every set you tick

The live instance of §1 and §3 together, and worth its own entry because it is
still true.

```dart
final volumeHistoryProvider = StreamProvider<VolumeHistory>((ref) { … })
```

Three facts that are individually fine and jointly bad:

1. It watches `db.setLogs` — **the hot table during a session**, written once per
   set ticked.
2. It is **not** `autoDispose`, so once the volume screen has been opened it stays
   subscribed for the rest of the app's life.
3. Since `All` was added it is unbounded: 19 478 rows and ~150ms on thirty years.

So: open the volume screen on `All` once, go and train, and every set you tick
re-queries and re-folds thirty years of history on the UI isolate, for a screen
you are not looking at.

`exerciseProgressProvider` had exactly this bug and its doc comment now explains
the fix at length — *"`autoDispose`, and that is the point"*. The lesson was
learned in one file and not carried to the other.

**What to do.** Either make it `autoDispose` (matching the exercise chart), or
give it the narrow stream treatment `history_providers.dart` uses —
`historyShapeChanges()` rather than every `set_logs` write. Probably both.

**Done when**: ticking a set with the volume screen backgrounded runs no volume
query. A test can assert this the way
`a set ticked in a live session cannot change the feed` already does.

---

## 5. Painters compute their own bounds and do not defend them

`clamp(lower, upper)` throws when `lower > upper`. That is not a rare edge — it is
what happens whenever a bound is computed from a layout that got small or a list
that got long. One instance killed the volume screen. The same pattern is still
present:

- `volume_history_bars.dart:276` — `(…).clamp(1.0, size.height)` throws if the
  widget is ever laid out under one logical pixel tall. Not currently reachable
  because both call sites pass a fixed height, which is exactly what was true of
  the one that did crash.
- `calendar.dart:49` — `initial.clamp(firstDay, lastDay)` throws if a caller ever
  passes a range whose end precedes its start.

**What to do.** Two options, in order of preference. Stop computing bounds that
can invert — `max(a, min(b, c))` cannot throw and says what it means. Or assert
the ordering at the top of `paint`, which turns a production crash into a debug
failure at the moment the bad input is produced.

Worth a rule in RULES.md: *a painter never clamps to a bound it computed.*

**Done when**: no `.clamp(` in `lib/` has a non-constant lower bound, or each one
that does is preceded by an assert.

---

## 6. A third of the app has never been used in a gym

From TODO.md, and repeated here because it is the biggest *product* risk and the
easiest to leave sitting: **twelve** features are built, analyzer-clean and
tested but have never been driven on real hardware in a real session. Among them
the hold pad, the rest tone, the haptics, the wakelock, audio ducking, the
ongoing-session notification and the scheduled rest alarm.

Tests do not tell you the hold pad is awkward with chalk on your hands, that the
rest tone is inaudible over gym music, or that the notification's countdown is
wrong on a locked screen. For an app whose primary screen is operated one-handed,
standing at a bar, mid-set, this is the difference between working and shipped.

**What to do.** One month of actual training with a notebook. Every friction
gets written down; at the end, delete rather than fix wherever possible — the
scope rules are the app's best feature and this is the data that feeds them.

**Done when**: the "Not yet driven on the device" section of TODO.md is empty,
by use or by deletion.

---

## 7. The comments are an asset with a maintenance cost

Said plainly because it is the one item here that is a *trade*, not a defect.

The comment density is why this codebase can be picked up quickly, and it should
not be reduced wholesale. But prose goes stale silently, and this project has
already produced a comment that became a lie (§1). The failure mode is specific:
comments that state **facts about other code** — how many rows a query returns,
what another provider does, what a caller guarantees — rot when that other code
changes, and nothing points back at them.

Comments that explain **why this code is shaped this way** do not rot, because
the reasoning outlives the numbers.

**What to do.** When a comment states a fact about something outside its own
function, either move the fact into an assert/test or make it a reference rather
than a copy. Prefer *"bounded by the range control — see the assert below"* over
*"nothing ever asks for more than a year"*.

**Done when**: nothing, really. This is a habit rather than a task. It is here so
that the next person who finds a stale comment treats it as a category rather
than an accident.

---

## 8. Smaller things, unranked

- **`pastPerformances` still builds a `WHERE … IN (…)` with one parameter per
  performance** (`training_repository.dart:1370`). The chart no longer uses it,
  but prefill still does, at `limit: 60` — safe today, and the same latent shape
  as the query that had to be rewritten. It is one `limit: null` away from being
  a two-thousand-parameter statement again.
- **`analysis_options.yaml` has no `unawaited_futures`.** In a codebase this full
  of `Future`-returning repository calls, a dropped `await` is a write that
  silently does not happen.
- **No test asserts the light theme.** THEME defines a full light ramp and every
  widget test builds `Brightness.dark`. Contrast bugs in light mode are currently
  invisible to CI that does not exist (§2).
- **Chart transitions are unverified.** The zoom animation is implemented and
  nothing tests it, because testing "it looked smooth" needs a golden or a frame
  timeline. At minimum a test could assert the frame's size never changes during
  a range switch, which is the part that would be *visibly* wrong.
