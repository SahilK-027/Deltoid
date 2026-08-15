# Deltoid — are the numbers right

## What an interpretation is, in this project

A **derived** number — anything the app computes rather than stores. An e1RM, a
volume total, a sets-per-week rate, an interpolated bodyweight, a bucket mean, a
rest target, a plate breakdown, a "3 days ago".

[INVARIANTS.md](INVARIANTS.md) asks whether the row you wrote is the row you
read. **This file asks whether the number on the screen is the right number.**
Storage can be perfect and the arithmetic still wrong: every set correctly on
disk, and the chart above them drawn against a bodyweight interpolated on a
date key instead of a day count.

The two share no findings by construction. A wrong *stored* value is an
invariant; a wrong *computed* value is an interpretation.

## The three test statuses, which are the whole point of the file

- **HAND** — a literal worked out by a person appears in the test.
- **UNVERIFIED** — a test exists and proves only self-consistency: the expected
  value is produced by calling the function under test, or by re-implementing
  its formula in the test. **This is the category the file exists to find.** It
  reads as coverage, counts as coverage, and proves the code agrees with itself.
  One bug on both sides of an `expect` satisfies it perfectly.
- **NONE** — nothing asserts the value.

Every entry states: the rule the number should implement, in words; where it is
implemented, with `file:line`; the inputs that would expose it being wrong; and
which of the three statuses it currently has.

**Ranked by how wrong the number can be × how long it takes to notice.** A
number 2 % wrong forever outranks one 100 % wrong for a frame — the first is
never questioned and the second is seen immediately.

## How an entry closes

**When the check it names passes**, with a banner recording how, the red output,
and **what the entry got wrong about itself**. In the round just finished, five
of eight entries were wrong about their own evidence, field or shape — one had
run its grep against the wrong string, one named `isDeload` as the risk when the
non-deterministic field was `workoutId`, one asked for a cross-check that is
false by design across the app's two real inputs, and one found its code correct
and its comments wrong. Recording that is worth more than the fix.

## The rules the fixing round runs under

The same four as [INVARIANTS.md](INVARIANTS.md) — red first, hand-computed
values, one item per commit — and one that belongs to this file in particular:

**A hand-computed literal over a fixture that cannot feel the bug is still a
test that proves nothing.** The consistency fixture had four correct hand
literals and stayed green when the window arithmetic was perturbed, because the
cutoff moved through an empty stretch of calendar. Put a data point either side
of every boundary the arithmetic names, then perturb the code and watch the
number move. Stage 3's rule is about the value; this is the other half of it.

---

## The prompt that regenerates this file

Run it when new derived numbers appear, or when the inputs behind existing ones
change. **Sync is such a change**: a merged row can carry a value combination
the write path can no longer produce — a working set with a count and no load,
say — and the arithmetic downstream will draw it.

```
Audit the correctness of every derived number this app displays. Not storage
integrity — arithmetic. ANALYSE ONLY; the deliverable is INTERPRETATION.md and
nothing else.

For each derived value state: the rule it should implement (in words), where it
is implemented (file:line), the inputs that would expose it being wrong, and
whether a test asserts the value against a HAND-COMPUTED expectation.

Cover at minimum:
  - resolvePrefill: session-scoped progression. The app's reason to exist.
  - effectiveLoad across all four LoadModes, including addedWeight and a null
    bodyweight.
  - scorePerformance: top set, e1RM (Epley, reps capped at 12), volume, and
    which SetTypes count. Holds separately: a hold's seconds live in reps, its
    top set is the longest rather than the heaviest, and it has no e1RM and no
    volume.
  - bodyweightOnOrdered: interpolation, and behaviour outside the series.
  - bucketize: mean vs sum, empty buckets, rows on a boundary day.
  - foldWeeks: sets-per-week across granularities.
  - countsAsVolume and the workout_exercises.muscle snapshot fallback.
  - cycle advance and deload scheduling.
  - dayKey <-> DateTime, week starts, and every calculation crossing a DST
    boundary or a leap day.
  - the heatmap folds, and the consistency rate under them.
  - backup round-trip: does every field survive exactly.
  - every number that reaches a screen through the REPOSITORY rather than
    through a pure function: the formulas being proved is not the wiring being
    proved. Which loadMode was read, whether measureMode arrived, which
    bodyweight series was used, whether a raw statement's columns still line
    up.

Flag every test whose expected value is computed by calling the same function
under test, or by re-implementing its formula in the test. Those prove the code
is self-consistent, not that it is right. List them as UNVERIFIED — they are the
quiet majority of "covered" behaviour in most projects and there will be some
here, including in tests written recently.

Rank by: how wrong the displayed number could be, and how long it would take a
user to notice.

End with the UNVERIFIED list gathered in one place, as a table, so it can be
worked through and struck off.
```

## What the last round learned about where the holes are

Two patterns, both worth checking first next time.

- **The untested code is the code nobody thinks of as arithmetic.** The pure
  domain layer was almost entirely HAND already. Every hole was at an *edge*:
  a fold with no test file, a three-tier fallback deciding a timer, a wrapper
  between a keypad and the best-covered function in the app. Between a proven
  calculation and a screen is where this audit keeps finding things.
- **The numbers nobody hand-computed are the numbers nobody checked.** Six of
  the seven UNVERIFIED tests sat in the two functions the audit ranked first and
  sixth. That was not a coincidence, and it is the cheapest heuristic in the
  file: find the self-referential assertions and you have found the audit's
  ranking before doing the ranking.
