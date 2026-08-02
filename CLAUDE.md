# Deltoid — read this first

Deltoid is a personal, offline-first training log built with Flutter, Riverpod
and drift over SQLite. It runs on Android only, serves one user, and makes no
network calls.

## The docs, and which one you want

| File                       | When                                                                                                                                                    |
| -------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **[RULES.md](RULES.md)**   | **Before changing anything.** Every invariant, the migration protocol, the traps already hit, and what is out of scope                                  |
| **[THEME.md](THEME.md)**   | Before touching anything visual. The app screen by screen, and the language it is drawn in — don't invent a card, row, button or sheet that isn't in it |
| **[README.md](README.md)** | Setup, commands, project layout, how the layers fit                                                                                                     |
| **[TODO.md](TODO.md)**     | What is done and what is left. Status lives there and nowhere else                                                                                      |

This file holds no facts of its own. If anything here contradicts one of those
four documents, the other document is the correct one.

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
8. **A column change is three edits** — `tables.dart`, the migration step, and a
   default in the backup codec — and every migration step must survive running
   twice. Regenerate after any schema edit: `dart run build_runner build`.
9. **No programme is hardcoded**, and no personal numbers, cues or links go in
   `seed_data.dart`.
10. **Never copy the project to keep an old version around.** No `old-*/`, no
    `*.bak`, no second checkout, no worktree "for reference". Read history with
    `git show <commit>:<path>`.

## Working here

Run both of these before calling any change done, and make sure both come back
clean:

```bash
flutter analyze && flutter test
```

The device belongs to the user. They drive the app on real hardware themselves,
so never launch an emulator on their behalf.

Check [RULES.md § Scope](RULES.md#6-scope) before adding a feature, because the
answer is usually no.
