# Deltoid — the list

Status only, one line per item: what is done, what is left. Why anything is
shaped the way it is belongs in [THEME.md](THEME.md), [RULES.md](RULES.md) and
[SYNC.md](SYNC.md), and the code carries the detail.

**1,099 tests and nine pgTAP tests, analyzer clean.**

---

## Done

### Core model

- [x] Regimes, sessions, slots and cycles; a cycle advances on work done, not on the calendar.
- [x] Deload after N cycles, per regime and overridable per slot.
- [x] Prefill scoped to the session, with ghost text and adoption on tick. A session with no history of its own opens blank; the ⓘ names where the movement was last done and fills nothing in.
- [x] Logging writes snapshots, so editing a programme never rewrites history.
- [x] Six regimes, one active, each with an identity hue and a unique living name.
- [x] The exercise catalog archives rather than deletes; starter catalog seeded, no regime ever is.
- [x] Stale open sessions: empty ones swept, ones with sets kept and offered Finish or Discard.

### Logging

- [x] One exercise per page: typed sets, set types, drop groups, delete, swap, skip, move, add mid-session, notes at three levels, force-stop recovery.
- [x] Docked keypad, stepped by the plate increment, last time's value one tap away.
- [x] Plate view inside the keypad, for a movement that knows its bar.
- [x] Rest timer with tone, wakelock, an OS exact alarm and an ongoing notification.
- [x] Rest is three numbers: per exercise in a day, a default in Settings, and one for the walk between exercises. The old fourth reading — the last rest a set happened to take — is gone.
- [x] The alarm is armed as the rest starts, not as the app leaves; the app takes it back 400 ms early so exactly one alert lands, whichever half rings it.
- [x] The session line is a foreground service, so the rest bar on it can drain a second at a time — a progress bar holds the last value posted to it, and a frozen app posts nothing. The chronometer went with it: the system draws that in the header's far corner, and the time left belongs beside the bar. Between sets there is no bar at all.
- [x] The rest tone can be turned off in Settings. The buzz is not part of the switch.
- [x] The exercise's own screen opens from the log's ⋯ menu, so a day's rest, bar and targets are editable without leaving the session.
- [x] The bar is per training day, and the bar a set was logged on is snapshotted onto the row — the plate diagram stopped reading the catalog live. Schema 3 → 4, server rung included.
- [x] Ticking advances the keypad to the next open set, across pages, and closes on the last.
- [x] Partial reps logged apart from full ones, shown as `8+3`, out of volume, e1RM and `beatsPrevious`.
- [x] Isometric holds through `MeasureMode`, with a stopwatch in place of the keypad.
- [x] Session summary: volume, sets, time, the session note, a recap and the offer to keep programme changes.

### Reading it back

- [x] History pages by keyset, indexes every exercise trained, opens a workout from its own snapshots.
- [x] Trend chart: e1RM or top weight, one line per session slot, deloads excluded, stalls flagged, pinch to zoom, holds in seconds.
- [x] Consistency heatmap, eighteen weeks on Workouts with the all-time view behind it.
- [x] Weekly muscle volume, six regions counted in SQL, arms and legs folding open.
- [x] Volume history screen: six tiles, one bar per week, averages over every week in the span.
- [x] A region opens onto a full chart plus the movements that produced its sets.
- [x] `workout_exercises.muscle` snapshots what a movement trained when it was logged.
- [x] Bodyweight log: monthly groups with deltas, its own trend, interpolated into every bodyweight lift.
- [x] The trend chart draws in the same frame as the list under it — 130ms to 26ms, same numbers.
- [x] An empty chart is still a chart: axes, gridlines, no sentence written across it.
- [x] History's exercise search falls through to the catalog.
- [x] Every chart folds through `chart_buckets.dart` and shares one control row, one axis and one transition.
- [x] Workouts arrives whole: every read it draws starts in the same frame, and no section drops in after the page.

### Cycle progress

- [x] The domain: a lift is a session and an exercise, a cycle's point is the mean change across the lifts in it, a deload scores nothing, and every cycle is measured against cycle 1 of its own regime — never against the last deload, and never reset.
- [x] The read walks a regime through its cycles rather than scanning every workout ever logged, and is watched on the shape of the log rather than on `set_logs`, so a whole regime is not re-scored on every set ticked.
- [x] The cycle axis on the one trend chart: deload bands, hairlines once `All` thins to blocks, a hollow open cycle, a tap-to-read line and a y band that never anchors at zero.
- [x] The strength card replaces Last session on Workouts, and carries its three states — trained, a first cycle, nothing trained.
- [x] The regime screen: the same card, how the number is arrived at folded away, and every lift grouped Stronger, No change and Weaker with the two sets behind each.
- [x] All time: one year of weeks at a time with two legends, the spells behind a fold, and a card per regime.

