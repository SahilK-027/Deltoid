# Chart audit for 1.19.0

Audit only. No production code was changed. Everything in `docs-scratch/` is
untracked and is not to be committed.

## Method

- Harness: `docs-scratch/chart_audit_test.dart`, a throwaway golden test. It
  loads Inter and Material Icons so text renders as on the device.
- Each case renders four panels side by side at 390 logical px: dark at 1.0,
  light at 1.0, dark at 1.3 and light at 1.3. The sheet is saved as
  `docs-scratch/shots/<case>.png`, and each panel separately as
  `docs-scratch/shots/panels/<case>.<variant>.png`.
- 88 cases (352 panels) were rendered in one run, with the log in
  `docs-scratch/run.log` and layout exceptions in `docs-scratch/shots/_errors.txt`.
  The two outlier cases were rerun after a generator fix, and the exercise
  group was rerun on the page background rather than in a card, which is how
  `exercise_history_screen.dart` actually places it.
- What was rendered:
  - The real widgets `ExerciseTrend`, `StrengthCard`, `AllTimeScreen` (with its
    providers overridden), `VolumeChart`, `VolumeTile`, `VolumeBars`,
    `ConsistencyHeatmap` and `YearHeatmap`.
  - Replicas of the private `_TrendCard` (bodyweight) and of the region and
    grid compositions. These copy the source layout line for line.
- Data sizes covered:
  - One entry, one week, three months, one year, five years and twenty years.
  - Awkward shapes: a long gap, a single outlier, all values equal, 0.1 kg over
    a year, 60 and 140 cycles with deloads, +250% over 60 cycles, a regime
    resumed after another one, nine sessions on one movement, a range with
    nothing in it, and a 3-digit weekly volume.
- Repro: `flutter test docs-scratch/chart_audit_test.dart --update-goldens --reporter expanded > docs-scratch/run.log 2>&1`

Caveats:

- The harness uses fixed generated data, and today is 15 Oct 2026, a Thursday.
- The live screens were not opened, because no emulator was used.
- The bodyweight card and the region and grid cards are replicas, so drift
  from the source is possible. The source was read to keep it minimal.

---

## Findings, ranked

Severity:

- **S1**: the chart looks broken or states something false. Fix first.
- **S2**: it breaks a THEME rule, or degrades badly at scale.
- **S3**: polish.

### S1: broken or misleading

1. **Cycle chart: the line runs out of the plot past +200%.**
   - **Chart and size:** `CycleAxisChart` in `StrengthCard`, on `All`, with 60
     cycles at +259%. The All time sparklines show the same at +280% and +341%.
   - **Shots:** `strength_c60big_All.png`, `alltime_7regimes_60c.png`
   - **What happens:** the latest point is drawn on top of the readout strip,
     and on All time the line climbs into the card header and the chevron.
   - **Cause:** `_cycleStep` tops out at a step of 50 and then returns 100. The
     band is always two steps, so it covers at most floor + 200.
   - **THEME:** The cycle axis, "the y band of data plus air".
   - **Fix:**
     - Extend the ladder beyond 100 (100, 200, 250, 500), or compute
       `ceil(range / 2)` snapped to 1, 2 or 5 × 10ⁿ.
     - Add a unit test that every point lies inside `[minY, maxY]` for gains up
       to +1000%.

2. **An empty bucket does not break the line.**
   - **Chart and size:** `TrendChart` for an exercise and for bodyweight, with
     a gap of eight to sixteen months, on All and on 1Y.
   - **Shots:** `exercise_gap_All.png`, `bodyweight_gap_All.png`,
     `bodyweight_gap_1Y.png`
   - **What happens:** a straight line is drawn across months with no data.
   - **Cause:**
     - Both callers drop `b.value == null` buckets and hand one contiguous spot
       list to `fl_chart`.
     - `exercise_trend.dart` even claims "a month you did not train this
       movement is a gap in the line", which is not what happens.
   - **THEME:** Charts, "A month with no weigh-in breaks the line". The trend
     rule "A solid line between two points claims the training between them"
     is also violated.
   - **Fix:**
     - Emit `FlSpot.nullSpot` for empty buckets between two non-empty ones.
       `fl_chart` breaks the line at a null spot.
     - Alternatively, split into one `LineChartBarData` per contiguous run.
     - Optionally join the runs with a 60% dashed segment, the cycle axis's
       jump style, so the two charts speak one dialect.

