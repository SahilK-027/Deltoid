# Deltoid — the list

Status only, one line per item: what is done, what is left. Why anything is
shaped the way it is belongs in [THEME.md](THEME.md), [RULES.md](RULES.md) and
[SYNC.md](SYNC.md), and the code carries the detail.

**808 tests and nine pgTAP tests, analyzer clean.**

---

## Done

### Core model

- [x] Regimes, sessions, slots and cycles; a cycle advances on work done, not on the calendar.
- [x] Deload after N cycles, per regime and overridable per slot.
- [x] Prefill scoped to the session, with ghost text, labelled borrows and adoption on tick.
- [x] Logging writes snapshots, so editing a programme never rewrites history.
- [x] Six regimes, one active, each with an identity hue and a unique living name.
- [x] The exercise catalog archives rather than deletes; starter catalog seeded, no regime ever is.
- [x] Stale open sessions: empty ones swept, ones with sets kept and offered Finish or Discard.

### Logging

- [x] One exercise per page: typed sets, set types, drop groups, delete, swap, skip, move, add mid-session, notes at three levels, force-stop recovery.
- [x] Docked keypad, stepped by the plate increment, last time's value one tap away.
- [x] Plate view inside the keypad, for a movement that knows its bar.
- [x] Rest timer with tone, wakelock, an OS exact alarm in the background and an ongoing notification.
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

### Around the edges

- [x] Backup export, restore and auto-export after a session, on an isolate, round-trip tested.
- [x] Settings: units, three themes drawn as miniatures, adaptive launcher icon.
- [x] One day picker for backfill, bodyweight and re-dating, ringing the days already logged.
- [x] Backfill asks for the day first and keeps it on screen.

### The rebrand

- [x] 0 · Foundation — tokens, type roles, primitives, nav bar.
- [x] 1 · Workouts.
- [x] 2 · Log.
- [x] 3 · History and workout detail.
- [x] 4 · Progress folded into History; the tab is gone.
- [x] 5 · The Regime cluster.
- [x] 6 · Settings, bodyweight log, all-time heatmap.
- [x] Feel — ink, folds, damped scrolling, no spinner over existing content.
- [ ] 7 · Reconciliation — light theme checked on five **empty** screens only. Unchecked, and all of it needs a populated log: chart lines, heatmap ramp, volume bars, a second regime's identity mark, deload orange, the log itself, and motion in either theme.

### Hardening

- [x] The gate: `hooks/pre-push` runs analyze and test, plus four lints including `unawaited_futures`.
- [x] Both audits run and worked through — can it corrupt data, and are the numbers right.
- [x] `test/integrity/invariant_oracle.dart`: sixteen structural rules in SQL, each with a perturbation test.
- [x] `test/integrity/model_fuzz_test.dart`: 1,350,000 operations, no violation, survives an unclean shutdown.
- [x] Queries that grow with the log are raw SQL behind a parity test against the drift path.
- [x] The volume screen stops querying when you leave it.
- [x] No painter clamps to a bound it computed.
- [x] Exceptions to THEME are written into THEME, enforced by a test.
- [x] Both colour ramps measured pair by pair; the four pairs under AA are named in THEME.
- [x] Where each load-bearing rule is checked: [RULES § 7](RULES.md#7-working-on-it).

### Not yet driven on the device

- [ ] Built and tested but never used in a gym: weekly volume bars, volume history screens, muscle chips, isometric holds, hold pad.
- [ ] Never verified on real hardware at all: rest tone, haptics, wakelock, audio ducking, share sheet.
- [ ] Newest and least driven: the ongoing session notification and the scheduled rest alarm.
- [ ] Sync's first half: a real sign-in, a real push, and the row count on the server against the phone's.

---

## Left

Cloud backup, in the seven phases of [SYNC § 18](SYNC.md#18-the-phases). Read
[SYNC.md](SYNC.md) before writing any of it — the design is § 1–16, the code is
§ 17–20.

- [x] **0 · The ground** — migration ladder at `schemaVersion` 2 with every rung idempotent, the nine `dirty` indexes, WAL, the shared table registry both readers answer to, the wire proved, `INTERNET` in the release manifest.
- [x] **1 · The server** — nine tables, RLS on every one with `using` and `with check`, granted to `authenticated` and never `anon`, the `server_updated_at` trigger, a `(user_id, server_updated_at)` index per table, `supabase/migrations` in the repo and proved by pgTAP.
- [x] **2 · Identity** — Google sign-in behind `SyncAuth`, the welcome screen, seeding moved behind its answer, the account section in Settings. Not yet driven on hardware.
- [x] **3 · Push** — the `dirty` drain in keyset pages, parents before children, `dirty` cleared only against an unchanged `updatedAt`; the transport behind an interface with an in-memory fake; four triggers (debounce, resume, connectivity, backstop) with exponential backoff; `SyncScope` at the root; Local / Synced / Pending derived off the database and shown in Settings. The backstop interval is a placeholder until phase 6 chooses it on hardware. Not yet driven on hardware.
- [x] **4 · Pull** — the merge as arithmetic in `domain/sync_merge.dart`, the applier in `pull.dart`: cursor in `app_settings` advanced only after a whole pass commits, one transaction per batch, parents before children, tombstones staying tombstones, a bad row skipped and named, `repairDatabase` after. The engine pulls before it pushes. Every § 12 row this phase owns is a named test against two databases and one fake backend. Not yet driven on hardware.
- [ ] **5 · Adoption** — the three shapes at sign-in, and the `starterKey` dedup.
- [ ] **6 · States and failures** — the three states in Settings, every row of [SYNC § 13](SYNC.md#13-when-it-fails), the backstop interval chosen on hardware.
- [x] **The tests** — the § 12 rows, plus `test/integrity/sync_fuzz_test.dart`: two phones, random operations on both, syncing at random points, the oracle after every step, a real convergence check and *nothing logged is lost*. It found five bugs on its first run — see the commit.

`supabase_flutter`, `google_sign_in` and `connectivity_plus` are in. Driving any
of it needs a Supabase project and Google OAuth clients that only the user can
create — see
[SYNC § 20](SYNC.md#20-what-this-needs-from-outside-the-repo).
