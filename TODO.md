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

- [x] **5 · Regime cluster** _(driven on the device)_ — the programme editor,
      rebuilt around a day you can read.

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

      **Driven twice, and the device found four things.** The first pass: the
      day tabs asked for an infinite width — a stretching column inside a
      horizontal scroll — and the Regime tab rendered as nothing at all behind
      one `BoxConstraints forces an infinite width` and a hundred `RenderBox
      was not laid out`. And the screen had no masthead until it had data, so a
      first launch opened on a bare empty state with nothing saying which tab
      you were in. `regime_screen_test.dart` now pumps all four states against
      a real database, because both were invisible to the analyzer and to every
      other test.

      The second pass, after the day became a list: creating a regime always
      activated it, so building next month's split abandoned the one you are
      mid-cycle on and a shelf of programmes was impossible to assemble — from
      the Regimes screen it creates and stays put, offering the switch in the
      snackbar, and only an empty app still activates on create. And the tab
      strip shrink-wrapped, so a regime with one day centred `Legs` and
      `Add day +` in the band while a regime with six had them against the
      gutter; the strip is full width now, whatever is in it.

      **The tab is the index of the section, not the editor.** It opened
      straight into the active regime, so the tab named after every programme
      only ever showed one, and the other regimes and the exercise catalog sat
      two sheets deep behind the sliders button — which is how a shelf of
      programmes managed to look deleted. The tab is the list now, in two
      sections — **`Active regime`** and **`Regime library`** — with the
      catalog as a row beneath them, since it belongs to no single regime.
      The heading carries the state, not a badge: an `Active` pill in one
      row's trailing slot and no other's shifted that row's layout against
      its neighbours, and the section says the same thing without bending
      the column. `Train this one` is `Activate regime` — it names the state
      it produces rather than the consequence.
      Tapping a regime pushes the same editor as before, wearing the app bar
      (THEME §5) and scoped to `regimeId` rather than to whatever is active —
      `regimeByIdProvider` and `sessionsForRegimeProvider`, carried down
      through the slot screen, which had been reading the active regime for a
      day that need not belong to it. A tap edits and never switches; `Train
      this one` stays in the row's ⋯ sheet, because training a programme is a
      decision rather than a side effect of looking at it. The cycle line
      renders only for the active regime — an inactive one has no cycle in
      flight.

      **A regime owns its colour, and there are six of them.** The mark was a
      hash of the regime id, which is stable but not unique — six hues means
      two programmes collide about a third of the time, and the mark is the
      thing History and Today are scanned by. `Regimes.identityIndex` (schema
      v5) stores the slot: assigned lowest-free on create, handed back on
      delete, backfilled oldest-first for an upgraded database. That makes the
      palette a cap — **six live regimes**, and the seventh create is refused
      by `RegimeSlotsFullException` rather than allowed to share. The library
      heading says so before `New` is tapped. Today and History hold a regime
      id and not the row, so they read `regimeIdentityProvider` (id → slot,
      deleted regimes included, or a deleted programme would turn every old
      row orange).

      **A name belongs to one regime.** Applying a template proposes the
      template's own name, so `Upper / Lower` could be applied four times and
      the History feed then held four identical rows in four colours. Live
      regime names are unique now — trimmed, case-insensitive, enforced in
      `createRegime`, `createRegimeFromTemplate` and `updateRegime`, and said
      in the name field while you type rather than in a snackbar after the
      sheet closes. A deleted regime releases its name. `promptForText` grew a
      `validate` callback for it, which is how the rename sheets check too.

      **Two templates, and blank.** `Push / Pull / Legs · 3 day` and `Full body
      · 3 day` are gone: five splits is a magazine, and the two kept are the
      shapes the model is built around. Scratch sits alone at the top of the
      sheet, the templates under a `Regime templates` heading — they are two
      different offers, and stacked together the empty card read as a template
      of nothing.

      **Deload is orange, and the session tile is blue.** Deload was amber, one
      notch from the yellow in `series[]` and from a yellow identity mark. Once
      it went orange the Today and History tiles — which took the *regime's*
      identity hue — hid it outright on the orange regime and drowned it on
      every other one. Those tiles are `heatOn` blue for a session and `deload`
      orange for a light week, which is the one distinction a feed of trained
      days is scanned for. Identity hues stay on the Regimes screen, where the
      colour separates programmes. `regimeIdentityProvider` went with the
      change; nothing outside that screen reads a slot now.

      **The palette went round a loop and came home.** There were three sets
      of the six hues — a light one tuned for charcoal, a saturated one identity
      marks filled with, and a third the light theme kept privately — so a call
      site had to know which job it was doing and the `blue` on Today was not
      the `blue` in the chart beside it. Collapsing onto the saturated set read
      as *too saturated*, correctly: it ran 4.0:1 at blue to 9.7:1 at yellow.
      Solving every hue to one contrast fixed the evenness and cost the hues —
      yellow came out `#A0812B`, an ochre, which is a number satisfying a
      constraint rather than a yellow.

      The answer was the six the app already had: `#FF8B66 · #689FFA · #FDD35F
      · #5DBA86 · #BE8CFF · #77D4E3`, plus the one red. Screenshots of the
      reference app's own charts sample within a few points of them on every
      hue, and it uses one set in both themes — so we do too, and `light` points
      at the same constants as `dark`. **A hue has to stay the hue**; evenness
      is worth solving for only where it doesn't cost that.

      The thing that made two sets look necessary was the *white* glyph these
      fills cannot carry (1.4:1 on yellow). That is gone:

      **a tile's glyph is its own hue taken down**, the way the reference app
      draws them: `#FF8B66` carries `#9E2600`, `#5DBA86` carries `#275C3E`. White was
      the rule and measured 1.9:1 on the old yellow; near-black fixed the ratio
      and lost the point, because a tile is one colour with a shape cut out of
      it and a black shape makes it two. `IconTile.glyphOn` walks the lightness
      down until the glyph clears 3.2:1 against its own fill — solved, not a
      fixed multiplier, which ranges 2.9–3.7 across the hues and is the
      uneven-set problem one level down. Every tile lands at 3.24–3.35:1,
      covered by `test/core/icon_tile_glyph_test.dart`. It is also what frees
      the fills to be light enough for one palette to serve both themes.

      **Restoring a pre-v5 backup no longer throws.** `Regime.fromJson` casts
      `identityIndex` straight to int and a file written before the column has
      no such key — `type 'Null' is not a subtype of type 'int'`, and the whole
      restore died on the first regime. The codec defaults it, and the restore
      deals the slots out afterwards, exactly as the migration does. A file
      that already carries slots keeps them.

      **An exercise is one screen now, wherever you came from.** There were
      three shapes for one noun: the slot screen, read-only, whose `General`
      section handed off to an `Edit` sheet; that sheet, the last form in the
      app — dropdowns, text fields, its own header, its own Save; and the same
      sheet again titled `New exercise`. So editing a movement looked nothing
      like looking at one, and creating one looked like neither.

      `exercise_screen.dart` is the noun's page. `Overrides` renders only when
      it was opened from a training day; `General` always, as rows that open one
      question at a time rather than a form. Dropdowns are gone — a Material
      menu has no room to say what an option means, and `How the weight is
      entered` is the field that re-reads every set ever logged. Existing rows
      save as you go; a new one holds a draft behind `Create exercise`, so a
      back-swipe out of a half-filled form leaves nothing in the catalog. The
      picker's "nothing found, make it" path pushes the same screen.

      **Creating one answers every question.** The fields shipped pre-set to
      chest / machine / total load, which is a guess wearing the clothes of an
      answer — tap Create without reading and a cable fly is filed as a chest
      machine, and load mode is the field that decides how every set ever logged
      against it is read. Each row shows `Choose` in `textTertiary` until it is
      answered and `Create exercise` stays off until all of them are. `Bar`
      counts only under a total load, since that is the only load a bar can be
      subtracted from and the row is not on screen otherwise. The cue stays
      optional: it is a note in your own words about a movement you may not have
      performed yet, and requiring one means inventing something to type.
      Equipment no longer pre-fills load mode and bar for the same reason it no
      longer pre-fills them on an existing row — a guess that satisfies a
      required field is indistinguishable from an answer once the sheet
      closes.

      `session_slot_screen.dart` is gone, and so are `showExerciseEditor`, its
      sheet and its `_Dropdown`. Name collisions are checked in the name prompt
      itself now, the way regime names are.