3. **The y labels repeat or misstate their gridline on a narrow band.**
   - **Chart and size:** bodyweight, with 0.1 kg over a year on 1Y, and a week
     of weigh-ins on 1W.
   - **Shots:** `bodyweight_tiny_1Y.png` prints `80.1 80.1 80.1 80 80`.
     `bodyweight_week_1W.png` prints `82.3` and `81.8` on gridlines at 82.25
     and 81.75.
   - **Cause:** `_niceStep` happily returns 0.025 or 0.25, then `formatValue`
     rounds to one decimal.
   - **THEME:** Charts, "snapped to a round step… every gridline lands on a
     number a person would say".
   - **Fix:**
     - Give `TrendChart` a `minStep`, the display precision: 0.1 kg for
       bodyweight, 0.5 kg or 1 lb for loads, 1 s for holds.
     - Also give it a `minSpan`, e.g. 2 kg for bodyweight and 5% of the value
       for e1RM, so that 0.1 kg of noise is not drawn as a full-height slope.
       That second point is also an S2 on its own: the tiny case reads as a
       steep climb.

4. **A single value draws an axis with one gridline and one label.**
   - **Chart and size:** `TrendChart` with one entry on any range, all values
     equal, or bodyweight flat. The cycle chart's flat case is fine.
   - **Shots:** `exercise_one_1W.png`, `exercise_flat_1Y.png`,
     `bodyweight_flat_1Y.png`
   - **What happens:**
     - `lowest == highest` gives `_niceStep(0) = 1`, a band of 1 and a single
       interior gridline.
     - The one dot floats between gridlines without a label of its own value.
     - It reads as a chart that half drew.
   - **THEME:** Charts, "4 drawn and 4 left out on every chart", and "One
     session is a chart with one dot on it".
   - **Fix:** when `highest - lowest < minSpan`, centre a `minSpan` band on the
     value, so there are always three or four gridlines and the dot sits on
     the middle one.

5. **The date labels collide on the line charts.**
   - **Chart and size:**
     - `TrendChart` on 1M (`d MMM`): touching at card width at 1.0, overlapping
       at 1.3.
     - On All for 1 to 8 years (`MMM ''yy`): colliding even at 1.0 on the page.
     - On All for 8+ years (`yyyy`): colliding at 1.3.
   - **Shots:** `exercise_week_1M.png`, `exercise_5y_All.png`,
     `exercise_gap_All.png`, `bodyweight_5y_All.png`, `bodyweight_stale_1M.png`,
     `exercise_20y_All.png`, `bodyweight_20y_All.png`
   - **Cause:** the count is fixed at seven and the format is chosen by span
     only, never measured. The cycle axis already measures its labels; the
     time axis does not.
   - **THEME:** Charts, "Seven date labels… room to print". Cycle axis, "How
     many numbers fit is a measurement, not a count".
   - **Fix:**
     - Measure the widest formatted label with `axisGutter`'s `TextPainter` and
       text scaler, as the cycle axis does.
     - If seven do not fit, step down the format ladder: `d MMM` to `d`
       plus a month on change, and `MMM ''yy` to `yyyy`.
     - Only then thin to four labels, still anchored on today.
     - See item 7 for snapping ticks to calendar boundaries, which shortens the
       labels as well.

6. **Bar list: the count column overflows at 3 digits and 1.3.**
   - **Chart and size:** `VolumeBars` with 95 to 410 sets or 140 sets.
   - **Shots:** `volumebars_big.png`, `volumebars_outlier.png`. Logged as
     "RenderFlex overflowed by 8.3 pixels".
   - **Cause:** `_Count` has a fixed `width: 64`.
   - **Fix:** measure the widest count at the current text scale, or use
     `IntrinsicWidth` once per list. Also see the S2 on `_nameWidth`.

