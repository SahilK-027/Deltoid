# Deltoid — read this first

**Read [README.md](README.md) before changing anything.** It carries the domain
model, the invariants, the environment quirks, and the traps already hit.

The short version, so you don't break it before you get there:

1. **Prefill is scoped to the session, not the exercise.** Push 1 and Push 2
   keep separate progressions for the same movement. This is the entire reason
   the app exists. Do not "simplify" `resolvePrefill`.
2. **`WorkoutExercise` / `SetLog` are snapshots of the template, not pointers.**
   Editing a programme must never rewrite past logs.
3. **No programme is hardcoded.** `seed/` ships an exercise catalog and
   *optional* templates. Never seed a regime, and never put personal numbers,
   cues or video links in `seed_data.dart` — those are the user's, added
   through the UI.
4. **The log screen is a `PageView`** — one exercise per page. Nothing inside it
   may use a horizontal gesture.
5. **History paging is keyset, not offset** (`HistoryCursor` on
   `startedAt` + id). Finishing a session while the list is open must not shift
   the page boundary.
6. **Never watch a constant query.** `customSelect('SELECT 1', readsFrom: …)`
   fires once and then goes silent forever, with no error. Use
   `db.watchQuery(...)` from `lib/data/db/watch.dart`.
7. **Pure logic lives in `lib/domain/`** and is tested without a database.
   Extend those tests when changing behaviour.
8. Regenerate drift code after any edit to `lib/data/db/tables.dart`:
   `dart run build_runner build`.

Before saying anything is done: `flutter analyze && flutter test`.

This is a personal tool for one person. Check the README's **Non-goals** before
adding a feature — the answer is usually no.
