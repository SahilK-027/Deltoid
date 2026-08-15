# Deltoid — are the numbers right

Every derived number this app puts on a screen, the rule it should implement,
where it is implemented, and whether anything asserts it against a value worked
out by hand. Produced by
[HARDENING.md § 2b](HARDENING.md#2b-interpretationmd-are-the-numbers-right).

**Analysis only.** No code changed to produce this.

[INVARIANTS.md](INVARIANTS.md) asks whether the row you wrote is the row you
read. This asks whether the number on the screen is the right number. They share
no findings.

Ranked by **how wrong the number can be × how long it takes to notice**. A
number that is 2 % wrong forever ranks above one that is 100 % wrong for a
frame.

## How to read an entry

- **UNVERIFIED** — a test exists and proves only self-consistency: the expected
  value is computed by calling the function under test, or by re-implementing
  its formula. Those prove the code agrees with itself.
- **HAND** — a literal worked out by a person appears in the test.
- **NONE** — no test asserts the value.

## The short version

The pure domain layer is in good shape: `metrics.dart`, `prefill.dart`,
`chart_buckets.dart`, `volume_history.dart`, `consistency.dart`, `units.dart`
and `plates.dart` are almost all tested with hand-computed literals, which is
unusual and is why this document is short at the top and long at the bottom.

**Three things are actually wrong**, and one of them is wrong by up to two
kilograms on every bodyweight lift ever charted.

**One structural gap runs through everything:** no test anywhere asserts a
hand-computed `best1RM`, `topSetLoad` or `volume` coming out of the *repository*.
`metrics_test.dart` checks the formulas; the repository tests check that a number
is `isNotNull` or that two repository methods agree. The wiring between them —
which load mode, which measure mode, which bodyweight, which sets — is
unverified end to end.

**The untested code is the code nobody thinks of as arithmetic.**
`heatmap_data.dart` has no test file at all (§ 7), `restTargetFor` — a three-tier
fallback that decides the number on the rest timer — has nothing either (§ 8),
and `plateLoadFor`, the wrapper between the keypad and the best-covered function
in the app, has none (§ 9). All three sit at the edge between a proven
calculation and a screen, which is where this document keeps finding the holes.

---

# 1. `bodyweightOnOrdered` interpolates on `yyyyMMdd`, not on days

**Rank 1.** Up to ~2 kg wrong, on every bodyweight and BW+ number the app has
ever shown, silently, forever.

**The rule it should implement.** Bodyweight on a day with no weigh-in is the
straight line between the weigh-in before it and the weigh-in after it, in
**days**.

**Where.** `lib/domain/metrics.dart:253-280`. The interpolation is:

```dart
final t = (dayKey - a.dayKey) / (b.dayKey - a.dayKey);   // metrics.dart:278
return a.weightKg + (b.weightKg - a.weightKg) * t;       // metrics.dart:279
```

`dayKey` is `year * 10000 + month * 100 + day` (`core/ids.dart:58-59`). **It is
not a day count.** The gap from the 28th to the 4th of the next month is 7 days
and 76 dayKey units. The gap from 31 December to 1 January is 1 day and 8 870
dayKey units. The binary search above it (`:264-273`) is correct — `dayKey` is
monotonic — but the ratio is not.

Everywhere else in the codebase this is done properly: `bucketize` converts with
`dateFromDayKey` before doing arithmetic (`chart_buckets.dart:239`), and so does
`computeVolumeHistory` (`volume_history.dart:277`). This one function does the
arithmetic on the key.

**Inputs that expose it.**

| Series | Query day | Correct | What the code returns | Error |
| --- | --- | --- | --- | --- |
| 1 Jan 2026 = 70.0, 1 Feb 2026 = 72.0 | 16 Jan 2026 | 15/31 → **70.968** | 15/100 → **70.300** | **0.67 kg** |
| 1 Dec 2025 = 70.0, 31 Jan 2026 = 74.0 | 1 Jan 2026 | 31/61 → **72.033** | 8900/8930 → **73.987** | **1.95 kg** |
| 28 Jan = 70.0, 4 Feb = 71.0 | 1 Feb | 4/7 → **70.571** | 73/76 → **70.961** | 0.39 kg |

The error is zero on a weigh-in day and worst across a month or year boundary,
which is to say it is worst exactly where a monthly weigh-in habit puts it.

**What it reaches.** `effectiveLoad` for `LoadMode.bodyweight` and
`bodyweightPlus` (`metrics.dart:25-28`), and therefore:

- `scorePerformance` → `topSetLoad`, `best1RM`, `volume` (`metrics.dart:141-146`)
- the progress chart (`training_repository.dart:1917-1923`)
- every history card (`training_repository.dart:1704-1718`)
- the session total (`session_summary_screen.dart:268-269`)

A pull-up log is scored against a bodyweight that is up to two kilograms wrong,
so the e1RM is wrong by the same proportion — and the *shape* of the curve
acquires a sawtooth at every month boundary that looks like real fluctuation.

**Time to notice: never.** The number is plausible. Nothing on screen shows the
interpolated bodyweight itself.

**Test status: UNVERIFIED.** `test/domain/metrics_test.dart:338-398` has seven
tests of `bodyweightOn` and **not one asserts an interpolated value**:

- `:344` `interpolates between entries` — asserts only `> 70` and `< 72`. Both
  the correct answer and the wrong one pass.
- `:387` `interpolates the same whatever order the entries arrive in` — the
  expectation is `bodyweightOn(day, ordered)`. **The same function on both
  sides.** This is the archetype the stage-3 rule exists for.
- `:351`, `:368`, `:377` test the clamps and the exact-hit cases, which are
  correct and correctly asserted.

**The check that closes it.**
`test/domain/metrics_test.dart` → `interpolates in days, not in date keys`:

```
// 1 Jan = 70.0, 1 Feb = 72.0. 16 Jan is 15 of the 31 days between them.
// 70 + 2 * (15 / 31) = 70.967741935…
expect(bodyweightOn(20260116, log), closeTo(70.9677, 1e-4));
```

plus the year-boundary row of the table above. Both are red against the current
code today.

---

# 2. A `Duration` is subtracted from a calendar date in nineteen places

**Rank 2.** Off by one day, twice a year, for a week — and in one case it drops a
whole week of sets from the chart rather than shifting it.

**The rule.** [chart_buckets.dart:20-23](lib/domain/chart_buckets.dart) states it
for the whole app: *"Buckets are walked as calendar dates, never as day
arithmetic. Adding seven days to a local `DateTime` crosses a daylight-saving
change correctly; adding `7 * 86400` seconds does not."*

`Duration(days: n)` **is** the `n * 86400` form, and `.difference(...).inDays` is
its mirror — a truncating division of an absolute span. **Nineteen sites in
`lib/`, across nine files, use one or the other on a calendar date.** Grouped by
what they reach:

**Reaches a stored key** — the serious one:

| Site | Code | Consequence |
| --- | --- | --- |
| `volume_history.dart:24-25` | `DateTime(y,m,d).subtract(Duration(days: date.weekday - 1))` | a week key that is not midnight, so a map lookup misses and the row is dropped |

**Reaches a displayed number:**

| Site | Code | Consequence |
| --- | --- | --- |
| `consistency.dart:91` | `.subtract(Duration(days: windowDays - 1))` | cutoff one day early; one extra session in the numerator |
| `consistency.dart:98` | `.subtract(Duration(days: today.weekday - 1))` | `thisWeek` starts a day early |
| `consistency.dart:82-85` | `.difference(...).inDays + 1` | `historyDays` one short; flips `perWeek` to null at the fortnight boundary |
| `workouts_providers.dart:76` | `dayKeyOf(DateTime.now().subtract(const Duration(days: volumeWindowDays - 1)))` | **the rolling 7-day volume window** — Today's muscle bars count 8 days |
| `workouts_screen.dart:371-375` | `DateTime(y,m,d).difference(DateTime(y,m,d)).inDays` | the date strip's "N days ago" reads one short; "Yesterday" becomes "Today" |
| `workouts_screen.dart:731-735` | same, on a `dayKey` | same |
| `volume_providers.dart:102` | `dayKeyOf(DateTime.now().subtract(const Duration(days: 365)))` | the `All` span's fallback start |
| `trend_chart.dart:91`, `:95`, `:97`, `:105` | `today.subtract(Duration(days: range.days))` | a chart range one day short at its left edge |
| `workouts_providers.dart:131` | `dayKeyOf(DateTime.now().subtract(Duration(days: heatmapWeeks * 7 + 7)))` | the heatmap's fetch window, one day short at its left edge |
| `workouts_screen.dart:282` | `DateTime _date = DateTime.now().subtract(const Duration(days: 1))` | **the backfill sheet's default date** — see below |
| `exercise_trend.dart:140`, `bodyweight_screen.dart:526`, `trend_chart.dart:264` | `to.difference(from).inDays` → `resolveGranularity` / `granularitiesFor` | a span one day short picks the wrong granularity at a threshold |

**Label only:**

| Site | Code | Consequence |
| --- | --- | --- |
| `volume_history.dart:39` | `start.add(const Duration(days: 6))` | `VolumeWeek.end`, never a key |
| `volume_chart.dart:266` | `bars.last.end.difference(bars.first.start).inDays` | axis span, layout |

**The two heatmaps are correct and are named here so their silence is not read
as an omission.** Both do the arithmetic in UTC precisely to avoid this:
`heatmap.dart:93-99` (`DateTime.utc(now.year, now.month, now.day)`, with the
reason at `:89-92`) and `year_heatmap.dart:63-67` (`DateTime.utc(widget.year, 1,
1)`, reason at `:55-56`). `dayKeyOf` reads only y/m/d, so the zone never
escapes. **This is the pattern the other nine sites should have copied.**

The `workouts_providers` / `volume_providers` / `trend_chart` cutoffs are the
narrowest of the reachable set: they subtract from `DateTime.now()`, which
carries an hour, so the day only shifts when the wall clock is within an hour of
midnight *and* a transition falls inside the span. Narrow is not zero, and the
first of them is the number on the Today screen.

**The backfill default is the one that writes a row.** Every other site on this
list moves a number on a screen; `workouts_screen.dart:282` seeds the date the
backfill sheet opens on, and that date becomes `startedAt` and `dayKey` on a real
workout if the user accepts it. Its label is computed by `_label` at `:371-375`
— `.inDays` between two local midnights — so on a day when the default is wrong
the label is wrong in the same direction and reads "Yesterday" for a date that is
not yesterday. **The check cannot be the label**, because the label shares the
bug. The fix is the calendar-named form — `DateTime(now.year, now.month,
now.day - 1)`, which Dart normalises across a month end — or the UTC pair both
heatmaps use. **Not** `dayKeyOf(...) - 1`: a `dayKey` is not a day count, which
is the whole of § 1.

**`weekStartOf` is the serious one.** Its result is used as a **map key**:

- `computeVolumeHistory` builds `indexOfWeek` by *walking* Mondays with
  `DateTime(w.year, w.month, w.day + 7)` (`volume_history.dart:257`) — always
  local midnight — and then looks up
  `indexOfWeek[weekStartOf(dateFromDayKey(row.dayKey))]` (`:277`).
- If `weekStartOf` returns 23:00 of the previous day instead of midnight, the
  lookup misses and the row is **silently dropped**: `if (i == null) continue;`
  (`:278`).
- `bucketize` has the same shape — `index[bucketStartOf(...)]` at
  `chart_buckets.dart:239`, `if (i == null) continue;` at `:240`, with
  `bucketStartOf` delegating weekly to `weekStartOf` (`:91`).

**PROVED that the shape is wrong. SUSPECT that it is reachable in most
timezones.** In every jurisdiction whose transition falls on a Sunday at
01:00–03:00 local — the EU, the UK, the US, Australia — the transition instant
always lies *outside* the within-week backward span, because `weekStartOf` starts
from Sunday-midnight, which precedes the transition. So the bug does not fire
there. It fires where midnight itself does not exist on the transition day
(Chile, Cuba, Iran, Lebanon, Brazil historically), where the transition is
mid-week, or on a permanent offset change pushed by a `tzdata` update.

**Time to notice.** A missing week on the volume chart is visible if you go
looking; nobody goes looking.

**Test status: NONE** for the crossing. `volume_history_test.dart:26-32` tests
`weekStartOf` on ordinary days, and `chart_buckets_test.dart:33-42` tests
`nextBucket` across February, a 31st and a leap year — but only the *forward*,
calendar-named path, which is the one that is already correct.

**The check that closes it.**
`test/domain/volume_history_test.dart` → `a week start is midnight across a
clock change`, over a fixed list of transition dates, asserting
`weekStartOf(d).hour == 0` and that `computeVolumeHistory` loses no rows in a
span containing one. The fix is one line —
`DateTime(date.year, date.month, date.day - (date.weekday - 1))` — and it is the
form the rest of the file already uses.

For the "days ago" pair, `test/features/` → `a workout logged yesterday reads as
yesterday across a clock change`: the fix is `.difference(...).inDays` on a **UTC**
pair — `DateTime.utc(y, m, d)` either side — not on two local midnights, and not
subtraction of one `dayKey` from another, which is § 1's bug wearing a different
hat. For `workouts_providers.dart:76` and `:131`, the fix is to build the cutoff
by naming the calendar date — `DateTime(now.year, now.month, now.day - 6)` —
rather than subtracting an absolute span from an instant.

**`consistency.dart` is the smaller half.** `historyDays` across a spring-forward
is 14 where it should be 15 (`.inDays` truncates 13 d 23 h to 13), which flips
`perWeek` from a number to `null` at exactly the two-week boundary
(`consistency.dart:106-108`), and shifts `windowDays` — the divisor — by one.
The cutoff at `:91` lands on the previous day, adding one session to the
numerator. Test status **NONE**; `consistency_test.dart:29-49` pins the window
arithmetic with hand-computed literals but never crosses a transition.

---

# 3. A working set with no load is a performance worth zero volume

> **CLOSED at the source rather than on the chart.**
>
> The entry asked whether a loadless performance should produce a chart point.
> The better answer was that the row should not exist. A set can be ticked two
> ways — tapping the box, and typing reps then pressing Next — and only the box
> refused an empty one. The rule was a private method on the log screen, so the
> second path never asked it.
>
> Both paths now call `missingBeforeDone` (`lib/features/log/set_completion.dart`),
> a function over plain values with eleven cases covering the four load modes,
> holds, and the ghost. Blank stays distinct from zero for `bodyweightPlus`: an
> unweighted set of a movement you sometimes load is a different fact from a
> belt you forgot to record, and only one should score as bodyweight alone.
>
> **Still worth the downstream guard**, at STALE rather than as a bug: the
> write path can no longer make such a row, but a restore or — after 5b — a
> merge can still deliver one, and the chart would draw the zero.
>
> Not red-first at the UI layer: there is no LogScreen test harness in the
> repo, so the rule is pinned and the wiring is not. Owed.

**Rank 3.** One chart point reading `0 kg` on a day you trained.

**The rule.** A performance with nothing scoreable in it should not produce a
point.

**Where.** `scorePerformance` counts a set toward `workingSets` on set type
alone — `if (!s.type.countsForProgress) continue; … count++`
(`metrics.dart:139-148`) — before it knows whether the set has a load or a count.
So `score.isEmpty` (`metrics.dart:114`) is false for a done working set with
`weight == null`, and `exerciseProgress` keeps the point
(`training_repository.dart:1924`) with `topSetLoad == null`, `best1RM == null`
and `volume == 0`.

**Inputs that expose it.** A `LoadMode.total` exercise performed for the first
time, where the reps are typed and the weight is not. Reachable: the tick path
only *adopts* a weight from the ghost (`log_screen.dart:983`), and on a first-ever
performance there is no ghost to adopt from. `_advance` requires `reps > 0` and
nothing more (`log_screen.dart:980`).

**Time to notice.** Immediately, if the volume series is on screen — a bar at
zero on a day you trained. Otherwise never.

**Test status: NONE.** `training_repository_test.dart:1686` (`a set taken back is
not on the chart, and an emptied day is not either`) covers `isDone = false`, not
`weight = null`.

**The check that closes it.**
`test/domain/metrics_test.dart` → `a set with a count and no load scores nothing`:
assert `scorePerformance(...).isEmpty` for
`[ScoredSet(type: working, reps: 8)]` under `LoadMode.total`. Red today —
it currently reports `workingSets: 1, volume: 0`.

**Note this is a judgement call, not obviously a bug.** `totalReps` of 8 is a
true fact about the day. The question is whether a point with no load belongs on
a load chart. Decide it before writing the test.

---

# 4. Two definitions of "the top set"

> **CLOSED, and the entry was wrong about the shape of it.**
>
> This was filed as *two implementations of one rule*. It is not. It is **one
> name over two different questions**, and the answer was never to merge them:
>
> - the summary row asks *what was the heaviest thing you did?* — a record of
>   the session, so back-offs belong in it
> - the chart asks *what counts as progress?* — so back-offs must stay out, or
>   a deliberately light week reads as a gain
>
> Merging the pools would have broken one of the two. Widening
> `scorePerformance` would put back-off and drop noise on the e1RM line;
> narrowing `heaviestLogged` would blank the summary row on a light day.
>
> **What actually shipped:**
>
> 1. **The ranker is now shared.** Both rank by `effectiveLoad` rather than the
>    figure typed in the box. That was the one real defect — disagreement 3 —
>    and it was **red first**:
>
>    ```
>    a set with no load does not outrank one that has a load
>      Expected: <0>   Actual: <1>
>    ```
>
>    A `total` set carrying only `addedWeight` sorted as though the belt were
>    on the bar, while the chart scored it as having no load at all.
> 2. **The pools stay different**, and each now says why in its own doc.
> 3. **`topSetIndex` is renamed `heaviestLogged`.** The name was the bug: it
>    read as a second opinion on the chart's question and got filed as a defect
>    twice. Two names, two questions, and nothing left that looks like a
>    contradiction.
>
> Disagreements 1 and 2 are therefore **not defects and are not "fixed"** —
> they are the two functions correctly answering different questions, and that
> is now written down where a reader will find it.
>
> Worth recording: **deload was never part of this.** `exercise_trend.dart`
> already excludes deload weeks from the plotted line (`:300`), the axis scale
> (`:226`), the all-time best (`:395`) and the stall badge (`:389`), with the
> reason stated there — *"a light week is periodisation, not a drop in
> strength"*.

**Rank 4.** A card names a top set on a day the chart has no point for.

**The rule.** One definition, per [RULES.md § 4](RULES.md#4-code), which records
that these two functions disagreed once already about every hold ever logged.

**Where.**

- `scorePerformance` ranks by `effectiveLoad` over **working and amrap only**
  (`metrics.dart:139`, `:161-164`).
- `topSetIndex` ranks by raw `weight ?? addedWeight` over **everything except
  warm-ups** (`set_format.dart:117`, `:120-122`).

**They agree on the ordering** for every load mode — `perSide` doubles
monotonically, `bodyweightPlus` orders by `addedWeight` either way, `bodyweight`
ties everything and both keep the first. **PROVED.** That is the part
[RULES.md § 4](RULES.md#4-code) was worried about and it is fine.

**They disagree on the pool, in three ways.**

1. `backoff`, `drop` and `restPause` are eligible top sets for `topSetIndex` and
   are not performances for `scorePerformance`. On a day whose only non-warm-up
   sets are back-offs — a deliberately light session — the summary's `_top`
   (`session_summary_screen.dart:602-603`, and the workout detail screen, which
   its comment says ranks the same way) names a top set while `exerciseProgress`
   returns no point at all.

2. **The all-warm-up fallback.** `topSetIndex` widens its pool to *every* set
   when nothing survives the warm-up filter — `final pool = counted.isEmpty ?
   [for (var i = 0; i < sets.length; i++) i] : counted` (`set_format.dart:119`),
   documented at `:105`. So a session where only warm-ups were ticked names a
   warm-up as the top set. `scorePerformance` returns `isEmpty` for the same
   list. Deliberate on its own terms — the doc says *"unless warm-ups are all
   there is"* — and still a second definition.

3. **`addedWeight` is ranked by one and ignored by the other.** `topSetIndex`
   ranks `sets[i].weight ?? sets[i].addedWeight` (`set_format.dart:121-122`),
   while `effectiveLoad` reads `addedWeight` only under `bodyweightPlus`
   (`metrics.dart:20-28`) — under `total` and `perSide` it returns `weight` and
   `weight * 2`, both null when `weight` is null. So a `total` set with
   `addedWeight` set and `weight` null is rankable by `topSetIndex` and scores
   `null` load. That is § 3's exact input, reached from the other side.

**Time to notice.** Never; the two are on different screens.

**Test status: NONE** for any of the three. `metrics_test.dart:162` and
`set_format_test.dart` each test their own function.

**The check that closes it.**
`test/domain/set_format_test.dart` → `the top set of a day is the same set the
score picked`, over a table of set lists covering each `SetType` and each
`LoadMode` — and including an all-warm-up list and a `total` set carrying only
`addedWeight` — asserting `topSetIndex` selects the set whose `effectiveLoad`
equals `scorePerformance(...).topSetLoad`, or that both agree there is no top
set. Then either widen `scorePerformance`'s pool or narrow `topSetIndex`'s —
deliberately, in one place.

---

# 5. The unit preference does not survive a restore

**Rank 5.** Every weight on every screen changes by a factor of 2.2, once.

`app_settings` is not in `_codecs` (`backup_service.dart:124-261`), so after a
restore onto a fresh install `weightUnit()` (`training_repository.dart:2148-2153`)
reads nothing and `WeightUnitX.parse(null)` returns `kg`
(`units.dart:53-56`).

Storage is kilograms throughout, so **no stored number is wrong** — but a pounds
user restoring onto a new phone sees their entire history in kilograms with
nothing said, and the deload rounding in `applyDeload`
(`prefill.dart:234` → `roundLoadIn`, `units.dart:63-67`) will snap the next
suggestion to a half-kilo rather than a pound.

**Time to notice: immediately**, which is the only reason this is not higher.

**Test status: NONE.** Also recorded as [INVARIANTS.md](INVARIANTS.md) § 17.

**The check that closes it.** `backup_service_test.dart` → `the unit preference
survives a restore`.

---

# 6. Nothing asserts a hand-computed score through the repository

**Rank 6, and the widest gap in the document.** Not a bug — an absence.

`metrics_test.dart` verifies the formulas properly:

| Value | Where | Test | Status |
| --- | --- | --- | --- |
| `effectiveLoad`, all four modes | `metrics.dart:13-30` | `metrics_test.dart:6-42` | **HAND** — 22.5 → 45, 73 → 73, bw 72 → 72, bw+10 → 82, bw+ with null bodyweight → 10 |
| `estimated1RM` Epley | `metrics.dart:37-41` | `metrics_test.dart:114` | **HAND** — `100 × (1 + 6/30) = 120` |
| the rep cap at 12 | `metrics.dart:39` | `metrics_test.dart:117-121`, `:292-294` | **UNVERIFIED** — `expect(at20, at12)`, both sides computed. The literal (`50 × 1.4 = 70`) is never written down |
| `scorePerformance` set-type filter | `metrics.dart:139` | `metrics_test.dart:132-147` | **HAND** — 1 working set, top 100, volume 600 |
| `sessionVolume` | `metrics.dart:199-218` | `metrics_test.dart:44-110` | **HAND** — 72 × 14, 450, 410, 700, 0 |
| a hold has no e1RM and no volume | `metrics.dart:150`, `:165` | `metrics_test.dart:185-246` | **HAND** — topReps 62, totalReps 157, volume 0, session total 300 |
| `beatsPrevious` | `metrics.dart:53-65` | `metrics_test.dart:284-336` | **HAND**, all five branches |
| `stalledSessions` | `metrics.dart:287-300` | `metrics_test.dart:400-417` | **HAND** |

**What no test does** is assert any of those numbers coming out of
`exerciseProgress` (`training_repository.dart:1845`) or `exerciseHistoryPage`
(`:1623`). The repository tests assert shape only:

- `training_repository_test.dart:1682` — `expect(points.last.best1RM, isNotNull)`
- `:1616`, `:1640`, `:1686`, `:1698` — counts, ordering, presence
- `:2437-2441` (`daily counts carry the day, and agree with the rolling
  window`) — `expect(row.sets, rolling[logged.muscle])`, **two repository methods
  compared against each other**. The neighbouring `expect(row.sets, logged.sets)`
  is against the fixture, which rescues it; the second line proves only that the
  raw SQL at `:881-903` and the drift query at `:775-788` agree, which is worth
  something and is not correctness.

So: the *formulas* are proved, the *wiring* is not. Which `loadMode` was read,
whether `measureMode` reached `scorePerformance`, whether the bodyweight series
was the right one, whether the raw SQL column order at
`training_repository.dart:1879-1889` still lines up — none of that is asserted
against a number.

**The check that closes it.**
`test/data/training_repository_test.dart` → `a charted point is the number worked
out by hand`. One dumbbell exercise (`perSide`), one bodyweight-plus exercise,
one hold. Log known sets, then:

```
// Incline DB press, perSide: 22.5 × 2 = 45 kg effective, 8 reps.
// Epley: 45 × (1 + 8/30) = 57.0
expect(point.topSetLoad, 45);
expect(point.best1RM, closeTo(57.0, 1e-9));
expect(point.volume, 360);   // 45 × 8
```

This is one test and it covers more surface than any other on the list.

---

# 7. The heatmap and its consistency rate have no tests at all

**Rank 7.** An absence, like § 6, and a narrower one — but it is the only file in
this audit with **zero** test coverage of any kind.

[lib/features/workouts/heatmap_data.dart](lib/features/workouts/heatmap_data.dart)
is pure folding logic with no test file. `grep -rn buildHeatmap test/` returns
nothing.

**What it computes.** Two functions that produce the same displayed values from
different sources:

- `buildHeatmap(List<Workout>)` (`:39-57`) folds raw workout rows into
  `Map<int, HeatDay>` — counting workouts per day, OR-ing `isDeload`, keeping
  the first `workoutId` — then hands `completed.map((w) => w.dayKey)` to
  `computeConsistency`. Used by `workoutsProvider`
  (`workouts_providers.dart:136`), which draws the Today screen's grid.
- `buildHeatmapFromDays(List<LoggedDay>)` (`:65-83`) takes rows SQL has
  **already** folded by day, and re-expands them: `for (var i = 0; i <
  d.workouts; i++) d.dayKey` (`:75-77`), because `computeConsistency` wants one
  key per session rather than per day. Used by `fullHeatmapProvider`
  (`workouts_providers.dart:53`), which draws the all-time view.

**The rule they should implement.** The same day's training produces the same
`Consistency` and the same `HeatDay` whichever path it arrives by. The
re-expansion at `:75-77` exists solely to make the second path agree with the
first, and nothing checks that it does.

**Inputs that would expose a break.** A day with two workouts, one of them a
deload: `buildHeatmap` OR-s `isDeload` across them, `buildHeatmapFromDays` reads
whatever `LoggedDay.isDeload` was aggregated as in SQL. If those two disagree,
one day is drawn as an easy week on Today and a normal one on the all-time view,
and the consistency rate underneath differs between two screens showing the same
history.

**Time to notice.** Never — the two grids are on different screens and cover
different spans, so a reader has no side-by-side moment.

**Test status: NONE.** Both functions, every field.

**The check that closes it.**
`test/features/heatmap_data_test.dart` → `both heatmap paths agree on the same
history`: build a fixture of workouts, run `buildHeatmap` over the rows and
`buildHeatmapFromDays` over the same history folded by day, and assert `days` and
`consistency` are equal field by field — plus hand-computed literals for a
two-workout day and a mixed deload day, so the test is not merely the two
implementations agreeing with each other. **This one needs both halves**: the
cross-check alone is exactly the UNVERIFIED shape this document exists to flag.

---

# 8. Nothing tests the number the rest timer opens on

**Rank 8.** A timer counting to the wrong target, on every set of a session.

**The rule.** The session slot's rest, if it has one; otherwise the last rest
actually taken on that movement; otherwise two minutes. Three tiers, in that
order, stated at `training_repository.dart:2155-2159`.

**Where.** `restTargetFor` (`training_repository.dart:2160-2190`). The slot
lookup filters `session_exercises.deleted_at` (`:2165-2170`); the fallback takes
the newest `set_logs.rest_seconds` for the exercise, ordered by `completed_at`
(`:2175-2187`); the floor is `?? 120` (`:2189`).

**Inputs that would expose it being wrong.** The same movement in two sessions
with different slot targets — pick the wrong tier and Push 2 opens on Push 1's
rest, which is [RULES.md § 1](RULES.md#1-the-one-rule)'s failure in a smaller
place. An exercise added mid-session has no slot at all — `setRestTarget` returns
false for exactly that case (`:2192-2199`) — so it must reach the second tier and
not the floor.

**One thing the second tier does not filter.** It joins `workout_exercises` and
constrains only `set_logs.deleted_at` (`:2181`) — not the slot's tombstone, not
the workout's. So it will read a rest value off a set orphaned by
`removeExerciseFromWorkout`. Those orphans are
[INVARIANTS.md](INVARIANTS.md) § 1, and this is the one read path that sees them;
recorded there as § 31.

**Time to notice.** Minutes — the timer is on screen and counting down in front
of you. That is the only reason this sits at rank 8 rather than higher.

**Test status: NONE.** `grep -rn restTarget test/` returns nothing.
`training_repository_test.dart:1204` writes a `restSeconds` and reads it back
through the workout, which asserts the column, not the resolution.

**The check that closes it.**
`test/data/training_repository_test.dart` → `rest comes from the slot, then the
last set, then 120` — three cases, three literals, plus a fourth asserting a
tombstoned slot's sets are not the fallback. Cheap, and it is the only thing that
would notice the three tiers being reordered.

---

# 9. Everything below here is verified, and is recorded so it is not re-audited

## `resolvePrefill` — the app's reason to exist

**Rule.** Session first, then a deload of the same session, then another session
labelled `otherSession` ([RULES.md § 1](RULES.md#1-the-one-rule)).

**Where.** `lib/domain/prefill.dart:143-209`. Three ordered passes at `:154-184`;
`scale = targetIsDeload && !pick.isDeload` at `:192` is the never-deload-a-deload
rule.

**Test status: HAND**, and thorough. `test/domain/prefill_test.dart:27-101` covers
all four sources with asserted weights (22.5, 20, 18); `:104-147` covers the
deload transform and the no-double-scaling rule; `:152-229` covers `applyDeload`
warm-up preservation, set trimming, the `math.max(1, …)` floor
(`prefill.dart:230`), partials carried unscaled (`:244`), continuations dropped
(`:227`), added weight scaled and bodyweight not (`prefill_test.dart:211`), and
half-kilo rounding (`:222`, `74.4 → 74.5`).

End to end through the database: `training_repository_test.dart:165` (`a
completed workout becomes next week's prefill for the same session`) and `:197`
(`Push 2 does not inherit Push 1 numbers for the same exercise`) — the one rule,
asserted with literals.

**Inputs that would expose a break.** Two performances of one movement on one
day: covered at `:980` and `:585`, resolved by the `(startedAt, slotId)` sort at
`training_repository.dart:1333-1337`. A movement fanned across many days pushing
the same-session performance out of the window: covered at `:1016` (`the
same-session lookup has no horizon`), which is what the second query at
`training_repository.dart:1307-1312` exists for.

**Nothing to add.**

## `bucketize`

**Rule.** Mean for a measurement, sum for a count; an empty bucket is `null`, not
zero; rows outside the span are dropped; boundary days are inside.
(`chart_buckets.dart:1-25`, `:214-265`.)

**Test status: HAND.** `chart_buckets_test.dart:57` (mean 72 over 3),
`:74` (sum 36), `:90` (a null bucket keeps its place), `:107` (a row outside is
dropped, `count == 1`), `:124` (six empty weeks with named start dates),
`:139` (a reversed span is no buckets), `:44` (a February bucket ends on the
29th in a leap year), `:151` (order in is irrelevant).

Boundary days: the filter is `row.dayKey < fromKey || row.dayKey > toKey`
(`:238`) — inclusive both ends, and `:107`'s fixture sits one day outside.
**Verified.**

## `foldWeeks` and sets-per-week

**Rule.** The value is sets **per week** at every granularity, never sets in the
bucket (`volume_history.dart:42-50`); untrained weeks divide
(`:66-68`, `:152-158`); daily is treated as weekly (`:93`).

**Test status: HAND.** `volume_history_test.dart:266` (weekly is the identity),
`:275` (`30 sets over 5 weeks → 6.0`, with the total and the week count asserted
separately), `:293` (a week belongs to its Monday's bucket — 7 and 3),
`:306` (peak follows the fold), `:155` (`averagePerWeek == 2.0` divides by all
three weeks), `:228` (`20.0` across regions).

`:188` (`expect(steady.averagePerWeek, lumpy.averagePerWeek)`) is **UNVERIFIED**
as a value, but the test's real assertions (`weeksTrained` 3 vs 1) are hand
literals, so the point being made is proved. Low priority.

## `computeVolumeHistory`

`volume_history.dart:239-304`. Weeks walked as calendar dates (`:257`); span
widened to whole weeks (`:244-245`); `other` counted nowhere
(`:275-276`); days outside the span dropped (`:272`).

**Test status: HAND** — `volume_history_test.dart:35` (a Sunday and the Monday
after are different weeks, 4 and 6), `:51`, `:61` (`[10, 0, 0]`), `:85` (legs 9 =
quads 6 + hams 2 + glutes 0 + calves 1), `:125` (`other` counted nowhere, total
3), `:141`, `:242` (a year folds to 52–54 weeks).

## `countsAsVolume` and the muscle snapshot fallback

**Rule.** Working, amrap and backoff count; warm-ups, drops and rest-pause do not
(`muscle_volume.dart:85-88`) — deliberately **not** `countsForProgress`
(`enums.dart:169`). The muscle is the snapshot on the logged row, falling back to
the catalog only when the row predates the column
(`training_repository.dart:818-819`, and the same `COALESCE` written out in raw
SQL at `:886`, grouped on the expression at `:900`).

**Test status: HAND**, and this one is well covered:
`training_repository_test.dart:2251`, `:2265` (an unticked set is not volume),
`:2276` (warm-ups and drop legs out, backoff in), `:2301`, `:2319` (sets count
mid-session), `:2334` (a skipped slot contributes nothing), `:2352` (the muscle
is snapshotted), `:2369` (**refiling an exercise does not rewrite March** — the
rule from [RULES.md § 2](RULES.md#2-data)), `:2397` (a pre-column row falls back
to the catalog).

The SQL list of volume set types is generated from `countsAsVolume` rather than
written out (`training_repository.dart:919-922`), so the raw statement cannot
drift. **Good.**

## Cycle advance and deload scheduling

**Rule.** `_cyclesSinceDeload(beforeIndex:)` is exclusive
([RULES.md § 2](RULES.md#2-data)); a deload never chains
(`cycle_engine.dart:70`); the counter resets when a deload begins (`:128`).

**Where.** `cycle_engine.dart:68-83`, `:122-130`;
`training_repository.dart:332-348` for the fold over completed cycles.

**Test status: HAND.** `cycle_engine_test.dart:73` (fires at 5, not 4), `:80`
(no chaining), `:94` (the countdown), `:112-130` (`planNextCycle`), and `:133`
(`a full run reaches deload exactly every N cycles` → `[7, 14, 21]`, which is the
property test that catches an off-by-one). Through the database:
`training_repository_test.dart:284`, `:316`, `:347`, `:385`.

**One thing nothing covers.** `_cyclesSinceDeload` counts only cycles with
`completed_at IS NOT NULL` (`training_repository.dart:336`). A deload cycle that
was tombstoned by `_reopenCycleIfIncomplete` (`:3293-3302`) rather than completed
does not reset the counter, so the next deload lands late. **SUSPECT** — the
sequence needs a deload cycle to be the successor that gets dropped. **Test
status: NONE.**

## `dayKey ↔ DateTime`, week starts, DST and leap days

- `dayKeyOf` / `dateFromDayKey` — `core/ids.dart:58-62`. Lossless round trip for
  any real date. **Test status: NONE directly**, used throughout every other
  test.
- Leap days and month ends: `nextBucket` names the next date rather than adding a
  `Duration` (`chart_buckets.dart:97-104`), and a bucket's `end` is the day before
  the next one opens (`:253-256`) — the only definition that survives February.
  **HAND** at `chart_buckets_test.dart:33`, `:44` (29 Feb 2024).
- Week start is Monday everywhere, from one function
  (`volume_history.dart:24`, re-exported into `chart_buckets.dart:29`), so the
  same Sunday session cannot land in two different weeks on two screens.
  **HAND** at `volume_history_test.dart:26` and `chart_buckets_test.dart:12`.
- **DST: see § 2.** The forward-walking calendar paths and both heatmaps (which
  work in UTC) are correct; the nine `Duration`-subtracting and
  `.inDays`-truncating sites are the exception.

## Weights, units and formatting

`units.dart`. Storage is kg, conversion at the edge (`:36-44`); display snapped
to the unit's granularity (`:48-51`); bodyweight to a tenth rather than to a
plate (`:103-115`); a signed delta computed from what is **shown**
(`:87-92`, the rule from [RULES.md § 4](RULES.md#4-code)).

**Test status: HAND**, comprehensively — `units_test.dart:8-132`: 225 lb ↔
102.058 kg, 100 kg → 220 lb, 74.4 → 74.5, `roundLoadIn` in both units, a deload
in pounds landing on 180 lb (`:52`), `+1` / `−0.5` / `null` for the deltas,
`76.4` surviving as `76.4` in bodyweight and rounding to `76.5` as a load
(`:103-108` — the two precisions asserted side by side, which is the test that
would catch them being merged).

## Set formatting

`set_format.dart:23-90`. **Test status: HAND** at
`test/domain/set_format_test.dart`. `formatCount` partials-as-suffix
(`enums.dart:76-80`) asserted at `metrics_test.dart:257-264`, including that a
hold never shows a partial.

## Consistency

`consistency.dart:64-110`. **Test status: HAND** —
`consistency_test.dart:19-126`: `perWeek` null under a fortnight, `1.5` over 14
days, the 28-day window (`0.25`), `2.0` over a long history, days-trained vs
sessions (`:86`), a fresh Monday at zero (`:93`). **Except the DST crossing —
see § 2.**

## Plate maths

**Rule.** `solvePlateLoad` breaks a total into bar plus plates, greedy from the
heaviest down — optimal for this set because every plate divides or halves the
next (`plates.dart:63-65`) — and reports what the rack cannot make as
`remainderKg` rather than rounding it away (`:37-43`). Null, not an empty load,
for a target at or under the bar (`:71`).

**Where.** `lib/domain/plates.dart:66-96`. The arithmetic runs in **integer half
kilos of total load** (`:80`), not in doubles and not per side, with the two
failures that forced it written down at `:73-79`: floating point leaving
`2.4999999999999996kg` unloadable on a bar that loads exactly, and a per-side
figure rounding `21.25` to `21.5` and inventing a kilo that is not on the bar.

**Test status: HAND**, every assertion. `test/domain/plates_test.dart`:
`:8-14` (100 on a 20 bar → one 25 and one 15 a side, `perSideKg` 40,
`loadedKg` 100, remainder 0), `:17-20` (140 → two 25s and a 10, stacking rather
than reaching for lighter plates), `:24-28` (a bare bar), `:32-33` and `:37`
(null under the bar and with no bar), `:43-47` (**62.5 on a 20 bar → a 20 a side
and 2.5 short**, which is the keypad's every-other-press case), `:55-59` (29 on
the 9kg EZ → a 10 a side, remainder exactly 0, which is the test that catches the
double-subtraction bug the comment describes), `:63-67` and `:71-77` (the bar
weights, and that only `none` is weightless).

**This is the best-covered function in the app**, which is right: it is the one
number read at arm's length with a bar in your hands. **Nothing to add to
`solvePlateLoad`.**

**One gap, and it is at the edge rather than in the maths.** `plateLoadFor`
(`lib/features/log/widgets/plate_view.dart:51-60`) is the wrapper the keypad
actually calls, and **nothing tests it**: `grep -rn plateLoadFor test/` returns
nothing. It decides four things — no bar, unparseable buffer, a non-kg display
unit, and the `unit.toKg` conversion — and the third is load-bearing, because
drawing a kilo breakdown for a pounds user would put a diagram on screen that no
gym can load. The guard is there (`:56`) and the reasoning is written down
(`:44-50`); it is simply unasserted.

**The check that closes it.** `test/features/` → `no plate diagram in pounds,
and none without a bar` — four cases against `plateLoadFor`, each expecting
null, plus one kg case expecting the same `PlateLoad` `solvePlateLoad` returns.
Cheap, and it pins the one branch that turns a correct function into a wrong
picture.

## Backup round trip

**Test status: HAND** where it counts. `backup_service_test.dart:94` (restoring
into an empty database reproduces it exactly), `:125` (enum and list columns
survive), `:157` (a file written before a column existed), `:182` (a null muscle
snapshot stays null rather than becoming `other`), `:206` (bar kind), `:235` (the
streamed file is byte-identical to `buildPayload`), `:293` (restore from bytes),
`:357` (history is still queryable afterwards).

**Two gaps in the round trip itself**, both carried over to
[INVARIANTS.md](INVARIANTS.md) §§ 17–18: the unit preference (§ 5 above) and the
absence of a test that every column of every codec has a default.

**And a third thing worth knowing while reading the above**: every test in that
list round-trips through `buildPayload` over a database nothing is writing. The
export the *app* runs pages by offset over a live one and can skip a row
entirely, and the `counts` header it writes is never checked against what a
restore lands — [INVARIANTS.md](INVARIANTS.md) §§ 5–6. Those are storage
findings rather than arithmetic ones, so they are catalogued there; they are
named here because "the backup round trip is well tested" is true of the codecs
and not of the file the phone actually produces.

---

# The UNVERIFIED list, in one place

Stage 3 replaces each of these with a hand-computed literal.

| Test | Why |
| --- | --- |
| `metrics_test.dart:387` `interpolates the same whatever order the entries arrive in` | `expect(bodyweightOn(d, shuffled), bodyweightOn(d, ordered))` — the same function on both sides. The only test that touches the § 1 bug, and it cannot see it |
| `metrics_test.dart:344` `interpolates between entries` | asserts a range, not a value. Passes under the bug |
| `metrics_test.dart:117` `caps reps so high-rep sets cannot masquerade as strength` | `expect(at20, at12)`, both computed. Write `50 × (1 + 12/30) = 70` |
| `metrics_test.dart:292` (inside `the rep cap in e1RM does not hide a 12 to 13 improvement`) | `expect(estimated1RM(45,13), estimated1RM(45,12))`, both computed. `45 × 1.4 = 63` |
| `volume_history_test.dart:188` `weeks trained is what the average cannot say` | `expect(steady.averagePerWeek, lumpy.averagePerWeek)`. The rest of the test is hand-computed; this line is not |
| `training_repository_test.dart:2441` `daily counts carry the day, and agree with the rolling window` | `expect(row.sets, rolling[logged.muscle])` compares two repository methods. Keep it — it is a real cross-check of the raw SQL against the drift query — and add a literal beside it |
| `training_repository_test.dart:1682` `a chart point knows its session and whether the week was light` | `expect(points.last.best1RM, isNotNull)`. § 6 |

Six of the seven are in the two functions this document ranks first and sixth,
which is not a coincidence: **the numbers nobody hand-computed are the numbers
nobody checked.**