7. **Volume chart: the y axis piles up to eleven labels.**
   - **Chart and size:** `VolumeChart` with one outlier week at 120 sets, and
     a peak of 60 at 1.3.
   - **Shots:** `volregion_outlier.png` (`110 100 90 … 10` stacked and
     overlapping), `volregion_peak60.png`
   - **Cause:** `_Axis.of` uses a step of 2, 5 or 10 and never more, so a peak
     of 120 gives eleven ticks in 150 px.
   - **THEME:** Charts, "4 drawn and 4 left out", and a bar axis "snapped to a
     round step — 2s, 5s, 10s".
   - **Fix:**
     - Choose the step from {2, 5, 10, 20, 25, 50, 100} so there are three or
       four ticks.
     - Share `_niceStep` with `TrendChart` rather than keep a second ladder.

### S2: breaks a THEME rule or degrades at scale

8. **Bar charts: the last date label is not today, and labels name bucket
   starts.**
   - **Chart and size:** `VolumeChart` at 13 weeks, 52 weeks, 5 years and 20
     years.
   - **What happens:**
     - At 13 weeks the last label is `12 Oct`, the Monday.
     - At 52 weeks it ends on `Sep`.
     - At 20 years it ends on `2025`.
     - At 5 years it mixes `Oct '21` with `Jan '22`.
   - **Shots:** `volregion_w13.png`, `volregion_w52.png`, `volregion_y20.png`,
     `volregion_y5.png`
   - **Cause:** `_Months` picks seven evenly spread bar indices at
     `(k + 0.5) / count` and prints each bar's `start`. This is not
     `TimeAxis`.
   - **THEME:** Charts, "Seven date labels, and the last one is today… the
     ladder is anchored on the right", and "Bars and lines share… the label
     ladder".
   - **Fix:** drive the bar chart's labels from `TimeAxis.of(window)` mapped
     onto bar slots, so both kinds of chart share one ladder. That is the
     THEME promise and today it is two implementations.

9. **The 3M range labels repeat months.**
   - **Chart and size:** every `TrendChart` on 3M.
   - **What happens:** `Jul Aug Aug Aug Sep Sep Oct`.
   - **Shots:** `exercise_3m_3M.png`, `exercise_nine_3M.png`,
     `bodyweight_3m_3M.png`
   - **Cause:** a span of about 105 days falls in the `MMM` band (≤ 400 days),
     and ticks are 15 days apart.
   - **THEME:** Charts, "Four ticks a day apart all render as the same month and
     read as mush".
   - **Fix:** use `d MMM` up to about 120 days. That collides, as item 5 shows,
     so it depends on the measured ladder. Alternatively snap ticks to month
     starts and label `MMM` only where the month changes.

10. **Uneven year spacing on long All ranges.**
    - **Chart and size:** 20 years on All.
    - **What happens:** `2006 2010 2013 2016 2020 2023 2026`, with gaps of 4, 3,
      3, 4, 3 and 3 years. The 5 year range labels arbitrary months (`Aug '22`,
      `Jun '23`).
    - **Shots:** `exercise_20y_All.png`, `exercise_5y_All.png`
    - **Fix:** past about 2 years, snap ticks to 1 January and step 1, 2, 5 or
      10 years backwards from the current year. Today stays the last label;
      this is the same ladder idea as the cycle axis.

11. **The cycle axis draws one gridline, not three.**
    - **Chart and size:** every `CycleAxisChart`.
    - **What happens:** there are labels at `0%`, `+1%` and `+2%`, but only the
      middle one has a dashed line. `TrendChart` likewise draws no line at its
      bounds, so the top and bottom 15–25% of every trend plot is blank air.
    - **Shots:** `strength_none_Last12.png`, `strength_c12_Last12.png`,
      `exercise_6M` (air)
    - **THEME:** The cycle axis, "Three gridlines, all of them labelled".
    - **Fix:**
      - Pass `checkToShowHorizontalLine: (_) => true`, or draw the bound lines
        via `extraLinesData`.
      - For the trend chart, cut the air to half a step on each side, so the
        band is no longer up to 1.5 steps over the data (131 was drawn in a
        60–160 band).

