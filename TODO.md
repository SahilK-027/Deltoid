# Deltoid — status and what's next

Transient state lives here. The other two documents don't move:

- **[README.md](README.md)** — the domain model, the invariants, the traps.
  Things that stay true release to release.
- **[THEME.md](THEME.md)** — the design language. What a card, a row, a sheet
  or a chart looks like, and why.
- **This file** — what is built, what isn't, and the order of the work in
  flight. Expected to be edited constantly and to be wrong the moment it isn't.

---

## In flight: the rebrand

Rebuilding every screen on the language in [THEME.md](THEME.md). Not a reskin —
the greys, type scale, component vocabulary and copy all change, and the layout
changes where the audit said it should.

Order is driven by which screens get used most and which shared pieces each one
forces into existence, so later steps cost less than earlier ones. Each step
ends analyzer-clean with tests green, in its own commit, and gets looked at on
a device before the next starts.

- [x] **0 · Foundation** — `tokens` (neutral ramp, white accent, identity and
      effort palettes), `theme` (nine type roles, capped 11–30sp), `primitives`
      (header band, list card + row, buttons, chips, segmented pill, sheets,
      bottom-anchored confirm), monochrome nav bar.
- [x] **1 · Today** — header band, flat hero with the regime's identity mark,
      white primary action. Cycle list dropped, backfill collapsed to one titled
      sheet, stale sessions given Finish / Discard.
- [x] **2 · Log** — `log_screen`, `set_row`, `keypad`, `exercise_rail`,
      `exercise_sheets`, `rest_timer`. Monogram tile (we have no exercise
      photos), value fields with the focused-outline state, `W`/`D` index chips,
      swipe-to-delete, keypad, plate view.

      **Plate view.** `BarKind` per exercise — Olympic 20 / women's 16 / EZ 9 /
      trap 25 / none, weighed in this gym rather than looked up (schema v4).
      `domain/plates.dart` holds the maths; the diagram and its one sentence
      grow in above the keypad's digits while a barbell weight is being typed,
      in competition plate colours from 25 down to 2.5.

      Three things it deliberately does not do: it never appears for a
      `perSide` or bodyweight-plus load, it never rounds — a weight the rack
      cannot make says how much it is short by instead of drawing a bar that
      lies — and it does nothing in pounds, because the plate set is metric and
      a pound breakdown off kilo plates is a diagram no gym can load.

      The keypad lost its title and its readout with it: both captioned what
      the screen behind them already said. Entry is capped by value (1000 for a
      load, 999 reps), not by digit count.
