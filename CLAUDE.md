# Deltoid — read this first

Deltoid is a personal, offline-first training log built with Flutter, Riverpod,
and drift over SQLite. It targets Android and serves a single user.

The app is complete and in daily use, and sync is finished. Offline-first is the
architecture and remains so: every screen reads from local storage, and nothing
waits on a server. A build with no configuration — which includes every clone of
this repository and every `flutter test` run — cannot sync at all and behaves
exactly as it did before sync existed. Sync is an additive layer over columns
that every syncable row already carries: an upload of locally changed rows, a
download that merges, and one question at first sign-in if both sides already
contain training data. [RULES § 6](RULES.md#6-scope) explains what that decision
does and does not permit, and [TODO.md](TODO.md) lists the one task still open.

The repository is private and MIT-licensed, and the app is a personal tool
rather than a product. Nothing personal belongs in the repository even so.
Privacy is not the reason for that rule: `seed_data.dart` is starter data for
an empty install, so putting personal numbers, coaching cues, or links there
hardcodes one training programme into an app whose whole design refuses to
assume one. That is rule 9 below, and it holds regardless of who can read the
code. Do not commit a real Supabase project reference, key, or OAuth client ID
either (`deltoid.env.json` is git-ignored, and `deltoid.env.example.json`
shows the expected shape). Those three values are not secrets — they ship
inside any release APK and are extractable from it — but they are the live
project's, and row-level security, not their obscurity, is what protects the
data behind them.

## The documents, and which one you need

| File                       | When to read it                                                                                                                                          |
| -------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **[RULES.md](RULES.md)**   | Before changing anything. Every invariant, the migration protocol, the traps already encountered, and what is out of scope                                 |
| **[THEME.md](THEME.md)**   | Before changing anything visual. The app screen by screen, and the design language it is drawn in. Do not invent a card, row, button, or sheet it does not describe |
| **[SYNC.md](SYNC.md)**     | Before changing cloud backup. Sections 1–16 are the design: what syncs, what never syncs, how a conflict resolves, and the ten things sync must never do. Sections 17–20 are the implementation: architecture, the seven phases, and what must exist outside the repository |
| **[README.md](README.md)** | Setup, commands, project layout, and how the layers fit together                                                                                          |
| **[TODO.md](TODO.md)**     | What is done and what is left. Status is recorded there and nowhere else                                                                                  |
| [SETUP-SYNC.md](SETUP-SYNC.md) | Only when the question is how a person configures their own Supabase and Google projects. Operational setup, not design                                |

This file contains no facts of its own. If anything here contradicts one of
those documents, the other document is correct.

## The rules most easily broken

These eleven cause the most damage when they are missed. All of them are
explained in full in [RULES.md](RULES.md).

1. **Prefill is scoped to the session, not the exercise.** Push 1 and Push 2
   maintain separate progressions for the same movement. This is the entire
   reason the app exists. Never "simplify" `resolvePrefill`.
2. **`WorkoutExercise` and `SetLog` are snapshots, not pointers.** Editing a
   programme must never rewrite a past log.
3. **`LoadMode` determines what the weight means; `MeasureMode` determines what
   the count means.** The seconds of a hold are stored in `reps`, and a hold has
   no estimated 1RM and contributes nothing to session volume.
4. **The log screen owns the horizontal axis.** It is a `PageView` with one
   exercise per page. Only the set row may claim a horizontal gesture, and only
   to reveal its delete action.
5. **Never watch a constant query.** `customSelect('SELECT 1', readsFrom: …)`
   emits once and then goes silent forever, without raising an error. Use
   `db.watchQuery(...)` instead.
6. **History paging is keyset-based, not offset-based**, and filters belong in
   the query rather than applied to the loaded page.
7. **Pure logic belongs in `lib/domain/`** and is tested without a database.
   Extend those tests whenever behaviour changes.
8. **The migration ladder is live, and every step is idempotent.** A schema
   change consists of an edit to `tables.dart`, a regeneration
   (`dart run build_runner build`), a default in `data/db/table_spec.dart`, and
   a step in `upgradeSchema` that uses `addColumnIfMissing` and
   `CREATE INDEX IF NOT EXISTS`. The unguarded forms throw at launch on a device
   that already has the column. See
   [RULES § 3](RULES.md#3-schema-and-migrations).
9. **No training programme is hardcoded**, and no personal numbers, cues, or
   links belong in `seed_data.dart`.
10. **Never copy the project to preserve an old version.** No `old-*/`
    directories, no `*.bak` files, no second checkout, and no worktree kept "for
    reference". Read history with `git show <commit>:<path>`.
11. **Every word this project publishes is finished prose.** That covers the
    strings in the app, commit subjects and bodies, release notes, and the
    documents. A string is a grammatical sentence or a clean noun phrase, it
    names what happens rather than gesturing at it, and it reads as though a
    release engineer wrote it: no exclamation marks, no slang or mascot voice,
    no clipped half-sentence standing in for an explanation, no interface
    riddle the reader has to solve. A commit subject is an imperative clause
    naming the change, not an aphorism about it, and a release note tells the
    user what is different rather than what the diff touched. Sentence case,
    plain vocabulary, and Commonwealth spelling throughout.
    [THEME § 4 "The words"](THEME.md#the-words) governs the app's strings and
    is the arbiter wherever this rule is less specific.

A load-bearing rule should be enforced by a mechanism rather than a comment: an
assertion, a schema constraint, or a test.
[RULES § 7](RULES.md#7-working-on-it) records where each rule is checked today.
Add to that table rather than writing a paragraph that nothing executes.

## Working on the project

Run both of the following before considering any change complete, and make sure
both finish cleanly:

```bash
flutter analyze && flutter test
```

The device belongs to the user, who tests the app on real hardware. Do not
launch an emulator on their behalf unless they explicitly ask you to.