12. **A resumed regime's jump is drawn solid.**
    - **Chart and size:** a cycle chart with cycles 1, 2, 3 and then 9 to 13.
    - **Shot:** `strength_resumed_Last12.png`
    - **Cause:** `soft:` is true only when positions differ by more than 1, but
      positions close the gap by design.
    - **THEME:** The cycle axis, "A jump in the line is dashed at 60% — across a
      deload, or across a spell on another regime".
    - **Fix:** dash when the cycle `index` values differ by more than 1, not
      only when the positions do.

13. **Deload hairlines turn long charts orange.**
    - **Chart and size:** `CycleAxisChart` on `All` with 60 or more cycles, and
      every All time sparkline.
    - **Shots:** `strength_c60_All.png`, `strength_c99_All.png` (35 lines),
      `alltime_7regimes_60c.png`
    - **What happens:** at 45% alpha and 1.5 px the lines dominate, and on a
      140-cycle chart they are a striped fill. THEME introduced hairlines to
      avoid exactly "an orange chart".
    - **Fix:**
      - Drop the alpha to about 20%, or draw a short tick under the axis
        rather than a full-height line.
      - On sparklines (`small`), drop deloads entirely, since a sparkline is
        read as a shape.

14. **Sparklines keep chart furniture.**
    - **Chart and size:** the `small` `CycleAxisChart` on All time.
    - **Shot:** `alltime_1regimes_4c.png`
    - **What happens:** it still draws a dashed gridline and a full-height
      deload block, which reads as a solid square at four cycles.
    - **THEME:** Charts, "Sparklines drop the axes entirely".
    - **Fix:** when `small`, use `gridData: show false` and no range
      annotations, or a much fainter band.

15. **Trend markers clump, or vanish too early.**
    - **Chart and size:**
      - `TrendChart` with 3 months of data on 1Y: 26 markers squeezed into the
        right quarter, overlapping.
      - Two series of 26 on 6M: markers dropped at 52 total points although
        each line has ~12 px between points.
    - **Shots:** `exercise_3m_1Y.png`, `exercise_1y_6M.png`
    - **Cause:** `dense = all.length > 40` counts points across all series, not
      pixel spacing.
    - **THEME:** Charts, "Markers only while they mark something. Past ~40
      points the circles touch".
    - **Fix:** decide per series on the minimum x distance in pixels: show
      markers when the gap between neighbours is at least 10 px.

16. **Bodyweight refuses to draw one dot, and captions an empty range.**
    - **Chart and size:** bodyweight with one weigh-in, and with nothing in
      1M.
    - **Shots:** `bodyweight_one_1W.png` ("Only one day has a weigh-in…"),
      `bodyweight_stale_1M.png` ("Nothing logged in this range.")
    - **THEME:** Charts:
      - "One session is a chart with one dot on it".
      - "A range you did not train in needs no caption; the empty graph is the
        sentence".
      - "The value axis keeps the scale of the whole history". Bodyweight uses
        the latest value ±5 instead.
    - **Fix:** use the `exercise_trend.dart` behaviour for bodyweight: draw a
      `TrendChart` for one or more marks, no caption for an empty range, and
      `scale` from the whole log.

17. **Volume chart: one week is a slab, and a gutter that collapses.**
    - **Chart and size:**
      - `VolumeChart` with 1 week: one bar the full plot width.
      - `VolumeTile` with 1 week: six solid colour blocks.
      - With 1 set in 52 weeks the y gutter vanishes and the plot widens.
    - **Shots:** `volregion_w1.png`, `voltiles_w1.png`, `volregion_sparse.png`
    - **Fix:**
      - Cap the bar width (e.g. 24 px) and keep right-anchored slots.
      - Make `_Axis.of` return at least `0 / 2` ticks for a peak of 1 or less,
        so the gutter holds its width. THEME: "The frame never resizes".

