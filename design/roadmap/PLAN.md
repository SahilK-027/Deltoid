# Deltoid roadmap: 1.17.0 to 1.19.0

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

Cycle progress and Weekly volume move here from Workouts, unchanged.

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

## Dropped: 1.20.0 AI analysis

AI analysis with Mr Delta was designed in full and then dropped on 17 October 2026.
Deltoid has one user, and a question to a model about a log its owner reads every day
does not justify an Edge Function, a key to hold, and a rule exception for a mascot. The
roadmap ends at 1.19.0. The design is kept in this file's history at `cb51122`, should
it ever return.

---

## Separate fix: deleted regimes on All time

Keep each deleted regime's name from its tombstone row, so the legend and run list
read `Push pull legs (deleted)` in grey. Fall back to a single `Deleted programme`
entry only when no name survives.

---

## Documents to amend before building

These decisions contradict the rules as written, so the rules change first and the
code follows.

- **RULES § 6:** allow streak and habit counts and the Progress tab. Record each
  reason. AI coaching stays out of scope.
- **THEME:** the five-tab navigation and the Home composition; the colour rule that
  every hue except the deload orange and the progress blue may be reused, which puts
  lavender on bulk, the Arms bar and the weigh-in habit, and cyan on cut and the Back
  bar.
- **CLAUDE.md rule 11:** a note that `programs` in the About text is deliberate.

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

1.19.0 ends the roadmap. The deleted-regime legend fix can land in any patch release.

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
