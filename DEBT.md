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
- **§6, twelve features never used in a gym.** Sync is the point after which
  deleting a feature stops being free — there will be rows of it on a server and
  a migration to write. Everything that should be deleted should be deleted
  first.

The order to work in: **§1** first, then **§6**. §7 is ongoing rather than blocking. §9 is closed: the light ramp is measured pair by pair in
`test/core/light_theme_test.dart`, with the four pairs that sit under AA written
into THEME → Contrast and pinned at the numbers they hold, and the chart's zoom
is held to not resizing on any frame of a range switch
(`test/features/chart_transition_test.dart`). §8 is closed: the three field call sites and the two-piece gap are named
exceptions in THEME now, and `test/core/documented_exceptions_test.dart` fails
a comment that cites THEME or RULES, claims an exception, and does not say
which section grants it. §4 is closed — the volume providers are `autoDispose` and
`test/features/volume_provider_lifetime_test.dart` says so. §5 is closed — the rule is in RULES § Interface and enforced by
`test/core/clamp_bounds_test.dart`. §3, the row-mapping conversions, is closed — the queries whose
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