18. **Volume tiles at 52 weeks merge into texture.**
    - **Chart and size:** `VolumeTile` at 1Y. The tile plot is about 140 px for
      52 bars, a slot of about 2.7 px, so the gap is 0 and the bars meet.
    - **Shot:** `voltiles_w52.png`
    - **THEME:** Charts, "the chart becomes a grey band with hairlines on it".
    - **Fix:** fold tiles by width, not by span: pick the finest level whose
      slot is at least 4 px. That would be monthly in a tile at 1Y, with the
      region chart staying weekly.

19. **The 5-year cliff to yearly bars.**
    - **Chart and size:** volume at 261 weeks.
    - **What happens:** `autoGranularityFor` computes 1827 / 30.44 = 60.02 > 60,
      so 5 years folds to 6 yearly bars (the first a partial `Oct '21`)
      instead of 60 monthly bars.
    - **Shots:** `volregion_y5.png`, `voltiles_y5.png`
    - **Fix:** compare against the ceiling with a tolerance of about 10%, or
      count calendar months rather than days / 30.44.

20. **The exercise "Change" mixes sessions and paints a drop red.**
    - **Chart and size:** `_Summary` under the exercise trend.
    - **Shots:** `exercise_week_1W.png` prints `−2.2%` in red. It compares the
      first Push 1 performance with the last Push 2 performance.
    - **What happens:** `real.first` and `real.last` ignore `sessionName`.
    - **THEME and RULES:**
      - CLAUDE rule 1: progressions are per session.
      - Strength card and Lift row: "dropping is not a fault the app is
        entitled to paint red".
      - `+0.0%` is shown in green on a flat history (`exercise_flat_1Y.png`),
        against Lift row's "`0 kg`, never … `+0.0%`".
      - `98 Sessions since best` is shown when every session equals the best.
    - **Fix:**
      - Compute the change per session and show the most recent session's
        change, or the mean.
      - Use `text` for a negative change and print `0%` with no sign.
      - Treat ties with the best as "at best".

21. **Units dropped or truncated.**
    - **What happens:**
      - Bodyweight prints `−3.2 over the range` with no `kg`.
      - `VolumeTile` ellipsizes `sets/wk` to `sets/...` at 1.3.
      - Bar list names ellipsize (`Should…`, `Hamstr…`) at 1.3.
    - **Shots:** `bodyweight_1y_1Y.png`, `voltiles_w52.png`,
      `volumebars_typical.png`
    - **THEME:** rule 5, "Every value carries its unit".
    - **Fix:**
      - Format the delta as `−3.2 kg`.
      - Let the tile unit wrap under the figure, or drop `/wk` in favour of the
        caption.
      - Size `_nameWidth` from the longest region label at the current scale.

22. **The year heatmap shrinks month labels below 11 sp and ignores text
    scale.**
    - **Chart and size:** `YearHeatmap` at any year.
    - **Shots:** `year_2026_typical.png`. The labels are identical at 1.0 and
      1.3, and `Apr May` and `Jul Aug` nearly touch.
    - **Cause:**
      - `_months` scales the font down to 0.62 × 11 sp, about 6.8 sp.
      - The `TextPainter`s have no `textScaler`.
    - **THEME:** Type, "Minimum 11sp".
    - **Fix:**
      - Pass `MediaQuery.textScalerOf(context)`.
      - Never scale below 11 sp. When labels do not fit, print every other
        month, or initials as the timeline strip does.