### Around the edges

- [x] Backup export, restore and auto-export after a session, on an isolate, round-trip tested.
- [x] Settings: units, three themes drawn as miniatures, adaptive launcher icon.
- [x] One day picker for backfill, bodyweight and re-dating. A ring on every day in range — its own colour when something is logged there, grey when nothing is — a dot on today, nothing on a day that cannot be picked, and a stated reason when one is tapped. Six full rows with the neighbouring months drawn back, turned by a drag or by either end of the month bar.
- [x] Backfill asks for the day first and keeps it on screen.
- [x] The system bars take their appearance from the app's own theme, said again once the launch window lifts — in the light theme the status bar had been white on white.

### Sync

- [x] 0–4 · The ground, the server, identity, push, pull — every row of SYNC § 12 a test, and the two-device fuzz converges.
- [x] 5 · Adoption: the three shapes at sign-in, the `starterKey` dedup, and the losing side written to a backup file first.
- [x] 6 · The states and the failures — Settings says which state, for how long and why; the second door of § 11; the empty state for a phone that has never had signal; sign-in from Settings runs adoption, same flow as the welcome screen.
- [x] A first pull shows progress, behind the sheet the export and the restore already use. Background drains show nothing.
- [x] The duplicate catalog is folded between the pull and the push of every drain, not only at a sign-in.
- [x] A backup button in the header of every tab and the log: green online, yellow with a count offline, opening onto what is only on this phone by session. An offline token refresh is no longer reported as a lost change.
- [x] The Supabase project exists, the schema is on it, and the nine RLS tests pass against a real Postgres.

### The rebrand

- [x] 0 · Foundation — tokens, type roles, primitives, nav bar.
- [x] 1 · Workouts.
- [x] 2 · Log.
- [x] 3 · History and workout detail.
- [x] 4 · Progress folded into History; the tab is gone.
- [x] 5 · The Regime cluster.
- [x] 6 · Settings, bodyweight log, all-time heatmap.
- [x] Feel — ink, folds, damped scrolling, no spinner over existing content.

### Hardening

- [x] The gate: `hooks/pre-push` runs analyze and test, plus four lints including `unawaited_futures`.
- [x] Both audits run and worked through — can it corrupt data, and are the numbers right.
- [x] A found-after-the-audit hole: two installs could share one `device_id`, and the pull applier read `(updated_at, device_id)` as a version identity. Auto Backup is refused, and the pair is compared by value.
- [x] The merge order has a last resort: two versions on one stamp and one device id are separated by the rows themselves, so both phones pick one winner instead of each keeping its own.
- [x] The connection's four pragmas are asserted off a real file rather than described in a comment — `synchronous` is `FULL`, so no commit is traded away.
- [x] `lib/data/db/invariants.dart`: twenty rules in SQL — seventeen structural, three about the sync columns — each with a perturbation test.
- [x] A backup arrives by rename, so a write that dies never leaves a truncated file under a real backup name.
- [x] The columns a merge decides on are judged too: a stamp at the epoch, a stamp past any clock, a row naming no device.
- [x] The oracle ships — a restore refuses a file it cannot put back, and a pull says what the repairs could not reach.
- [x] The stamp clamp survives a restart, so a phone whose clock moved backwards cannot lose every row it wrote to the version it replaced.
- [x] `test/integrity/model_fuzz_test.dart`: 1,350,000 operations, no violation, survives an unclean shutdown.
- [x] Queries that grow with the log are raw SQL behind a parity test against the drift path.
- [x] The volume screen stops querying when you leave it.
- [x] No painter clamps to a bound it computed.
- [x] Exceptions to THEME are written into THEME, enforced by a test.
- [x] Both colour ramps measured pair by pair; the four pairs under AA are named in THEME.
- [x] A deep fuzz campaign — 200 model seeds and 100 two-phone seeds — and the one
      bug it found: reopening a cycle assumed the only open one could be numbered
      above it, which stops being true once a merge re-numbers.
- [x] The active flag is derived from `regimes.activated_at`, not merged: it is one
      answer spread over every row, and resolving it row by row let two phones
      settle on opposite ones permanently. Ten seeds of 1,577 found it.
- [x] Where each load-bearing rule is checked: [RULES § 7](RULES.md#7-working-on-it).

---

## Left

**Rebrand 7 · Reconciliation**, above, and nothing else. The light theme has
been checked on five empty screens, and its status bar is no longer white on
white; everything that needs a populated log is still unchecked.

Sync is built and its design is settled. Two numbers in `sync_engine.dart` — a
20-minute backstop and a 4-second debounce — are placeholders by design rather
than oversights, and [SYNC § 16](SYNC.md#16-still-to-decide) says why they can
only be chosen against a phone and a real week.
