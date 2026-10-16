# Deltoid roadmap: 1.17.0 to 1.20.0

The plan agreed on 15 October 2026. Releases 1.17.0 and 1.18.0 are built; nothing after them is yet.

- **Prototype:** [`prototype.html`](prototype.html) opens in any browser. It draws every
  screen in the app's own tokens, greys out everything that stays exactly as it is
  today, and has a switch to simulate having no connection. A hosted copy is at
  <https://claude.ai/artifact/NkQuNBQ9RV6WxfCXd8mwqH>.
- **Chart audit:** [`chart-audit.md`](chart-audit.md) ranks 33 chart problems found by
  rendering every chart from one entry to twenty years of data. Its screenshots
  were written to an untracked `docs-scratch/` folder and are not kept here.

The redesign is a change of navigation, not of design. Every screen and card that
exists today keeps its current look, and only what is new is allowed to look new.

---

## 1.17.0: Navigation

### Five tabs

**Home · Regimes · Progress · History · More.** More uses a circle with three dots
as its icon (`Icons.pending_outlined`, filled when selected).

### Home

Home replaces Workouts. It is the page you land on and the place you enter things.

- **Masthead:** the date, the title `Home`, the rest line (`Rested 3 days`) and the
  backup button, as today.
- **Today's session:** the current hero, unchanged.
- **Habits:** two tiles side by side.
  - `Weigh-ins` and `Workouts`, each with a 30-day grid and `N/7 this week`.
  - Weigh-ins carries a grey round + button that opens the weigh-in sheet.
  - Workouts carries a grey round play button that starts the session that is due.
  - Tapping either tile opens its full map: Workouts opens today's Consistency
    screen; Weigh-ins opens a new screen with today's bodyweight trend card, the
    weigh-in year maps in today's year-map design, and a Log weight button.
- **Past sessions:** a card holding `Log a past session`. It replaces the calendar
  icon in the masthead.
- The card order is fixed. Customise Home was considered and cut.

### Regimes, History

Unchanged, including the exercise catalog under Movements on Regimes.

### Progress

Cycle progress and Weekly volume move here from Workouts, unchanged. The AI card
joins them in 1.20.0.

### More

Today's Settings without its Bodyweight section, plus:

- A profile header when signed in: a 46px initials circle in the accent colour, the
  name from the Google sign-in, and `Backed up since` the date the account was created.
- The Account row reads `Account` with the email beneath it and opens the sign-out sheet.
- The About card text becomes: "A training tracker that puts you in full control of
  your programs. Design your own routines, log every set and rep, and track your
  strength over time with clear, organised records." The spelling `programs` is the
  owner's choice and deliberate.

---

## 1.18.0: Phases

- **Data:** a syncable `phases` table holding the kind (bulk, cut or maintenance), the
  start day and an optional planned length of 8, 12 or 16 weeks. It needs the full
  migration ladder and the server rung.
- **Phase card on Home:** the phase and its icon, `Since 3 Sep 2026`, a `Week 7 of 12`
  pill, a bodyweight sparkline tinted by phase, and three figures: bodyweight, change
  since the start and change per week. `Change` opens the phase sheet.
- **Keeping it current:** the card itself, never a notification, asks what comes next
  once the planned length has passed, or when the weigh-ins have run against the
  declared phase for about three weeks.
- **Cycle progress chart:** each cycle's slot is tinted by the phase most of its
  sessions ran in: maintenance grey, bulk lavender, cut cyan. The readout names the
  phase: `Cycle 6 · Cut · +6.4% on cycle 1`. The legend adds the three phases.
- **Deloads stay exactly as today:** an orange band 80% of the slot at 14%, no point,
  an orange cycle number and a dashed line across. Phase tints stop at the deload
  band's edges and are never drawn under it.
- **The bodyweight trend chart carries no phase bands.**

---

## 1.19.0: Charts