23. **The y range is set by a single outlier.**
    - **Chart and size:** `TrendChart` with one typo entry (260 kg among 100s,
      or 182 kg bodyweight).
    - **Shots:** `exercise_outlier_1Y.png`, `bodyweight_outlier_1Y.png`.
      `strength_spike_Last12.png` shows the cycle-axis equivalent.
    - **What happens:** the year is drawn as a flat line along the floor with
      one spike. This is honest, but it is the "looks broken" case the release
      wants to fix.
    - **Fix (a design decision; propose, do not assume):**
      - Leave the data alone, and let the 1.19 averaging and markers make the
        spike tappable so it can be found and corrected.
      - Or clip the y band to the 2nd–98th percentile and draw an off-scale
        caret at the edge.
      - THEME currently says nothing either way, so whichever is chosen belongs
        in THEME → Charts first.

24. **The cycle band is two steps, so up to half the height is empty.**
    - **Chart and size:** cycle axis spike (0 to 60 gives a 0–100 band), and
      c60 All (0 to 68 gives 0–100).
    - **Shots:** `strength_spike_Last12.png`, `strength_c60_All.png`
    - **Fix:** allow 3 steps when 2 would leave more than 40% empty, or add 15,
      30 and 40 to the ladder. This touches the THEME line "steps of 1, 2, 4,
      5, 10, 20, 25 or 50", so it is a doc change too.

### S3: polish

25. **Too many orange labels on the cycle axis.** On `Last 24` and `All`, a
    ladder of 2 or 4 lands on every deload (cycles 4, 8, 12…), so half the axis
    numbers are orange (`strength_c24_All.png`, `strength_c60_Last24.png`). A
    possible fix is to colour a deload number only when the ladder is 1.
26. **The cycle readout wraps at 1.3 and the top y label touches it.** In
    `strength_c2_Last12.png` and `strength_c12_Last12.png`, `+20%` sits directly
    under the readout strip, about 2 px away. The space is `Space.sm` plus a
    reserved top of 10, but the label's own half-height eats it. Use `Space.md`,
    or reserve the label's measured half-height.
27. **The open cycle loses its open style when selected.** A selected open
    cycle is drawn filled `progress`, so the `textTertiary` "unfinished" stroke
    disappears (`strength_c2_Last12.png`).
28. **Two identical series hide each other.** Push 1 and Push 2 at the same
    value draw as one line (`exercise_flat_1Y.png`, `exercise_hold_1Y.png`).
    This is acceptable, but the legend then names a line nobody can see.
29. **The year chip shows a year that is not in force.** When a rolling range
    is selected, the chip reads `2026`, or `2025` on a stale log, which can be
    read as the year being applied (`exercise_stale_1M.png`).
30. **"Last 261 weeks" and "Last 1044 weeks".** Volume captions count weeks at
    any span. Past about a year, name years.
31. **The legend grows by up to 3 rows with session count** (`exercise_nine_3M.png`),
    so the header height changes when the range changes which sessions are
    present. A fixed two-row legend with "and N more" would stop the page
    moving.
32. **The empty trend chart and the drawn chart use different gridline
    densities.** The empty chart shows 5 labels and the drawn chart 3 to 4
    (`exercise_stale_1M.png` against `exercise_1y_1Y.png`). Unify them through
    the same band function.
33. **Volume chart y labels have no visible gridlines.** The ticks are drawn
    behind full-height `heatEmpty` tracks, so `5 10 15` float with nothing to
    read against. THEME allows dropping the lines over `heatEmpty`, but then
    the labels need a top value to anchor them, and today the maximum is never
    printed.

---

## Spacing and padding inconsistencies across chart cards

| Card | Card padding | Chart height | Range control | Gap control → chart | Gap chart → next |
| --- | --- | --- | --- | --- | --- |
| Exercise trend (on page, no card) | page gutter 16 | 220 | above, `TrendRangeBar` | 16 | 16 (to stat tiles) |
| Bodyweight `_TrendCard` | 16 | 190 (loading placeholder 260) | **below** the chart | 16 (chart → range) | — |
| Strength card | 16 | 150 | above, `SegmentedPill`, then readout | 12 / 8 (readout → chart) | 8 (to legend) |
| All time regime card | 16 | 64 sparkline | none | 12 | 12 + divider + 12 |
| Region volume card | 16 | 150 + 16 label row | outside the card, padded `lg,md` | 16 (figure → chart) | 8 (bars → labels) |
| Volume tile | 16 | 44 | none (screen-level) | 16 | 16 + divider + 12 |
| Weekly volume (bar list) | **12** | n/a | none | n/a | row padding 8 |
| Consistency heatmap card | 16 | grid | none | 16 | 16 + divider + 12 |
| Year heatmap card | **12, 12, 12, 8** | grid | year stepper elsewhere | n/a | n/a |