- [x] **6 · Settings, bodyweight, all-time heatmap** _(driven on the device)_

      **Bodyweight is one tap.** It had never once been logged through the UI:
      it was behind a cog, then behind a card that pushed a screen with a `+`
      in its bar — three taps to type a number you are asked for daily.
      Tapping the figure in Settings *is* the log, prefilled when today already
      has an entry (the table is keyed by day, so a second weighing corrected
      rather than duplicated either way; now it says so), and the past is a
      `History` link on the section header rather than the card's only purpose.
      The prompt is a sheet, not an `AlertDialog` that opens mid-screen and
      then fights the keyboard for the same space, and delete moved into it —
      off every row, as archiving did in step 5.

      The log is grouped by month, and a month's first row still reads its
      delta against the last entry of the month before it. Settings' peek query
      is gone with its `limit(30)`, which had been printing "30 logged" for a
      count that could only grow.

      **The list layouts**: `ListTile` and two hand-rolled `AnimatedContainer`
      pickers gone, for `ListCard` + `AppRow`. Restore's confirm is
      `confirmAction` now, rather than two equal-weight text buttons with the
      one that wipes the device on the right.

      **The two settings are pictures and radios, not tracks.** Theme is three
      miniatures of the app — background, heading, chart series, cards — with
      System split on the diagonal, because a setting that is neither light nor
      dark has no honest single picture and three words in a track ask you to
      remember what it did last time. Units are rows with `AppRadio` (§5, built
      for this): the unit changes what every number in the app means, and a row
      has the width to say so. Switching theme no longer cross-fades —
      `MaterialApp` was lerping every colour in the tree for 200ms, which over
      cards, charts and a heatmap is a long grey wash through the midpoint of
      two palettes.

      **Backup stops freezing the app.** `jsonEncode` and `jsonDecode` over the
      whole history are single synchronous calls, and on the UI isolate they
      took the app with them — no frames, no progress, no way to tell a slow
      export from a hung one, and a hung restore gets killed halfway, which is
      the one failure that costs data. Both run in another isolate now (via
      top-level functions: a closure inside `BackupService` captures `this`,
      and the FFI database handle cannot cross an isolate boundary). So does
      the automatic export that fires after every session. Both jobs report
      `BackupStep`s — phase, detail, and a fraction that is null where a phase
      genuinely cannot say — onto one progress sheet.

      **Export can save to Downloads.** The share sheet was the only way out,
      and sharing a backup to yourself is a strange thing to have to do. A
      choice sheet offers Downloads or Share; the copy lands in
      `Download/Deltoid_Backup` through MediaStore on Android 10+, and through
      the public directory below that (`WRITE_EXTERNAL_STORAGE`, capped at
      API 28). The platform side streams from the path rather than taking the
      file through the channel as one string.

      `settings_screen_test.dart` covers both screens against a real database
      and the month grouping without one; `units_test.dart` covers the delta
      rule, and `seed_years_test.dart` now asserts progress never goes
      backwards.

      **Bodyweight shows tenths**, and is the one weight in the app that does.
      Storage was always exact; the display rounded to the 0.5 kg plate
      increment, so 76.4 came back as 76.5 — in the figure, in the trend, and
      in the sheet, which prefilled the rounded number so correcting the *date*
      of an entry moved its weight. `formatBodyweight` /
      `formatBodyweightDelta` in `domain/units.dart`, covered in
      `units_test.dart`. Loads still round to the plates: that number has to be
      loadable on a bar, and this one does not.

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
  was deleted in step 3. The feed filters by training day and by deload, in the
  query rather than over the loaded page, so keyset paging still holds
  (README invariant 5); the picker only offers days that appear in history.
