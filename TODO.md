# Deltoid — status and what's next

Status only. Durable facts live in **[README.md](README.md)** (domain model,
invariants, traps) and **[THEME.md](THEME.md)** (the design language). If
something here is still true in six months, it is in the wrong file.

---

## In flight: the rebrand

Every screen rebuilt on [THEME.md](THEME.md). Ordered by how much a screen is
used and what shared pieces it forces into existence, so later steps cost less.
Each step ends analyzer-clean and green, in its own commit, and is looked at on
a device before the next starts.

- [x] **0 · Foundation** — tokens, the nine type roles, `primitives`, nav bar.
- [x] **1 · Today** — header band, flat hero, white primary action, backfill in
      one sheet, Finish / Discard for stale sessions.
- [x] **2 · Log** — log screen, set row, keypad, rail, sheets, rest timer, and
      the plate view (README → Non-goals for why it exists at all).
- [x] **3 · History + workout detail** _(driven on the device)_ — full-bleed
      feed rows, month headings, composed masthead, workout detail rebuilt.
      Session summary screen, notes at three levels, keep-today's-changes, and
      the sheet/link/subtitle rules now in THEME §5.
- [x] **4 · Progress folds into History, and the chart language gets built** —
      three commits, as planned.

      1. **Fold.** `progress_screen` is gone; `exercise_trend.dart` puts the
         chart at the head of an exercise's own history, where the list under it
         is that exercise's performances. The tab's exercise picker went with
         it — the `Exercises` index is that, done better.
      2. **Metric screen.** Metric strip pinned in the header band while the
         chart scrolls beneath, value-first rows (`92.5 kg × 5` over
         `Sat, 12 Jul · Push 1`), month grouping. Two metrics — est. 1RM and
         heaviest weight — because a 3-RM and a 10-RM are the same Epley curve
         with a different constant.
      3. **Rename.** `Workouts · Regime · History · Settings`. Settings is a
         destination with a masthead, and Today's cog is gone with it.

      **Driven, and the device found four things**, all fixed: the chart's Y
      bounds came from the data so the axis labelled `1197.5` and wrapped onto
      two lines, and X ticks were raw days so a year rendered `Jul Jun Jun Jul`
      — both snap to round steps and calendar units now, with edge labels
      dropped. Deload weeks are out of the chart entirely: an e1RM taken off
      80% of your working weight is a number about the programme, not about
      you. Markers vanish past ~40 points and the chart takes pinch-to-zoom,
      because `All` on a long history was unreadable at any zoom.

      **`All` is gone**, replaced by `1W · 1M · 3M · 1Y` and a year picker
      listing only years with something in them. A year at a time is legible
      and two of them are compared by switching; everything at once never was.

- [ ] **5 · Regime cluster** — built, and driven once. **Wants another pass on
      the device** now that the day reads as a list.

      The Regime tab is the programme editor: day tabs under a band that names
      the regime, the day's exercises under a count heading, and Rename and
      Re-order as chips. `session_editor.dart` is gone — a training day was a
      context you switch, not a screen you push into.

      An exercise is **one row** — name, muscle, target on the right — opening
      its own screen. It was a block with a muscle pill and a targets card
      under it, three stacked things and 130pt per exercise, and six of those
      is a wall rather than a day you can read. The slot screen carries the
      **General / Overrides** split. Overrides are that day's — targets, note,
      and the per-slot deload whose columns had existed since the first
      migration with no way to set them.
      `prefillForWorkout` read the regime's figures whatever the slot said, so
      an exercise added mid-session deloaded differently from the same exercise
      at the door; it reads the slot first now, as `startWorkout` does.

      Cycle controls left the page for a sheet behind one status line; the
      regime's own settings (name, deload, day order, catalog, other regimes)
      sit behind the sliders button. The catalog and the picker are the same
      thing built the same way now — search, muscle chips, full-bleed rows —
      and archiving moved into the exercise's sheet, off eighty rows.

      Creation is choice cards in a sheet, and naming is a sheet rather than a
      dialog. No wizard.

      Three deviations from THEME §7, all deliberate: **no `⋮` on an exercise
      row**, because everything it would hold is one tap away on the slot
      screen; **no targets card**, because the figure reads fine as the row's
      trailing value and the card existed only to be a second tap target; and
      **the target editor is not a set table**, because a slot holds one rep
      range and four identical rows would draw per-set targets this app cannot
      store.

      **Driven, and the device found two things.** The day tabs asked for an
      infinite width — a stretching column inside a horizontal scroll — and the
      Regime tab rendered as nothing at all behind one `BoxConstraints forces
      an infinite width` and a hundred `RenderBox was not laid out`. And the
      screen had no masthead until it had data, so a first launch opened on a
      bare empty state with nothing saying which tab you were in.
      `regime_screen_test.dart` now pumps all four states against a real
      database, because both were invisible to the analyzer and to every other
      test.