Specific inconsistencies:

1. **The range control is above the chart everywhere except bodyweight.** THEME
   says every chart is driven by the same row. Move it above the chart on
   bodyweight. The loading placeholder (260) does not match the loaded card's
   height either.
2. **Three line-chart heights: 220, 190 and 150.** Pick two at most: a full chart
   and a card chart. A sparkline is the third.
3. **Gaps to the chart: 16 for trends, 8 for the cycle chart under its readout,
   and 16 for volume.** The cycle chart's top label then touches the readout
   (finding 26).
4. **Card padding: 16 nearly everywhere, but 12 on the weekly-volume bar list
   and 12/12/12/8 on the year heatmap.** The year heatmap's is documented in
   code. The bar list's 12 plus 8 of row padding gives a different left inset
   from the heatmap card directly above it on Workouts.
5. **Legends: four implementations.**
   - `TrendChart` uses 8 px circles and `bodySmall`, with a gap of 16.
   - The strength card uses 10 px squares and `labelSmall`, with a gap of 12.
   - All time uses 10 px squares and `labelSmall` in groups.
   - `HeatmapLegend` uses 10 px squares and `labelSmall`, with a gap of 16.

   One `ChartLegend` widget would end this.
6. **Hint and caption under the plot.** The trend chart puts `Pinch to zoom…`
   8 below in `textTertiary`. The bodyweight empty message sits at the same
   place, but bodyweight's range bar then follows 16 below. The strength
   legend is 8 below.
7. **X-label strip: `fl_chart` reserves 30 for the trend and cycle charts, while
   `VolumeChart` uses a fixed 16 px row placed 8 below.** At 1.3 the volume
   labels overflow their 16 px row, and the strip is not measured.
8. **Y gutter gap.** `TrendChart` and the cycle chart put `Space.xs` inside the
   reserved size. `VolumeChart` adds `Space.xs` outside and measures with
   `gap: 0`. These are equivalent today, but both are worth folding into one
   `axisGutter` call. `VolumeChart` also measures its gutter against the
   chosen `by`'s axis and draws the `safe` one, so the two can disagree.
9. **`StatTile` rows have no gap between tiles.** At 1.3 in a card, labels run
   into each other (`Best est. 1RMChange` in the card rendering; on the page
   they are just apart). Add `Space.md` between `Expanded` tiles.

---

## Suggested order for the overhaul

1. Make the y band one shared function, used by every chart:
   - Data plus air, half a step each side.
   - A `minStep` from the display precision and a `minSpan` for a degenerate
     band.
   - A step ladder that grows without a cap.
   - Bound gridlines drawn.

   This fixes items 1, 3, 4, 7, 11 and 24, and needs a pure test in
   `lib/domain/`.
2. Make the time axis one shared, measured ladder:
   - Right-anchored and calendar-snapped (month or year starts).
   - The format stepped down when the labels do not fit at the current text
     scale.
   - Used by `TrendChart`, `EmptyTrendChart` and `VolumeChart`.

   This fixes items 5, 8, 9 and 10.
3. Break lines at empty buckets (item 2), and dash regime jumps on the cycle
   axis (item 12).
4. Make density decisions by pixels rather than counts: markers (15), tile
   folding (18), bar width cap (17) and the 5-year cliff (19).
5. Deload treatment on long cycle charts and sparklines (13, 14, 25).
6. Bodyweight parity with the exercise trend (16, 21, and the range bar
   position).
7. Text scale fixes: bar list widths (6, 21), the year heatmap labels (22) and
   the stat tile gap.
8. Decide the outlier policy in THEME first (23).