Every chart is made to look as good with twenty years of data as with a week, working
through the 33 findings in [`chart-audit.md`](chart-audit.md). THEME's chart rules were
settled first (`d71cf89`): an outlier is shown as a caret rather than allowed to stretch
the axis, line charts are 220 tall as a screen's main chart and 150 in a card, one
legend sits under every plot, chart cards share one spacing rule, and the range control
sits above every chart. The steps, each mapped to the audit's findings, are under
"1.19.0, charts" in **Order of work** below.

---

## 1.20.0: AI analysis

### The card

An `AI analysis` section at the top of Progress. The card has a 2px multicolour
border that turns slowly (pink, lavender, cyan, green and yellow, never the reserved
progress blue or deload orange) and holds, top to bottom:

- Mr Delta beside a speech bubble. At rest it reads `I am Mr Delta. Ask me anything
  about your training.`; while working, `Looking through your log…` then `Working it
  out…`; once an answer lands, the span of data it rests on, such as `Based on six
  cycles of bench press and your current cut.`
- A question field.
- Suggested questions as full-width rows.
- While an answer is being worked out: the question as its heading; under `Reading`,
  the figures being gathered appear one by one as tags; once Mr Delta starts writing,
  the label becomes `Worked out from` and three pulsing placeholder lines stand in
  for the answer. The question field and the suggestions are locked meanwhile.
- While an answer is open: the question as its heading with a close button, the
  answer revealed paragraph by paragraph, and a `Worked out from` row naming the
  figures it used. The remaining questions sit under `Ask something else`.
- The line `Needs a connection. Deltoid works out the figures on this phone and sends
  only those.`

### Mr Delta

A pixel-art mascot drawn from the owner's design: an open delta on top, a solid
lavender body carrying the face (dark eyes with a glint, a white mouth with a pink
tongue, pink cheeks), raised arms, two legs and a shadow. Every motion moves in whole
pixels with stepped timing, and every motion stops under reduced motion.

| Mood | When | What he does |
|---|---|---|
| Rest | Waiting | Bobs and blinks |
| Workout | At rest, every 8 to 12 seconds, for 5 seconds | Presses a barbell overhead, with a sweat drop |
| Searching | While the figures are gathered | Sweeps a magnifying glass across his face |
| Thinking | While the answer is written | Looks up while three dots appear |
| Happy | For 3 seconds after the answer lands | Arms up, a hop, sparkles |
| Asleep | With no connection | Eyes closed, breathing, Zs rising |

In the app the searching and thinking moods follow the real request rather than
fixed timers.

### With no connection

- Mr Delta sleeps and the card is muted. The bubble reads `I need a connection to
  answer.` There is no way to save a question for later; it is asked again once the
  connection is back.
- The question field is disabled: `Available when you are back online`.
- **Answers already received stay readable**, listed under `Your recent answers`
  and marked `Answered earlier, saved on this phone`.
- A note states that cycle progress, weekly volume and everything logged keep working,
  and that only Mr Delta needs the internet.

### Under the hood

- The API key lives in a Supabase server function and never in the app.
- The app computes the figures and sends only those with the question. The model asks
  the app for exact figures rather than doing arithmetic on raw logs.
- Model: Claude Opus 5.5 (`claude-opus-5-5`) at `medium` effort. At four or five
  questions a month the cost is a few cents.
  A setting to choose Sonnet 5.5 instead was considered and left out of 1.20: the
  difference is cents a month and it would add a question and a second set of evals.
  If it is added later, it is one More row (`More thorough` / `Faster`), and the
  server function accepts only an allowlist of `claude-opus-5-5` and
  `claude-sonnet-5-5`, with the app sending a choice rather than a model ID.
- The server function is the only place that names a provider, so changing provider
  later is a one-file change.

### Architecture: the same cost and speed at any amount of history

**The raw log never leaves the phone.** A question never carries sets or workouts.
It carries a few hundred folded figures, so twenty years of training costs the same
to ask about as two months.