- **Progress** — e1RM over time, one line per session slot, stall detection,
  deload weeks excluded. Rebuilt in step 4.
- **Consistency heatmap** — eighteen weeks on Today, all-time view behind it.
- **Backup** — export / restore / auto-export, round-trip tested.
- **Bodyweight log** — schema, repository, interpolation, its own screen, and
  since step 6 one tap from Settings to log or correct a weight. The screen is a
  trend chart over the app's one range control, then one collapsed row per month
  (average and change) opening to its days on `surfaceHigh` — a year of daily weights was 365 rows and
  could not answer the question it was opened with.
- **The day picker** — `core/widgets/calendar.dart`, a month grid in a dialog,
  used by backfill, the bodyweight log and re-dating a workout. Material's
  `showDatePicker` was the one surface the theme could not reach. Backfill rings
  every day already logged (blue, or orange for a deload) and asks, on a day
  that has one, whether you came to read it or to add to it.
- Light / dark / system theme, adaptive launcher icon.
- **Feel** — ink on rows and nav (THEME §4), animated folds, no spinner where
  there is already content, an optimistic order under a reorder drag, damped
  scrolling everywhere, and the all-time heatmap aggregated in SQL instead of
  shipping every workout row across the database isolate's port.

  The four that actually cost frames, all found by reading rather than
  guessing: the shell keyed its transition on the tab index, which discarded
  the `IndexedStack` and **rebuilt all four screens on every switch**; the log
  screen's prefill key was the exercise ids *in order*, so a reorder re-walked
  every movement's history against fifty years of logs; that prefill resolved
  one exercise at a time, making first paint the sum of six round trips rather
  than the longest; and the bodyweight screen built every month row eagerly —
  six hundred of them to show eight.

**283 tests** — prefill and deload rules, cycle timing, metrics and volume,
session diff and template writes, backup round-trip, history paging, keypad,
the stale-session sweep, Today's single-frame arrival and above-the-fold
budget, the programme editor and Settings pumped against a real database, and
repository integration against real in-memory SQLite.

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
