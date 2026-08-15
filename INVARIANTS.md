# Deltoid — the data-integrity invariants

What must be true of the rows on disk, where each rule is enforced today, and
what would violate it if nothing did. Produced by
[HARDENING.md § 2a](HARDENING.md#2a-invariantsmd-can-it-corrupt-or-lose-data).

**Analysis only.** No code changed to produce this.

Scope is one question: *can this app lose, silently alter, or corrupt logged
training data?* Anything that cannot belongs in [DEBT.md](DEBT.md).

## How to read an entry

- **PROVED** — the claim is read off the code cited. **SUSPECT** — the shape is
  there, the reachability is argued rather than demonstrated.
- **Severity**: `CORRUPTION` (data wrong or lost) / `STALE` (data right, shown
  wrong) / `COSMETIC`.
- Every claim carries `file:line` or says `unverified`.
- **CLOSED** — the check named by the entry exists, was red first, and is now
  passing. A closed entry keeps its number and stays where it is rather than
  moving tier: the numbers are referenced from thirty other entries and from
  [HARDENING.md § 3](HARDENING.md#stage-3--build-the-net), and a renumber per
  close would break them all. The tier headings count what is still open.

## The short version

The schema is in unusually good shape. **Nine unique indexes, fifty-one CHECK
constraints and thirty-one transactions already hold most of what matters** —
counted at `grep -c 'CREATE UNIQUE INDEX' lib/data/db/tables.dart`, `grep -o
'CHECK (' lib/data/db/tables.dart | wc -l`, and `grep -rn 'db.transaction('
lib/`, of which 28 are in the two repositories, 2 in `seeder.dart` and 1 in
`backup_service.dart`. The places where a rule is only prose are mostly narrow.
The catalogue below is 31 entries; **eight are CORRUPTION**, four of those were
the same shape — a parent tombstoned without its children, entry 1, now
**closed** — and two more were the export and restore paths, both now closed
too.

The audit checked the six writers HARDENING named. `ensureOpenCycle`,
`_healDuplicateOpenCycles`, `logBodyweight` and `completeWorkout` each open their
own transaction; `createExercise` is a single insert and never needed to be;
`_tombstoneChildren` is **not** transactional and borrows atomicity from both of
its callers — entry 29.

Two of HARDENING's sweeps came back clean and are recorded rather than omitted:
every hard delete in the app is one of the restore's nine `clear()` closures
(entry 30), and no read path outside the backup codecs drops
`deleted_at IS NULL` except the one entry 31 names.

---

# Tier 1 — CORRUPTION

Eight entries, **five closed**. Four were one bug in four places — that is entry
1, closed; entry 2 is closed with it. Entries 4 and 6 are the restore, also
closed, and entry 5 is the export, closed. Entry 3 belongs to § 3b; entries 7
and 8 are positions and are what is left.

---

## 1. A tombstoned parent tombstones every live row beneath it

> **CLOSED.** `write_integrity_test.dart` → `a tombstoned parent leaves nothing
> live beneath it`, four tests, **red first** against the code as it stood:
>
> ```
> removing an exercise mid-session takes its sets     Expected: <0>  Actual: <3>
> swapping an exercise takes the sets logged into…    Expected: <0>  Actual: <3>
> deleting a training day takes its slots             Expected: <0>  Actual: <6>
> deleting a programme takes its cycles and nothing…  Expected: <0>  Actual: <1>
> ```
>
> Fixed in `removeExerciseFromWorkout`, `replaceExerciseInWorkout`,
> `deleteSession` and `deleteRegime`; the four counts and both companion
> assertions now pass, and the full suite is green at 561.
>
> **The entry stays here in full.** Its exception list is not a record of a bug
> that was fixed, it is the rule the fix had to stop at, and the § 3b harness
> needs both halves.

**Invariant.** For every `set_logs` row with `deleted_at IS NULL`, its
`workout_exercises` parent has `deleted_at IS NULL`. Likewise
`workout_exercises` → `workouts`, `session_exercises` → `sessions`, and
`cycles` → `regimes`.

**Read the exceptions below before acting on this.** The edge list is
deliberately narrower than "every foreign key", and widening it would delete
history.

Mechanically: each of these queries must return zero rows.

```sql
SELECT COUNT(*) FROM set_logs s JOIN workout_exercises we ON we.id = s.workout_exercise_id
  WHERE s.deleted_at IS NULL AND we.deleted_at IS NOT NULL;
SELECT COUNT(*) FROM workout_exercises we JOIN workouts w ON w.id = we.workout_id
  WHERE we.deleted_at IS NULL AND w.deleted_at IS NOT NULL;
SELECT COUNT(*) FROM session_exercises se JOIN sessions ss ON ss.id = se.session_id
  WHERE se.deleted_at IS NULL AND ss.deleted_at IS NOT NULL;
SELECT COUNT(*) FROM cycles c JOIN regimes r ON r.id = c.regime_id
  WHERE c.deleted_at IS NULL AND r.deleted_at IS NOT NULL;
```

The second count is the one `healOrphanedSnapshots` already repairs, and it is
here rather than omitted as solved: the § 3b harness needs it as an assertion to
prove the heal keeps working, not as a hole to close.

### The exceptions, and why widening this is a stop

**`workouts` → `regimes` is deliberately live.** `deleteRegime`'s own doc says
so (`regime_repository.dart:201-204`): *"Workouts hold their own snapshots and
stay in History exactly as they were logged"*. No history read joins `regimes`
at all — `_workoutsOlderThan` filters on `workouts` alone
(`training_repository.dart:1443-1444`). A count asserting this edge would fire
on correct behaviour.

**`sessions` → `regimes` must NOT be cascaded, and this is why the invariant
above no longer claims it.** `loggedSessions` filters
`db.sessions.deletedAt.isNull()` (`training_repository.dart:1592`), so
tombstoning a regime's sessions removes every one of them from History's session
filter — the list of things you can page history by. Cascading here to satisfy a
tidier rule would silently delete the one navigation path onto a retired
programme's history.

**`workouts` → `sessions` is live for the same reason**, stated at
`regime_repository.dart:440-441`: *"past workouts keep pointing at the session,
so history survives a programme change"*.

So the rule is not "no live row under a tombstoned parent". It is: **a
tombstoned row takes the rows that only exist to describe it, and never the rows
that record what was done.** `session_exercises` describe a session;
`workouts` record training under it. That distinction is the whole content of
this entry, and stage 3 must implement it rather than the general form.

**Enforced today — everywhere, since the close.** The four `no` rows are what
this entry was:

| Path | Takes its children? | Evidence |
| --- | --- | --- |
| `deleteWorkout` | yes | calls `_tombstoneChildren` |
| `abandonWorkout` | yes | same |
| `healOrphanedSnapshots` | yes, at launch | wired at `core/providers.dart:37` |
| `completeWorkout` (unticked sets) | yes | one transaction with the status write |
| `removeExerciseFromWorkout` | **yes, now** | was a lone `workout_exercises` write; now a transaction around `_tombstoneSetsOf` and the slot |
| `replaceExerciseInWorkout` | **yes, now** | tombstones the displaced slot's `set_logs` inside the transaction it already had |
| `deleteSession` | **yes, now** | was a lone `sessions` write; now a transaction taking its `session_exercises` |
| `deleteRegime` | **yes, now** | takes its `cycles`. Its `sessions` and `workouts` staying live is **correct** and is asserted — see the exceptions above |

The shared write is `_tombstoneSetsOf`, which is deliberately **not** a
transaction of its own: it is half of a cascade and each caller owes the other
half. That is entry 29.

`healOrphanedSnapshots` does **not** close these. Its predicate is
`workout_exercises.deleted_at IS NULL AND workouts.deleted_at IS NOT NULL`
(`training_repository.dart:536-537`) — it looks one level up only, and only at
the workout. Nothing in the app looks for a live `set_log` under a tombstoned
`workout_exercise`, or a live `session_exercise` under a tombstoned session.

**PROVED** — read directly off the four write paths.

**How a user reaches it.** Swap an exercise mid-session after logging two sets
into it (`replaceExerciseInWorkout`); or delete a training day from the Regime
screen (`regime_screen.dart:503`); or delete a regime
(`regimes_screen.dart:360`). All three are ordinary actions.

**What each path owes.** `removeExerciseFromWorkout` and
`replaceExerciseInWorkout` owe their `set_logs`; `deleteSession` owes its
`session_exercises`; `deleteRegime` owes its `cycles` **and nothing else**.

**What it costs today.** Almost nothing visible: every read that carries a number
joins the parent and filters `deleted_at IS NULL` — `_volumeQuery` at
`training_repository.dart:841-855`, `workoutDetail` at `:2291`,
`exerciseProgress`'s `live` predicate at `:1857`.

**One read does not, and it is worth naming**: `restTargetFor` (`:2175-2187`)
joins `workout_exercises` but filters only `set_logs.deleted_at`, so the rest
timer can open on a value logged into a slot that was later swapped away. A rest
target rather than a logged number, so it costs nothing on disk — but "nothing
reads an orphan" is not true, and the next path added will not be checked
against a rule nobody wrote down. See entry 31.

**And it removes the bound entry 2 relies on.** `doneSetCount` (`:3008-3021`)
filters `workout_exercises.deleted_at IS NULL`, so ticked sets orphaned by
`replaceExerciseInWorkout` do not count as work done. That is what makes entry 2
able to sweep a workout the user actually trained.

**What it costs after SYNC.md.** These are live rows carrying `dirty = true`.
They are exactly what the first push sends
([SYNC.md § 6](SYNC.md#6-push)), and a device that pulls them holds an orphan
forever, because no tombstone will ever arrive to clear it. This is the failure
`abandonWorkout`'s own doc comment describes at `training_repository.dart:3090-3096`
— fixed there and left standing in four other places.

**The check that closes it.**
`test/data/write_integrity_test.dart` →
`a tombstoned parent leaves nothing live beneath it`, parameterised over the four
paths, asserting the four SQL counts above are zero after each — **plus a
companion assertion that the exception edges are still live**: after
`deleteRegime`, its `workouts` and its `sessions` must both still be
`deleted_at IS NULL`, or the fix has cascaded past its boundary. **Exists**, and
was red on all four paths before any `lib/` code moved. What was there before
covered neither: `write_integrity_test.dart:56-145` covers positions, not
orphans, and `training_repository_test.dart:1737` (`discarding a session takes
its sets and snapshots with it`) covers `abandonWorkout` only.

**Severity: CORRUPTION — closed.** Latent locally, certain once there is a
second writer, which is why it was first.

---

## 2. A workout with logged sets is never swept

> **CLOSED.** `write_integrity_test.dart` → `the sweep reads how long ago the row
> was written`, **red first**:
>
> ```
> a backdated session is not swept the moment it is created  Expected: <0>  Actual: <1>
> a session genuinely left open is still swept               Expected: <1>  Actual: <0>
> ```
>
> The sweep now keys on `updatedAt` rather than `startedAt`. The second test is
> the guard that the fix narrowed the sweep instead of disabling it, and the two
> together pin the column choice rather than the behaviour.
>
> Three existing tests in `training_repository_test.dart` aged the row by moving
> `startedAt`, through a helper whose doc comment asserted that
> `startWorkout(at:)` moved only the day key. **That comment was the bug's
> cover** — it is false, and it is why nobody looked. Helper and comment
> corrected with the fix.

**Invariant.** `sweepAbandonedWorkouts` tombstones a workout only when
`doneSetCount == 0` **and** it is genuinely stale.

**Enforced today.** The `doneSetCount` half is enforced at
`training_repository.dart:3081`. The staleness half was
`t.startedAt.isSmallerThanValue(cutoff)`, where `cutoff = nowMs() - 24h`, and is
now `t.updatedAt`.

**The hole, as it was.** `startWorkout(at:)` writes `startedAt` to the
*backdated* moment — `training_repository.dart:2015-2018` and `:2067`. So a
session you are backfilling for three weeks ago was `inProgress` with `startedAt`
three weeks in the past, and was **already past the sweep cutoff the instant it
was created**. `sweepAbandonedWorkouts` runs before first paint on every launch
(`core/providers.dart:28`).

`updatedAt` is the column that cannot be backdated: stamped by `nowMs` on the
insert, re-stamped on every write to the row, and never moved by the backfill
sheet. Ticking a set writes `set_logs` rather than `workouts`, so a session
trained and left open overnight still ages — which is correct, because
`doneSetCount` is what keeps that one.

**PROVED, then demonstrated** — the two lines were unambiguous, and the test
above drove the sequence and watched it delete the session.

**How a user reaches it.** Open the backfill sheet, pick a date last week, get
the log screen, leave without ticking anything, and let Android reclaim the
process. The workout is gone with no message on the next launch.

**Needs a cold start, not a backgrounding.** `sweepAbandonedWorkouts` is awaited
inside `appInitProvider` (`core/providers.dart:28`), which resolves once per
process — returning from the background does not re-run it. That narrows the
window to "the app was killed or restarted before you came back to the
backfill", which on Android is routine rather than rare.

**What is lost.** Bounded to a workout with zero ticked sets — so the exercise
snapshots and the empty set rows, not logged work. It is on this tier because
the *mechanism* is a launch-time delete keyed on a column the app deliberately
backdates, and the bound depends on `doneSetCount` continuing to be checked
first.

**A composition with entry 1 that dissolved when entry 1 closed, recorded
because the reasoning is worth keeping.** `doneSetCount`
(`training_repository.dart:3008-3021`) filters
`workout_exercises.deleted_at IS NULL`. While entry 1 was open, a swap left two
ticked sets live under a tombstoned slot, `doneSetCount` could not see them
through the dead parent, read **0**, and the sweep took a session the user had
actually trained.

Entry 1's fix removes it, and **not** by changing `doneSetCount`: a swap now
tombstones the displaced slot's sets explicitly, so they are discarded by the
user's own action at the moment they stop being visible, and a workout with
nothing else in it is genuinely empty when the sweep looks. Disk agrees with the
screen, which it did not before. The check that would have caught this — `a
swapped-out exercise still counts as work done` — is **green the moment it is
written** now, which by
[HARDENING.md § 3](HARDENING.md#stage-3--build-the-net) rule 1 means it is not
worth writing. What remains is the backdating hole above, which is independent
of entry 1 and still open.

**The check that closes it.**
`test/data/write_integrity_test.dart` →
`a backdated session is not swept the moment it is created`: start a workout with
`at: 3 weeks ago`, run `sweepAbandonedWorkouts()`, assert the workout is still
`inProgress` and not tombstoned. **Exists**, plus its guard. What was there
before covered three sweep cases, none of them backdated — and aged the row
through the column the bug lived in.

**Only those two.** The companion check the composition above suggested is green
against the code as it now stands, so it is not written — see the paragraph
above for why, and rule 1 for why a green-on-arrival test is worse than none.

**Severity: CORRUPTION — closed.**

---

## 3. A keystroke that reached the screen reaches the disk

**Invariant.** Once a digit is drawn in a set cell, it is either written to
`set_logs` or the user is told it was not.

**Enforced today — by convention, not by a mechanism.** The log screen debounces
writes 300 ms (`log_screen.dart:896`) and flushes on: the next cell
(`:940`), dismiss, page turn, `dispose` (`:203`), and every
`paused`/`hidden`/`detached` lifecycle callback (`:234`). Failures are surfaced
through `reportOnError` (`:915`, `:919`, `:933`) — the channel
[RULES.md § 4](RULES.md#4-code) describes.

**The hole is wider than "no lifecycle callback fired".** `_flushWrite`
(`log_screen.dart:899`) returns `void` and does not await the write it starts:
each branch is `repo.updateSet(...).reportOnError(...)` (`:913-915`, `:917-919`,
`:930-933`), a future dropped on the floor by design, because
`didChangeAppLifecycleState` is a `void` callback (`:221`) and **structurally
cannot await anything**. Neither can `dispose` (`:203`).

So the flush at `:234` *starts* the write on the way out; it does not finish it.
What the lifecycle path actually buys is not "the keystroke is safe" but "the
keystroke is in flight" — one drift isolate round trip plus an fsync, at the
exact moment Android is tearing the process down. The comment at `:227-233`
claims the stronger property and is wrong about it.

**PROVED** — read off the signatures; `_flushWrite` has no `await` and no
`Future` return, and no caller could await it if it did. **SUSPECT** for how
often the race is lost, which needs a device and is the same evidence
[DEBT.md § 6](DEBT.md) is waiting on.

**How a user reaches it.** Type `82.5`, phone dies inside 300 ms — or type
`82.5`, background the app, and have Android kill the process before the write
lands.

**What is lost.** One field of one set. The set is not lost — the tick is a
separate un-debounced write (`log_screen.dart:988-995`), which is dropped on the
floor the same way.

**The check that closes it.** Crash injection, and only that — this belongs
wholly to [HARDENING.md § 3b](HARDENING.md#3b-the-fuzz-harness).

**Do not write the widget test.** `test/features/` → `a pending keystroke is
flushed before the widget goes`, driving `didChangeAppLifecycleState(paused)`,
would have to `await pumpEventQueue()` before asserting — at which point the
in-flight write has landed and the test is **green the moment it is written**.
That fails [HARDENING.md § 3](HARDENING.md#stage-3--build-the-net) rule 1, and
worse, it would stand as evidence for a property nobody has actually checked.
The only honest check kills the process between the callback and the commit.

**Severity: CORRUPTION** (bounded to one field, and to the flight time of one
write rather than to the 300 ms debounce).

---

## 4. A restore either replaces the database entirely or changes nothing

> **CLOSED — and the check was green the moment it was written.**
> `backup_service_test.dart` → `a row violating a CHECK leaves the pre-restore
> database intact`: a payload carrying `cycleIndex: 0` against
> `CHECK (cycle_index >= 1)`, restored, expecting a throw and an unchanged
> census. It passed on the first run.
>
> [HARDENING § 3](HARDENING.md#stage-3--build-the-net) rule 1 says to record
> that rather than dress it up, and this entry had already predicted it: *"the
> current behaviour is correct"*. So it is a **characterisation test**, not a
> bug fixed — it holds the transaction boundary in place for whoever touches
> `restore` next, which is the pull applier. That is the only reason it is
> worth having, and it is a good one.

**Invariant.** After `restore`, the database holds exactly the file's rows, or
exactly what it held before.

**Enforced today.** One transaction (`backup_service.dart:602`), clears children
first (`:624`), inserts parents first (`:627`), foreign keys deferred to commit
(`:615`), identity-slot backfill inside the same transaction (`:668` — moved
there for exactly this reason, per the comment at `:658-663`). A newer `format`
or `schemaVersion` is refused before anything is cleared (`:521`, `:536`).
Covered by `test/data/backup_service_test.dart:224` (`a malformed file is
rejected before anything is deleted`) and `:376`.

**The hole.** `db.batch(b.insertAll(...))` at `backup_service.dart:640` is a
plain insert. A file whose rows violate a CHECK or one of the nine unique
indexes — a hand-edited export, or, once sync lands, a merged history — fails the
whole restore. That is the *right* answer for a file
([SYNC.md § 13](SYNC.md#13-when-it-fails) only exempts the pull applier), and it
is worth stating that **nothing today skips-and-reports a single bad row**. When
5b is written, the pull applier must not reuse this path as-is.

**PROVED.**

**Severity: CORRUPTION** — as a *constraint on future work*, not as a live
defect. The current behaviour is correct.

**The check that closes it.** Exists in part
(`backup_service_test.dart:224`). What is missing: `a row violating a CHECK
leaves the pre-restore database intact` — assert row counts and a known workout
id after a restore that throws.

---

## 5. A backup holds every row the database held when it was written

> **CLOSED.** `_pageOf` (`backup_service.dart:269`) pages by cursor, not by
> offset, and both loops carry the last id written forward. Two checks in
> `backup_service_test.dart` → `an export reads a moving table without losing
> its place`, red first against the offset paging:
>
> ```
> a row arriving behind the cursor is not written twice
>   Expected: <5>  Actual: <4>   a row was written twice
> a row leaving behind the cursor does not take a neighbour
>   Expected: contains all of ['id-4', 'id-6', 'id-8']
>     Actual: ['id-2', 'id-4', 'id-8']
>      Which: has no match for 'id-6' at index 1
> ```
>
> **This entry had the direction backwards** and the correction is worth
> keeping. An *insert* behind the cursor shifts later rows one place **forward**
> and re-reads the boundary row — a duplicate, refused by the restore's primary
> key, loud. A *hard delete* shifts them **back** and steps over the boundary
> row — silently absent. The entry assigned the silent loss to the insert.
>
> Which matters, because it moves what was reachable. Ids are UUID v7, so a
> locally created row always sorts after every existing one and can never land
> behind a cursor; nothing outside the restore's `clear()` closures hard-deletes
> (entry 30). **Neither variant was reachable today.** Both are held off by
> properties of other files that nobody had written down as load-bearing, and
> the first one **stops being true the day sync lands**: a row merged from the
> other phone was created there, earlier, and carries that earlier time in its
> leading bits. That is the argument for fixing it now rather than in Stage 5.
>
> **No transaction, and that is the decision, not an omission.** Drift
> serialises on one connection, so a transaction around a minutes-long export
> blocks every write the app makes for its duration — the freeze the paging
> exists to avoid, arriving mid-session instead. Keyset buys the guarantee that
> matters: no row present for the whole export is missed. A row written *during*
> one may or may not be in the file, and that is what a backup is.
>
> The `betweenPages` seam this needed is `@visibleForTesting` in spirit and null
> in every production path; `pageSize` is injectable for the same reason.

**Invariant.** The file `writeBackup` produces carries exactly the rows each
table contained, none skipped and none written twice.

**Enforced today: nothing enforces this.** `writeBackup`
(`backup_service.dart:331`) walks each table with `..limit(limit, offset: offset)`
ordered by `id` — the nine codecs from `:127` down — a page of 2 000 rows at a
time (`_pageSize`, `:274`), and **awaits `sink.flush()` between pages** (`:367`).
The flush is deliberate and is the reason a long export does not freeze the UI,
stated at `:326-327`.

There is no transaction around any of it. `backup_service.dart` holds exactly
one and it is `restore` (`:602`).

**The hole.** Offset paging is only stable over a table nothing is writing. The
ordering is by `id`, and `newId()` is not monotonic, so an insert landing on an
id that sorts *before* the current offset shifts every later row back one
position — and the row on the offset boundary is **never read**. It is absent
from the file with nothing said. An insert sorting after the offset is written
twice instead, which a later `restore` rejects on the primary key: loud, and
therefore the better of the two.

This is [CLAUDE.md](CLAUDE.md) rule 6 — *history paging is keyset, not offset* —
held everywhere in `training_repository` (`_olderThan`, `:1422-1425`, with the
reason at `:1445-1447`) and not here, in the one path where a skipped row is not
a missing page of a list but a row that stops existing.

`buildPayload` (`:287-291`) has the same shape. It is used by the tests and the
seed tool rather than by the app, which means the round-trip suite walks the
same offsets over the same quiet database and cannot see this.

**PROVED** for the shape — read off the paging loop (`:355-356`) and the absence
of a transaction. **SUSPECT** for reachability, which needs a write to land
between two pages of a running export.

**How a user reaches it.** Tap "back up now" in Settings, leave the screen, start
a session, tick a set. The `flush()` back-pressure is precisely what keeps the
app usable while the export runs, and an export of a long history is minutes
long.

**What is lost.** Nothing on disk — the database is untouched. What is lost is
rows from the file, silently. It is on this tier because that file is the
artefact [SYNC.md](SYNC.md)'s first promise rests on, and a backup that is
quietly short is worse than none: it is discovered at restore time, on the new
phone, after the old one has been wiped.

**The check that closes it.**
`test/data/backup_service_test.dart` → `an export taken while rows are being
written loses nothing` — seed a table past two pages, wrap `codec.page` so an
insert fires after the first page returns, and assert the file's row count
equals the table's. **Does not exist today**: `backup_service_test.dart:235`
compares the streamed file against `buildPayload`, which pages identically.

**Severity: CORRUPTION.**

---

## 6. A restore lands every row the file claims to carry

> **CLOSED.** `backup_service_test.dart` → `a file whose body is shorter than
> its header is refused`, **red first**:
>
> ```
> Expected: throws anything
>   Actual: <Instance of 'Future<ImportResult>'>
>    Which: emitted <Instance of 'ImportResult'>
> ```
>
> A file with one `bodyweight_logs` row removed from the body and its header
> untouched restored silently and reported success, on a database that had
> already been cleared.
>
> `restore` now counts each table after inserting and refuses on
> `landed < declared`, inside the transaction, so the clear rolls back. A third
> test — `a body longer than its header is accepted` — pins the comparison as
> `<` rather than `!=`, because a set logged mid-export makes the body honestly
> longer and refusing that file would be the worse bug.

**Invariant.** After `restore`, each table holds the number of rows that file's
own `counts` header names.

**Enforced today: nothing enforces this.** The header is written from
`codec.count()` (`backup_service.dart:332-335`) **before** a single row is
streamed, and read back by `summarise` (`:544-556`) only to size a progress bar.
The comment there says so outright (`:546-548`): *"The counts are a header, not
the data."* `restore` returns a `rowsWritten` it never compares against them.

**The hole.** A file whose body is shorter than its header restores silently —
and it restores **after** the nine `clear()` closures have emptied every table
(`:624`). Three ways to hold such a file: entry 5's export race, a hand edit,
and, once 5b lands, a merge.

The counts can also disagree honestly, because they are counted before the pages
are read: a row logged mid-export makes the body *longer* than the header. So
the check is `restored < declared`, not `restored != declared`, and entry 5 is
what makes the difference meaningful rather than noise.

**PROVED.**

**What is lost.** Whatever the file was short by, against a database that has
already been cleared, while the screen says the restore succeeded.

**The check that closes it.** `backup_service_test.dart` → `a file whose body is
shorter than its header is refused` — decrement one entry of `counts`, restore,
expect a throw and the pre-restore database intact (entry 4's assertion). Three
lines of comparison, and the format already carries the number they need.

**Severity: CORRUPTION.**

---

## 7. `set_logs.deleted_at` is only ever set forward

**Invariant.** A tombstone is never moved backwards past the row's birth, and a
tombstoned row is never silently revived onto a slot another row holds.

**Enforced today — the first half only.** `_liveOrTombstoned`
(`tables.dart:42`) refuses `deleted_at <= 0` on every syncable table. The nine
partial unique indexes are all scoped `WHERE deleted_at IS NULL`, so a tombstone
frees its slot — tested at `schema_constraints_test.dart:140` and `:445`.

**The hole — revival collides.** `restoreSessionExercise`
(`regime_repository.dart:521`) clears `deleted_at` and **keeps the row's old
`order_index`**. `addExerciseToSession` (`regime_repository.dart:489-500`) picks
`nextPosition` over **live rows only**. So:

1. A session has slots at 0,1,2,3,4. Remove the last one → tombstone at 4.
2. Add a different exercise → `nextPosition([0,1,2,3]) = 4`. New live row at 4.
3. Tap the undo action (`exercise_screen.dart:733`) → revive the tombstone at 4.
4. `idx_session_exercises_position_live` refuses it. The write throws.

**PROVED** by reading the two position computations against the index at
`tables.dart:212-215`. **SUSPECT** on the visible symptom: `restoreSessionExercise`
is called bare at `exercise_screen.dart:733`, with no `reportOnError`, so per
[RULES.md § 4](RULES.md#4-code) the throw reaches
`PlatformDispatcher.onError` and the user sees a toast — or, if it lands
somewhere unhandled, a button that does nothing.

**What is lost.** Nothing on disk. The undo silently fails; the slot's set target
and rep range stay buried.

**The check that closes it.** `test/data/write_integrity_test.dart` →
`undoing a removed slot after another was added still finds a free position`.
**Does not exist today.**

**Severity: CORRUPTION** by the letter of "a write the user asked for does not
happen"; arguably STALE. Ranked here because the fix is the same
`nextPosition`-on-revive that every other append already does.

---

## 8. `renumber` must be handed every live row in its scope

**Invariant.** `renumber(orderedIds, from: …)` may only be called when
`orderedIds` is the complete set of live rows under the parent — otherwise its
second pass writes `0..n-1` over positions a row it never saw still holds.

**Enforced today — by the caller, in prose.** `renumber`
(`db/renumber.dart:25-36`) documents the rule at `:22-24`: *"[from] must be
computed inside the same transaction … over every live row in the scope rather
than only the ones being moved."* That covers the first pass. The **second** pass
(`:33-35`) is what collides, and nothing states or checks that `orderedIds`
itself is complete.

Callers:

| Caller | Complete? |
| --- | --- |
| `applySessionChanges` (`training_repository.dart:1122-1138`) | yes — `wanted` is seeded from `live` at `:1128-1130` |
| `reorderSessions` (`regime_repository.dart:456`) | takes the caller's word |
| `reorderSessionExercises` (`regime_repository.dart:560`) | takes the caller's word |
| `reorderWorkoutExercises` (`training_repository.dart:2648`) | takes the caller's word; `scope` at `:2655` is read but only for `from` |

**SUSPECT.** Every UI call site today passes the full list, so this is not
reachable through a screen. It is reachable from a sync pull applier, which
[SYNC.md § 9](SYNC.md#9-collision--two-rows-one-slot) says will call `renumber`
directly.

**The check that closes it.** `test/data/write_integrity_test.dart` →
`a reorder that omits a live row is refused rather than colliding` — plus an
`assert` in `renumber` comparing `orderedIds.length` against the scope size,
which is the cheap mechanism [DEBT.md § 1](DEBT.md) asks for.

**Severity: CORRUPTION** if reached; unreachable today.

---

# Tier 2 — STALE

Data on disk is right; a screen or a derived number can read it wrong.

---

## 9. `day_key` and `started_at` name the same day

**Invariant.** `dayKeyOf(DateTime.fromMillisecondsSinceEpoch(started_at)) == day_key`.

**Enforced today: nothing enforces this.** The CHECKs at
`tables.dart:347-348` bound each column's *range* and nothing compares them. The
doc comment above them (`tables.dart:334-343`) describes the failure — *"a
restored or merged row could put one session on two different days at once"* —
and then constrains the range instead. This is exactly the pattern
[DEBT.md § 1](DEBT.md) names: a load-bearing comment with no mechanism.

Every write in the app does hold it: `startWorkout` derives both from one
`DateTime` (`training_repository.dart:2064`, `:2067`), and `setWorkoutDate` moves
them together (`:3191-3192`).

**PROVED.**

**How it is violated.** A restore of an edited file, or a merged row after 5b.

**What breaks.** The heatmap and calendar group on `day_key`
(`loggedDays`, `training_repository.dart:732-737`); History pages on `started_at`
(`_olderThan`, `:1422-1425`). The row is ringed on Tuesday and filed under
Monday.

**The check that closes it.** `test/data/schema_constraints_test.dart` →
`a workout cannot claim two different days` — insert a row with mismatched
columns and expect a refusal. Needs a schema CHECK; SQLite can express it
(`CAST(strftime('%Y%m%d', started_at/1000, 'unixepoch', 'localtime') AS INTEGER)`
is *not* safe — it is UTC-relative and the column is local-day). **Does not exist,
and needs a design decision before it can.**

---

## 10. Exactly one open workout, one active regime, one bodyweight per day

**Enforced today, properly, in the database.**

| Rule | Index | Test |
| --- | --- | --- |
| one `inProgress` workout | `tables.dart:316-319` | `schema_constraints_test.dart:381` |
| one active regime | `tables.dart:113-116` | `schema_constraints_test.dart:111` |
| one bodyweight per day | `tables.dart:521-524` | `schema_constraints_test.dart:87`, `:98` |

The Dart guards are second lines rather than the rule: `startWorkout`'s check is
a read outside its own transaction (`training_repository.dart:1972`, documented
as such at `tables.dart:308-315`), and `logBodyweight` wraps look-up and write in
one transaction (`:1778-1779`), tested at `write_integrity_test.dart:167`.

**Nothing to do. Recorded so the catalogue is honest about what is already
held.**

---

## 11. One cycle open per regime, numbered from 1, no duplicates

**Enforced today.** `idx_cycles_regime_index_live` (`tables.dart:268-271`),
`CHECK (cycle_index >= 1)` and `completed_at >= started_at` (`:284-289`).
`ensureOpenCycle` is a transaction (`training_repository.dart:368`), `advanceCycle`
(`:1188`) and `closeCycleIfSatisfied` (`:1243`) each wrap close-then-open so the
regime is never momentarily cycle-less — the race their comments describe at
`:1183-1187`.

`healDuplicateOpenCycles` (`:446`) repairs phones from a build where it was not.
Its two-step shape — cheap scan outside, transaction only when there is work —
is deliberate (`:447-458`) and correct: the scan is advisory, the merge re-reads
inside the transaction at `:477`.

Tested at `write_integrity_test.dart:180`, `:201`, `schema_constraints_test.dart:123`.

**Residual: nothing enforces *one open cycle per regime* in the schema.** The
unique index is on `(regime_id, cycle_index)`, not on
`(regime_id) WHERE completed_at IS NULL`. `healDuplicateOpenCycles` exists
because that gap was reached once. **SUSPECT** that it is now unreachable — the
only writer is a transaction, but a pull applier would be a second one.

**The check that closes it.** A tenth partial unique index,
`ON cycles (regime_id) WHERE completed_at IS NULL AND deleted_at IS NULL`, plus
`schema_constraints_test.dart` → `a regime cannot hold two open cycles`.
**Neither exists.**

---

## 12. Interrupted `completeWorkout` leaves nothing half-finished

**Invariant.** A workout is `completed` with its empty sets tombstoned and its
cycle settled, or it is untouched.

**Enforced today, fully.** `completeWorkout` is one transaction
(`training_repository.dart:2932`) covering the tombstoning of unticked sets
(`:2953`), the status write (`:2971`) and the cycle close (`:2994`). The doc at
`:2918-2924` records that the cycle close used to run after the commit.

`deleteWorkout` mirrors it (`:3244-3258`), and `setWorkoutDate` pulls both cycle
settlements into its own transaction (`:3187-3210`).

**Answer to HARDENING's question — "does an interrupted `completeWorkout` leave a
half-finished workout?" — no, given the journal mode below.**

**`journal_mode` is UNVERIFIED, and it is load-bearing for this entry.**
[SYNC.md § 16](SYNC.md#16-still-to-decide) says `delete`, and nothing in `lib/`
sets it: `_open()` is a bare
`driftDatabase(name: 'deltoid', native: DriftNativeOptions())`
(`database.dart:110`), and `beforeOpen` (`database.dart:52-85`) sets
`foreign_keys`, `busy_timeout` and `optimize` and not this. So the mode is
whatever sqlite3 defaults to under the packaged library — argued, not read off
code, which by this document's own rules makes it unverified rather than true.

**The check that closes it.** `test/data/schema_constraints_test.dart` →
`the database is not in a journal mode that can lose a committed transaction` —
`SELECT * FROM pragma_journal_mode()` and assert it. One line, and it turns the
premise of this entry and of § 3b's crash injection into something the suite
holds rather than something SYNC.md remembers.

**Recovery after an unclean shutdown is also correct**: `openWorkout`
(`:1945`) returns the newest live `inProgress` row, and the single-open index
guarantees there is at most one.

**Nothing to do.**

---

## 13. Prefill never reads a deleted or abandoned performance

**Invariant.** `pastPerformances` returns only live slots on live, `completed`
workouts.

**Enforced today.** `_performances` filters all three
(`training_repository.dart:1351-1354`). `exerciseProgress` uses the same
predicate (`:1857-1858`), and `exerciseHistoryPage` the same again (`:1648-1651`).

**PROVED, and correct.** Tested at `training_repository_test.dart:1698`
(`deleting a workout removes it from every history view`).

**Nothing to do.**

---

## 14. `set_logs.parent_set_id` names a real set in the same exercise

**Enforced — half.** The column is a real reference (`tables.dart:467-468`), so
the id must exist, and `CHECK (parent_set_id IS NULL OR parent_set_id <> id)`
(`:489`) refuses self-parenting. Tested at `schema_constraints_test.dart:72`,
`:597`.

**Not enforced: the head must be under the same `workout_exercise_id`.** A leg
could point at a head in a different exercise, or a different workout, and
SQLite would accept it. Unreachable through the app — `addDropLeg`
(`:2513-2548`) and `setSetType` (`:2581`) always pass a head from the same slot —
and reachable through a restore.

**PROVED** for the gap. **SUSPECT** on the consequence: the log's drop-group
walk (`addDropLeg`'s `while` at `:2538`) is scoped to one slot's `sets` list, so
a cross-slot head would simply never be found — a leg drawn with no head, not
wrong arithmetic.

**The check that closes it.** A trigger or an application-level assert;
`schema_constraints_test.dart` → `a drop leg cannot name a head in another
exercise`. **Does not exist.**

**Severity: STALE.**

---

## 15. Two writers to one row

**Today's writers.** One phone, one drift connection on one background isolate,
`busy_timeout = 5000` (`database.dart:63`). Two concurrent Dart calls to
`updateSet` for one set serialise, and the second wins. That is correct: the
value is the same buffer's latest.

The genuine double-write hazards are all **appends**, and all are already inside
a transaction that reads the position and takes it:

| Path | Transaction | Test |
| --- | --- | --- |
| `addSet` | `training_repository.dart:2421` | `write_integrity_test.dart:147` |
| `addSetAfter` | `:2455` | `training_repository_test.dart:2017` |
| `addDropLeg` | `:2521` | `training_repository_test.dart:2042` |
| `addExerciseToWorkout` | `:2804` | — |
| `addSession` | `regime_repository.dart:359` | `write_integrity_test.dart:97` |
| `addExerciseToSession` | `regime_repository.dart:491` | `write_integrity_test.dart:75` |
| `logBodyweight` | `:1779` | `write_integrity_test.dart:167` |

**PROVED, and this is in good shape.**

**After SYNC.md**, the second writer is another device and every one of those
`max + 1` computations collides — which
[SYNC.md § 9](SYNC.md#9-collision--two-rows-one-slot) already anticipates and
answers. Nothing to add here beyond: **the resolution must go through
`nextPosition` and `renumber`, and entry 8 above is a precondition of that.**

---

## 16. Every update stamps `deviceId`, `updatedAt` and `dirty`

**Enforced today.** Every `.write(...)` in both repositories carries the trio.
Spot-verified across `training_repository.dart` (`:1191`, `:1253`, `:2409`,
`:2632`, `:2874`, `:2971`, `:3130`, `:3198`, `:3250`, `:3298`) and
`regime_repository.dart` (`:192`, `:211`, `:311`, `:341`, `:433`, `:446`, `:512`,
`:525`, `:552`). Tested at `write_integrity_test.dart:419`.

`nowMs` is clamped monotonic (`core/ids.dart:27-30`), tested at
`write_integrity_test.dart:437`.

**One gap, deliberate and documented**: `db.into(...).insert(...)` relies on
`clientDefault` (`tables.dart:27-31`), which is right for an insert.

**Nothing to do.** This is the invariant the codebase holds best.

---

## 17. `app_settings` is not in the backup

**PROVED.** `_codecs` (`backup_service.dart:124-261`) covers nine tables;
`appSettings` is absent, matching
[SYNC.md § 4](SYNC.md#4-what-the-server-holds)'s rule for sync.

For `device_id` this is correct — a restored phone should mint its own
(`database.dart:95-108`).

**For `units` it is a silent behaviour change**: restore onto a fresh install and
`weightUnit()` (`training_repository.dart:2148-2153`) falls back to `kg`
(`units.dart:53-56`), so a pounds user's whole history redraws in kilograms with
nothing said. Storage is unaffected — kg throughout — so no data is wrong.

**Severity: STALE.** Also filed in [INTERPRETATION.md](INTERPRETATION.md) § 5.

**The check that closes it.** `backup_service_test.dart` → `the unit preference
survives a restore`, or a deliberate note in `SYNC.md`/`RULES.md` that it does
not. **Neither exists.**

---

## 18. A restore round-trips every column

**Enforced today, and well tested.** Defaults are spread under each restored row
for every column added after v1 — `barKind` and `measureMode`
(`backup_service.dart:141-143`), `identityIndex` (`:161`), `muscle` (`:229`),
`partialReps` (`:245`). Tested at `backup_service_test.dart:157`, `:182`, `:206`,
`:125` (enum and converter columns), `:235` (streamed file is byte-identical to
`buildPayload`).

**Two residual gaps.**

- **A column added tomorrow with no default here.** The discipline is prose
  ([RULES.md § 3](RULES.md#3-schema-and-migrations) step 3) plus one test per
  column. Nothing fails a build when a new column skips it. **SUSPECT** that this
  will be missed — it already was once per the comment at
  `backup_service.dart:135-138`.
- **A row the current schema does not know.** Unknown top-level keys in a row
  map are passed to `fromJson`, which is generated against today's columns and
  ignores extras — so a *newer* file's extra column is dropped. `summarise`
  refuses a newer `schemaVersion` outright (`:536`), so this is unreachable via
  the file path. It is exactly the case
  [SYNC.md § 14](SYNC.md#14-two-builds-one-account) must answer for pull.

**The check that closes it.** `backup_service_test.dart` → `every column of every
codec has a default or is present in every file` — reflect over
`table.$columns` and assert each name is either in the default map or in a
freshly written payload. **Does not exist**, and it is the one test that makes
step 3 mechanical instead of remembered.

**Severity: STALE** today, CORRUPTION the first time a column is added without
its default.

---

## 19. `WorkoutExercise` and `SetLog` are snapshots

**Invariant.** No write triggered by a programme edit may touch a
`workout_exercises` or `set_logs` row.

**Enforced today — verified exhaustively.** Every writer of those two tables:

| Writer | Touches logged rows for a programme reason? |
| --- | --- |
| `applySessionChanges` (`:1022-1153`) | no — `session_exercises` only, asserted by its doc at `:1015-1017` and by `training_repository_test.dart:935` |
| `updateSessionExercise`, `reorderSessionExercises`, `removeSessionExercise`, `restoreSessionExercise` | no — `session_exercises` only |
| `updateExercise` (`regime_repository.dart:621`) | no — `exercises` only |
| every `training_repository` writer | belongs to the workout being logged |

**The muscle snapshot** is written at log time and read back with a fallback:
`_musclesOf` (`:795`) → `muscle: Value(...)` at `:2091`, `:2821`, `:2886`;
`_loggedMuscle = coalesce([workout_exercises.muscle, exercises.muscle])` at
`:818-819`, mirrored in raw SQL at `:886`. Tested at
`training_repository_test.dart:2352`, `:2369`, `:2397`.

**PROVED. This invariant is held.** The name is deliberately read live rather
than snapshotted (`:932-936`), which is a documented exception, not a leak.

**Nothing to do.** Worth an executable guard anyway — see the closing list.

---

## 20. A restore leaves a state the app's own invariants accept

**PROVED that it can fail in one narrow way.** A pre-v5 file carries no identity
slots, every regime lands on 0, and the backfill at `backup_service.dart:668`
deals them out — inside the transaction, correctly. But the backfill only runs
when **at least one row lacks the key** (`:665-667`). A file that carries
`identityIndex` on every row and has *duplicates* in it — hand-edited, or merged
— restores with two regimes on one hue, which
[RULES.md § 2](RULES.md#2-data) says must never happen. There is no unique index
on `identity_index`; the CHECK at `tables.dart:160` bounds the range only.

**SUSPECT** on reachability: no app path produces such a file.

**Severity: STALE** (a colour, not a number).

**The check that closes it.** A partial unique index on
`regimes (identity_index) WHERE deleted_at IS NULL`, plus
`schema_constraints_test.dart` → `two live regimes cannot share a hue`.
**Neither exists.**

---

## 21. History paging is keyset and holds while history is written

**Enforced today.** `_olderThan` (`:1422-1425`) on `(startedAt, id)`, ordering
`_newestFirst` (`:1427-1430`), filters inside the query at `:1448-1457` and
`:1648-1656` with the reason spelled out at `:1445-1447` and `:1635-1637`.
Tested at `training_repository_test.dart:1304`, `:1326`, `:1438`.

**Nothing to do.**

---

## 22. A restore is checked by the same repairs a launch is

**Invariant.** Whatever validates the database at launch also validates it after
a restore, because a restore is the one act that replaces every row at once.

**Enforced today: nothing enforces this.** Four steps run at launch, all inside
`appInitProvider` (`core/providers.dart:22-38`):

| Step | Wired at | What it catches |
| --- | --- | --- |
| `ensureStarterCatalog` | `core/providers.dart:24` | a database with no exercise catalog at all |
| `sweepAbandonedWorkouts` | `:28` | an open workout with nothing in it |
| `healDuplicateOpenCycles` | `:32` | two open cycles under one regime |
| `healOrphanedSnapshots` | `:37` | a live snapshot under a tombstoned workout |

`BackupService.restore` runs none of them. Its transaction
(`backup_service.dart:602-669`) clears, inserts, backfills identity slots, and
commits; the only thing after it is `ANALYZE` (`:676`). `appInitProvider` is a
`FutureProvider` that resolves once per process, so a restore performed from
Settings — which is every restore that is not a first launch — leaves the file's
rows unexamined until the next cold start.

**PROVED** for the gap: none of the four appear anywhere in
`backup_service.dart`, and `restore` is called from the Settings screen with the
app already running. `ensureStarterCatalog` is the mildest of them — a restored
file carries its own `exercises` — and is listed so the table is the whole of
what a launch does and a restore does not.

**How it is violated.** Restore a file written by a phone that carried duplicate
open cycles — which is exactly the phone `healDuplicateOpenCycles` was written
for, and exactly the history someone restoring an old export has. Nothing looks.
After 5b, a merged file is the same case with no historical excuse.

**What it costs.** Whatever the unrepaired state costs: for duplicate open
cycles, `ensureOpenCycle` picking one of two arbitrarily, a deload counted
against the wrong chain, and "UP NEXT" over a full row of dots — the failures
§ 11's healer exists to undo.

**Severity: STALE** today, because the next launch does repair it. CORRUPTION
if a restore is ever followed by writes in the same session, which the Settings
screen permits.

**The check that closes it.** `backup_service_test.dart` → `a restored database
satisfies the invariants a launched one does` — restore a fixture carrying two
open cycles and assert the counts from § 11 and § 1 are zero without a relaunch.
**Does not exist.** The cheap fix is to call the three repairs at the end of
`restore`, which is where a reader would expect them.

---

## 23. `workouts.cycle_id` names a live cycle

**Invariant.** For every live `workouts` row with a non-null `cycle_id`, that
cycle has `deleted_at IS NULL`.

**Enforced today: nothing enforces this.** The column is a real reference, so
the id must *exist*; nothing says it is not tombstoned.

**The hole.** `_reopenCycleIfIncomplete` (`training_repository.dart:3269-3312`)
tombstones every cycle later than the one it is reopening. It guards that with
`if ((await _completedSessionIds(c.id)).isNotEmpty) return;` (`:3289`) —
**completed** sessions only. A workout that is `inProgress`, or one that was
abandoned, does not count as content, so its cycle is tombstoned out from under
it and the workout is left pointing at a dead row.

**SUSPECT** on reachability: it needs a backdate (`setWorkoutDate`, `:3207`)
that moves a workout across a cycle boundary while a later cycle holds an open
or abandoned workout and no completed one. Reachable in principle, not driven.

**What it costs.** Nothing on disk, and nothing today reads a workout's cycle
through a `deleted_at` filter — so this is the mirror of § 1: invisible locally,
a dangling reference on the wire once there is a second device.

**Severity: STALE.**

**The check that closes it.** A fifth count beside § 1's four —
`SELECT COUNT(*) FROM workouts w JOIN cycles c ON c.id = w.cycle_id
WHERE w.deleted_at IS NULL AND c.deleted_at IS NOT NULL` — asserted by the § 3b
harness after every operation, plus `write_integrity_test.dart` →
`reopening a cycle does not orphan an open workout`. **Does not exist.**

---

# Tier 3 — COSMETIC

## 24. `_prefillOnOpen` cannot serve a stale answer

Read-once and removed (`training_repository.dart:2726`), cleared on every
`startWorkout` (`:2051`). Window is milliseconds, documented at `:312-318`,
tested at `training_repository_test.dart:643`. **Held.**

## 25. `StringListConverter` never fails a result set

`fromSql` swallows both malformed-JSON and wrong-type
(`db/converters.dart:22-32`). **Held**, and it is the right shape — the enum
columns get the same protection from CHECKs (`tables.dart:90-98`, `:400-408`),
walked by `schema_constraints_test.dart:281`.

## 26. `watchQuery` never drops a write that lands mid-read

`db/watch.dart:29-89` — never pauses the subscription, coalesces overlapping
writes, reports errors rather than ending the stream. **Held**, and it is the
answer to [RULES.md § 4](RULES.md#4-code)'s `SELECT 1` trap. Tested in
`test/data/watch_query_test.dart`.

## 27. `createExercise` needs no transaction

`regime_repository.dart:593-619` is a single `insert`. HARDENING listed it among
the multi-statement writers; **it is not one.** Recorded so the question is not
re-asked.

## 28. `healOrphanedSnapshots` and `healDuplicateOpenCycles` are idempotent and
cheap on a healthy database

`:459` returns before opening a transaction; `:539` returns before opening one.
Both run at launch (`core/providers.dart:32`, `:37`). **Held**, tested at
`training_repository_test.dart:1755` and `write_integrity_test.dart:201`.

## 29. `_tombstoneChildren` is not itself a transaction

`training_repository.dart:3117-3140` is a bare helper: it reads the workout's
slots, writes `set_logs`, then writes `workout_exercises`, and opens nothing. It
is atomic because **both** of its callers wrap it — `abandonWorkout` (`:3100`)
and `deleteWorkout` (`:3245`).

**Held today, and recorded because it is a property of the callers rather than of
the helper.** Entry 1 is about to add four more cascading paths; each owes its
own transaction, and reusing this helper does not supply one.

## 30. The only hard deletes in the app are the restore's nine `clear()` closures

HARDENING asked for every hard delete. There are nine, all in
`backup_service.dart` — `:145`, `:162`, `:175`, `:188`, `:201`, `:214`, `:230`,
`:246`, `:259` — all inside `restore`'s single transaction (`:602`), all issued
children-first (`:624`), and all correct: a restore replaces the database rather
than merging into it. Nothing else in `lib/` issues a `DELETE`.

**Held**, and recorded so the sweep is not run again.

## 31. Read paths and `deleted_at`

All 113 `select(db.…)` sites in `lib/` were walked for a missing tombstone
filter. The ones without one are by-id lookups — where the id came from a
filtered query and the caller wants that row's own state — and the nine backup
codecs, which **must** carry tombstones or a restore would resurrect every
deleted row.

**One genuine exception, and it belongs to entry 1**: `restTargetFor`
(`training_repository.dart:2175-2187`) joins `workout_exercises` and filters only
`set_logs.deleted_at`, so it can read a rest value off a set orphaned by
`removeExerciseFromWorkout`. A rest target rather than a logged number, so
**COSMETIC** on its own — listed because it is the counter-example to entry 1's
"nothing visible reads an orphan", and because nothing tests `restTargetFor` at
all ([INTERPRETATION.md](INTERPRETATION.md) § 8).

---

# The smallest set of checks that would justify trusting this with real data

Fourteen, of which **five are done**. Every one is executable, and every one must
be **red first**
([HARDENING.md § 3](HARDENING.md#stage-3--build-the-net) rule 1).

**Five structural invariants, asserted as SQL after every mutation.** These are
the oracle the fuzz harness of § 3b runs against, and they close entries 1, 9,
11, 20 and 23 together:

1. `no live row under a tombstoned parent` — the four counts in entry 1, zero.
   **Read entry 1's exception list before writing this one**: `workouts` under a
   tombstoned `regime` or `session` is correct and must not be asserted, and the
   check needs the companion assertion that those two edges stayed live.
2. `every live position is unique among its siblings` — the nine indexes,
   re-asserted as queries so the harness catches a path that bypasses them.
3. `at most one open cycle per regime, at most one open workout, at most one
   active regime, at most one live bodyweight per day`.
4. `day_key agrees with started_at on every workout`.
5. `every live workout names a live cycle` — entry 23's count, zero.

**Four write-path tests:**

6. ✅ `a tombstoned parent leaves nothing live beneath it`, over
   `removeExerciseFromWorkout`, `replaceExerciseInWorkout`, `deleteSession`,
   `deleteRegime` — entry 1, each asserting only the edges that entry says it
   owes, plus the companion assertions that a deleted regime keeps its workouts
   and its sessions. **Written, red on all four, now passing.**
7. ✅ `a backdated session is not swept the moment it is created` — entry 2,
   with `a session genuinely left open is still swept` beside it as the guard.
   **Written, both red, now passing.**
8. `undoing a removed slot after another was added still finds a free position` —
   entry 7.
9. `a logged workout is byte-identical after every programme edit` — snapshot up
   the `workout_exercises` and `set_logs` rows of a completed workout, run every
   mutator in `RegimeRepository`, assert nothing moved. Entry 19 is currently
   held by inspection; this is what keeps it held.

**Five backup and durability tests:**

10. `every column of every codec has a default or is in every file` — entry 18,
    the one that makes [RULES.md § 3](RULES.md#3-schema-and-migrations) step 3
    mechanical.
11. ✅ `a restore that throws leaves the database exactly as it was` — entry 4.
    **Written, and green on arrival** — the entry said it would be. Kept as a
    characterisation test for the pull applier.
12. `an export taken while rows are being written loses nothing` — entry 5. The
    whole of stage 5a rests on the file being complete, and nothing has ever
    asserted that it is.
13. ✅ `a file whose body is shorter than its header is refused` — entry 6.
    **Written, red, now passing**, with `a body longer than its header is
    accepted` beside it to pin the comparison as `<` rather than `!=`.
14. `the database is not in a journal mode that can lose a committed
    transaction` — entry 12. One `pragma_journal_mode()` read, and it is the
    premise every other durability claim in this document rests on.

**Not on the list, deliberately:** the keystroke window (entry 3) is crash
injection, not a unit test, and belongs wholly to § 3b — the widget test that
looks like it would cover it is green on the first run, which entry 3 explains.
Entries 8, 14 and 15's second-writer cases belong to 5b and cannot be red until
there is a pull applier to make them fail. Entry 22 (a restore is not checked by
the launch repairs) is a one-line wiring fix rather than a check, and lands with
whichever of these touches `restore` first. Entries 29, 30 and 31 are recorded
results rather than holes, and close nothing.
