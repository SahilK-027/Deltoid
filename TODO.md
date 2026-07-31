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
      effort palettes), `theme` (nine type roles, capped 11–27sp), `primitives`
      (header band, list card + row, buttons, chips, segmented pill, sheets,
      bottom-anchored confirm), monochrome nav bar.
- [x] **1 · Today** — header band, flat hero with the regime's identity mark,
      white primary action. Cycle list dropped, backfill collapsed to one titled
      sheet, stale sessions given Finish / Discard.
- [ ] **2 · Log** — `log_screen`, `set_row`, `keypad`, `exercise_rail`,
      `exercise_sheets`, `rest_timer`. ~2,800 lines and the most-used screen.
      Forces the pieces the rest reuse: monogram tile (we have no exercise
      photos), value fields with the focused-outline state, `W`/`D` index chips,
      swipe-to-delete, keypad, plate view. Review in two passes — set table and
      rail, then keypad / plate / rest timer / sheets.
- [ ] **3 · History + workout detail** — the furthest from the language today.
      Date-group headers, identity tiles, expandable exercise rows. Layout only:
      keyset paging and `HistoryCursor` are not touched.
- [ ] **4 · Progress + exercise history** — builds the chart language once:
      dashed gridlines, right-hand Y labels, range pill, legend chips, em-dash
      empty state instead of a gridded void. Three screens consume it.
- [ ] **5 · Regime cluster** — `regime_screen`, `session_editor`,
      `exercise_catalog_screen`, `regimes_screen`, `regime_setup`. Day tabs,
      count-as-heading, single targets card + editor sheet, catalog picker with
      search and filter chips. Creation stays in sheets: no wizard.
- [ ] **6 · Settings, bodyweight, all-time heatmap** — mostly deletion of
      bespoke layout once the list primitives exist.
- [ ] **7 · Reconciliation** — light theme audited on every screen (only checked
      at token level so far), empty states, motion consistency, and THEME.md
      corrected where the build taught us something the audit didn't.

Two things to preserve through all of it, both easy to lose in a redesign:

- The log screen owns the horizontal axis. Nothing inside its `PageView` may
  take a horizontal gesture.
- The prefill attribution line — `From Push 2 · 12 Jul` — has to survive. It is
  the one rule the app exists for.

---

## Built

Analyzer-clean and unit-tested where there is logic. "Driven on the emulator"
marks flows exercised end to end by hand.

**Those marks are stale.** They predate the audit fixes *and* the rebrand;
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
- **History** — three views. The Notion table was driven on the emulator; the
  paged session feed, the day detail and the per-exercise history are
  unit-tested against a real SQLite database but not clicked through.
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

**167 tests**: prefill rules (including a deload never re-scaling a light week),
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
