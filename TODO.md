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
- [ ] **4 · Progress folds into History, and the chart language gets built** —
      the one structural step. Three commits, in this order:

      1. **Fold.** `progress_screen` becomes the exercise's own view inside
         History; the Progress tab goes. "How has my bench moved" is a history
         question, and the `Exercises` index is already the picker the Progress
         tab opens with, done better. It deliberately does *not* fold into
         Today, which is the busiest screen in the app.
      2. **Chart language**, per THEME §5 → Charts and The metric screen: card
         contract, metric tab strip (pinned) over a scrolling chart, value-first
         rows, month-grouped list beneath.
      3. **Rename the tabs** to `Workouts · Regime · History · Settings`.
         "Today" backfills other days, so it was already lying. Settings takes
         the freed slot because **bodyweight lives in it** and is not a setting.

      Keep the metric tabs to **two** (1-RM, heaviest weight) unless a third
      earns itself — 10-RM is the same curve as 1-RM with a different constant.

- [ ] **5 · Regime cluster** — regime screen, session editor, catalog, setup.
      Day tabs, count-as-heading, targets card + editor sheet, catalog picker
      with search and filter chips. Creation stays in sheets: no wizard.
      The exercise's own screen gets the General / Overrides split (THEME §5).
- [ ] **6 · Settings, bodyweight, all-time heatmap** — mostly deletion once the
      list primitives exist. Settings is a tab by now, so it gets a masthead,
      and bodyweight comes up out of it to one tap.
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
- **Cycles + deload**, **stale-session sweep**, **multiple regimes**, **regime
  editor**, **exercise catalog** (archive, never delete).
- **History** — paged session feed + per-exercise index. The Notion-style table
  was deleted in step 3.
- **Progress** — e1RM over time, one line per session slot, stall detection,
  deload weeks excluded. Rebuilt in step 4.
- **Consistency heatmap** — eighteen weeks on Today, all-time view behind it.
- **Backup** — export / restore / auto-export, round-trip tested.
- **Bodyweight log** — schema, repository, interpolation, its own screen. Never
  logged through the UI, because it is behind a settings cog.
- Light / dark / system theme, adaptive launcher icon.

**220 tests** — prefill and deload rules, cycle timing, metrics and volume,
session diff and template writes, backup round-trip, history paging, keypad,
the stale-session sweep, Today's single-frame arrival and above-the-fold
budget, and repository integration against real in-memory SQLite.

---

## Blocked / not started

- **Supabase sync** — needs the project URL + anon key. Every table already
  carries the sync columns, so it is additive: no migration.
- **iOS** — needs Xcode. Nothing iOS-specific is known broken, and nothing is
  verified.
- **Per-exercise deload overrides** — columns exist
  (`session_exercises.deload_set_delta` / `deload_weight_pct`), no UI.

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