- [x] **3 · History + workout detail** — header band + segmented pill for the
      three views, month headings in `section` on the page background, and the
      feed rebuilt as full-bleed rows: identity tile in the regime's colour
      (amber on a deload), session name, a meta line, and the movements as one
      ellipsized line. Cards are gone from both screens.

      The exercise *count* went with them — the names are the same fact and the
      useful one, so `WorkoutSummary` now carries `regimeName` and
      `exerciseNames` instead of the feed inventing a count to print. Keyset
      paging and `HistoryCursor` untouched.

      Workout detail lost its date card to the header band (weekday + date as
      the eyebrow, session name as the title, facts as one line under it); the
      note is a row, the popup menu is a sheet, and exercises are full-bleed
      rows that expand into set lines — index chip, `60 kg × 8`, inset
      dividers — with the per-exercise history as a text link inside the
      expansion rather than the whole block being a link somewhere else.

      The Table view is gone (see **Built** → History). Two views left, so the
      segmented pill carries two segments.

      The masthead is composed across the band's width, not stacked flush
      left: `HISTORY` on the left, the session total on the right in `value`
      over a `micro` caption, and the segmented pill spanning both underneath
      (`SegmentedPill.expand`). Backed by one aggregate, `historyOverview`.

      The total is **sessions**, not sets: after years of training a set count
      runs to five digits and the header becomes a wall, while the session
      count stays three and is what the page is a list of. Month headings carry
      their own count on the right, of the rows loaded under them.

      What the masthead deliberately does *not* say: `SINCE JULY 2026` on a
      history one day old — the eyebrow appears only once the log crosses a
      calendar month, the same honesty rule as the sessions-per-week rate — and
      not how long since you trained, which is Today's question. The
      end-of-list footer dropped its count and now hides entirely on a list
      that never filled a page.

      Row meta lost `0 min`, a clock that never ran, and the programme name,
      which the tile already carries as colour and which ellipsized the line on
      a phone. `WorkoutSummary.regimeName` went with it.

      The session drawer behind the overflow was double-inset: `ListCard` rows
      inside `AppSheet`'s gutter, so every action stood in from the title above
      it, and a card inside a sheet is a panel inside a panel. Rows are
      full-bleed now (`AppSheet.contentPadding`), each with a subtitle saying
      what it does, and `SheetHeader` gained the 4pt over the ✕ that the drag
      handle was sitting on.

      The log's three sheets — exercise menu, set actions, skip reason — were
      still hand-built out of `ListTile` on their own insets, so the same action
      list sat at different spacing depending on which screen opened it. All
      three are `AppSheet` + `AppRow` now, which is what makes the log and
      workout detail agree — and the rules between rows went with the rebuild:
      a hairline under every row turned five choices into five boxes, on a
      surface that already has one under its header. `OutlinedButton` on the move pair
      became `SecondaryButton`, and the set-type chips became picker rows with
      a radio — the sheet was the only place in the app where choosing meant
      hitting a pill rather than a row, and a chip has no room to say what a
      warm-up does to progression.

      **The log header got an ⓘ and lost a caption.** "First time — no
      previous log" was a line announcing an absence, on the screen with the
      least room for one; the attribution line it shares a slot with stays
      exactly as it was when there *is* something to attribute — `From Push 2 ·
      12 Jul` is untouched, and still the one rule this app exists for. The ⓘ
      beside the ⋯ opens `showExerciseInfo`: where today's numbers came from in
      a sentence, muscle and equipment, what the load field means, the bar and
      its empty weight, today's note, form videos. The ⋯ menu is actions only
      now — the cue and the videos moved out of it, since a menu that opens
      with two paragraphs before its first button is a page.

      **The caption moved inside the ⓘ, and left a dot behind.** `Last time ·
      12 Jul` was the info sheet's `Last logged` row printed a second time, in
      the header, on the screen with the least room for one — rule 6. It is
      gone. What is *not* gone is the warning it carried: when prefill borrows
      from another session the ⓘ wears an amber dot, and the sheet's first row
      is `Borrowed from Push 2` — amber, wearing the same dot, so the badge has
      a visible cause the moment you open it — subtitled `First time here — 3
      Aug's numbers, until you log your own`. That is one row saying one thing;
      it started as a row plus a three-line paragraph on its own insets. Three
      states, one control: no dot (this session's own numbers), dot (borrowed),
      and the sheet for the detail.

      **Today's improvisation can be kept.** `domain/session_diff.dart` diffs
      what was trained against the session template — added, removed,
      reordered — and the summary screen offers each change as its own
      checkbox: keep the leg raises you added, throw away the order you ran them
      in. The section says what it is before it asks anything — "You changed
      Push 1 today / These changes apply to today either way. Tick anything Push
      1 should do every time from now on." — each row states its own outcome
      (`Today only` until it is ticked, then `In Push 1 from now on`), and the
      button is live with nothing ticked, where it reads *Keep Push 1 as it is*.
      A dead button gave no way to say the thing most people mean and left the
      section looking unanswered. Nothing is ticked by default, and `applySessionChanges` writes
      `session_exercises` and only that, so past workouts are untouched
      (invariant 2, with a test standing on it). Re-adding a movement revives
      its tombstoned slot rather than making a second one, so its set target and
      rep range come back with it. Appending an exercise deliberately does not
      also report a reorder — one decision, one question.

      Both note surfaces were wrong on the first pass and are fixed: the sheet's
      field sat on `surfaceSunken`, the keypad's bed, which on a `surface` sheet
      reads as a hole rather than as somewhere to type — it is `surfaceHigh`
      now, going to a white 2px outline on focus like every other field. The
      note *displayed* on workout detail was a sunken quote block with a rule
      down its left, in caption grey: the one piece of writing on the page, in
      the darkest box on it, at the lowest contrast. It is an `AppCard` of
      `body` text in `textPrimary` now, with a pencil on the right.

      **Notes are capped** — 500 characters, 200 for a set note, with the
      counter reading `120 / 500`. Nothing truncates an existing note: the cap
      is on typing, so anything already stored stays whole.

      **Notes are sheets, not pop-ups.** `promptForNote` in `primitives`
      replaces the `AlertDialog` every note used to open — session note,
      per-exercise note, per-set note, from the log, the summary and workout
      detail. Sunken field, autofocus, one white Save, and it rides above the
      keyboard instead of fighting it. `promptForText` stays for *names*, which
      are one line and belong in a dialog.

      **Workout detail's expansion has a hierarchy.** Three unrelated things
      used to sit there as three identical links. Now: the sets are a table, the
      note is a card of prose in the primary colour — `_NoteBlock` — and
      only the one thing that navigates (`All Back Squat history`) looks like a
      link. The day's own note uses the same block under a `Session note`
      heading, so the page has one way of showing a note instead of two.

      **The summary screen stopped impersonating workout detail**, over three
      passes. Same facts, opposite posture: the band is composed *centre* — ✕
      that leaves, `Session complete`, the session's name under it — where
      detail is left-flush with a back arrow and an overflow. The note is a
      field you write in, where detail quotes it back. The exercises are one
      card of rows that never open, where detail's are full-bleed and expand
      into every set.

      It briefly had no band at all and a `surfaceSunken` well under the note,
      which made it the one page in the app darker than the page — reverted. The
      three numbers were briefly stat tiles too; they are labelled rows now
      (`Volume · 4 250 kg`, `Sets logged · 18`, `Duration · 47 min`), because
      tiles are for a dashboard you scan and this is a short list of facts read
      once, where a row carries a unit and an em-dash without its caption
      wrapping. One way out, pinned.

      **Bodyweight sessions reported `0 kg` moved.** The summary computed volume
      by hand off `weight`, which is null on every bodyweight set, so a day of
      chins and dips totalled nothing. `sessionVolume` in `domain/metrics.dart`
      now does it through `effectiveLoad` with the interpolated bodyweight —
      dumbbells count double, BW+ adds the belt, warm-ups count (this is work
      done, not a progression score). Five tests, no database. With no
      bodyweight ever logged the total is genuinely unknown, so the tile prints
      a dash rather than a number that dropped half the session.

      **Sheet subtitles identify or they go.** They had become a scope caption
      — "This workout only" under a title that was already an exercise name —
      which is rule 6 duplication and made the header two lines tall for
      nothing. What is left names *which* thing: the date under a session name,
      the exercise under `Set 2`. Three sheets lost theirs outright.

      **Links lost their underline.** `LinkAction` is text plus a chevron now.
      Some links were underlined and some weren't, depending on whether the
      screen used the widget or wrote its own `Text`, and a rule under a word
      is the one decoration that has to be perfectly consistent to read as
      anything but a mistake. Tab and segment underlines are unaffected — those
      are indicators, not links.

      **Driven on the device**, which is what the tick is for: the feed and
      workout detail, both drawers, the note sheet against the keyboard, the
      summary screen, and the ⓘ with its dot. Everything above went through
      several passes on real hardware before this step closed.
- [ ] **4 · Progress folds into History, and the chart language gets built** —
      the one structural step in the rebrand. Everything else so far has been
      one screen at a time; this moves a feature out of its own tab and changes
      what the nav bar is a list of.

      **Progress stops being a tab.** "How has my bench moved" is a *history*
      question, and History's per-exercise index already asks half of it —
      tapping an exercise there should open its chart, rather than sending you
      to a fourth tab to ask the same thing with a different picker. One screen,
      one job. `progress_screen` becomes the exercise's own view inside History;
      the tab goes.

      It deliberately does **not** fold into Today. Today is the busiest screen
      in the app and the one that breaks rule 6 most, and it already has weekly
      sets per muscle queued for it. A chart on top of the hero, the cycle, the
      heatmap and the rate makes it a dashboard, which is the thing §1 exists to
      stop.

      **The chart never enters the infinite list.** History's masthead and pill
      sit outside the scroll view and the keyset-paged feed under `Sessions` is
      untouched. The `Exercises` segment is the catalog — forty rows, finite,
      searchable — and tapping one pushes `ExerciseHistoryScreen`, which is
      where the chart goes: at the head of that exercise's own performances,
      newest first. Finite list, short by construction.

      The chart **scrolls away** with those performances rather than pinning.
      It is a summary, not a control, and pinned it costs half a phone screen
      while you are reading the sets under it. The range pill travels with it.

      Two things the move improves rather than merely relocates: Progress's
      "one line per session slot" is self-evident on a per-exercise screen —
      bench in Push 1 and bench in Push 2 as two lines is the app's thesis
      *drawn* instead of explained — and the exercise picker the Progress tab
      opens with is deleted, because the `Exercises` index is that picker done
      properly.

      **The chart language, built once**: dashed gridlines, right-hand Y labels,
      range pill, legend chips, em-dash empty state instead of a gridded void.
      Two screens consume it now rather than three, which is the point of doing
      the move first.

      **Then the nav bar becomes Workouts · Regime · History · Settings.**

      - `Today` → **Workouts**. The name was already wrong: the screen backfills
        a session logged on Tuesday and resumes one left open yesterday, so a
        tab named after a day shows other days. The *page* keeps the date as its
        title (§9) — only the nav label moves.
      - Progress's slot goes to **Settings**, which is behind a gear on Today
        today. The argument is not symmetry, it is that **bodyweight logging**
        lives in there and is not a setting at all: it is data entered weekly
        that feeds every pull-up and dip score in the app, currently two taps
        deep behind a cog.

      Order matters, and it is three commits, not one: fold Progress into
      History (structural), then build the chart language, then rename the tabs
      (cosmetic). Renaming inside the move makes a diff nobody can review.
- [ ] **5 · Regime cluster** — `regime_screen`, `session_editor`,
      `exercise_catalog_screen`, `regimes_screen`, `regime_setup`. Day tabs,
      count-as-heading, single targets card + editor sheet, catalog picker with
      search and filter chips. Creation stays in sheets: no wizard.
- [ ] **6 · Settings, bodyweight, all-time heatmap** — mostly deletion of
      bespoke layout once the list primitives exist. Settings is a *tab* by the
      time this runs (step 4), so it gets a header band and a masthead like
      every other destination rather than the pushed-screen app bar it wears
      now, and bodyweight comes up out of it far enough to be reachable in one
      tap.
- [ ] **7 · Reconciliation** — light theme audited on every screen (only checked
      at token level so far), empty states, motion consistency, and THEME.md
      corrected where the build taught us something the audit didn't.

Two things to preserve through all of it, both easy to lose in a redesign:

- The log screen owns the horizontal axis. Nothing inside its `PageView` may
  take a horizontal gesture.
- Prefill attribution has to survive. It is the one rule the app exists for.
  It is no longer a caption in the log header: it is the `Last logged` line in
  the exercise's ⓘ, plus an amber dot on that button whenever the numbers were
  borrowed from another session. Moving it is fine; losing it is not.

---

## Built

Analyzer-clean and unit-tested where there is logic. "Driven on the emulator"
marks flows exercised end to end by hand.

**Those marks are stale.** They predate the audit fixes _and_ the rebrand;
every screen has been touched since and none has been driven again. Treat them
as evidence about the design, not about the current build. What wants real
hardware rather than a test: anything with a plugin behind it (the end-of-rest
tone and haptics, the wakelock, audio ducking against music) and anything whose
layout moved — which, after the rebrand, is everything.

- **Logging** _(driven on the emulator)_ — one exercise per page, horizontal
  rail, typed sets (warmup / working / backoff / drop / rest-pause / AMRAP),
  custom gym keypad with a one-plate step and one-tap "Last: 22.5", auto rest
  timer, per-set notes, swap / skip-with-reason / move / add exercise
  mid-session. Resuming an interrupted session survives a force-stop.

  Rest ends out loud: a double haptic and a tone on the Android alarm stream
  (`core/rest_alert.dart`, audio focus `gainTransientMayDuck`, so music dips
  rather than stops), and the screen is held awake for the whole session. The
  bar then says "Rest done" and removes itself after five seconds — it never
  counts overtime, but the start time is kept, because actual rest is measured
  from it. _Not yet driven: the tone and the wakelock want a real device._

  Finishing with sets still open is allowed but never silent: the confirmation
  names every exercise and how far it got. Turning the page early is allowed
  too — supersets and busy racks are normal — and the page says how much is
  left behind. Starting a session twice in one tap-tap creates one workout, not
  two.

- **Three levels of note** — `exercises.notes` is the permanent cue,
  `set_logs.note` is one set, and `workout_exercises.notes` is this exercise on
  this day ("shoulder felt off on incline today"). The third is new to the UI,
  not to the schema: the column already existed on the snapshot row and was
  never written. Editable from the exercise menu mid-session, from the summary
  screen, and from the exercise's expansion in workout detail; shown under the
  cue on the log page. Writing it can never reach the catalog or the template —
  invariant 2, and there is a test standing on it.

- **Session end screen** — finishing no longer drops straight back to Today.
  `session_summary_screen.dart` opens as a *replacement* for the log: sets,
  volume moved and time in the header, then every exercise with what it came to
  and its note for the day, and the session note written from the screen rather
  than found again in History. It sits after `completeWorkout`, so there is
  nothing to confirm on it — the finish-with-sets-open confirmation still
  happens before the write, unchanged. Back and Done are the same single pop.

- **Session-scoped prefill** _(driven on the emulator)_ — ghost values,
  cross-session borrowing labelled, ghost adopted on completion, beat-last-time
  highlight.
- **Cycles + deload** _(driven on the emulator)_ — cycle completes when every
  session is trained; deload after N cycles cuts sets and scales weight %,
  configurable per regime, visually distinct (amber) everywhere including the
  resume path.
- **Stale sessions** — a workout left open past 24 hours with nothing logged in
  it is abandoned at launch; one with sets in it is kept, and Today offers
  Finish (saved to the day it was started) or Discard.
- **History** — two views: the paged session feed and the per-exercise index,
  both unit-tested against a real SQLite database but not clicked through. The
  third — the Notion table, exercises down the side and one column per date —
  was deleted in step 3, along with `sessionHistory`, `SessionHistory` and
  `HistoryCell`. The feed answers "which day" better and the per-exercise
  history answers "how has this moved" better; the table was the spreadsheet
  this app replaced, re-created inside it.
- **Progress** _(driven on the emulator)_ — e1RM over time, one line per session
  slot, 3M/1Y/All, stall detection. Deload weeks excluded so a light week isn't
  drawn as a regression.
- **Consistency heatmap** _(driven on the emulator; the year view is unit-tested
  only)_ — eighteen weeks on Today, auto-filled, deload days distinct. Tapping
  it opens every year since the first logged session, one horizontally scrolled
  grid per year, parked on today.

  The sessions/week figure beside it is **not always a rate**. It was
  `sessionsInTheLast29Days / 4`, which told a two-day-old install it was
  training "0.3 / week" — a number produced by dividing by three weeks that had
  not happened. `domain/consistency.dart` now divides by the weeks it actually
  has, and reports a plain count below a fortnight of history. Any change here
  belongs in that file, tested without a database.

- **Backup** — export / restore / auto-export. Round-trip is unit-tested against
  a second in-memory database, including enum and JSON-list columns. On device,
  only the restore file picker was opened; the share sheet and a real restore
  were not completed.
- **Bodyweight log** — schema, repository, interpolation and BW / BW+X load
  maths are unit-tested. Its own screen behind Settings: full history, add,
  correct by tapping a row, delete, and the change against the previous entry.
  No weight has been logged through the UI.
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

**220 tests**: prefill rules (including a deload never re-scaling a light week),
cycle/deload timing and closing a cycle early, metrics, unit conversion, keypad
key handling, backup round-trip, history paging, deleting a workout (including
the cycle it reopens), swap-in-place, mid-session prefill, date and note
editing, rest targets, the multi-regime rules, the stale-session sweep, the
create-regime flow as a widget test, Today's single-frame arrival and its
above-the-fold budget, and repository integration against a real in-memory
SQLite.

---

## Not built

- **Supabase sync** — schema, RLS, magic-link auth, push dirty rows / pull since
  `last_pull_at`, LWW merge on `updated_at`, tombstones. **Blocked:** needs the
  project URL + anon key. Every table already carries the sync columns (`id`,
  `updated_at`, `deleted_at`, `device_id`, `dirty`), so this is additive — no
  migration required.
- **iOS** — needs Xcode installed. The codebase is cross-platform; nothing
  iOS-specific is known to be broken, and nothing is verified either.

---

## After the rebrand

1. Drive the whole app on a device. Reinstall first — the schema changed, and
   every emulator mark above predates the rebrand.
2. Supabase sync (above).
3. iOS verification once Xcode exists.
4. Per-exercise deload overrides — the columns exist
   (`session_exercises.deload_set_delta` / `deload_weight_pct`), no UI yet.

---

## Wanted, not designed yet

Asked for and agreed; none of it is specified, and each one has a decision in
front of it that has to be made before any code. Check the README's
**Non-goals** before starting any of them — the answer there is usually no, and
these are on this list because they survived that check, not because they
skipped it.

- **Records on the summary screen.** The end of a session prints sets, volume
  and time, but never says what was *beaten*. `beatsPrevious` already answers
  it live in the log, per set, against the same slot last time — the summary
  cannot reuse that because it opens *after* `completeWorkout`, when the ghosts
  are gone. Doing it honestly means re-resolving prefill for every exercise on
  that screen. Cheap to fold into step 4, which is in that code anyway.

- **All-time PRs.** A separate feature from the above, and the harder one,
  because it is the first thing in this app that would deliberately cross the
  session boundary. `beatsPrevious` compares against *this session's* last
  time, so a 100kg bench in Push 1 lights up green over last week's 97.5 even
  when 105 is sitting in Push 2's history.

  **Decide first:** is a PR per exercise across every session, or per
  session-slot? Global is what "my best ever bench" means to a person;
  session-scoped is the thesis of the whole app. Getting this wrong turns the
  one rule the app exists for into a footnote. Worth seeing step 4's chart
  first — it may already answer the question, and then the badge is redundant.

- **Weekly sets per muscle.** The volume figure that actually drives
  programming decisions, and the one thing this log cannot currently answer:
  "am I doing enough for side delts". `exercises.muscle` is already an enum on
  every row, so the data is there and this is a pure aggregation over a rolling
  seven days — `domain/`, tested without a database.

  **Decide first:** what counts. Working sets only, or warm-ups too (no).
  Direct muscle only, or fractional credit for secondaries (there is no
  secondary-muscle column, so: direct only, and say so). A deload week counted
  or excluded — the consistency rate has the same problem and already made this
  choice once; follow it.

- **Weekly sets per muscle on Today.** The surface for the above. Today is
  already the busiest screen in the app and rule 6 is the one it breaks most,
  so this arrives as *one* block or not at all — most likely a short bar list
  under the heatmap, muscle name and count, no chart. It replaces nothing; it
  has to earn its height against the consistency grid.

- **Muscle chip on every exercise.** `muscle` is rendered as text in the
  catalog and nowhere else. As a chip on the exercise row it makes the catalog
  filterable by tapping what you can see, which is what the picker mid-session
  actually needs — you are looking for "a triceps thing that is free", not
  scrolling an alphabet. Ties directly into the filter chips step 5 already
  plans for the catalog picker.

- **Isometric holds.** Planks, dead hangs, L-sits, wall sits. **The only item
  here that needs a migration**, and the reason it is not trivial: a set is
  currently `weight × reps`, and a hold is `load × seconds`. That is a third
  measurement axis, and it lands in the middle of everything — `SetLog` needs a
  duration, the keypad needs a seconds mode, `effectiveLoad` and `estimated1RM`
  need to refuse to score it (a 90-second plank has no 1RM), prefill has to
  suggest a time instead of a weight, and the set row has to render `2:00`
  where it renders `60 kg × 8`.

  **Decide first:** is a hold a new `SetType`, or a property of the *exercise*
  (a `MeasureMode` beside `LoadMode`)? Exercise-level is almost certainly
  right — a plank is never sometimes reps — and it keeps every set of that
  movement consistent instead of letting one row be reps and the next be time.
  The rest of the app can then branch on one enum in one place.
