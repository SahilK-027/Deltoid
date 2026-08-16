# Deltoid — known weaknesses

What is wrong with this codebase, why it is wrong, and how to tell when it has
been fixed. **Not status** — status is [TODO.md](TODO.md) and nowhere else.
This is the list of things that are *true right now* and would be found by
someone reviewing the app critically, written down so they can be argued with
rather than rediscovered.

Each entry says what to change and how to know it worked. An entry leaves this
file when the check it names passes, not when it feels handled.

## This comes before sync

**Nothing in [SYNC.md](SYNC.md) should be written until this file is empty.**

Not because sync is hard — it is designed in full and the design is good — but
because every weakness below is one that a sync layer *multiplies*:

- **§1, invariants in prose.** Sync is fifteen sections of rules about what may
  never happen: a write never lost, never fabricated, never refused. If this
  codebase's existing invariants can rot into comments that lie — and they have,
  three times — then sync's will too, and sync's failures are silent and
  permanent rather than a slow screen. A conflict rule that is only a paragraph
  is a data-loss bug waiting for the second device.
- **§4, unbounded queries on hot tables.** Sync adds a *second* writer to
  every syncable table. Today `volumeHistoryProvider` recomputes thirty years on
  every set you tick; after sync it recomputes on every set another device ticks,
  arriving in batches, on the UI isolate.
- **§5, painters that crash on their own geometry.** A pull that lands more rows
  than the local log has ever held is exactly the input that made the last one
  throw.
- **§6, twelve features never used in a gym.** Sync is the point after which
  deleting a feature stops being free — there will be rows of it on a server and
  a migration to write. Everything that should be deleted should be deleted
  first.

The order to work in: **§1 and §5** first (they are the same habit — make the
rule mechanical), then **§4**, then **§6**. §7, §8 and §9 are ongoing rather
than blocking. §3, the row-mapping conversions, is closed — the queries whose
row count grows with the log are raw and covered by
`test/data/query_conversion_test.dart`, and the ones that stay in drift say in
a comment why their row count does not grow.

The gate itself — a pre-push hook and a linter with rules in it — was §2 and is
done. The numbering below keeps its gap deliberately, because
[HARDENING.md](HARDENING.md) names the remaining entries by number.

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

## 8. Comments that grant themselves exceptions to the docs

A specific failure inside §1, and the one most likely to spread, because each
instance is individually reasonable.

The pattern: a comment states a global rule, notes that this code breaks it, and
explains why — and that is the whole approval process. THEME is never told. So
the rule stays written down as absolute while the code accumulates exceptions,
and the next person to read THEME believes something about the app that is no
longer true.

**Done right** (keep doing this): `hold_pad.dart:180` runs its clock at 44sp over
the 30sp type cap, and says *"the one place in the app that goes over it — see
THEME → Type"*. THEME → Type says the same thing from the other side: *"One
exception, a clock. The hold pad's timer runs at 44sp."* Two documents, one
fact, neither surprising.

**Done wrong**, currently:

- THEME → Fields: *"Fields are declared once, in the theme. Fill, radius, focused
  outline, hint colour and insets belong to the input theme; a call site passes a
  hint, a prefix or a suffix **and nothing else**."* Three call sites pass more:
  `exercise_screen.dart:1054` (type, alignment **and** `contentPadding`, with a
  comment declaring itself *"the one field that overrides the theme's insets"*),
  `bodyweight_screen.dart:793` (type and suffix style),
  `regime_screen.dart:736` (type). The rule reads as absolute and has three
  standing exceptions, one of which announces itself.
- `exercise_history_screen.dart:207` builds the 28 between sections out of
  `Space.xl` plus an 8 separator, calling itself *"the one place the gap is built
  out of two pieces"*. The value obeys THEME; the construction is a local
  invention that the next spacing change will not find.
- `exercise_screen.dart:46` says the General section *"was the exception"* to
  editing one question at a time. It reads as historical, and I could not tell
  from the code whether it still is — which is its own problem: a comment about
  a rule should not need archaeology to evaluate.

**What to do.** One rule, and it is cheap: **an exception to a documented rule is
a change to the document.** If code needs to break THEME or RULES, the fix is a
sentence in THEME naming the exception and why — as the hold pad already does —
and the comment then points at it rather than arguing its own case. An exception
that is not worth writing into the document is not worth taking.

**Done when**: every comment in `lib/` that cites THEME or RULES either conforms
or points at a named exception in the document it cites. The three field call
sites above are the immediate work: either widen the theme's input decoration to
cover them, or write the exception down.

---

## 9. Smaller things, unranked

- **No test asserts the light theme.** THEME defines a full light ramp and every
  widget test builds `Brightness.dark`. Contrast bugs in light mode are currently
  invisible to CI that does not exist (§2).
- **Chart transitions are unverified.** The zoom animation is implemented and
  nothing tests it, because testing "it looked smooth" needs a golden or a frame
  timeline. At minimum a test could assert the frame's size never changes during
  a range switch, which is the part that would be *visibly* wrong.
