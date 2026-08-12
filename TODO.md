# Deltoid — the list

This is the single list of what the app is made of: everything that is done,
and everything that is left. Within each group, the newest work is at the
bottom.

This file carries status and nothing else. Why a feature is shaped the way it is
belongs in [THEME.md](THEME.md), and the rules it must not break belong in
[RULES.md](RULES.md).

The app currently has **448 tests** and is analyzer clean.

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

- [ ] **Cloud backup.** Designed in full — see [SYNC.md](SYNC.md), which is the
      document to read before writing any of it. Scope-approved and bounded by
      [RULES.md § 6](RULES.md#6-scope): a backup you do not have to remember to
      take, not collaboration and not a feature.

The shape, decided: **correct on any number of devices, live on
      none.** Two phones never lose a write, fabricate one, or refuse each
      other's rows; what they do not do is update each other within seconds. A
      held socket is what Keep and Notion need for two people in one document,
      and it would cost a battery budget here to serve a case one person with
      one phone does not produce — while the correctness it gets confused with
      is built either way.

      **Identity** is Google through Supabase Auth, which is also what makes the
      anon key harmless: with RLS keyed to `auth.uid()` the key alone grants
      nothing. **What syncs** is the nine `SyncColumns` tables and never
      `app_settings`. **Conflict** is row-level last-write-wins throughout,
      ordered on a server timestamp rather than a phone's — field-level merge
      was rejected because a `SetLog` is one physical event, and merging
      `60 × 8` with `62.5 × 5` field-by-field yields a lift nobody performed.
      Only **`journal_mode`** is still open: `delete` today, so a sync reader
      and a writer serialise completely, and WAL trades a little durability.

      **The local schema does not change.** `user_id` is server-side only,
      attached from the session at push time. Nothing in `tables.dart` moves.

      In build order, each piece landing on its own:

      - [ ] Migration ladder — the prerequisite below, before any of this ships.
      - [ ] Supabase project: nine tables, `user_id`, RLS with `using` *and*
            `with check` on every one. Needs the project URL and anon key.
      - [ ] A `SyncClient` seam with a fake behind it, so push, pull, conflict
            and adoption are all testable without a network or a credential.
      - [ ] Push: drain `dirty`, parents first, idempotent upserts, and clear
            `dirty` only against an unchanged `updatedAt`.
      - [ ] Pull: `last_pull_at` cursor on `server_updated_at`, LWW applier
            through the repositories, tombstones as tombstones, a bad row
            skipped and named rather than stopping the batch.
      - [ ] Collision resolution for the nine unique indexes — re-slot,
            re-flag, re-number, never delete. The first four are not edge cases:
            two devices appending to one parent both compute `max + 1`.
      - [ ] Defer `ensureStarterCatalog` until the welcome screen is answered,
            so a fresh phone signing in does not end up with two catalogs and
            its history split across two ids for one movement.
      - [ ] A test per row of [SYNC.md § 12](SYNC.md#12-every-edge-case-and-what-it-does),
            so a later change that breaks one fails a build rather than a
            history.
      - [ ] Adoption: the three shapes at sign-in, and for the third a prompt
            offering keep-account / keep-phone / merge, with counts on both
            sides and the side not kept exported to a file first.
      - [ ] Sign-in on Google, session persisted, seen once.
      - [ ] The welcome screen — the app's one illustrated page, drawn to
            [THEME.md § Illustration](THEME.md), monochrome, with declining
            given equal standing.
      - [ ] Settings: connect, state, last run, and the two sign-out doors.
      - [ ] Scheduling: debounced after writes, on resume, on connectivity, plus
            an idle backstop whose interval wants a real phone to choose it.
            Needs `connectivity_plus` — the design says "on connectivity
            regained" in three places and nothing in `pubspec.yaml` can detect
            it.
      - [ ] Catalog deduplication on `starterKey`, with references repointed.
            Needed whenever a phone that has trained offline signs into an
            account that already has a catalog, which is the ordinary
            offline-first order — not a rare case.

- [ ] **The migration ladder, as a prerequisite of sync rather than a
      consequence.** `schemaVersion` is 1 with no `onUpgrade`, which holds only
      while every database is one we can throw away. Sync ends that: two devices
      can run different builds and exchange rows, so a released schema change
      needs both an upgrade path for the local file and a wire format that
      survives a row carrying one column more or fewer than the reader knows.
      See [RULES.md § 3](RULES.md#3-schema-and-migrations) for the rules the
      ladder itself has to follow.
