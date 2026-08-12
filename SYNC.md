# Deltoid — cloud backup

Everything about getting a training history off one phone and onto another.
Nothing here is built yet: this is the design, agreed before the code, because
the parts that are expensive to change are the parts you cannot see.

The rules this must not break live in [RULES.md](RULES.md). The screens it adds
are drawn in [THEME.md](THEME.md). What is done and what is left is in
[TODO.md](TODO.md).

1. [What this is, and is not](#1-what-this-is-and-is-not)
2. [The three states](#2-the-three-states)
3. [Identity](#3-identity)
4. [What the server holds](#4-what-the-server-holds)
5. [The write path never changes](#5-the-write-path-never-changes)
6. [Push](#6-push)
7. [Pull](#7-pull)
8. [Conflict — two versions of one row](#8-conflict--two-versions-of-one-row)
9. [Collision — two rows, one slot](#9-collision--two-rows-one-slot)
10. [Adoption](#10-adoption)
11. [Signing out](#11-signing-out)
12. [Every edge case, and what it does](#12-every-edge-case-and-what-it-does)
13. [When it fails](#13-when-it-fails)
14. [Two builds, one account](#14-two-builds-one-account)
15. [What sync may never do](#15-what-sync-may-never-do)
16. [Still to decide](#16-still-to-decide)

---

## 1. What this is, and is not

**A backup you do not have to remember to take.** The app is the only copy of a
history that takes years to accumulate, and a lost phone currently loses it.
There is already an export — a real answer, and one that depends on the user
remembering. This is the same answer without the remembering.

**Correct on any number of devices. Live on none.** Two phones signed into one
account never lose a write, never fabricate one, and never refuse each other's
rows — every shape that can happen has a rule, and [§ 12](#12-every-edge-case-and-what-it-does)
lists all of them. What they do not do is update each other in seconds. A device
catches up when it is opened, when it reconnects, or shortly after it writes.

That line is deliberate. Keep and Notion hold a socket open because two people
edit one document at once; this is one person with a phone in their hand between
sets. Building for seconds-level liveness would cost a held connection and a
battery budget to serve a case that does not occur — while the *correctness* it
is often confused with is built either way, and is built here.

**Not collaboration, and not a feature.** One person, their own devices. No
sharing, no profiles, no feed. A login seen once and never again.
[RULES.md § 6](RULES.md#6-scope) sets that boundary and this document stays
inside it.

**Not what makes the app work.** Offline-first is finished and stays the
architecture. Every screen reads local disk; no read waits on a server; the app
is fully usable with the radio off, forever, whether or not anyone signs in.

---

## 2. The three states

| State | Means | How you can tell |
| --- | --- | --- |
| **Local** | Never connected, or declined at first launch | Settings offers `Back up to your Google account` |
| **Synced** | Signed in, nothing owed | Settings shows when it last ran |
| **Pending** | Signed in, rows owed — offline, or a push that failed | Settings says how many and why |

**Pending is normal, not an error.** A session logged in a basement gym is
pending for an hour and that is the design working. The only thing that makes it
worth mentioning is how long it has been true.

There is no fourth state for "syncing right now". A spinner on a background job
nobody is waiting for is a spinner that teaches the user to wait.

---

## 3. Identity

**Google, through Supabase Auth.** One provider to start. Email is a later
addition and changes nothing below it.

The session is persisted and refreshed silently. A signed-in user sees the
sign-in screen exactly once and never again unless they sign out or the refresh
token is revoked.

**Signing in is never required to use the app.** The one room this app must work
in is a gym basement with no signal, and the moment it would be gated is the
worst one there is: a new phone, a fresh install, standing in that basement. An
existing session works offline indefinitely; only a first launch could ever be
blocked, and it is not. Declining is a real answer — see
[THEME.md](THEME.md) for the screen and why the decline has equal standing on
it.

### Why the anon key stops being a problem

The anon key ships inside the APK and is extractable. With **RLS on every table
keyed to `auth.uid()`**, that key on its own grants nothing: no session, no
rows. This is why the design is worth having auth for at all — the alternative
once considered, an anon key plus a client-asserted `user_id`, is a public
database with a guessable filter.

```sql
create policy "own rows only" on <table>
  for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());
```

`with check` as well as `using`, or a client can write rows it then cannot read.

---

## 4. What the server holds

The nine tables carrying `SyncColumns`, and those only:

`exercises`, `regimes`, `sessions`, `session_exercises`, `cycles`, `workouts`,
`workout_exercises`, `set_logs`, `bodyweight_logs`.

**`app_settings` never syncs.** It holds `device_id`, the unit preference and
the theme — which phone you are on, and how that phone should look. Syncing
`device_id` in particular would break the tie-break it exists for.

### Two columns the server adds

- **`user_id`** — attached from the session as a row is pushed, and the column
  RLS is keyed to.
- **`server_updated_at`** — `now()`, stamped by Postgres on every insert and
  update. **This is the clock conflicts are decided on**, and
  [§ 8](#8-conflict--two-versions-of-one-row) explains why it has to be.

### The local schema does not change

Local rows carry neither of those. They do not need `user_id` — one install is
signed into one account at a time — and `server_updated_at` arrives with a
pulled row rather than being computed by a phone.

`updatedAt`, `deletedAt`, `deviceId` and `dirty` have been on every syncable row
since the schema was written, and the audit that preceded this made all four of
them true. **Nothing in `tables.dart` changes to support sync.**

Server-side, `id` stays the primary key — ids are UUID v7 and do not collide
across devices — with `user_id` indexed beside it.

---

## 5. The write path never changes

A write goes to SQLite and returns. It sets `dirty`, as it already does. That is
the whole of the UI's involvement with sync.

**No screen ever awaits the network.** Not the log, not Settings, not the first
launch. This is [RULES.md § 6](RULES.md#6-scope)'s offline-first rule and nothing
in this document may override it: the app must behave identically with the radio
off, including on the frame after a set is ticked.

So "each update is written to the phone and to the cloud" is true in effect and
not in sequence. The phone is written synchronously; the cloud is written by a
background worker draining `dirty`. Anything else puts a radio between a thumb
and a set.

---

## 6. Push

**What.** Every row where `dirty = true`, oldest `updatedAt` first.

**When.** Debounced after a write settles; on app resume; on connectivity
regained; and on a long idle timer as a backstop. Never on the frame of a
keystroke.

**Order.** Parents before children — the same order `backup_service.dart`
already uses for its codecs — so foreign keys hold server-side at every
intermediate point.

**How.** Batched upserts on `id`. Idempotent, so a retry after a half-finished
push is safe and needs no bookkeeping.

**Clearing `dirty` is the step to get right.** Clear it only for rows whose
`updatedAt` is unchanged since the batch was read. A row edited while its own
push was in flight is still owed, and clearing it on the response would strand
that edit on the phone forever — invisibly, because nothing downstream ever
looks at a row that is not dirty.

---

## 7. Pull

**What.** Rows with `server_updated_at > last_pull_at`, which lives in
`app_settings`.

**When.** On sign-in, on resume, on connectivity regained. Pull before push, so
a conflict is resolved before it is propagated.

**How.** Apply row by row under [§ 8](#8-conflict--two-versions-of-one-row) and
[§ 9](#9-collision--two-rows-one-slot), inside one transaction per batch, in
parent-before-child order.

**Through the repositories, not around them.** A pulled row gets the same
constraints, transactions and stamping as a typed one. A second write path is a
second set of bugs, and it is the path with no screen watching it.

**Advance `last_pull_at` from `server_updated_at`, and only after the batch
commits.** A cursor advanced before the write loses every row in the batch it
did not finish.

**Tombstones arrive as rows.** `deleted_at` set is a delete, applied as a
tombstone, never as a hard delete — a hard delete has no `deleted_at` to push
and would be resurrected by the next pull from the other side.

---

## 8. Conflict — two versions of one row

**Row-level last-write-wins, on `server_updated_at`.** The whole row is taken
from the winner. Ties break on `deviceId`, deterministically, so both devices
reach the same answer rather than each keeping its own.

### Why the server's clock and not the phone's

`updatedAt` is a phone's wall clock. Two phones do not agree on it, and the
disagreement does not average out: a device running ten minutes fast wins every
conflict it is ever in, forever, and the other device's edits vanish silently.

`nowMs` was made monotonic *within* a run during the audit, which is the half of
the problem that is local. Agreement *between* devices is a server's job, and
`server_updated_at` is that answer. The client's `updatedAt` keeps doing its own
job — ordering the offline queue on the device that made it.

### Why not field-level merge

Because for the tables that matter it fabricates data. A `SetLog` is not a bag
of independent fields, it is **one physical event**: "60 kg for 8 reps."

- Phone A: `60 × 8`
- Phone B, stale: `62.5 × 5`
- Merged newest-per-field: `62.5 × 8` — **a lift nobody performed**, and one
  that could stand as a personal record.
- Row-level: one device's complete, coherent set. True, even when it is the
  older one.

Inventing a PR is worse than losing an edit. The same argument holds for
`bodyweight_logs` (one reading), `workouts` (`dayKey` and `startedAt` must move
together, and a field merge could split them) and `cycles` (derived state, only
coherent whole).

The remaining tables are genuinely independent attributes, where a merge would
be safe — but two devices editing one template row at once is rare enough that a
second merge strategy is not worth maintaining for it. **Row-level everywhere.**

### What row-level costs, stated plainly

Phone A ticks a set done. Phone B, stale, edits that set's note and syncs later.
B wins, and the set comes back **un-ticked**. That is losing logged work, and it
is the honest price of this rule.

It is accepted rather than engineered around because the rolling automatic
backup already covers it: `autoExport` writes a full snapshot after every
session and keeps the last four. A conflict archive would be a second net under
a case this app does not produce.

---

## 9. Collision — two rows, one slot

The case row-level last-write-wins **cannot** resolve, because the conflict is
not between two versions of one row. It is between two *different* rows that
both claim a slot the database allows only one of.

The hardening that preceded this added nine unique indexes. Every one is correct
for a single device, and every one is reachable by two devices doing something
entirely ordinary. The first four are not edge cases at all — **appending is the
commonest action in the app, and two devices appending to the same parent both
compute `max + 1`.**

### The rule

> **No merge may ever delete logged work. Re-slot, re-flag or re-number.**

Every resolution is deterministic and symmetric, so two devices reach the same
state without negotiating.

| Index | Two phones doing something ordinary | Resolution |
| --- | --- | --- |
| `set_logs_position_live` | both add a set to one exercise | Both live. Loser takes the next free `setIndex`, ordered by `id` — UUID v7, so creation order, and both devices compute the same answer |
| `workout_exercises_position_live` | both add a movement to one workout | as above, on `orderIndex` |
| `session_exercises_position_live` | both add an exercise to one day | as above |
| `sessions_position_live` | both reorder the training days | as above |
| `sessions_name_live` | both rename a day to the same thing | Both live. Loser keeps its name with a disambiguating suffix; the user renames it |
| `workouts_single_open` | both have a session in progress | Newer stays open. Older is **completed**, never discarded — its sets are real work |
| `regimes_single_active` | A activates PPL, B activates Upper/Lower | The *flag* is the conflict, not the row. LWW on activation; the losing regime survives, just not active |
| `bodyweight_day_live` | both log today's weight | Genuinely the same measurement. LWW, tombstone the loser |
| `cycles_regime_index_live` | both advance the cycle → two "cycle 7" | Both are real cycles. Loser renumbers to the next free index |

Resolution happens in the pull applier, using the repositories' own
`nextPosition` and `renumber` — so a slot is chosen by the same code whether the
row came from a thumb or from a server.

---

## 10. Adoption

### Seeding moves

`ensureStarterCatalog` runs today in `appInitProvider`, before first paint. That
has to change: **the catalog is seeded only after the welcome screen is
answered.**

Without that, a brand-new phone signing straight in ends up with **two catalogs
— roughly 120 exercises**, "Bench Press" twice under different ids, and its
history split across both. That last part is not cosmetic; it breaks the one
thing the app exists for, because per-session progression is keyed to an
exercise id.

Deferring it removes the problem from the common path entirely. Sign in and pull
and the catalog arrives from the account, already carrying the user's own notes
and edits. Decline, or find the account empty, and it is seeded then.

### The three shapes

| Local | Cloud | What happens |
| --- | --- | --- |
| nothing | data | **Pull.** New phone. Nothing to lose. |
| training | empty | **Push.** First sign-in on the phone you have been using. |
| training | training | **Ask.** Below. |

### The third shape

Never resolved silently. Two independent histories share no ids — every id is
UUID v7 — so a merge is not a reconciliation, it is a union, and a union claims
you trained twice as often as you did on any day both sides recorded.

So it asks, once, with the numbers on both sides:

> **This account already has training on it**
> The account has 214 sessions, most recently 3 March.
> This phone has 6 sessions, most recently today.
> `Keep the account's history` · `Keep this phone's history` · `Merge both`

**Whichever side is not kept is written to a backup file first, automatically,
before anything is overwritten.** Same folder as every other export, and the
prompt says so. A decision made once at a sign-in screen must not be the only
thing between a user and a deleted history.

**Merge is offered but is not the default**, and the button says what it leaves
behind. Mechanically it is easy — a union with no id collisions, and most of the
nine indexes in [§ 9](#9-collision--two-rows-one-slot) are scoped to a parent,
so two histories with distinct parents cannot collide on them. What it costs is
readability: duplicated exercises to tidy up, deduped on `starterKey` where the
app seeded them and left alone where the user created them. "Nothing is lost"
and "the result is clean" are different promises, and merge only makes the
first.

Three global rules still apply to a merge: one active regime, one open workout,
one bodyweight per day — resolved as [§ 9](#9-collision--two-rows-one-slot) says.
A merged shelf can also exceed the six identity hues, in which case two
programmes share a colour until one is deleted.

---

## 11. Signing out

- **Sign out** — the session goes, the data stays, the app returns to `Local`.
- **Sign out and remove the history from this phone** — the local database is
  cleared after a confirmation naming the number of sessions.

**Signing into a different account is the second door, forced.** One install is
signed into one account at a time; local rows carry no `user_id`, so mixing two
accounts in one file is not a state the schema can represent. The prompt says so
rather than letting it be discovered later.

---

## 12. Every edge case, and what it does

The list is exhaustive as far as the schema can be reasoned about. **Anything
missing from it is something not yet thought of, not something known to be
safe** — and every row here becomes a test, so a later change that breaks one
fails a build rather than a history.

| # | Situation | What happens |
| --- | --- | --- |
| 1 | Two devices edit **different** rows | Union. Both survive. The overwhelming majority of all sync. |
| 2 | Two devices edit the **same** row | Row LWW on `server_updated_at`, tie on `deviceId`. [§ 8](#8-conflict--two-versions-of-one-row) |
| 3 | Two rows claim one slot | [§ 9](#9-collision--two-rows-one-slot). Nothing deleted. |
| 4 | Both start a session | Newer stays open, older completed with its sets intact. |
| 5 | Both activate a different regime | LWW on the flag. Both regimes survive. |
| 6 | Both log today's bodyweight | Same measurement. LWW, loser tombstoned. |
| 7 | Both append a set, exercise or day | Both survive; loser takes the next free position. |
| 8 | A deletes a workout, B adds a set to it | The set arrives under a tombstoned parent. `healOrphanedSnapshots` already runs at every launch and tombstones it. |
| 9 | Both delete, or one deletes and one restores | `deletedAt` is a column like any other. LWW. |
| 10 | A device offline for months reconnects | Its old edits lose to newer server rows; rows it *created* are new and survive. Correct in both directions. |
| 11 | Both train on the same day | Legal — no constraint, and training twice in a day is real. Two sessions appear; the user deletes one if it was a mistake. |
| 12 | Killed mid-push | `dirty` stays set, upserts are idempotent, the retry is free. |
| 13 | Killed mid-pull | The batch transaction rolls back and `last_pull_at` never moved. Re-pulled next time. |
| 14 | Devices with skewed clocks | Ordering is `server_updated_at`, so a fast phone wins nothing. [§ 8](#8-conflict--two-versions-of-one-row) |
| 15 | Merge pushes past six regimes | Hues wrap; two programmes share a colour until one is deleted. |
| 16 | A pulled row fails a local CHECK | Skipped, named through the failure channel, batch continues. [§ 13](#13-when-it-fails) |
| 17 | Sign out mid-sync | Nothing shared. The queue stays on the device and resumes if the same account signs back in. |
| 18 | Account holds rows from a newer build | [§ 14](#14-two-builds-one-account). Unknown columns ignored, missing ones defaulted. |

---

## 13. When it fails

| Failure | What happens | What the user sees |
| --- | --- | --- |
| No network | Rows stay dirty, retry later | Nothing, until it has been a while |
| Auth expired, refresh failed | Queue keeps filling, no data lost | Settings asks for a sign-in; the app keeps working |
| Push rejected — RLS, constraint | `dirty` stays set, backed off, reported | The failure channel says it once |
| Partial push | Upserts are idempotent; retry | Nothing |
| Server row fails a local CHECK | Row skipped and reported, batch continues | The failure channel; the rest still lands |

That last one matters more than it looks. The local database now refuses rows
that cannot mean anything, and a pull is exactly the writer those constraints
were added for. **One bad row must not stop a restore** — it is skipped, named,
and the other twenty thousand still arrive.

Everything reportable goes through `core/failure.dart`, which already exists and
already surfaces. Sync gets no error channel of its own.

---

## 14. Two builds, one account

Sync does not merely put the app on a second device, it lets **a phone on one
build exchange rows with a server written by another**. Upgrading the app is the
ordinary way to reach that.

So a pull must tolerate a row with one column more, or one fewer, than the
reader knows:

- **A column the reader has never heard of is ignored**, not an error.
- **A column the reader expects and the row lacks gets the same default the
  backup codec gives it.**

That second rule is not new work. `backup_service.dart` spreads a default map
under every restored row for exactly this reason, and
`test/data/backup_service_test.dart` restores a payload with a column stripped
out to keep it honest. **The pull applier uses the same defaults and the same
test discipline.** The two paths are the same problem — reading a row written by
a build that is not this one — and they must not drift apart.

This is also why the migration ladder is a prerequisite of sync rather than a
consequence of it. See [RULES.md § 3](RULES.md#3-schema-and-migrations).

---

## 15. What sync may never do

1. **No screen waits on the network.** Reads come from local disk; a write
   returns when SQLite returns.
2. **No merge deletes logged work.** Re-slot, re-flag, re-number.
   [§ 9](#9-collision--two-rows-one-slot)
3. **No silent union of two histories.** [§ 10](#10-adoption)
4. **Conflicts are decided on the server's clock**, never a phone's.
   [§ 8](#8-conflict--two-versions-of-one-row)
5. **`dirty` is cleared only against an unchanged `updatedAt`.**
   [§ 6](#6-push)
6. **`last_pull_at` advances only after its batch commits.** [§ 7](#7-pull)
7. **Deletes stay tombstones.** A hard delete has nothing to push and returns on
   the next pull.
8. **`app_settings` never syncs**, `device_id` least of all.
9. **A single bad row never stops a restore.** [§ 13](#13-when-it-fails)
10. **Pulled rows go through the repositories**, not around them.

---

## 16. Still to decide

- **The backstop interval.** Battery against staleness. Wants a real phone to
  choose it.
- **Whether a first pull shows progress.** A full history through the importer
  needs a bar; a first pull is the same volume down a different path. Probably
  reuses `BackupPhase`.
- **`journal_mode`.** `delete` today, so a sync reader and a writer serialise
  completely. WAL fixes that and trades a little durability.
- **Email sign-in.** Google only to start. Additive.
- **A delete bin.** Recommended, and deliberately **not part of this work** — it
  is a local recovery feature that needs no server, and coupling it to sync
  would only delay both. Tombstones already exist and `deleteWorkout` already
  takes the whole tree, so it is a Settings row and a list. It is a new screen,
  so it gets judged against [RULES.md § 6](RULES.md#6-scope) on its own merits.