- [ ] **6 · Settings, bodyweight, all-time heatmap** — mostly deletion once the
      list primitives exist. Settings has its masthead already (step 4 made it
      a tab); what is left is bodyweight coming up out of it to one tap, and
      the list layouts.

      **The all-time heatmap is done**, out of order, because thirty years of
      seeded data made it unusable: it was eleven thousand widgets — a
      `Tooltip` per day inside a `ListView` that builds its children eagerly —
      and it scrolled like a slideshow. A year is one `CustomPaint` now, years
      build lazily, and tapping a day replaces 366 tooltips with one readout
      line.

      It also fits the width instead of scrolling sideways, since a year you
      drag through is not a year at a glance. The ramp went with it: one tone
      for a day you trained (a single session is a full day's work and used to
      render darkest), solid amber for a deload rather than an outline, and the
      month strip under the grid with the weekday column dropped.
- [ ] **7 · Reconciliation** — light theme on every screen (only checked at
      token level), empty states, motion, and THEME corrected where the build
      taught us something the audit didn't.

---

## Built

Analyzer-clean, and unit-tested wherever there is logic. **Device marks below
predate the rebrand** except step 3's — treat them as evidence about the design,
not the current build. What still wants real hardware: the rest tone, haptics,
the wakelock, audio ducking, and the share sheet.

- **Logging** — one exercise per page, typed sets, gym keypad, plate view, auto
  rest timer with a tone on the alarm stream, swap / skip / move / add
  mid-session, notes at three levels, force-stop recovery.
- **Session-scoped prefill** — ghost values, borrowing labelled on the ⓘ, ghost
  adopted on completion, beat-last-time highlight.
- **Session summary** — the screen a workout finishes on: volume, sets, time,
  the session note, a recap, and the offer to keep today's changes to the
  programme (`domain/session_diff.dart` → `applySessionChanges`).
- **Cycles + deload** (regime-wide, and per slot), **stale-session sweep**,
  **multiple regimes**, **programme editor**, **exercise catalog** (archive,
  never delete).
- **History** — paged session feed + per-exercise index. The Notion-style table
  was deleted in step 3.
- **Progress** — e1RM over time, one line per session slot, stall detection,
  deload weeks excluded. Rebuilt in step 4.
- **Consistency heatmap** — eighteen weeks on Today, all-time view behind it.
- **Backup** — export / restore / auto-export, round-trip tested.
- **Bodyweight log** — schema, repository, interpolation, its own screen. Never
  logged through the UI, because it is behind a settings cog.
- Light / dark / system theme, adaptive launcher icon.

**232 tests** — prefill and deload rules, cycle timing, metrics and volume,
session diff and template writes, backup round-trip, history paging, keypad,
the stale-session sweep, Today's single-frame arrival and above-the-fold
budget, and repository integration against real in-memory SQLite.

---

## Blocked / not started

- **Supabase sync** — needs the project URL + anon key. Every table already
  carries the sync columns, so it is additive: no migration.
- **iOS** — needs Xcode. Nothing iOS-specific is known broken, and nothing is
  verified.

---

## Wanted, not designed yet

Agreed but unspecified. Each carries the decision that blocks it. Check the
README's **Non-goals** first — these are here because they survived that check.

- **Records on the summary screen.** The end of a session never says what was
  *beaten*. `beatsPrevious` answers it live in the log, but the summary opens
  after `completeWorkout`, when the ghosts are gone, so it means re-resolving
  prefill on that screen. Cheap to fold into step 4.

- **All-time PRs.** *Decide first:* per exercise across all sessions, or per
  session-slot? Global is what "my best bench" means to a person; session-scoped
  is the thesis of this app. Step 4's chart may answer it and make the badge
  redundant.

- **Weekly sets per muscle.** Pure aggregation over a rolling seven days —
  `domain/`, no database. *Decide first:* working sets only (yes), direct muscle
  only (yes — there is no secondary column), deload weeks counted or not (follow
  `domain/consistency.dart`, which already chose once).

- **The hero becomes a two-page pager**, with the muscle bars as page two —
  THEME §5 → Muscle volume bars and The hero pager. Page one is always the
  action.

- **Muscle chip on every exercise**, making the catalog filterable by tapping
  what you can see. Lands with step 5's filter chips.

- **Isometric holds.** The only item here needing a **migration**: a set is
  `weight × reps` and a hold is `load × seconds`, which touches `SetLog`, the
  keypad, `effectiveLoad`, `estimated1RM` (a plank has no 1RM), prefill and the
  set row. *Decide first:* a new `SetType`, or a `MeasureMode` on the
  **exercise**? Exercise-level is almost certainly right — a plank is never
  sometimes reps.
