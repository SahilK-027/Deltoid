# Deltoid — cloud backup

Everything about getting a training history off one phone and onto another.
The design came before the code, because the parts that are expensive to change
are the parts you cannot see. Phases 0–4 of [§ 18](#18-the-phases) are built —
the server, sign-in, the push and the pull — and where the two-device fuzz
proved a rule here wrong, this document was corrected rather than the test
loosened. Adoption and the failure states are still ahead; see
[TODO.md](TODO.md).

The rules this must not break live in [RULES.md](RULES.md). The screens it adds
are drawn in [THEME.md](THEME.md). What is done and what is left is in
[TODO.md](TODO.md).

**§ 1–16 are the design: what sync must do.** **§ 17–20 are the build: the code
that does it**, in what order, and what has to exist outside this repo first.
The first half is settled and the second half answers to it.

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
17. [The architecture](#17-the-architecture)
18. [The phases](#18-the-phases)
19. [Traps](#19-traps)
20. [What this needs from outside the repo](#20-what-this-needs-from-outside-the-repo)

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
battery budget to serve a case that does not occur — while the _correctness_ it
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

| State       | Means                                                 | How you can tell                                 |
| ----------- | ----------------------------------------------------- | ------------------------------------------------ |
| **Local**   | Never connected, or declined at first launch          | Settings offers `Back up to your Google account` |
| **Synced**  | Signed in, nothing owed                               | Settings shows when it last ran                  |
| **Pending** | Signed in, rows owed — offline, or a push that failed | Settings says how many and why; the header button turns yellow with a count once there is no connection or an attempt has failed |

**Pending is normal, not an error.** A session logged in a basement gym is
pending for an hour and that is the design working. The only thing that makes it
worth mentioning is how long it has been true.

**The header button answers at a glance, on every tab and on the log.** It is
drawn whenever an account is signed in: green while the phone is online and no
attempt has failed, yellow when there is no network interface or the last
attempt failed. The interface is read from the platform directly, so the button
turns yellow the moment signal drops, not at the next push. Online, a set is
owed for the few seconds the push waits for writes to settle; those seconds stay
green and carry no number, so nothing blinks while you log. Behind the button, a
sheet says that everything is saved on this phone, lists what is only on this
phone by session, and names the last session the account holds in full. It
exists because a person training offline should not have to leave the log for
Settings to learn that nothing is lost.

There is no state for "syncing right now". A spinner on a background job nobody
is waiting for is a spinner that teaches the user to wait.

**One moment needs a message rather than a state: a new phone taken to the gym
before it has ever had signal.** `Local`, nothing logged, and the history
sitting on a server this phone cannot reach. Nothing can fix that until there is
a network — but the app must not look like an install that lost everything. The
empty state says the history is probably on an account this phone has not signed
into yet, which is the difference between a user who waits and a user who
reinstalls in a panic.

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

**No internet at first launch needs no special handling.** Sign-in fails, the
app is used offline, and connecting later is the same Settings row every
`Local` install already has. There is deliberately no remembered intent and no
prompt that comes back when the network does: that is a flag, a listener bound
to it and a decision about how often to reappear — which is a nag, and this app
does not nag. The `Local` state is visible in Settings, and someone who wanted a
backup and could not get one will go and get it.

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

**Written by the same code that writes a restored row.** A pulled row gets the
same constraints, the same transaction discipline and the same repairs as a
restored one. A second write path is a second set of bugs, and it is the path
with no screen watching it.

This said _through the repositories_ until the code was read, and that is not a
thing that can be done. The repositories are shaped like intentions — `addSet`,
`renameSession`, `completeWorkout` — and there is no `upsertSession(row)`
anywhere, nor should there be: a repository that took a whole row would be a
second way to write every table, which is the very thing this rule is against.
`restore` already has the honest shape — one batched insert per table, inside
one transaction, foreign keys deferred to the commit — and a pull is the same
act on a smaller batch. **One row-writing path, shared, answerable to
`invariant_oracle` and followed by `repairDatabase`.** See
[§ 17](#17-the-architecture).

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

`nowMs` was made monotonic _within_ a run during the audit, which is the half of
the problem that is local. Agreement _between_ devices is a server's job, and
`server_updated_at` is that answer. The client's `updatedAt` keeps doing its own
job — ordering the offline queue on the device that made it.

### The one column last-write-wins cannot decide

**`regimes.is_active` is one answer spread across every row.** Activating a
regime deactivates another, so a single decision moves two rows — and
last-write-wins is defined on one row at a time. It has nothing to say about a
pair.

Resolving it pairwise is what the applier used to do: each arriving row was
compared against whatever happened to be active locally at that moment. That
makes the answer depend on the order rows arrive in, and two phones pulling in
different orders reached opposite answers. Nothing corrected them afterwards,
because the losing side's deactivation deliberately minted no new version — so
both phones held **one version of the row and two values of the flag**, each
looking up to date to the other, forever. `sync_fuzz_test` found it on ten seeds
out of 1,577, all shrinking to an activation on one phone against a delete on
the other.

**So the flag is not merged at all.** `regimes.activated_at` is a stamp, a fact
about its own row, and it merges like every other column. Each phone then
derives the flag from it:

> the active regime is the live one holding the highest `activated_at`,
> `deviceId` then `id` breaking a tie.

`resolveActiveRegime` in `domain/sync_merge.dart` is that sentence, and
`PullService._reconcileActiveRegime` applies it to every regime at once at the
end of each `regimes` batch — inside the batch's own transaction, so no commit
is ever visible with two active or, on a phone that has one, with none.

A pure function of rows both phones agree on gives the same answer on both
phones however the rows got there. That is the property the pairwise rule never
had, and the only reason the flag can still go unstamped: it no longer has to
travel.

**Null is not zero.** A regime nobody has ever activated is not a candidate, so
deleting the only one that ever was leaves none active rather than promoting a
programme the user never chose. `deleteRegime` picks the successor itself and
stamps it, which is what the other phone reads.

### The one row the server's clock cannot decide

**A local row that is `dirty` has never been pushed, so it has no
`server_updated_at` at all.** Nothing above gives an answer for it, and the
schema does not change to give it one ([§ 4](#4-what-the-server-holds)).

So that one case falls back to the two phones' own `updatedAt`, ties broken on
`deviceId`, in `resolveRow`. Both alternatives are worse: taking the remote
always discards an edit made seconds ago on the phone in your hand, and keeping
the local always lets a device offline for a month overwrite every newer row on
reconnect, which [§ 12](#12-every-edge-case-and-what-it-does) row 10 forbids.

The blast radius is one comparison. A _clean_ local row is a copy of what the
account already holds — every local write sets `dirty` — so it is taken from the
server without weighing anything, which is what almost every pulled row does.
And an unpushed edit that wins stays dirty, is pushed immediately behind the
pull, and every conflict it is in afterwards is decided on the server's clock,
exactly as this section requires.

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
not between two versions of one row. It is between two _different_ rows that
both claim a slot the database allows only one of.

The hardening that preceded this added **twelve** unique indexes. Every one is
correct for a single device, and eleven of them are reachable by two devices
doing something entirely ordinary. The first four are not edge cases at all —
**appending is the commonest action in the app, and two devices appending to the
same parent both compute `max + 1`.**

This said nine until `tables.dart` was counted. Three were missing, and two of
those are as reachable as any in the list: creating a regime and advancing a
cycle are both things a person does without thinking about it.

### The rule

> **No merge may ever delete logged work. Re-slot, re-flag or re-number.**

Every resolution is deterministic and symmetric, so two devices reach the same
state without negotiating.

| Index                             | Two phones doing something ordinary               | Resolution                                                                                                                                                               |
| --------------------------------- | ------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `set_logs_position_live`          | both add a set to one exercise                    | Both live. Loser takes the next free `setIndex`, ordered by `id` — UUID v7, so creation order, and both devices compute the same answer                                  |
| `workout_exercises_position_live` | both add a movement to one workout                | as above, on `orderIndex`                                                                                                                                                |
| `session_exercises_position_live` | both add an exercise to one day                   | as above                                                                                                                                                                 |
| `sessions_position_live`          | both reorder the training days                    | as above                                                                                                                                                                 |
| `sessions_name_live`              | both rename a day to the same thing               | Both live. Loser keeps its name with a disambiguating suffix; the user renames it                                                                                        |
| `workouts_single_open`            | both have a session in progress                   | Newer stays open. Older is **completed**, never discarded — its sets are real work                                                                                       |
| `regimes_single_active`           | A activates PPL, B activates Upper/Lower          | The _flag_ is not merged at all — see [§ 8](#the-one-column-last-write-wins-cannot-decide). Both regimes survive; each phone derives which is active from `activated_at` |
| `bodyweight_day_live`             | both log today's weight                           | Genuinely the same measurement. LWW, tombstone the loser                                                                                                                 |
| `cycles_regime_index_live`        | both advance the cycle → two "cycle 7"            | Both are real cycles. Loser renumbers to the next free index                                                                                                             |
| `regimes_identity_live`           | both create a regime; both take the same free hue | Both live. Loser takes the next free slot, ordered by `id`. **A shelf with no free slot cannot wrap** — see below                                                        |
| `cycles_regime_open_live`         | both advance a regime's cycle → two open cycles   | Newer stays open, older is **completed** — the same answer as `workouts_single_open`, and `healDuplicateOpenCycles` already writes it                                    |

**The seventh regime.** This section said a full shelf wraps and two programmes
share a colour, and the schema says otherwise: `identity_index` carries a
`CHECK (0..5)` _and_ a unique index over live rows, so **six live regimes is the
ceiling**. Five live plus two devices each creating one offline is seven rows
for six slots, and no re-slotting makes that fit — it is reachable by ordinary
use, not only by a merge.

So `freeIdentitySlot` returns null and the applier lands that regime
**tombstoned**, reporting it through `core/failure.dart`. The programme and
every session, workout and set under it still arrive and are kept: rule 2 of
[§ 15](#15-what-sync-may-never-do) is about logged work, and refusing the row
outright would orphan its children — the same loss with more steps. It is not on
the shelf until a slot frees, and that is the honest price. Row 15 of
[§ 12](#12-every-edge-case-and-what-it-does) is corrected to match.

The twelfth, `set_logs_slot_identity`, needs no rule and is listed so the count
stops drifting. It is not partial and it is not a rule about the data: it exists
only as the parent key for the composite foreign key on `(parent_set_id,
workout_exercise_id)`, which is what stops a drop leg naming a head in another
exercise's slot. Nothing two devices can do collides on it that has not already
collided on `set_logs_position_live`.

Resolution happens in the pull applier, using `nextPosition` and `renumber` from
`data/db/renumber.dart` — the same code that chooses a slot for a thumb, so a
slot is chosen the same way whether the row came from a tap or from a server.

**A reorder is not one of these collisions, and answering it as though it were
destroys the order.** The table above is about two devices _appending_, where
the loser taking the next free slot is right. A permutation arriving row by row
looks identical to the applier and is not: every row of it lands on a position
another row of the same batch still holds, and shunting each one to the end in
turn leaves an order nobody chose and positions climbing away from zero. So a
batch parks every row it is about to move into a scratch range first, exactly as
`renumber` does within one device, and only what is left over after that is a
collision at all.

**A resolution that both devices compute must not mint a new version.** Which
regime is active is derived from two stamps both phones can see, so writing it
with a fresh `updatedAt` makes a merge's own bookkeeping outrank a real edit —
the fuzz found it as a programme one phone had deleted and the other silently
brought back, because a deactivation written a millisecond later won the
last-write-wins against the delete.
Which slot is free is arithmetic over plain values, so the deciding lives in
`domain/` and is tested without a database; see [§ 17](#17-the-architecture).

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

Deferring it removes the problem from the path where sign-in comes _before_ use.
Sign in and pull and the catalog arrives from the account, already carrying the
user's own notes and edits. Decline, or find the account empty, and it is seeded
then.

**It does not remove the problem from the other order, which is the more likely
one.** Installing with no signal, training offline for a month and signing in
afterwards seeds a catalog locally first, and then meets an account whose
catalog was seeded on another phone long ago — the same `starterKey`s under
different ids. So **deduplicating on `starterKey` and repointing references is
real work, not a rare case**, and it is the same work whether the second history
arrives by push or by merge. Rows the user created themselves carry no
`starterKey` and are never deduplicated by name: two exercises genuinely called
`Cable fly` may be two different movements, and only the user knows.

### The three shapes

| Local    | Cloud    | What happens                                              |
| -------- | -------- | --------------------------------------------------------- |
| nothing  | data     | **Pull.** New phone. Nothing to lose.                     |
| training | empty    | **Push.** First sign-in on the phone you have been using. |
| training | training | **Ask.** Below.                                           |

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
indexes in [§ 9](#9-collision--two-rows-one-slot) are scoped to a parent, so two
histories with distinct parents cannot collide on them. What it costs is
readability: duplicated exercises to tidy up, deduped on `starterKey` where the
app seeded them and left alone where the user created them. "Nothing is lost"
and "the result is clean" are different promises, and merge only makes the
first.

### What each answer costs mechanically

`adoption.dart` runs one of three things, and the backup file is written before
any of them:

- **Keep the account's history** — the phone's database is written to a file,
  every syncable table is cleared, the cursor is dropped and the account is
  pulled from its beginning. The catalog arrives with it; seeding is skipped.
- **Keep this phone's history** — the account is written to a file first, in the
  backup format, straight off the wire. Then **every row the account holds and
  the phone does not is written locally as a tombstone and pushed.** The
  transport upserts and never deletes, so this is the only way the account's
  history stops arriving on the next pull. A tombstone claims nothing — every
  unique index in [§ 9](#9-collision--two-rows-one-slot) is partial on
  `deleted_at IS NULL` — so none of them can collide with the history being kept.
- **Merge both** — pull, then the `starterKey` dedup, then push. Nothing is
  overwritten, so nothing is backed up.

The dedup is [`catalog_merge.dart`](lib/domain/catalog_merge.dart) and is pure:
among the live rows sharing a `starterKey`, the smallest id survives and every
reference moves to it. _Deterministic_ is the load-bearing half rather than
_oldest_, because both phones run it over the same union without asking each
other — a rule that disagreed with itself across two devices would tombstone
both survivors and empty the catalog. **`workout_exercises.muscle` never moves.**
It is a snapshot of what the movement trained the day it was logged, and only
the id is repointed.

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

| #   | Situation                                    | What happens                                                                                                                                                                                                                                                                                                                      |
| --- | -------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | Two devices edit **different** rows          | Union. Both survive. The overwhelming majority of all sync.                                                                                                                                                                                                                                                                       |
| 2   | Two devices edit the **same** row            | Row LWW on `server_updated_at`, tie on `deviceId`. [§ 8](#8-conflict--two-versions-of-one-row)                                                                                                                                                                                                                                    |
| 3   | Two rows claim one slot                      | [§ 9](#9-collision--two-rows-one-slot). Nothing deleted.                                                                                                                                                                                                                                                                          |
| 4   | Both start a session                         | Newer stays open, older completed with its sets intact.                                                                                                                                                                                                                                                                           |
| 5   | Both activate a different regime             | Both regimes survive. The flag is derived from `activated_at`, not merged.                                                                                                                                                                                                                                                        |
| 6   | Both log today's bodyweight                  | Same measurement. LWW, loser tombstoned.                                                                                                                                                                                                                                                                                          |
| 7   | Both append a set, exercise or day           | Both survive; loser takes the next free position.                                                                                                                                                                                                                                                                                 |
| 8   | A deletes a workout, B adds a set to it      | The set arrives under a tombstoned parent, and `healOrphanedSnapshots` tombstones it at the end of every pull. It had to grow a second half for this: a delete takes the whole tree, so the set's _snapshot_ is already tombstoned and the original pass — which looks for live snapshots under dead workouts — could not see it. |
| 9   | Both delete, or one deletes and one restores | `deletedAt` is a column like any other. LWW.                                                                                                                                                                                                                                                                                      |
| 10  | A device offline for months reconnects       | Its old edits lose to newer server rows; rows it _created_ are new and survive. Correct in both directions.                                                                                                                                                                                                                       |
| 11  | Both train on the same day                   | Legal — no constraint, and training twice in a day is real. Two sessions appear; the user deletes one if it was a mistake.                                                                                                                                                                                                        |
| 12  | Killed mid-push                              | `dirty` stays set, upserts are idempotent, the retry is free.                                                                                                                                                                                                                                                                     |
| 13  | Killed mid-pull                              | The batch transaction rolls back and `last_pull_at` never moved. Re-pulled next time.                                                                                                                                                                                                                                             |
| 14  | Devices with skewed clocks                   | Ordering is `server_updated_at`, so a fast phone wins nothing. [§ 8](#8-conflict--two-versions-of-one-row)                                                                                                                                                                                                                        |
| 15  | Merge pushes past six regimes                | Six live regimes is the schema's ceiling, so the seventh lands **tombstoned** and is reported — everything logged under it arrives and is kept. [§ 9](#9-collision--two-rows-one-slot)                                                                                                                                            |
| 16  | A pulled row fails a local CHECK             | Skipped, named through the failure channel, batch continues. [§ 13](#13-when-it-fails)                                                                                                                                                                                                                                            |
| 17  | Sign out mid-sync                            | Nothing shared. The queue stays on the device and resumes if the same account signs back in.                                                                                                                                                                                                                                      |
| 18  | Account holds rows from a newer build        | [§ 14](#14-two-builds-one-account). Unknown columns ignored, missing ones defaulted.                                                                                                                                                                                                                                              |

---

## 13. When it fails

| Failure                         | What happens                              | What the user sees                                 |
| ------------------------------- | ----------------------------------------- | -------------------------------------------------- |
| No network                      | Rows stay dirty, retry later              | The header button turns yellow; never a toast      |
| Auth expired, refresh failed    | Queue keeps filling, no data lost         | Settings asks for a sign-in; the app keeps working |
| Push rejected — RLS, constraint | `dirty` stays set, backed off, reported   | The failure channel says it once                   |
| Partial push                    | Upserts are idempotent; retry             | Nothing                                            |
| Server row fails a local CHECK  | Row skipped and reported, batch continues | The failure channel; the rest still lands          |

That last one matters more than it looks. The local database now refuses rows
that cannot mean anything, and a pull is exactly the writer those constraints
were added for. **One bad row must not stop a restore** — it is skipped, named,
and the other twenty thousand still arrive.

Everything reportable goes through `core/failure.dart`, which already exists and
already surfaces. Sync gets no error channel of its own.

**A sentence said once is not an answer to _why is this still pending_.** A
toast is gone in four seconds and a phone can be offline for a week, so the
engine also carries a standing `SyncTrouble` — `offline` or `refused`, cleared
by the first drain that lands — and Settings reads it under the account row. It
is a state, not an event: it changes on change and says nothing per retry.

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
10. **A pulled row is written by the same code that writes a restored row.**
    [§ 7](#7-pull)

---

## 16. Still to decide

- **The backstop interval.** Battery against staleness, and the one thing on
  this list that cannot be reasoned to an answer — it wants a real phone, a real
  week, and the ordinary rhythm of actually training. Chosen in
  [§ 18](#18-the-phases)'s last phase, on hardware.
- ~~**Whether a first pull shows progress.**~~ **Settled: it does**, and only
  it. `JobPhase` in `core/progress.dart` is one vocabulary for an export, a
  restore and a pull, behind one sheet; `PullService.pull` takes an `onProgress`
  and the row count the account reported, so the bar has a denominator rather
  than an invented number. **Every background drain passes neither** — a spinner
  on a job nobody is waiting for is a spinner that teaches the user to wait
  ([§ 2](#2-the-three-states)) — and so is a sign-in with nothing to adopt,
  where a sheet would flash for one frame.

### Settled, and where

| Was open                      | Now                                           | Why                                                                                                                                                                                                                                                                                 |
| ----------------------------- | --------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `journal_mode`                | **WAL**, in the first phase                   | `delete` serialises a sync reader against a UI writer completely, and `busy_timeout = 5000` turns that into a screen waiting on a background job. WAL lets them overlap for a little durability. Decided early on purpose: every later test then runs on the mode the phone runs on |
| The client library            | **`supabase_flutter`**, realtime never opened | Google sign-in, a persisted session and silent refresh are the parts worth not hand-rolling. Wrapped behind our own interface so nothing under `features/` imports it, and no socket is ever held — [§ 1](#1-what-this-is-and-is-not) rules that out                                |
| Where the server schema lives | **`supabase/migrations/*.sql`, in this repo** | The RLS policies are the whole of the security, and a policy that exists only in a browser has no diff, no review and no way to be rebuilt onto a fresh project                                                                                                                     |
| How the keys reach the app    | **`--dart-define`**                           | The anon key is extractable from any APK and RLS is what protects the data ([§ 3](#3-identity)), so this is hygiene rather than secrecy — it keeps a live project reference out of the tree                                                                                         |

**Email sign-in** stays out for now. Google only to start, and adding a second
provider changes nothing below [§ 3](#3-identity).

**A delete bin** is recommended and deliberately **not part of this work** — it
is a local recovery feature that needs no server, and coupling it to sync would
only delay both. Tombstones already exist and `deleteWorkout` already takes the
whole tree, so it is a Settings row and a list. It is a new screen, so it gets
judged against [RULES.md § 6](RULES.md#6-scope) on its own merits.

---

## 17. The architecture

### Where it lives

```
lib/
  data/
    db/
      table_spec.dart        the per-table registry both backup and sync read
      migrations.dart        the ladder — one idempotent step per released change
    sync/
      sync_config.dart         URL, anon key and client id, from --dart-define
      sync_backend.dart        the transport interface, and nothing implementing it
      supabase_backend.dart    the only file that imports package:supabase_flutter
      sync_auth.dart           sign in, sign out, who is signed in
      sync_engine.dart         the triggers, the debounce, the backoff
      push.dart                drains dirty
      pull.dart                applies a batch: conflict, collision, cursor
      adoption.dart            the three shapes at sign-in, and the starterKey dedup
      sync_state.dart          Local / Synced / Pending, read off the database
  domain/
    sync_merge.dart          who wins a row, and where a re-slot goes
    catalog_merge.dart       two seeded catalogs into one

supabase/
  migrations/*.sql           tables, RLS, indexes, the server clock
```

`data/sync/` sits beside `data/backup/`, because they are the same kind of
thing: code that reads and writes the whole database and is not a screen. The
dependency direction is unchanged — `features/` → `data/` → `domain/`, with
`core/` available to all three — and **nothing under `features/` ever imports
the Supabase package.** One file does, and swapping the backend or testing
without one is then a constructor argument rather than an excavation.

### One registry, two readers

`BackupService` already holds a per-table registry: `_TableCodec`, carrying the
table's name, its drift `TableInfo`, and a `parse` that spreads a map of
defaults underneath a row so a file written before a column existed still
restores. [§ 14](#14-two-builds-one-account) says the pull applier must use the
same defaults and the same test discipline — and **the way to make that true is
to share the code, not to remember the rule.** Two lists of defaults that must
agree forever will not.

So the half both paths need is promoted out of `backup_service.dart` into
`data/db/table_spec.dart`: the name, the table, the parser with its defaults,
and whether the table syncs at all. `BackupService` keeps its pager, its
`count`, its `clear` and its `keep`, and builds its codecs from the registry;
push and pull walk the same list, forwards, which is parents before children.

The test that already walks every column of every table and asserts each parser
survives that column going missing moves with it, and now covers both readers at
once. That is [RULES § 7](RULES.md#7-working-on-it) applied to the one rule this
document had been stating twice in prose.

### The transport is an interface

Four methods: upsert a batch, read everything since a cursor, count the rows on
the account, and read the largest value of one column. The last two exist only
so [§ 10](#10-adoption)'s prompt can say _214 sessions, most recently 3 March_
rather than _some_. The column is named by the caller because the date the
prompt wants is `workouts.started_at` — when the user trained — and not
`updated_at`, which would report a decade-old session as today's the moment a
merge restamped it.

It deals in `Map<String, dynamic>`, never in typed rows. That is the same
currency the backup codec speaks, and it is the only one that can carry a column
this build has never heard of — which [§ 14](#14-two-builds-one-account) requires
it to carry rather than choke on.

The fake is the point. An in-memory implementation with its own monotonic clock,
able to misbehave deliberately — drop the response after committing the write,
hand back a row from a newer build, fail every third call — is what makes
[§ 12](#12-every-edge-case-and-what-it-does) testable at all. No test talks to a
real Supabase; a small opt-in suite against a local stack proves the RLS
policies and nothing else, because that is the only thing a fake cannot check.

**The cursor compares `>=`, not `>`.** Two rows can share a `server_updated_at`,
and a strict `>` drops whichever one falls on the far side of a page boundary —
silently, once, with no second chance. Re-reading the boundary row costs an
upsert that is idempotent anyway.

### The wire

Drift's generated `fromJson` reads the keys it knows and ignores the rest, so
half of [§ 14](#14-two-builds-one-account) — _a column the reader has never heard
of is ignored_ — is already true and costs a test rather than a mechanism. The
other half is the default map, which the registry above already carries.

Two mismatches between what drift writes and what Postgres wants, both quiet:

- **Drift's JSON keys are camelCase and Postgres columns are snake_case.**
  `updatedAt` against `updated_at`, `tzOffsetMinutes` against
  `tz_offset_minutes`. Drift derives its own SQL names by exactly that rule, so
  the conversion is a pair of pure functions and a test that walks every column
  of every table asserting the round trip. Ten hand-written maps are ten chances
  to type a column into silence.
- **`exercises.form_video_urls` is `text` server-side, not `jsonb`.**
  `StringListConverter` is a `JsonTypeConverter<List<String>, String>`, so the
  JSON form of that column is a string _containing_ JSON rather than an array. A
  `jsonb` column would round-trip it into a JSON string of a string. `text`, and
  the converter carries on doing its own decoding — it already never throws, so
  a malformed list from a server reads as no links instead of blanking the
  catalog.

Enums are `text` server-side too. The local `CHECK` is the gate that matters,
and a Postgres enum would make adding one value a migration on both sides.

**There are no `CHECK` constraints server-side at all.** The local column is the
backstop for a number that cannot mean anything
([RULES § 2](RULES.md#2-data)), and a server that refuses the same row instead
strands it dirty forever with nothing able to clear it. The phone refuses bad
rows; the server stores what it is given.

### The merge is arithmetic

Which version of a row wins, which free index a loser takes, which regime keeps
the active flag, which workout stays open — all of it is a function of plain
values, and it lives in `domain/sync_merge.dart` where it is tested without a
database, per [RULES § 4](RULES.md#4-code). `pull.dart` does the input and
output: read the scope, ask the domain, write the answer through `renumber`.

That split is what makes [§ 9](#9-collision--two-rows-one-slot)'s twelve rows
twelve unit tests rather than twelve integration tests.

### Three transactions, never one

Read the batch, close. Call the network, holding nothing. Write the result,
close.

There is one drift connection with `busy_timeout = 5000`, and a transaction held
open across a round trip is a screen frozen on a background job — the exact
thing [§ 5](#5-the-write-path-never-changes) exists to prevent, arriving through
the back door.

The engine itself runs on the UI isolate and only ever awaits: drift already
does its work on a background isolate and HTTP is not arithmetic. **Do not reach
for `Isolate.run`** — a closure written inside a class captures `this`, and an
`AppDatabase` wrapping an FFI handle fails at the send rather than in the JSON.
Both backup helpers are top-level functions for this reason and sync's must be
too. A first push of a decade of training chunks and yields, as `writeBackup`
already does.

### The state is read, not remembered

`Local`, `Synced` and `Pending` are derived: count the rows still owed, read
`last_pull_at`, and that is the whole of it. Nothing to keep in step, because
there is no second copy of the answer — which is the same reason
[§ 2](#2-the-three-states) has no state for _syncing right now_.

Counting what is owed needs an index, though. `COUNT(*) WHERE dirty` across a
`set_logs` holding 168k rows is a scan, re-run every time a set is ticked; a
partial index on `dirty = 1` is empty whenever nothing is owed and costs nothing
to carry. Nine of them, one per syncable table, and they are the first rung of
the ladder.

### What must never be re-stamped

Every local write sets `deviceId`, `updatedAt` and `dirty = true` together —
today at forty call sites, spelled out each time. **A pulled row gets none of
it.** It keeps the server's `updatedAt` and the writing device's `deviceId`, and
it lands with `dirty = false`.

A pull that goes down the ordinary write path stamps every row it applies as
locally owed, pushes them all straight back, and the two devices trade the same
rows forever, each one arriving as news. Nothing about that is visible from a
screen.

So the trio becomes a named helper and gets a named counterpart — the write that
deliberately does not stamp — rather than staying a convention that forty sites
happen to follow. `tables.dart` has referred to that helper as `stampedNow` in a
doc comment since the columns were written; the symbol never existed.

---

## 18. The phases

Seven, each ending in something that can be driven on a phone. The order is not
arbitrary: **the ladder is a prerequisite of sync rather than a consequence of
it** ([RULES § 3](RULES.md#3-schema-and-migrations)), because sync is precisely
what lets two devices running _different builds_ exchange rows.

### 0 · The ground

Local, testable today, and blocking everything after it.

- **The migration ladder.** `schemaVersion` 1 → 2, with an `onUpgrade` whose
  every step is idempotent — `addColumnIfMissing`, `CREATE INDEX IF NOT EXISTS`,
  never a bare `m.addColumn` or `m.createIndex`. A device handed an earlier build
  comes back with the structure already in place and the stamp behind it, and the
  bare form throws on launch before any screen is drawn. Plus the test
  [RULES § 3](RULES.md#3-schema-and-migrations) asks for: a full upgrade run over
  a database that already has everything.
- **The first rung**: nine partial indexes on `dirty`.
- **WAL**, in `beforeOpen`. `schema_constraints_test` currently asserts the mode
  is one of four and explains that nothing in `lib/` sets it; that reasoning
  inverts, and the test should now name WAL exactly.
- **The registry**, and `BackupService` rebuilt on it, with the missing-column
  test moved to walk it.
- **The wire, proved**: a row with an unknown column and a row missing a known
  one, through every table's parser. And the name conversion, with the round-trip
  test over every column.
- **`android.permission.INTERNET` in the main manifest.** It is only in the debug
  manifest today, which Flutter injects for hot reload — so a release build has
  no network at all, and every request fails with a `SocketException` that reads
  like a broken server.

_Done when_ the upgrade test passes over a fully populated database, the journal
mode reads `wal` off a file, and a reinstall has stopped being the upgrade path.

### 1 · The server

The nine tables, `user_id` and `server_updated_at` beside them, `id` still the
primary key, and a composite index on `(user_id, server_updated_at)` because that
is every pull query there will ever be.

**RLS on all nine, `using` and `with check`**, as [§ 3](#3-identity) writes it. A
trigger stamps `server_updated_at = now()` on every insert and update, so the
clock conflicts are decided on is the server's and a client cannot forge it.

`app_settings` is not created server-side. It never syncs, `device_id` least of
all.

_Done when_ a reset rebuilds the schema from the migration alone, and a test
proves RLS refuses a row belonging to somebody else.

### 2 · Identity

Google sign-in through Supabase Auth, the session persisted and refreshed
silently, seen once and never again. The welcome screen exactly as
[THEME.md](THEME.md) draws it — one screen, one question, and `Use without an
account` given equal standing.

**Seeding moves here**, and it is the riskiest change in the list.
`ensureStarterCatalog` runs today inside the launch repairs, before first paint;
it has to wait until the welcome is answered, or until a pull has found the
account empty. [§ 10](#10-adoption) explains what it costs to leave it: two
catalogs, roughly 120 exercises, `Bench Press` twice, and a history split across
both — which breaks the one thing the app exists for, because per-session
progression is keyed to an exercise id.

The care it needs is that first paint is gated on those repairs, and a restore
runs the same list. The repairs take a flag, the welcome screen renders over an
unseeded database, and a restore never seeds because the seeder already declines
a table that is not empty.

Settings gains the account section.

_Done when_ a sign-in survives a force-stop, and declining is final, repairable
from Settings, and never asked again.

### 3 · Push

One writer, so nothing from [§ 8](#8-conflict--two-versions-of-one-row) or
[§ 9](#9-collision--two-rows-one-slot) is needed yet. **This phase on its own is
the point of the feature**: a lost phone stops losing the history.

Every dirty row, oldest `updatedAt` first, batched upserts on `id`, parents
before children. `dirty` cleared only against an unchanged `updatedAt`. Triggers
debounced after a write settles, on resume, on connectivity regained, and on a
long idle backstop, with exponential backoff on failure.

The lifecycle hook is new. There is exactly one `WidgetsBindingObserver` in the
app and it belongs to the log screen, which is already carrying the rest alarm;
sync mounts its own at the root.

_Done when_ a session logged in a basement reads `Pending`, arrives when the
signal does, and the server's row count matches the phone's.

### 4 · Pull

Rows since the cursor, applied under [§ 8](#8-conflict--two-versions-of-one-row)
and [§ 9](#9-collision--two-rows-one-slot), one transaction per batch, cursor
advanced only after it commits. Tombstones arrive as rows and stay tombstones. A
row that fails a local `CHECK` is skipped, named, and the batch carries on.
`repairDatabase` after each one.

_Done when_ every row of [§ 12](#12-every-edge-case-and-what-it-does) is a
passing test and the two-device fuzz converges.

### 5 · Adoption

The three shapes at sign-in, and the `starterKey` dedup that follows the third.
The losing side written to a backup file first, automatically, before anything
is overwritten.

Not a rare path: installing with no signal, training for a month and signing in
afterwards is the _likely_ order, and it seeds a catalog locally before ever
meeting the account's.

### 6 · The states, and the failures

Settings says which of the three it is in, and for how long. The empty state for
a phone that has never had signal says the history is probably on an account it
has not signed into yet — the difference between a user who waits and a user who
reinstalls in a panic. Every row of [§ 13](#13-when-it-fails) reaches
`core/failure.dart`.

The backstop interval is chosen here, on a phone, over a real week.

### The tests

Each row of [§ 12](#12-every-edge-case-and-what-it-does) becomes one named test
against two in-memory databases and one fake backend. The list claims to be
exhaustive as far as the schema can be reasoned about, so every row of it
failing a build is what keeps that claim honest.

Then `test/integrity/sync_fuzz_test.dart`, in the shape `model_fuzz_test.dart`
already established — seeded operations, the sequence printed on failure, greedy
shrinking. Two devices, random operations on both, syncing at random points, and
after every step the oracle on both databases plus **a convergence check**: once
both sides are quiet and have synced twice, they hold the same rows. That is the
only thing that can find a collision this document merely anticipated.
`invariant_oracle.dart` was written for it — its header already names _"after
SYNC.md a row another device pushed"_ as the third case a schema constraint
cannot speak to.

---

## 19. Traps

The ones this feature can hit that are specific to this codebase.
[RULES § 4](RULES.md#4-code) holds the rest and they all still apply.

- **Never watch a constant query.** Sync wants _is anything owed_, which is
  exactly the shape that tempts a `customSelect('SELECT 1', readsFrom: …)` — and
  that fires once and goes silent forever with no error anywhere. `watchQuery`,
  which was already hardened for a pull landing a batch of rows in the middle of
  a read.
- **`Isolate.run` inside a class captures `this`.** Covered in
  [§ 17](#17-the-architecture); it is here as well because it failed at the send
  once already and the message named the JSON.
- **`valueOrNull ?? const []` turns loading into empty.** The account section has
  more than one query behind it.
- **Don't hold a `WidgetRef` across an await that changes the screen.** Sign-in
  and adoption both await a network and then swap what is on screen; capture the
  container first.
- **A re-slot goes through `renumber`.** Writing the index directly collides with
  whoever is standing on it, and the unique partial index refuses a permutation
  that is perfectly legal once finished.
- **Catalog dedup repoints `workout_exercises.exercise_id`**, and that is
  correct: both rows are the same seeded movement, and leaving them split is the
  bug, because prefill is keyed on the exercise id. It must not touch `muscle`,
  which is a snapshot of what the set trained and is _entitled_ to disagree with
  the catalog — that is the whole reason the column exists.
- **WAL leaves `-wal` and `-shm` files beside the database.** Nothing copies the
  database file today — a backup writes JSON — so this is safe, and it stops
  being safe the moment anything copies the file.

---

## 20. What this needs from outside the repo

None of it can be created from a checkout: it needs a Google account, a Supabase
account, and two installs that ask for a password. Nothing in
[§ 18](#18-the-phases)'s first phase is blocked on any of it.

**Before phase 1**

1. **A Supabase project.** An org, a project, a region worth being close to.
   What the app needs from it is the **project URL** and the **anon key**. The
   free tier is more than enough for one person — but a free project **pauses
   after seven days with no requests**, and a paused project is a sync outage on
   the phone rather than an email. Worth knowing before it happens.
2. **The Supabase CLI, and Docker**, for `supabase/migrations` and for the local
   stack the RLS tests run against. Then `supabase login`, and `supabase link`
   against the project ref.

**Before phase 2**

3. **A Google Cloud project with an OAuth consent screen**, and two client ids
   under it: a **Web** client, whose id and secret go into Supabase's Google
   provider, and an **Android** client for `com.deltoid.deltoid` registered with
   the SHA-1 of **both** keystores — the debug one and the release one in
   `android/key.properties`. Two fingerprints, not one, or sign-in works in
   development and fails on the build that matters.

   The app needs the **Web client id** at runtime. The secret never leaves
   Supabase.

**Throughout.** The device belongs to the user
([RULES § 7](RULES.md#7-working-on-it)). Every phase above ends in something to
drive on real hardware, and none of them ends in an emulator launched on their
behalf.
