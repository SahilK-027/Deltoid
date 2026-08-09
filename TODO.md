# Deltoid — the list

This is the single list of what the app is made of: everything that is done,
and everything that is left. Within each group, the newest work is at the
bottom.

This file carries status and nothing else. Why a feature is shaped the way it is
belongs in [THEME.md](THEME.md), and the rules it must not break belong in
[RULES.md](RULES.md).

The app currently has **342 tests** and is analyzer clean.

---

## Done

### Core model

- [x] Regimes, sessions, session slots and cycles are built. A cycle advances
      when the work is done rather than when the calendar turns.
- [x] Deload fires after a configurable number of cycles and applies fewer sets
      and a lighter bar. It can be configured per regime and overridden per slot.
- [x] Prefill is scoped to the session. Last time's numbers sit in the fields as
      ghost text, borrowed numbers are labelled on the exercise's ⓘ, the ghost is
      adopted when a set is completed, and beating last time lights the row up.
- [x] Logging writes snapshots, so a workout keeps its own copy of the day and
      editing the programme never rewrites history.
- [x] Up to six regimes live at once with one of them active. Each owns an
      identity hue, and names are unique among the living ones.
- [x] The exercise catalog archives rather than deletes. The starter catalog is
      seeded on first launch, and no regime is ever seeded.
- [x] Stale sessions are handled: one left open with nothing in it is swept
      silently, and one with sets in it is kept and offers Finish or Discard.

### Logging

- [x] The log screen shows one exercise per page and supports typed sets, set
      types, drop groups, swipe-to-delete, swapping, skipping, moving and adding
      a movement mid-session, notes at three levels, and recovery from a force
      stop.
- [x] The keypad is docked and stepped by the plate increment, and it puts last
      time's value one tap away.
- [x] The plate view sits inside the keypad and shows what to load on the bar,
      for a movement that knows which bar it uses.
- [x] The rest timer starts itself when a set is ticked, plays its tone on the
      alarm stream, and holds a wakelock while a session is open. A rest still
      running when the app goes to the background is handed to the OS as an
      exact alarm, so it rings on time with the screen off, and an ongoing
      silent notification carries the session, its set count and a system-drawn
      countdown.
- [x] Ticking a set moves the keypad to the next open set — turning the page
      when that set is on the next exercise — and closes it on the last one, so
      the finish button is the only thing left on screen.
- [x] Partial reps are logged apart from full ones. The count cell splits in
      equal halves only once there is a second number in it — `P` on the pad
      asks for it and `F` closes it again, a number on the row or in the ghost
      keeps it. Either box takes focus on its own tap; only the pad's `F`
      closes the half. Last time's partials show as a ghost and are never
      adopted. History reads them as `8+3`. They are recorded only: out of volume,
      out of e1RM and out of `beatsPrevious`.
- [x] Isometric holds are measured in time through `MeasureMode` on the
      exercise. A stopwatch replaces the keypad for them, so starting and
      stopping the clock writes the hold, ticks the set and starts rest, and a
      hold that was timed elsewhere is typed as a clock instead.
- [x] The session summary reports volume, sets and time, carries the session
      note and a recap, and offers to keep today's changes to the programme.

### Reading it back

- [x] History pages the session feed by keyset, indexes every exercise trained,
      and opens a workout from that day's own snapshot rows. Filters run in the
      query rather than over the loaded page.
- [x] The trend chart plots estimated 1RM or heaviest weight over time with one
      line per session slot, excludes deload weeks, detects stalls and takes
      pinch to zoom. A timed hold is plotted in seconds instead.
- [x] The consistency heatmap shows eighteen weeks on Workouts with the all-time
      view behind it, drawing a year per `CustomPaint`.
- [x] Weekly muscle volume shows six region rows under the heatmap, counted in
      SQL, with arms and legs folding open onto their own muscles.
- [x] The bodyweight log is one tap from Settings, groups by month with deltas,
      has its own trend, and is interpolated into every bodyweight lift's score.

### Around the edges

- [x] Backup exports, restores and auto-exports after a session, saving to
      Downloads or through the share sheet. The JSON runs on another isolate and
      reports progress, and the round trip is tested.
- [x] Settings covers units (kilograms or pounds, display only), the light, dark
      and system themes drawn as three miniatures of the app, and the adaptive
      launcher icon.
- [x] One day picker serves backfill, the bodyweight log and re-dating a
      workout, and it rings the days that are already logged.
- [x] Backfill logs a past session, asking for the day first and keeping it on
      screen while you choose.

### The rebrand

Every screen was rebuilt on [THEME.md](THEME.md), ordered by how much a screen
is used and by what shared pieces it forced into existence.

- [x] 0 · Foundation — the tokens, the type roles, the primitives and the nav
      bar.
- [x] 1 · Workouts — the header band, the flat hero and one white action.
- [x] 2 · Log — the set rows, index chips, keypad, rail, sheets and rest timer.
- [x] 3 · History and workout detail — full-bleed rows, month headings, the
      session summary and notes at three levels.
- [x] 4 · Progress folded into History, so the chart now lives at the head of an
      exercise's own history and the tab is gone.
- [x] 5 · The Regime cluster — the tab became the library, a regime pushes the
      editor, and an exercise is one screen wherever you came from.
- [x] 6 · Settings, the bodyweight log and the all-time heatmap.
- [x] Feel — ink on rows and the nav bar, animated folds, damped scrolling, and
      no spinner anywhere there is already content on screen. The four things
      that actually cost frames were found by reading the code rather than by
      guessing, and all four are fixed.
- [ ] **7 · Reconciliation** — the light theme has only been checked at token
      level and needs driving on every screen, along with the empty states and
      the motion. THEME.md gets corrected wherever the build taught us something
      the original audit did not.

### Not yet driven on the device

Four things are built, analyzer clean and tested, but have not yet been used in
a gym: the weekly volume bars, the muscle chips, isometric holds and the hold
pad. Five more have never been verified on real hardware at all: the rest tone,
the haptics, the wakelock, audio ducking and the share sheet. Newest and least
driven: the ongoing session notification and the scheduled rest alarm — the
notification permission prompt, the countdown on the lock screen and the alarm
firing with the screen off have only been built, not felt.

---

## Left

- [ ] **Supabase sync.** This is the one feature still outstanding, and it needs
      the project URL and the anon key before it can be started. Every table
      already carries the sync columns (`updatedAt`, `deletedAt`, `deviceId` and
      `dirty`), so the work is additive and needs no migration.