1. **Facts layer, on the phone, in Dart.** A new set of pure functions in
   `lib/domain/` (tested without a database, like everything there) answers fixed
   questions about the log: one lift's best set by cycle, a muscle's weekly sets,
   bodyweight by week, the phases and their dates, the regimes and their spells.
   They reuse the queries and the bucketing the charts already use
   (`chart_buckets.dart`), so every figure Mr Delta quotes is the figure the chart
   draws, and every result is capped at about sixty points, the same rule the charts
   follow. One implementation of the maths, in one language.
2. **The brief.** With each question the app sends a short standing summary: units,
   the active regime and its cycle, the current phase, the last 12 weeks of volume and
   bodyweight, and each lift's best set per year. About 3,000 tokens, whatever the
   length of the history.
3. **Two passes, not an open loop.** The first call gives the model the question, the
   brief and a catalogue of the facts it can request, and it replies with a structured
   list of the facts it needs (at most five). The app computes those on the phone and
   sends them back in a second call, which writes the answer. Two round trips at most,
   a bounded wait, and the `Worked out from` tags are exactly the facts requested.
4. **Server function.** A Supabase Edge Function holds the API key, accepts only a
   signed-in user's token, limits each account to a handful of questions a day, and
   relays the two calls. It never reads the synced tables, so it never needs its own
   copy of the training maths.
5. **Saved answers.** Each answer is stored on the phone in a new drift table with the
   question, the text, the facts it used and the date it was asked, as a snapshot in
   the way a set log is. That is what keeps past answers readable offline. Whether the
   table syncs is decided when it is built.
6. **Checking the numbers.** The prompt requires every number in the answer to come
   from the supplied facts. The app then checks that each number in the reply appears
   in those facts and, if one does not, shows the answer with a line saying a figure
   could not be checked rather than presenting it as fact.
7. **What is never sent.** Notes, exercise names the user typed beyond the ones the
   question needs, account details and device identifiers stay on the phone.
8. **Failure states Mr Delta must have.** Offline (asleep), timed out after 30
   seconds, the daily limit reached, the model declining the question, and a server
   error. Each gets a plain sentence in the bubble and leaves the card usable.
9. **Tests.** Domain tests for every fact function, a fixed brief built from a seeded
   database and compared against a stored copy, and an evaluation of about ten real
   questions with known answers, run before each model change.

At four or five questions a month, prompt caching, batching and cost tuning are not
worth building; the design keeps each question small instead.

### After 1.20: Mr Delta elsewhere (ideas, not agreed)

- **One home, many doors.** The card on Progress stays the only place Mr Delta
  answers. Other screens get an `Ask Mr Delta` link that opens the card with a question
  already filled in: a lift's history (`Why has this lift stalled?`), a past workout
  (`How did this session compare?`), the Phase card (`How is this phase going?`).
- **Never on the log screen.** Nothing may stand between the thumb and a set.
- **Drafting a regime.** Describe what you want (days a week, time per session,
  equipment, anything to avoid) and Mr Delta drafts a regime from exercises already in
  the catalog. The draft opens in the ordinary regime editor, nothing is saved until
  you save it, and every slot can be changed like any other. A structured output keeps
  the draft to real catalog exercises and valid set counts, and the app validates it
  before showing it.
- **This conflicts with two written rules.** THEME says creation never offers to
  "build you a plan" because "the user is the planner", and RULES § 6 lists AI coaching
  as deliberately absent. Drafting a regime only fits if those are rewritten to say the
  user still decides and Mr Delta only proposes a starting point.
- **A smaller step that conflicts with nothing:** Mr Delta reviewing a regime you
  built, for example pointing out that back gets 18 sets a week and chest 10, and
  leaving every change to you.

---

## Separate fix: deleted regimes on All time

Keep each deleted regime's name from its tombstone row, so the legend and run list
read `Push pull legs (deleted)` in grey. Fall back to a single `Deleted programme`
entry only when no name survives.

