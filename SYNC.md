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
8. [Conflict](#8-conflict)
9. [Adoption — the hard case](#9-adoption-the-hard-case)
10. [Signing out](#10-signing-out)
11. [When it fails](#11-when-it-fails)
12. [Two builds, one account](#12-two-builds-one-account)
13. [What sync may never do](#13-what-sync-may-never-do)
14. [Still to decide](#14-still-to-decide)

---

## 1. What this is, and is not

**It is a backup you do not have to remember to take.** The app is the only copy
of a history that takes years to accumulate, and a lost phone currently loses
it. There is already an export — a real answer, and one that depends on the user
remembering. This is the same answer without the remembering.

**It is not collaboration, and it is not a feature.** One person, their own
devices. No sharing, no profiles, no feed. A login seen once and never again.
[RULES.md § 6](RULES.md#6-scope) sets that boundary and this document stays
inside it.

**It is not what makes the app work.** Offline-first is finished and stays the
architecture. Every screen reads local disk; no read waits on a server; the app
is fully usable with the radio off, forever, whether or not anyone ever signs
in. Sync is a background reconciliation of tables the screens already read.

---

## 2. The three states

| State | Means | How you can tell |
| --- | --- | --- |
| **Local** | Never connected, or declined at first launch | Settings offers `Back up to your Google account` |
| **Synced** | Signed in, nothing owed | Settings shows when it last ran |
| **Pending** | Signed in, rows owed — offline, or a push that failed | Settings says how many and why |

**Pending is normal, not an error.** A session logged in a basement gym is
pending for an hour and that is the design working. The only thing that makes it
worth mentioning on screen is how long it has been true.

There is no fourth state for "syncing right now". A spinner on a background job
nobody is waiting for is a spinner that teaches the user to wait.

---

## 3. Identity

**Google, through Supabase Auth.** One provider to start. Email is a later
addition and changes nothing below it.

The session is persisted and refreshed silently. A signed-in user sees the
sign-in screen exactly once, at first launch, and never again unless they sign
out or the refresh token is revoked.

`auth.uid()` is the identity. It is never stored as the source of truth in
`app_settings` — the session is — because a copy of an id that outlives its
session is a way to push someone else's rows.

### Why the anon key stops being a problem

The anon key ships inside the APK and is extractable. With **RLS on every table
keyed to `auth.uid()`**, that key on its own grants nothing: no session, no
rows. This is the whole reason the design is worth having auth for at all — the
alternative once considered, an anon key plus a client-asserted `user_id`, is a
public database with a guessable filter.

Every table gets the same policy, and the policy is the security model:

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

### The local schema does not change

`user_id` is a **server-side column only**, attached from the session as a row
is pushed. Local rows do not carry it and do not need to: one install is signed
into one account at a time, so every local row belongs to whoever is signed in.

That is worth stating plainly because it is the difference between this being an
additive layer and a migration: `updatedAt`, `deletedAt`, `deviceId` and `dirty`
have been on every syncable row since the schema was written, and the audit that
preceded this made all four of them true. **Nothing in `tables.dart` changes to
support sync.**

Server-side, `id` stays the primary key — ids are UUID v7 and do not collide
across devices — with `user_id` as a column, indexed, and RLS over it.

---

## 5. The write path never changes

A write goes to SQLite and returns. It sets `dirty`, as it already does. That is
the whole of the UI's involvement with sync.

**No screen ever awaits the network.** Not the log, not Settings, not the first
launch. This is [RULES.md § 6](RULES.md#6-scope)'s offline-first rule and it is
not negotiable by anything in this document: the app must behave identically
with the radio off, including on the frame after a set is ticked.

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

**What.** Rows with `updated_at > last_pull_at`, which lives in `app_settings`.

**When.** On sign-in, on resume, on connectivity regained. Pull before push, so
a conflict is resolved before it is propagated.

**How.** Apply row by row under [§ 8](#8-conflict), inside one transaction per
batch, in parent-before-child order.

**Advance `last_pull_at` from the server's clock, not the phone's**, and only
after the batch commits. A pull that advances the cursor before it writes loses
every row in the batch it did not finish.

**Tombstones arrive as rows.** `deleted_at` set is a delete; it is applied as a
tombstone locally, never as a hard delete, exactly as every local delete already
works. A hard delete has no `deleted_at` to push and would be resurrected by the
next pull from the other side.

---

## 8. Conflict

**Row-level last-write-wins.** The incoming row wins when its `updated_at` is
greater; the tie is broken on `device_id`, deterministically, so both sides pick
the same winner rather than each keeping its own.

Both of those columns are now trustworthy, which they were not before the audit:
`updatedAt` is monotonic within a run and `deviceId` names the device that wrote
*that version* rather than the one that created the row.

**Why row-level and not column-level.** Column-level merging exists to preserve
two people editing different fields of one row at the same moment. This design
has one person, usually on one phone. The case it would protect — the same set
edited on two phones inside one sync interval — is rare enough that the
complexity is not repaid, and the failure when it does happen is losing the
older of two edits to one set.

**If that turns out to be wrong**, the place to change it is the pull applier,
and `set_logs` is the only table it would be worth changing for.

---

## 9. Adoption — the hard case

Signing in has three shapes and only one of them is interesting.

| Local | Cloud | What happens |
| --- | --- | --- |
| empty | has data | **Pull.** New phone, restored history. Nothing to lose. |
| has data | empty | **Push.** First sign-in on the phone you have been using. Nothing to lose. |
| has data | has data | **Ask.** See below. |

**The third case is never merged silently.** Merging two histories by row id
invents workouts that never happened —
[`backup_service.dart`](lib/data/backup/backup_service.dart) already says this
about restore, and it is the same argument: two independent histories share no
ids, so a merge is not a reconciliation, it is a union that claims you trained
twice as often as you did.

So it asks, once, in the shape the restore prompt already uses: what is in each,
in numbers, and which one to keep.

> **This account already has training on it**
> The account has 214 sessions, most recently 3 March.
> This phone has 6 sessions, most recently today.
> `Keep the account's history` · `Keep this phone's history`

**Whichever side loses is written to a backup file first, automatically, before
anything is overwritten** — same folder as every other export. The prompt says
so. A decision made once at a sign-in screen must not be the only thing standing
between a user and a deleted history.

The common shape of the third case is not two real histories. It is someone who
used the app for a week before signing in, against an account with years on it —
which is why the numbers are in the prompt rather than the word "merge".

---

## 10. Signing out

Two doors, because they answer different questions:

- **Sign out** — the session goes, the data stays, the app returns to `Local`.
  For handing the phone over, or switching accounts.
- **Sign out and remove the history from this phone** — the local database is
  cleared after a confirmation that names the number of sessions. For a phone
  you are giving away.

**Signing into a different account is the second door, forced.** One install is
signed into one account at a time; local rows carry no `user_id`, so mixing two
accounts in one file is not a state the schema can represent. The prompt says
that plainly rather than discovering it later.

---

## 11. When it fails

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

## 12. Two builds, one account

The part that is easy to miss: sync does not merely put the app on a second
device, it lets **a phone on one build exchange rows with a server written by
another**. Upgrading the app is the ordinary way to reach that.

So a pull must tolerate a row with one column more, or one fewer, than the
reader knows:

- **A column the reader has never heard of is ignored**, not an error.
- **A column the reader expects and the row lacks gets the same default the
  backup codec gives it.**

That second rule is not new work. `backup_service.dart` spreads a default map
under every restored row for exactly this reason, and
`test/data/backup_service_test.dart` restores a payload with a column stripped
out to keep it honest. **The pull applier uses the same defaults, and the same
test discipline.** The two paths are the same problem — reading a row written by
a build that is not this one — and they should not drift apart.

This is also why the migration ladder is a prerequisite of sync rather than a
consequence of it. See [RULES.md § 3](RULES.md#3-schema-and-migrations).

---

## 13. What sync may never do

The invariants. If one of these is broken, something that used to work is
quietly wrong and nothing raises an error to say so.

1. **No screen waits on the network.** Reads come from local disk. A write
   returns when SQLite returns.
2. **No silent merge of two histories.** [§ 9](#9-adoption-the-hard-case).
3. **`dirty` is cleared only against an unchanged `updatedAt`.**
   [§ 6](#6-push).
4. **`last_pull_at` advances only after the batch commits**, from the server's
   clock. [§ 7](#7-pull).
5. **Deletes stay tombstones.** A hard delete has nothing to push and comes
   back on the next pull.
6. **`app_settings` never syncs**, `device_id` least of all.
7. **A single bad row never stops a restore.** [§ 11](#11-when-it-fails).
8. **Sync writes go through the repositories**, not around them. The
   constraints, the transactions and the stamping are the same for a pulled row
   as for a typed one — a second write path is a second set of bugs.

---

## 14. Still to decide

- **Two phones at once.** This design describes backup and restore, and it
  behaves correctly if a second phone signs in and stays signed in — that is
  what [§ 8](#8-conflict) is for. What it does not do is make that pleasant:
  there is no "this device is primary", and two phones logging the same session
  offline produce two workouts, not one. Acceptable for backup; state it before
  anyone assumes otherwise.
- **How often the backstop timer runs.** Battery against staleness. Needs a
  number, and the number wants a real phone to choose it.
- **Whether a first pull shows progress.** A restore of fifty years through the
  existing importer takes long enough to need a bar; a first pull is the same
  volume through a different path. Probably reuses `BackupPhase`.
- **Email sign-in.** Google only to start. Additive.
