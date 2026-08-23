# Deltoid — read this first

Deltoid is a personal, offline-first training log built with Flutter, Riverpod
and drift over SQLite. It runs on Android only and serves one user.

**It now pushes to a server, and no screen has noticed.** Offline-first is the
finished half and stays the architecture: every screen reads local disk, and
nothing waits on a server — a build with no configuration, which is every clone
of this repo and every `flutter test`, cannot sync at all and works exactly as
it did. Sync is an additive layer over the columns every syncable row already
carries: a drain of `dirty`, a pull that merges, and one question at the first
sign-in when both sides have been trained on. See
[RULES.md § 6](RULES.md#6-scope) for what that decision does and does not open,
and [TODO.md](TODO.md) for the four phases still to come.

## The docs, and which one you want

| File                       | When                                                                                                                                                    |
| -------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **[RULES.md](RULES.md)**   | **Before changing anything.** Every invariant, the migration protocol, the traps already hit, and what is out of scope                                  |
| **[THEME.md](THEME.md)**   | Before touching anything visual. The app screen by screen, and the language it is drawn in — don't invent a card, row, button or sheet that isn't in it |
| **[SYNC.md](SYNC.md)**     | Before touching cloud backup. § 1–16 is the design — what syncs, what never does, how a conflict resolves, the ten things sync may never do. § 17–20 is the build — the architecture, the seven phases, and what has to exist outside the repo |
| **[README.md](README.md)** | Setup, commands, project layout, how the layers fit                                                                                                     |
| **[TODO.md](TODO.md)**     | What is done and what is left. Status lives there and nowhere else                                                                                      |

This file holds no facts of its own. If anything here contradicts one of those
five documents, the other document is the correct one.

## The rules most easily broken

These are the ten that cost the most when they are missed. All of them are
explained properly in [RULES.md](RULES.md).

1. **Prefill is scoped to the session, not the exercise.** Push 1 and Push 2
   keep separate progressions for the same movement. This is the entire reason
   the app exists. Never "simplify" `resolvePrefill`.
2. **`WorkoutExercise` / `SetLog` are snapshots**, not pointers. Editing a
   programme must never rewrite past logs.
3. **`LoadMode` decides what the weight means; `MeasureMode` decides what the
   count means.** A hold's seconds live in `reps`, and a hold has no e1RM and no
   session volume.
4. **The log screen owns the horizontal axis** — a `PageView`, one exercise per
   page. Only the set row may claim a horizontal gesture, to uncover its delete.
5. **Never watch a constant query.** `customSelect('SELECT 1', readsFrom: …)`
   fires once and goes silent forever, with no error. Use `db.watchQuery(...)`.
6. **History paging is keyset, not offset**, and filters belong in the query.
7. **Pure logic lives in `lib/domain/`** and is tested without a database.
   Extend those tests when behaviour changes.
8. **The migration ladder is running, and every rung is idempotent.** A schema
   change is `tables.dart`, a regenerate (`dart run build_runner build`), a
   default in `data/db/table_spec.dart`, and a rung in `upgradeSchema` —
   `addColumnIfMissing` and `CREATE INDEX IF NOT EXISTS`, never the bare form,
   which throws at launch on a device that already has the column. See
   [RULES.md § 3](RULES.md#3-schema-and-migrations).
9. **No programme is hardcoded**, and no personal numbers, cues or links go in
   `seed_data.dart`.
10. **Never copy the project to keep an old version around.** No `old-*/`, no
    `*.bak`, no second checkout, no worktree "for reference". Read history with
    `git show <commit>:<path>`.

A load-bearing rule gets a mechanism rather than a comment — an assert, a schema
constraint, a test. [RULES § 7](RULES.md#7-working-on-it) lists where each one is
checked today; add to that table rather than writing a paragraph nothing runs.

## Working here

Run both of these before calling any change done, and make sure both come back
clean:

```bash
flutter analyze && flutter test
```

The device belongs to the user. They drive the app on real hardware themselves,
so never launch an emulator on their behalf unless they explicitly permit you to do so.

Check [RULES.md § Scope](RULES.md#6-scope) before adding a feature, because the
answer is usually no.