---

## Documents to amend before building

These decisions contradict the rules as written, so the rules change first and the
code follows.

- **RULES § 6:** allow streak and habit counts, the Progress tab, and AI analysis,
  which § 6 currently rules out by name as AI coaching. Record each reason.
- **THEME:** the five-tab navigation and the Home composition; the colour rule that
  every hue except the deload orange and the progress blue may be reused, which puts
  lavender on bulk, the Arms bar, the weigh-in habit and Mr Delta, and cyan on cut and
  the Back bar; and one exception for the AI card covering its gradient border, the
  mascot and its animation.
- **CLAUDE.md rule 11:** an exception for Mr Delta's voice, and a note that `programs`
  in the About text is deliberate.

## Order of work

One piece at a time. Each step that changes the app ends with `flutter analyze &&
flutter test` passing, a run on the Android emulator to check it behaves correctly,
and screenshots of every new or changed screen. The next step starts only after the
owner approves those screenshots.

**1.17.0, navigation**

1. Commit this roadmap folder.
2. Amend the documents for 1.17: THEME (five tabs, Home, More, the Habits tile, the
   Weigh-ins screen), RULES § 6 (habit counts, the Progress tab, bodyweight's new home)
   and the CLAUDE.md note on `programs`.
3. The tab shell: five tabs, the More icon, Settings renamed More, its Bodyweight
   section removed.
4. Home: the Workouts hero moved unchanged, the Past sessions card, the calendar icon
   removed from the masthead. The tab's code is renamed to match, as its own
   refactor commit before any behaviour changes: `lib/features/workouts/` becomes
   `lib/features/home/`, `workouts_screen.dart` and `workouts_providers.dart` become
   `home_screen.dart` and `home_providers.dart`, `WorkoutsScreen` and
   `workoutsProvider` become `HomeScreen` and `homeProvider`, and
   `test/features/workouts_screen_test.dart` becomes `home_screen_test.dart`. RULES
   § 2's "Workouts loads through one snapshot" is renamed with them. Names that
   mean a workout itself stay: `workout_notifications.dart`,
   `workout_detail_screen.dart`, `live_workout_vs_editing_test.dart`, the `Workout`
   table and everything in `lib/data/` and `lib/domain/`.
5. Habits: the two tiles, their + and play buttons, and the Weigh-ins screen with the
   trend card and the year maps.
6. Progress: Cycle progress and Weekly volume moved unchanged. Their files move from
   `lib/features/home/` to `lib/features/progress/`: `all_time_screen.dart`,
   `cycle_progress_providers.dart`, `regime_progress_screen.dart`,
   `region_volume_screen.dart`, `volume_history_screen.dart`, `volume_providers.dart`,
   and the strength card and volume widgets. The consistency heatmap files stay
   with Home, whose Workouts tile opens them.
7. More: the profile header, the Account row and the new About text.
8. Release 1.17.0: version bump and changelog entry.

1.17.0 shipped on 16 October 2026 (`bd35ca3`, tag `v1.17.0`).

**1.18.0, phases**

1. Amend the documents for 1.18: THEME (the Phase card, the phase sheet, the phase
   tints on the cycle chart and the Phase card's graph, and the colours: bulk lavender,
   cut cyan, maintenance grey), RULES § 6 (phases as a recorded exception, with the
   reason), and SYNC.md (the new syncable table, how it merges, and that it is never a
   question asked at the bar).
2. The data: the `phases` table through the full migration ladder (`tables.dart`,
   regeneration, a default in `table_spec.dart`, an idempotent `upgradeSchema` step),
   the server rung with row-level security and its pgTAP test, push and pull, backup
   export and restore, and the invariants. Plus the pure domain functions in
   `lib/domain/` with their tests: the phase on a given day, the phase most of a cycle's
   sessions ran in, the weekly rate of change, and the two staleness checks. No screen
   changes in this step.
3. The Phase card on Home and the phase sheet: set, change or clear a phase, its start
   day from the existing day picker, and the optional planned length; the card's figures
   and its bodyweight graph tinted by phase.
4. The staleness prompts on the Phase card: when the planned length has passed, and when
   the weigh-ins have run against the phase for about three weeks. Never a notification.
5. The cycle progress chart: phase tints behind each cycle, the phase in the readout, and
   the legend; deloads drawn exactly as today with no tint beneath them.
6. Release 1.18.0. Before the release commit, run the pgTAP tests with Docker and the
   local Supabase stack up: `phases_rls_test.sql` (added in `d5741ac`) has not run yet.
   The changelog needs Upgrade notes for schema 7 and `supabase db push`.

1.18.0 shipped on 16 October 2026 (`1f8208a`, tag `v1.18.0`), with its server migration
applied the same day.

**1.19.0, charts**

Each step works through the findings in [`chart-audit.md`](chart-audit.md); the
numbers in brackets are its finding numbers.

1. Amend THEME's chart sections first: the outlier policy (23), the line-chart heights
   (two at most), one legend component, card padding, and where the range control sits.
2. One shared y-range function for every chart: the line leaving the plot past +200%
   (1), labels that repeat or misstate their gridline (3), a single value drawing one
   gridline (4), the volume chart's pile of labels (7), the cycle axis drawing one
   gridline instead of three (11) and its half-empty band (24).
3. One shared, measured ladder of date labels: colliding labels (5), bar charts whose
   last label is not today (8), repeated months on 3M (9), uneven years on long ranges
   (10), and the cliff to yearly bars at five years (19).
4. Gaps and jumps: lines break at empty buckets (2) and a resumed regime's jump is
   dashed (12).
5. Density decided by pixels rather than counts: clumping or vanishing markers (15),
   volume tiles merging into texture at 52 weeks (18), and the one-week slab and
   collapsing gutter on the volume chart (17).
6. Long cycle charts and sparklines: deload hairlines turning long charts orange (13),
   sparklines that keep chart furniture (14), and too many orange labels (25).
7. Bodyweight parity and text scale: bodyweight refusing one dot and captioning an
   empty range (16), dropped or truncated units (21), the bar list count column at
   three digits (6), year-heatmap labels below 11 sp (22), the readout wrapping (26),
   and the exercise trend's `Change` figure mixing sessions and painting a drop red
   (20). Also on the Weigh-ins screen: replace the floating `Log weight` button,
   which covers the current months of the year map, with a round `+` in the app bar
   beside the calendar button, matching the `+` on the Home tile (see the prototype).
8. Spacing across chart cards: the spacing table at the end of the audit (heights,
   legends, gaps, padding, the range control's position) plus the remaining polish
   findings (27 to 33).
9. Release 1.19.0. Before the release commit, re-run the audit's chart harness at every
   data size and confirm each finding is fixed or deliberately kept, then the version
   bump, the changelog and a final emulator pass.

**Then** 1.20.0 AI analysis, broken down the same way when it starts. The deleted-regime
legend fix can land in any patch release.

## Versioning

Every release above is a minor version, following the changelog's rule that a minor
release adds behaviour and a patch release only corrects it. That is how this repository
already treats schema changes: a new table or column is a minor release whose
**Upgrade notes** say that the local schema migrates on first launch and that the server
migration must be applied before installing on a synced phone. A backup written by the
new schema is refused by older builds, which say so; that is expected, not a break.

1.18.0 is such a release. Its changelog entry needs Upgrade notes for the `phases`
table: the schema version it migrates to, and `supabase db push` before installing on a
synced phone.

A 2.0.0 would mean the app stops honouring something it has promised: no longer
restoring backups written by older versions, a migration path removed so an old install
cannot upgrade, or logged data reinterpreted. None of the planned work does that.
